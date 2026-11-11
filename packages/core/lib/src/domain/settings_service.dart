import 'package:drift/drift.dart';

import '../data/local/app_database.dart';
import '../data/local/sync_writer.dart';
import 'enums.dart';
import 'school_settings.dart';
import 'stable_id.dart';

/// إعدادات غير صالحة: مفتاح الإعداد ← رسالة الخطأ بالعربية.
class SettingsValidationException implements Exception {
  const SettingsValidationException(this.errors);

  final Map<String, String> errors;

  @override
  String toString() => errors.values.join('، ');
}

/// قراءة إعدادات المدرسة وحفظها. الكتابة عبر `SyncWriter` فتصل كل الأجهزة.
class SettingsService {
  SettingsService(this.db, this.writer);

  final AppDatabase db;
  final SyncWriter writer;

  /// الإعدادات الحالية (الافتراضية لما لم يُحفظ).
  Future<SchoolSettings> load() async {
    final rows = await db.select(db.settings).get();
    return SchoolSettings.fromMap({for (final r in rows) r.key: r.value});
  }

  /// الإعدادات وتتحدث مع كل تغيير (حتى القادم من جهاز آخر).
  Stream<SchoolSettings> watch() => db
      .select(db.settings)
      .watch()
      .map(
        (rows) =>
            SchoolSettings.fromMap({for (final r in rows) r.key: r.value}),
      );

  /// يحفظ ما تغيّر فقط. يرمي [SettingsValidationException] إن كانت القيم غير
  /// صالحة، فلا يُكتب شيء.
  Future<void> save(SchoolSettings settings) async {
    final errors = settings.validate();
    if (errors.isNotEmpty) throw SettingsValidationException(errors);
    final current = await db.select(db.settings).get();
    final stored = {for (final r in current) r.key: r.value};
    final wanted = settings.toMap();
    final changed = [
      for (final entry in wanted.entries)
        if (stored[entry.key] != entry.value) entry,
    ];
    if (changed.isEmpty) return;
    await db.transaction(() async {
      for (final entry in changed) {
        await writer.save(
          db.settings,
          SettingsCompanion.insert(
            key: entry.key,
            value: entry.value,
            updatedAt: writer.now(),
          ),
          key: {'key': entry.key},
        );
      }
    });
  }
}

/// المستويات الدراسية: الافتراضية عند أول تشغيل، ثم قابلة للتعديل.
class LevelService {
  LevelService(this.db, this.writer);

  final AppDatabase db;
  final SyncWriter writer;

  /// ترتيب الطور في الفرز: كل طور في مئة، وسنواته بعد ذلك.
  static int _base(EducationStage stage) => (stage.index + 1) * 100;

  /// يضيف المستويات الافتراضية (ابتدائي 1–5، متوسط 1–4، ثانوي 1–3) مرة واحدة.
  ///
  /// من حذف مستوى افتراضياً لا يعود إليه عند إعادة التشغيل. وجهازان يبدآن
  /// دون إنترنت ينتجان نفس المعرّفات فيندمجان عند المزامنة.
  Future<void> ensureDefaults() async {
    final seeded = await (db.select(
      db.settings,
    )..where((t) => t.key.equals(_seededKey))).getSingleOrNull();
    if (seeded != null) return;
    final existing = await (db.select(db.levels)).get();
    await db.transaction(() async {
      if (existing.isEmpty) {
        for (final stage in EducationStage.values) {
          for (var grade = 1; grade <= stage.defaultGrades; grade++) {
            final id = StableId.defaultLevel(stage.code, grade);
            await writer.save(
              db.levels,
              LevelsCompanion.insert(
                id: id,
                createdAt: 0,
                updatedAt: 0,
                name: '$grade ${stage.label}',
                stage: stage.code,
                sortOrder: _base(stage) + grade,
              ),
              key: {'id': id},
            );
          }
        }
      }
      await writer.save(
        db.settings,
        SettingsCompanion.insert(
          key: _seededKey,
          value: '1',
          updatedAt: writer.now(),
        ),
        key: {'key': _seededKey},
      );
    });
  }

  static const String _seededKey = 'levels_seeded';

  /// المستويات الحية مرتبة بالطور ثم السنة.
  Stream<List<LevelRow>> watchAll() {
    final query = db.select(db.levels)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]);
    return query.watch();
  }

  /// يضيف مستوى جديداً في آخر طوره. يرمي [ArgumentError] إن كان الاسم فارغاً
  /// أو مكرراً.
  Future<LevelRow> add({
    required String name,
    required EducationStage stage,
  }) async {
    final trimmed = name.trim();
    await _checkName(trimmed);
    final range = await (db.select(
      db.levels,
    )..where((t) => t.stage.equals(stage.code) & t.deletedAt.isNull())).get();
    final top = range.fold<int>(
      _base(stage),
      (max, r) => r.sortOrder > max ? r.sortOrder : max,
    );
    final id = writer.newId();
    await writer.save(
      db.levels,
      LevelsCompanion.insert(
        id: id,
        createdAt: 0,
        updatedAt: 0,
        name: trimmed,
        stage: stage.code,
        sortOrder: top + 1,
      ),
      key: {'id': id},
    );
    return (db.select(db.levels)..where((t) => t.id.equals(id))).getSingle();
  }

  /// يغيّر اسم مستوى. يعيد `false` إن لم يوجد.
  Future<bool> rename(String id, String name) async {
    final trimmed = name.trim();
    await _checkName(trimmed, exceptId: id);
    return writer.patch(db.levels, key: {'id': id}, values: {'name': trimmed});
  }

  /// حذف ناعم؛ التلاميذ والمواد المرتبطة تحتفظ باسم المستوى في سجلاتها.
  Future<bool> remove(String id) =>
      writer.softDelete(db.levels, key: {'id': id});

  Future<void> _checkName(String name, {String? exceptId}) async {
    if (name.isEmpty) throw ArgumentError('أدخل اسم المستوى');
    final clash = await (db.select(
      db.levels,
    )..where((t) => t.name.equals(name) & t.deletedAt.isNull())).get();
    if (clash.any((r) => r.id != exceptId)) {
      throw ArgumentError('يوجد مستوى بهذا الاسم');
    }
  }
}
