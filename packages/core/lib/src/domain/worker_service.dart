import 'package:drift/drift.dart';

import '../auth/permissions.dart';
import '../data/local/app_database.dart';
import '../data/local/sync_writer.dart';
import 'account_service.dart';
import 'catalog_service.dart';
import 'enums.dart';
import 'money.dart';
import 'phone.dart';
import 'qr_code.dart';
import 'wage_service.dart';

/// عامل في القائمة.
class WorkerItem {
  const WorkerItem({required this.worker});

  final WorkerRow worker;

  String get id => worker.id;
  String get name => worker.name;

  /// برنامجه الأسبوعي.
  WorkerSchedule get schedule => WorkerSchedule.fromJson(worker.weeklySchedule);

  /// صلاحياته.
  WorkerPermissions get permissions =>
      WorkerPermissions.decode(worker.permissions);

  /// عدد أيام عمله في الأسبوع (يوم كامل أو نصف).
  int get workDays => [
    for (var d = 1; d <= 7; d++)
      if (schedule.kindOn(d) != WorkDayKind.off) d,
  ].length;
}

/// نتيجة إضافة عامل: صفه وبيانات حسابه (تُعرض للمدير مرة واحدة).
class WorkerCreated {
  const WorkerCreated({required this.worker, required this.account});

  final WorkerRow worker;
  final ProvisionedAccount account;
}

/// العمال: إضافة (مع حسابه ورمز QR ورسالة بياناته)، تعديل أجرَيه وبرنامجه،
/// ضبط صلاحياته، وحذفه.
class WorkerService {
  WorkerService(this.db, this.writer, this.accounts);

  final AppDatabase db;
  final SyncWriter writer;
  final AccountService accounts;

  static const String fieldName = 'name';
  static const String fieldPhone = AccountService.fieldPhone;
  static const String fieldFullWage = 'full_wage';
  static const String fieldHalfWage = 'half_wage';
  static const String fieldHours = 'hours';
  static const String fieldSchedule = 'schedule';

  /// العمال الأحياء مرتبين بالاسم، ولحظياً.
  Stream<List<WorkerItem>> watchAll() {
    final query = db.select(db.workers)
      ..where((w) => w.deletedAt.isNull())
      ..orderBy([(w) => OrderingTerm.asc(w.name)]);
    return query.watch().map(
      (rows) => [for (final row in rows) WorkerItem(worker: row)],
    );
  }

  /// أخطاء بيانات العامل: اسم الحقل ← الرسالة. فارغة إن كانت سليمة.
  static Map<String, String> validate({
    required String name,
    required int fullDayWage,
    required int halfDayWage,
    required int startMinutes,
    required int endMinutes,
    required WorkerSchedule schedule,
  }) {
    final errors = <String, String>{};
    if (name.trim().isEmpty) errors[fieldName] = 'أدخل اسم العامل';
    final fullError = _wageError(fullDayWage);
    if (fullError != null) errors[fieldFullWage] = fullError;
    final halfError = _wageError(halfDayWage);
    if (halfError != null) {
      errors[fieldHalfWage] = halfError;
    } else if (halfDayWage > fullDayWage && fullError == null) {
      errors[fieldHalfWage] = 'أجر نصف اليوم لا يزيد عن أجر اليوم الكامل';
    }
    if (startMinutes < 0 ||
        endMinutes > 24 * 60 ||
        endMinutes <= startMinutes) {
      errors[fieldHours] = 'نهاية العمل تكون بعد بدايته';
    }
    final workDays = [
      for (var d = 1; d <= 7; d++)
        if (schedule.kindOn(d) != WorkDayKind.off) d,
    ];
    if (workDays.isEmpty) {
      errors[fieldSchedule] = 'اختر يوم عمل واحداً على الأقل';
    }
    return errors;
  }

  /// يضيف عاملاً وحسابه ويضع رسالة بيانات الدخول في الطابور.
  ///
  /// يرمي [ValidationException] إن كانت البيانات غير صالحة أو الهاتف مستعملاً.
  Future<WorkerCreated> add({
    required String name,
    required String phone,
    required int fullDayWage,
    required int halfDayWage,
    required WorkerSchedule schedule,
    int startMinutes = 480,
    int endMinutes = 1020,
    WorkerPermissions permissions = WorkerPermissions.none,
  }) async {
    final errors = validate(
      name: name,
      fullDayWage: fullDayWage,
      halfDayWage: halfDayWage,
      startMinutes: startMinutes,
      endMinutes: endMinutes,
      schedule: schedule,
    );
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

    final workerId = writer.newId();
    final trimmed = name.trim();
    final account = await accounts.create(
      role: UserRole.worker,
      entityId: workerId,
      displayName: trimmed,
      phone: phone,
    );
    final qr = await _uniqueQr();
    await writer.save(
      db.workers,
      WorkersCompanion.insert(
        id: workerId,
        createdAt: 0,
        updatedAt: 0,
        name: trimmed,
        phone: PhoneNumbers.normalize(phone),
        email: email,
        qrCode: qr,
        expectedStartMinutes: Value(startMinutes),
        expectedEndMinutes: Value(endMinutes),
        fullDayWage: Value(fullDayWage),
        halfDayWage: Value(halfDayWage),
        weeklySchedule: Value(schedule.toJson()),
        permissions: Value(permissions.encode()),
        authUserId: Value(account.accountId),
      ),
      key: {'id': workerId},
    );
    final row = await (db.select(
      db.workers,
    )..where((w) => w.id.equals(workerId))).getSingle();
    return WorkerCreated(worker: row, account: account);
  }

  /// يعدّل بيانات العامل وأجرَيه وبرنامجه. بريد الدخول لا يتغير مع الهاتف.
  /// يعيد `false` إن لم يوجد.
  Future<bool> update(
    String id, {
    required String name,
    required String phone,
    required int fullDayWage,
    required int halfDayWage,
    required WorkerSchedule schedule,
    required int startMinutes,
    required int endMinutes,
  }) async {
    final errors = validate(
      name: name,
      fullDayWage: fullDayWage,
      halfDayWage: halfDayWage,
      startMinutes: startMinutes,
      endMinutes: endMinutes,
      schedule: schedule,
    );
    if (!PhoneNumbers.isValid(phone)) {
      errors[fieldPhone] = 'رقم الهاتف يبدأ بـ 05 أو 06 أو 07 ويتبعه 8 أرقام';
    }
    if (errors.isNotEmpty) throw ValidationException(errors);

    final trimmed = name.trim();
    return db.transaction(() async {
      final changed = await writer.patch(
        db.workers,
        key: {'id': id},
        values: {
          'name': trimmed,
          'phone': PhoneNumbers.normalize(phone),
          'full_day_wage': fullDayWage,
          'half_day_wage': halfDayWage,
          'weekly_schedule': schedule.toJson(),
          'expected_start_minutes': startMinutes,
          'expected_end_minutes': endMinutes,
        },
      );
      if (!changed) return false;
      final account = await _account(id);
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

  /// يضبط صلاحيات العامل. تسري على جلسته فور تجديد الجلسة. يعيد `false` إن
  /// لم يوجد.
  Future<bool> setPermissions(String id, WorkerPermissions permissions) {
    return writer.patch(
      db.workers,
      key: {'id': id},
      values: {'permissions': permissions.encode()},
      action: 'set_permissions',
    );
  }

  /// يحذف العامل (ناعماً) ويعطّل حسابه؛ تبقى سجلات حضوره وأجره.
  Future<bool> remove(String id) {
    return db.transaction(() async {
      final removed = await writer.softDelete(db.workers, key: {'id': id});
      if (!removed) return false;
      final account = await _account(id);
      if (account != null) await accounts.disable(account.id);
      return true;
    });
  }

  /// يعيد توليد كلمة سر العامل ويرسلها له.
  Future<ProvisionedAccount> resetPassword(String workerId) async {
    final account = await _account(workerId);
    if (account == null) {
      throw ValidationException.field('account', 'لا حساب لهذا العامل');
    }
    return accounts.resetPassword(account.id);
  }

  Future<UserAccountRow?> _account(String workerId) =>
      (db.select(db.userAccounts)
            ..where((a) => a.entityId.equals(workerId) & a.deletedAt.isNull()))
          .getSingleOrNull();

  static String? _wageError(int wage) {
    if (wage < 0) return 'الأجر لا يكون سالباً';
    if (wage % 10 != 0) return 'الأجر من مضاعفات 10 ${Money.currency}';
    return null;
  }

  /// رمز QR غير مستعمل (الفهرس فريد، والتصادم شبه مستحيل لكن يُفحص).
  Future<String> _uniqueQr() async {
    for (var i = 0; i < 10; i++) {
      final code = QrCodes.generate(QrOwnerKind.worker);
      final clash = await (db.select(
        db.workers,
      )..where((w) => w.qrCode.equals(code))).get();
      if (clash.isEmpty) return code;
    }
    throw StateError('تعذّر توليد رمز QR فريد');
  }
}
