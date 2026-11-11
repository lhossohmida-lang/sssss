import 'package:drift/drift.dart';

import '../data/local/app_database.dart';
import '../data/local/sync_writer.dart';
import 'account_service.dart';
import 'catalog_service.dart';
import 'enums.dart';
import 'phone.dart';
import 'qr_code.dart';

/// أستاذ مع أسماء مواده لعرضه في القوائم.
class TeacherItem {
  const TeacherItem({required this.teacher, required this.subjectNames});

  final TeacherRow teacher;
  final List<String> subjectNames;

  String get id => teacher.id;
  String get name => teacher.name;
}

/// نتيجة إضافة أستاذ: صفه وبيانات حسابه (تُعرض للمدير مرة واحدة).
class TeacherCreated {
  const TeacherCreated({required this.teacher, required this.account});

  final TeacherRow teacher;
  final ProvisionedAccount account;
}

/// الأساتذة: إضافة (مع حسابه ورمز QR ورسالة بياناته)، تعديل، وحذف.
class TeacherService {
  TeacherService(this.db, this.writer, this.accounts);

  final AppDatabase db;
  final SyncWriter writer;
  final AccountService accounts;

  static const String fieldName = 'name';
  static const String fieldPhone = AccountService.fieldPhone;
  static const String fieldRate = 'rate';

  /// الأساتذة الأحياء مع أسماء موادهم، مرتبين بالاسم.
  Stream<List<TeacherItem>> watchAll() {
    return db
        .customSelect(
          'SELECT t.*, (SELECT group_concat(s.name, \'|\') '
          'FROM teacher_subjects ts JOIN subjects s ON s.id = ts.subject_id '
          'WHERE ts.teacher_id = t.id AND ts.deleted_at IS NULL '
          'AND s.deleted_at IS NULL) AS subject_names '
          'FROM teachers t WHERE t.deleted_at IS NULL ORDER BY t.name',
          readsFrom: {db.teachers, db.teacherSubjects, db.subjects},
        )
        .watch()
        .map(
          (rows) => [
            for (final row in rows)
              TeacherItem(
                teacher: db.teachers.map(row.data),
                subjectNames: (row.read<String?>('subject_names') ?? '')
                    .split('|')
                    .where((n) => n.isNotEmpty)
                    .toList(),
              ),
          ],
        );
  }

  /// معرّفات مواد الأستاذ الحالية.
  Future<Set<String>> subjectIdsOf(String teacherId) async {
    final rows =
        await (db.select(db.teacherSubjects)..where(
              (t) => t.teacherId.equals(teacherId) & t.deletedAt.isNull(),
            ))
            .get();
    return {for (final r in rows) r.subjectId};
  }

  /// يضيف أستاذاً وحسابه ويضع رسالة بيانات الدخول في الطابور.
  ///
  /// يرمي [ValidationException] إن كانت البيانات غير صالحة أو الهاتف مستعملاً.
  Future<TeacherCreated> add({
    required String name,
    required String phone,
    required Set<String> subjectIds,
    required int ratePerStudent,
  }) async {
    final trimmed = name.trim();
    final errors = <String, String>{};
    if (trimmed.isEmpty) errors[fieldName] = 'أدخل اسم الأستاذ';
    final rateError = _rateError(ratePerStudent);
    if (rateError != null) errors[fieldRate] = rateError;
    String email = '';
    try {
      email = AccountService.emailFor(phone);
    } on ValidationException catch (e) {
      errors.addAll(e.errors);
    }
    if (errors.isEmpty && await accounts.findByEmail(email) != null) {
      errors[fieldPhone] = 'رقم الهاتف مستعمل في حساب آخر';
    }
    if (errors.isNotEmpty) throw ValidationException(errors);

    final teacherId = writer.newId();
    final account = await accounts.create(
      role: UserRole.teacher,
      entityId: teacherId,
      displayName: trimmed,
      phone: phone,
    );
    final qr = await _uniqueQr();
    await db.transaction(() async {
      await writer.save(
        db.teachers,
        TeachersCompanion.insert(
          id: teacherId,
          createdAt: 0,
          updatedAt: 0,
          name: trimmed,
          phone: PhoneNumbers.normalize(phone),
          email: email,
          qrCode: qr,
          ratePerStudent: Value(ratePerStudent),
          authUserId: Value(account.accountId),
        ),
        key: {'id': teacherId},
      );
      await _linkSubjects(teacherId, subjectIds);
    });
    final row = await (db.select(
      db.teachers,
    )..where((t) => t.id.equals(teacherId))).getSingle();
    return TeacherCreated(teacher: row, account: account);
  }

  /// يعدّل بيانات الأستاذ ومواده. بريد الدخول لا يتغير مع الهاتف.
  /// يعيد `false` إن لم يوجد.
  Future<bool> update(
    String id, {
    required String name,
    required String phone,
    required Set<String> subjectIds,
    required int ratePerStudent,
  }) async {
    final trimmed = name.trim();
    final errors = <String, String>{};
    if (trimmed.isEmpty) errors[fieldName] = 'أدخل اسم الأستاذ';
    if (!PhoneNumbers.isValid(phone)) {
      errors[fieldPhone] = 'رقم الهاتف يبدأ بـ 05 أو 06 أو 07 ويتبعه 8 أرقام';
    }
    final rateError = _rateError(ratePerStudent);
    if (rateError != null) errors[fieldRate] = rateError;
    if (errors.isNotEmpty) throw ValidationException(errors);

    return db.transaction(() async {
      final changed = await writer.patch(
        db.teachers,
        key: {'id': id},
        values: {
          'name': trimmed,
          'phone': PhoneNumbers.normalize(phone),
          'rate_per_student': ratePerStudent,
        },
      );
      if (!changed) return false;
      await _linkSubjects(id, subjectIds);
      // اسم الحساب يتبع اسم الأستاذ.
      final account =
          await (db.select(db.userAccounts)
                ..where((t) => t.entityId.equals(id) & t.deletedAt.isNull()))
              .getSingleOrNull();
      if (account != null && account.displayName != trimmed) {
        await writer.patch(
          db.userAccounts,
          key: {'id': account.id},
          values: {'display_name': trimmed},
        );
      }
      return true;
    });
  }

  /// يحذف الأستاذ (ناعماً) ويعطّل حسابه. يرمي [ValidationException] إن كانت
  /// له مجموعات نشطة، فتُنقل أو تُؤرشف أولاً.
  Future<bool> remove(String id) async {
    final active = await db
        .customSelect(
          'SELECT COUNT(*) AS n FROM groups WHERE teacher_id = ? '
          'AND deleted_at IS NULL AND archived_at IS NULL',
          variables: [Variable<String>(id)],
          readsFrom: {db.groups},
        )
        .getSingle();
    final count = active.read<int>('n');
    if (count > 0) {
      throw ValidationException.field(
        'groups',
        'للأستاذ $count مجموعة نشطة؛ انقلها أو أرشفها قبل الحذف',
      );
    }
    return db.transaction(() async {
      final removed = await writer.softDelete(db.teachers, key: {'id': id});
      if (!removed) return false;
      final account =
          await (db.select(db.userAccounts)
                ..where((t) => t.entityId.equals(id) & t.deletedAt.isNull()))
              .getSingleOrNull();
      if (account != null) await accounts.disable(account.id);
      return true;
    });
  }

  /// يعيد توليد كلمة سر الأستاذ ويرسلها له.
  Future<ProvisionedAccount> resetPassword(String teacherId) async {
    final account =
        await (db.select(db.userAccounts)..where(
              (t) => t.entityId.equals(teacherId) & t.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    if (account == null) {
      throw ValidationException.field('account', 'لا حساب لهذا الأستاذ');
    }
    return accounts.resetPassword(account.id);
  }

  String? _rateError(int rate) {
    if (rate < 0) return 'المبلغ لا يكون سالباً';
    if (rate % 10 != 0) return 'المبلغ من مضاعفات 10 دج';
    return null;
  }

  /// رمز QR غير مستعمل (الفهرس فريد، والتصادم شبه مستحيل لكن يُفحص).
  Future<String> _uniqueQr() async {
    for (var i = 0; i < 10; i++) {
      final code = QrCodes.generate(QrOwnerKind.teacher);
      final clash = await (db.select(
        db.teachers,
      )..where((t) => t.qrCode.equals(code))).get();
      if (clash.isEmpty) return code;
    }
    throw StateError('تعذّر توليد رمز QR فريد');
  }

  /// يجعل مواد الأستاذ مطابقة لـ [wanted]: تُضاف الجديدة (أو تُعاد المحذوفة)
  /// وتُحذف ناعماً ما أُزيل.
  Future<void> _linkSubjects(String teacherId, Set<String> wanted) async {
    final rows = await (db.select(
      db.teacherSubjects,
    )..where((t) => t.teacherId.equals(teacherId))).get();
    final live = {
      for (final r in rows)
        if (r.deletedAt == null) r.subjectId,
    };
    for (final subjectId in wanted.difference(live)) {
      await writer.save(
        db.teacherSubjects,
        TeacherSubjectsCompanion.insert(
          teacherId: teacherId,
          subjectId: subjectId,
          updatedAt: 0,
          deletedAt: const Value(null),
        ),
        key: {'teacher_id': teacherId, 'subject_id': subjectId},
      );
    }
    for (final subjectId in live.difference(wanted)) {
      await writer.softDelete(
        db.teacherSubjects,
        key: {'teacher_id': teacherId, 'subject_id': subjectId},
      );
    }
  }
}
