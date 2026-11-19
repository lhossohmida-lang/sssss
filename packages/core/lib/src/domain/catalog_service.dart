import 'package:drift/drift.dart';

import '../data/local/app_database.dart';
import '../data/local/sync_writer.dart';

/// بيانات غير صالحة: اسم الحقل ← رسالة الخطأ بالعربية.
class ValidationException implements Exception {
  const ValidationException(this.errors);

  /// خطأ واحد على حقل.
  ValidationException.field(String field, String message)
    : errors = {field: message};

  final Map<String, String> errors;

  @override
  String toString() => errors.values.join('، ');
}

/// مادة مع اسم مستواها لعرضها في القوائم.
class SubjectItem {
  const SubjectItem({required this.subject, this.levelName});

  final SubjectRow subject;

  /// اسم المستوى؛ `null` لمادة عامة لكل المستويات.
  final String? levelName;

  String get id => subject.id;
  String get name => subject.name;
  int get monthlyPrice => subject.monthlyPrice;

  /// المواد التي تُعرض لتلميذ في مستوى [levelId]: مواد مستواه والمواد العامة (كل المستويات)، دون العامة
  /// التي لها مادة بالاسم نفسه في مستواه (فأفواج سنته أولى). ودون مستوى تُعرض كلها.
  static List<SubjectItem> offeredFor(
    List<SubjectItem> subjects,
    String? levelId,
  ) {
    if (levelId == null) return subjects;
    final specific = {
      for (final s in subjects)
        if (s.subject.levelId == levelId) s.name,
    };
    return [
      for (final s in subjects)
        if (s.subject.levelId == levelId ||
            (s.subject.levelId == null && !specific.contains(s.name)))
          s,
    ];
  }
}

/// المواد: اسم، مستوى اختياري، وسعر الشهر الافتراضي.
class SubjectService {
  SubjectService(this.db, this.writer);

  final AppDatabase db;
  final SyncWriter writer;

  /// حقول التحقق.
  static const String fieldName = 'name';
  static const String fieldPrice = 'price';
  static const String fieldLevel = 'level';

  /// المواد الحية مع أسماء مستوياتها، مرتبة بالاسم.
  Stream<List<SubjectItem>> watchAll() {
    return db
        .customSelect(
          'SELECT s.*, l.name AS level_name FROM subjects s '
          'LEFT JOIN levels l ON l.id = s.level_id '
          'WHERE s.deleted_at IS NULL ORDER BY s.name, l.sort_order',
          readsFrom: {db.subjects, db.levels},
        )
        .watch()
        .map(
          (rows) => [
            for (final row in rows)
              SubjectItem(
                subject: db.subjects.map(row.data),
                levelName: row.read<String?>('level_name'),
              ),
          ],
        );
  }

  /// يضيف مادة. يرمي [ValidationException] إن كانت البيانات غير صالحة.
  Future<SubjectRow> add({
    required String name,
    String? levelId,
    required int monthlyPrice,
  }) async {
    final trimmed = await _validate(name, levelId, monthlyPrice);
    final id = writer.newId();
    await writer.save(
      db.subjects,
      SubjectsCompanion.insert(
        id: id,
        createdAt: 0,
        updatedAt: 0,
        name: trimmed,
        levelId: Value(levelId),
        monthlyPrice: Value(monthlyPrice),
      ),
      key: {'id': id},
    );
    return (db.select(db.subjects)..where((t) => t.id.equals(id))).getSingle();
  }

  /// يعدّل مادة. يعيد `false` إن لم توجد.
  Future<bool> update(
    String id, {
    required String name,
    String? levelId,
    required int monthlyPrice,
  }) async {
    final trimmed = await _validate(name, levelId, monthlyPrice, exceptId: id);
    return writer.patch(
      db.subjects,
      key: {'id': id},
      values: {
        'name': trimmed,
        'level_id': levelId,
        'monthly_price': monthlyPrice,
      },
    );
  }

  /// حذف ناعم؛ المجموعات والتلاميذ المرتبطون يحتفظون بالمادة في سجلاتهم.
  Future<bool> remove(String id) =>
      writer.softDelete(db.subjects, key: {'id': id});

  /// مادة السنة [levelId] التي تحمل اسم المادة [subjectId]: فلكل فوج مادته الخاصة وسنته الدراسية، ولا فوج
  /// «لكل المستويات». إن كانت [subjectId] مادة عامة (بلا سنة) أُعيدت مادة بالاسم نفسه لتلك السنة: الموجودة
  /// إن وُجدت، وإلا تُنشأ بسعر المادة العامة، ويُعطى أساتذةُ المادة العامة تدريسها كذلك (من يدرّس الرياضيات
  /// يدرّسها لكل سنة). ومادة لها سنة أصلاً تُعاد كما هي إن طابقت [levelId] وإلا يُرفض الطلب.
  Future<SubjectRow> ensureForLevel(String subjectId, String levelId) {
    return db.transaction(() async {
      final general =
          await (db.select(db.subjects)
                ..where((s) => s.id.equals(subjectId) & s.deletedAt.isNull()))
              .getSingleOrNull();
      if (general == null) {
        throw ValidationException.field(fieldName, 'المادة غير موجودة');
      }
      if (general.levelId != null) {
        if (general.levelId == levelId) return general;
        throw ValidationException.field(
          fieldLevel,
          'هذه المادة مرتبطة بسنة دراسية أخرى',
        );
      }
      final level =
          await (db.select(db.levels)
                ..where((l) => l.id.equals(levelId) & l.deletedAt.isNull()))
              .getSingleOrNull();
      if (level == null) {
        throw ValidationException.field(fieldLevel, 'اختر السنة الدراسية');
      }
      final existing =
          await (db.select(db.subjects)..where(
                (s) =>
                    s.name.equals(general.name) &
                    s.levelId.equals(levelId) &
                    s.deletedAt.isNull(),
              ))
              .get();
      final specific = existing.isNotEmpty
          ? existing.first
          : await add(
              name: general.name,
              levelId: levelId,
              monthlyPrice: general.monthlyPrice,
            );
      final teachers =
          await (db.select(db.teacherSubjects)..where(
                (t) => t.subjectId.equals(general.id) & t.deletedAt.isNull(),
              ))
              .get();
      final linked = {
        for (final row in await (db.select(
          db.teacherSubjects,
        )..where((t) => t.subjectId.equals(specific.id))).get())
          if (row.deletedAt == null) row.teacherId,
      };
      for (final link in teachers) {
        if (linked.contains(link.teacherId)) continue;
        await writer.save(
          db.teacherSubjects,
          TeacherSubjectsCompanion.insert(
            teacherId: link.teacherId,
            subjectId: specific.id,
            updatedAt: 0,
            deletedAt: const Value(null),
          ),
          key: {'teacher_id': link.teacherId, 'subject_id': specific.id},
        );
      }
      return specific;
    });
  }

  Future<String> _validate(
    String name,
    String? levelId,
    int price, {
    String? exceptId,
  }) async {
    final errors = <String, String>{};
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      errors[fieldName] = 'أدخل اسم المادة';
    }
    if (price < 0) {
      errors[fieldPrice] = 'السعر لا يكون سالباً';
    } else if (price % 10 != 0) {
      errors[fieldPrice] = 'السعر من مضاعفات 10 دج';
    }
    if (trimmed.isNotEmpty) {
      final clash =
          await (db.select(db.subjects)..where(
                (t) =>
                    t.name.equals(trimmed) &
                    t.deletedAt.isNull() &
                    (levelId == null
                        ? t.levelId.isNull()
                        : t.levelId.equals(levelId)),
              ))
              .get();
      if (clash.any((r) => r.id != exceptId)) {
        errors[fieldName] = levelId == null
            ? 'توجد مادة بهذا الاسم'
            : 'توجد مادة بهذا الاسم في هذا المستوى';
      }
    }
    if (errors.isNotEmpty) throw ValidationException(errors);
    return trimmed;
  }
}

/// القاعات: اسم وسعة (عدد المقاعد).
class RoomService {
  RoomService(this.db, this.writer);

  final AppDatabase db;
  final SyncWriter writer;

  static const String fieldName = 'name';
  static const String fieldCapacity = 'capacity';

  /// القاعات الحية مرتبة بالاسم.
  Stream<List<RoomRow>> watchAll() {
    final query = db.select(db.rooms)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.asc(t.name)]);
    return query.watch();
  }

  Future<RoomRow> add({required String name, required int capacity}) async {
    final trimmed = await _validate(name, capacity);
    final id = writer.newId();
    await writer.save(
      db.rooms,
      RoomsCompanion.insert(
        id: id,
        createdAt: 0,
        updatedAt: 0,
        name: trimmed,
        capacity: Value(capacity),
      ),
      key: {'id': id},
    );
    return (db.select(db.rooms)..where((t) => t.id.equals(id))).getSingle();
  }

  Future<bool> update(
    String id, {
    required String name,
    required int capacity,
  }) async {
    final trimmed = await _validate(name, capacity, exceptId: id);
    return writer.patch(
      db.rooms,
      key: {'id': id},
      values: {'name': trimmed, 'capacity': capacity},
    );
  }

  /// حذف ناعم؛ الحصص والمجموعات التي استعملتها تحتفظ باسمها.
  Future<bool> remove(String id) =>
      writer.softDelete(db.rooms, key: {'id': id});

  Future<String> _validate(
    String name,
    int capacity, {
    String? exceptId,
  }) async {
    final errors = <String, String>{};
    final trimmed = name.trim();
    if (trimmed.isEmpty) errors[fieldName] = 'أدخل اسم القاعة';
    // السعة صفر لا تسع أحداً فلا تُقترح القاعة أبداً.
    if (capacity < 1) errors[fieldCapacity] = 'السعة 1 على الأقل';
    if (capacity > 500) errors[fieldCapacity] = 'السعة 500 على الأكثر';
    if (trimmed.isNotEmpty) {
      final clash = await (db.select(
        db.rooms,
      )..where((t) => t.name.equals(trimmed) & t.deletedAt.isNull())).get();
      if (clash.any((r) => r.id != exceptId)) {
        errors[fieldName] = 'توجد قاعة بهذا الاسم';
      }
    }
    if (errors.isNotEmpty) throw ValidationException(errors);
    return trimmed;
  }
}
