import 'package:drift/drift.dart';

import '../auth/account_provisioner.dart';
import '../auth/credentials.dart';
import '../data/local/app_database.dart';
import '../data/local/sync_writer.dart';
import 'catalog_service.dart';
import 'enums.dart';
import 'phone.dart';
import 'setting_keys.dart';
import 'sms_templates.dart';

/// حساب دخول أُنشئ للتو: بياناته تُعرض للمدير مرة واحدة وتُرسل برسالة.
class ProvisionedAccount {
  const ProvisionedAccount({
    required this.accountId,
    required this.email,
    required this.password,
    required this.created,
    this.smsQueued = false,
  });

  final String accountId;
  final String email;

  /// كلمة السر المؤقتة؛ فارغة إن كان الحساب موجوداً من قبل ولم يُنشأ جديد.
  final String password;

  /// `false` إن رُبط بحساب موجود (وليّ له أبناء سابقون بنفس الهاتف).
  final bool created;

  /// هل وُضعت رسالة بيانات الدخول في طابور الإرسال؟
  final bool smsQueued;
}

/// إنشاء حسابات الدخول لأصحابها (أستاذ، عامل، وليّ): بريد من رقم الهاتف،
/// كلمة سر عشوائية، صف في `user_accounts`، ورسالة SMS تحملهما (إجابة ب1).
class AccountService {
  AccountService(this.db, this.writer, this.provisioner);

  final AppDatabase db;
  final SyncWriter writer;
  final AccountProvisioner provisioner;

  /// حقل الهاتف في أخطاء التحقق.
  static const String fieldPhone = 'phone';

  /// يتحقق من الهاتف ويعيد بريد الدخول المبني منه، أو يرمي
  /// [ValidationException].
  static String emailFor(String phone) {
    if (!PhoneNumbers.isValid(phone)) {
      throw ValidationException.field(
        fieldPhone,
        'رقم الهاتف يبدأ بـ 05 أو 06 أو 07 ويتبعه 8 أرقام',
      );
    }
    return LoginCredentials.emailForPhone(phone);
  }

  /// الحساب الحي صاحب هذا البريد، أو `null`.
  Future<UserAccountRow?> findByEmail(String email) =>
      (db.select(db.userAccounts)
            ..where((t) => t.email.equals(email) & t.deletedAt.isNull()))
          .getSingleOrNull();

  /// ينشئ حساباً جديداً، أو يربط بالموجود إن كان [reuseExisting] ومن نفس
  /// الدور (وليّ أبنائه بنفس الهاتف).
  ///
  /// يرمي [ValidationException] إن كان الهاتف غير صالح أو مستعملاً في حساب
  /// آخر. الاتصال الخارجي (إنشاء المستخدم) يتم قبل الكتابة المحلية، فإن فشلت
  /// الكتابة بقي مستخدم بلا صف محلي، ويُعاد إنشاؤه بإعادة المحاولة.
  Future<ProvisionedAccount> create({
    required UserRole role,
    required String entityId,
    required String displayName,
    required String phone,
    bool reuseExisting = false,
  }) async {
    final email = emailFor(phone);
    final existing = await findByEmail(email);
    if (existing != null) {
      if (reuseExisting && existing.role == role.code) {
        return ProvisionedAccount(
          accountId: existing.id,
          email: email,
          password: '',
          created: false,
        );
      }
      throw ValidationException.field(
        fieldPhone,
        'رقم الهاتف مستعمل في حساب آخر',
      );
    }

    final credentials = LoginCredentials.generateFor(phone);
    final accountId = await provisioner.provision(
      email: credentials.email,
      password: credentials.password,
      role: role,
    );
    final message = await _message(
      SmsTemplateKeys.accountCreated,
      name: displayName,
      credentials: credentials,
    );
    await db.transaction(() async {
      final now = writer.now();
      await writer.save(
        db.userAccounts,
        UserAccountsCompanion.insert(
          id: accountId,
          createdAt: now,
          updatedAt: now,
          email: credentials.email,
          role: role.code,
          entityId: Value(entityId),
          displayName: Value(displayName),
          mustChangePassword: const Value(true),
        ),
        key: {'id': accountId},
      );
      await _queueSms(phone, message, SmsTemplateKeys.accountCreated);
    });
    return ProvisionedAccount(
      accountId: accountId,
      email: credentials.email,
      password: credentials.password,
      created: true,
      smsQueued: true,
    );
  }

  /// يولّد كلمة سر جديدة لحساب ويرسلها لصاحبه، ويجعله يغيّرها عند الدخول.
  Future<ProvisionedAccount> resetPassword(String accountId) async {
    final account =
        await (db.select(db.userAccounts)
              ..where((t) => t.id.equals(accountId) & t.deletedAt.isNull()))
            .getSingleOrNull();
    if (account == null) {
      throw ArgumentError.value(accountId, 'accountId', 'حساب غير موجود');
    }
    final phone = await _phoneOf(account);
    final password = LoginCredentials.generatePassword();
    await provisioner.resetPassword(accountId: accountId, password: password);
    final message = await _message(
      SmsTemplateKeys.passwordReset,
      name: account.displayName,
      credentials: GeneratedCredentials(
        email: account.email,
        password: password,
      ),
    );
    await db.transaction(() async {
      await writer.patch(
        db.userAccounts,
        key: {'id': accountId},
        values: {'must_change_password': 1},
      );
      if (phone != null) {
        await _queueSms(phone, message, SmsTemplateKeys.passwordReset);
      }
    });
    return ProvisionedAccount(
      accountId: accountId,
      email: account.email,
      password: password,
      created: false,
      smsQueued: phone != null,
    );
  }

  /// يعطّل الحساب (حذف ناعم): لا يدخل صاحبه بعد الآن.
  Future<bool> disable(String accountId) =>
      writer.softDelete(db.userAccounts, key: {'id': accountId});

  /// رقم هاتف صاحب الحساب من جدول دوره.
  Future<String?> _phoneOf(UserAccountRow account) async {
    final entityId = account.entityId;
    if (entityId == null) return null;
    final table = switch (UserRole.fromCode(account.role)) {
      UserRole.teacher => 'teachers',
      UserRole.worker => 'workers',
      UserRole.parent => 'parents',
      UserRole.owner => null,
    };
    if (table == null) return null;
    final row = await db
        .customSelect(
          'SELECT phone FROM $table WHERE id = ?',
          variables: [Variable<String>(entityId)],
          readsFrom: {db.teachers, db.workers, db.parents},
        )
        .getSingleOrNull();
    return row?.read<String>('phone');
  }

  Future<String> _message(
    String key, {
    required String name,
    required GeneratedCredentials credentials,
  }) async {
    final school = await (db.select(
      db.settings,
    )..where((t) => t.key.equals(SettingKeys.schoolName))).getSingleOrNull();
    final schoolName = school?.value.trim() ?? '';
    return SmsTemplateRenderer(db).render(key, {
      'name': name,
      'school': schoolName.isEmpty ? 'المدرسة' : schoolName,
      'email': credentials.email,
      'password': credentials.password,
    });
  }

  Future<void> _queueSms(String phone, String message, String kind) async {
    final stamp = writer.now();
    final id = writer.newId();
    await writer.save(
      db.smsQueue,
      SmsQueueCompanion.insert(
        id: id,
        createdAt: stamp,
        updatedAt: stamp,
        phone: PhoneNumbers.toInternational(phone),
        message: message,
        status: Value(SmsStatus.pending.code),
        kind: Value(kind),
        createdBy: Value(writer.actor().userId),
      ),
      key: {'id': id},
    );
  }
}
