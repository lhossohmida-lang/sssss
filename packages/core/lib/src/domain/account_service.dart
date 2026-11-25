import 'package:drift/drift.dart';

import '../auth/account_provisioner.dart';
import '../auth/auth_gateway.dart';
import '../auth/credentials.dart';
import '../data/local/app_database.dart';
import '../data/local/sync_writer.dart';
import 'catalog_service.dart';
import 'enums.dart';
import 'phone.dart';
import 'setting_keys.dart';
import 'sms_kind_policy.dart';
import 'sms_templates.dart';

/// حساب دخول أُنشئ للتو: بياناته تُعرض للمدير مرة واحدة وتُرسل برسالة.
class ProvisionedAccount {
  const ProvisionedAccount({
    required this.accountId,
    required this.email,
    required this.password,
    required this.created,
    this.smsQueued = false,
    this.pending = false,
  });

  final String accountId;
  final String email;

  /// كلمة السر المؤقتة؛ فارغة إن كان الحساب موجوداً من قبل ولم يُنشأ جديد.
  final String password;

  /// `false` إن رُبط بحساب موجود (وليّ له أبناء سابقون بنفس الهاتف).
  final bool created;

  /// هل وُضعت رسالة بيانات الدخول في طابور الإرسال؟
  final bool smsQueued;

  /// `true`: لا إنترنت الآن، فحُفظ كل شيء محلياً ويُنشأ الحساب على الخادم (أو تُغيَّر كلمة سره)
  /// وتُرسل رسالته وحدها عند عودة الاتصال. كلمة السر المعروضة هي التي ستُعتمد.
  final bool pending;
}

/// نتيجة معالجة طابور الحسابات المنتظرة.
class PendingAccountsReport {
  const PendingAccountsReport({this.done = 0, this.left = 0, this.blocked = 0});

  final int done;
  final int left;
  final int blocked;
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

  static const String _create = 'create';
  static const String _reset = 'reset';

  /// الحساب الحي صاحب هذا البريد، أو `null`. يشمل حساباً أُنشئ دون إنترنت ولم يصل الخادم بعد.
  Future<UserAccountRow?> findByEmail(String email) async {
    final row =
        await (db.select(db.userAccounts)
              ..where((t) => t.email.equals(email) & t.deletedAt.isNull()))
            .getSingleOrNull();
    if (row != null) return row;
    final pending = await _pendingCreate(email);
    if (pending == null) return null;
    return UserAccountRow(
      id: pending.id,
      createdAt: pending.createdAt,
      updatedAt: pending.createdAt,
      email: pending.email,
      role: pending.role,
      entityId: pending.entityId,
      displayName: pending.displayName,
      mustChangePassword: true,
    );
  }

  Future<PendingAccountRow?> _pendingCreate(String email) =>
      (db.select(db.pendingAccounts)
            ..where((t) => t.email.equals(email) & t.kind.equals(_create))
            ..limit(1))
          .getSingleOrNull();

  /// عدد الحسابات التي تنتظر الخادم (للعرض).
  Stream<int> watchPendingCount() => db.pendingAccounts.count().watchSingle();

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
    final requestedId = writer.newId();
    final String accountId;
    try {
      accountId = await provisioner.provision(
        email: credentials.email,
        password: credentials.password,
        role: role,
        id: requestedId,
      );
    } on AuthFailureException catch (e) {
      if (e.failure != AuthFailure.network) rethrow;
      // دون إنترنت: يُحفظ الحساب محلياً بمعرّفه المطلوب، ويُنشأ على الخادم بعد عودة الاتصال.
      await db
          .into(db.pendingAccounts)
          .insert(
            PendingAccountsCompanion.insert(
              id: requestedId,
              kind: _create,
              email: credentials.email,
              password: credentials.password,
              role: role.code,
              entityId: Value(entityId),
              displayName: Value(displayName),
              createdAt: writer.now(),
            ),
          );
      return ProvisionedAccount(
        accountId: requestedId,
        email: credentials.email,
        password: credentials.password,
        created: true,
        pending: true,
      );
    }
    final message = await _message(
      SmsTemplateKeys.accountCreated,
      name: displayName,
      credentials: credentials,
    );
    var smsQueued = false;
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
      smsQueued = await _queueSms(
        phone,
        message,
        SmsTemplateKeys.accountCreated,
      );
    });
    return ProvisionedAccount(
      accountId: accountId,
      email: credentials.email,
      password: credentials.password,
      created: true,
      smsQueued: smsQueued,
    );
  }

  /// يولّد كلمة سر جديدة لحساب ويرسلها لصاحبه، ويجعله يغيّرها عند الدخول.
  Future<ProvisionedAccount> resetPassword(String accountId) async {
    final password = LoginCredentials.generatePassword();
    // حساب لم يصل الخادم بعد: تتغير كلمة السر التي سيُنشأ بها.
    final waiting =
        await (db.select(db.pendingAccounts)
              ..where((t) => t.id.equals(accountId) & t.kind.equals(_create)))
            .getSingleOrNull();
    if (waiting != null) {
      await (db.update(db.pendingAccounts)
            ..where((t) => t.id.equals(accountId)))
          .write(PendingAccountsCompanion(password: Value(password)));
      return ProvisionedAccount(
        accountId: accountId,
        email: waiting.email,
        password: password,
        created: false,
        pending: true,
      );
    }
    final account =
        await (db.select(db.userAccounts)
              ..where((t) => t.id.equals(accountId) & t.deletedAt.isNull()))
            .getSingleOrNull();
    if (account == null) {
      throw ArgumentError.value(accountId, 'accountId', 'حساب غير موجود');
    }
    final phone = await _phoneOf(account);
    try {
      await provisioner.resetPassword(accountId: accountId, password: password);
    } on AuthFailureException catch (e) {
      if (e.failure != AuthFailure.network) rethrow;
      await db
          .into(db.pendingAccounts)
          .insertOnConflictUpdate(
            PendingAccountsCompanion.insert(
              id: accountId,
              kind: _reset,
              email: account.email,
              password: password,
              role: account.role,
              entityId: Value(account.entityId),
              displayName: Value(account.displayName),
              createdAt: writer.now(),
            ),
          );
      await writer.patch(
        db.userAccounts,
        key: {'id': accountId},
        values: {'must_change_password': 1},
      );
      return ProvisionedAccount(
        accountId: accountId,
        email: account.email,
        password: password,
        created: false,
        pending: true,
      );
    }
    final message = await _message(
      SmsTemplateKeys.passwordReset,
      name: account.displayName,
      credentials: GeneratedCredentials(
        email: account.email,
        password: password,
      ),
    );
    var smsQueued = false;
    await db.transaction(() async {
      await writer.patch(
        db.userAccounts,
        key: {'id': accountId},
        values: {'must_change_password': 1},
      );
      if (phone != null) {
        smsQueued = await _queueSms(
          phone,
          message,
          SmsTemplateKeys.passwordReset,
        );
      }
    });
    return ProvisionedAccount(
      accountId: accountId,
      email: account.email,
      password: password,
      created: false,
      smsQueued: smsQueued,
    );
  }

  /// ينشئ على الخادم ما أُنشئ دون إنترنت (ويغيّر كلمات السر المنتظرة)، بالترتيب. يتوقف عند أول
  /// انقطاع ويُعاد بعد الجولة التالية؛ والرفض النهائي (البريد مستعمل) يُعلَّم ولا يُعاد.
  /// تستدعيه المزامنة بعد كل جولة ناجحة.
  Future<PendingAccountsReport> processPending() async {
    final rows =
        await (db.select(db.pendingAccounts)
              ..where((t) => t.blocked.equals(false))
              ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
            .get();
    var done = 0;
    var blocked = 0;
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      try {
        if (row.kind == _create) {
          await _finishCreate(row);
        } else {
          await _finishReset(row);
        }
        done++;
      } on AuthFailureException catch (e) {
        final permanent = e.failure != AuthFailure.network;
        await (db.update(
          db.pendingAccounts,
        )..where((t) => t.id.equals(row.id))).write(
          PendingAccountsCompanion(
            attempts: Value(row.attempts + 1),
            lastError: Value(e.message),
            blocked: Value(permanent),
          ),
        );
        if (permanent) {
          blocked++;
          continue;
        }
        return PendingAccountsReport(
          done: done,
          left: rows.length - i,
          blocked: blocked,
        );
      }
    }
    return PendingAccountsReport(done: done, blocked: blocked);
  }

  Future<void> _finishCreate(PendingAccountRow row) async {
    final accountId = await provisioner.provision(
      email: row.email,
      password: row.password,
      role: UserRole.fromCode(row.role),
      id: row.id,
    );
    final message = await _message(
      SmsTemplateKeys.accountCreated,
      name: row.displayName,
      credentials: GeneratedCredentials(
        email: row.email,
        password: row.password,
      ),
    );
    await db.transaction(() async {
      final now = writer.now();
      await writer.save(
        db.userAccounts,
        UserAccountsCompanion.insert(
          id: accountId,
          createdAt: now,
          updatedAt: now,
          email: row.email,
          role: row.role,
          entityId: Value(row.entityId),
          displayName: Value(row.displayName),
          mustChangePassword: const Value(true),
        ),
        key: {'id': accountId},
      );
      // خادم أعاد معرّفاً غير المطلوب: يُصحَّح ربط صاحب الحساب به.
      if (accountId != row.id) {
        final owners = <TableInfo<Table, Object?>>[
          db.parents,
          db.teachers,
          db.workers,
        ];
        for (final table in owners) {
          final linked = await db
              .customSelect(
                'SELECT id FROM ${table.actualTableName} '
                'WHERE auth_user_id = ?',
                variables: [Variable<String>(row.id)],
                readsFrom: {table},
              )
              .get();
          for (final owner in linked) {
            await writer.patch(
              table,
              key: {'id': owner.read<String>('id')},
              values: {'auth_user_id': accountId},
            );
          }
        }
      }
      final phone = LoginCredentials.phoneOfEmail(row.email);
      if (phone != null) {
        await _queueSms(phone, message, SmsTemplateKeys.accountCreated);
      }
      await (db.delete(
        db.pendingAccounts,
      )..where((t) => t.id.equals(row.id))).go();
    });
  }

  Future<void> _finishReset(PendingAccountRow row) async {
    await provisioner.resetPassword(accountId: row.id, password: row.password);
    final message = await _message(
      SmsTemplateKeys.passwordReset,
      name: row.displayName,
      credentials: GeneratedCredentials(
        email: row.email,
        password: row.password,
      ),
    );
    await db.transaction(() async {
      final phone = LoginCredentials.phoneOfEmail(row.email);
      if (phone != null) {
        await _queueSms(phone, message, SmsTemplateKeys.passwordReset);
      }
      await (db.delete(
        db.pendingAccounts,
      )..where((t) => t.id.equals(row.id))).go();
    });
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
      'phone': LoginCredentials.displayLogin(credentials.email),
      'email': credentials.email,
      'password': credentials.password,
    });
  }

  /// يضع الرسالة في الطابور، ويعيد `false` إن أوقف المدير هذا النوع فلم توضع.
  Future<bool> _queueSms(String phone, String message, String kind) async {
    if (!await SmsKindPolicy(db, writer).isEnabled(kind)) return false;
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
    return true;
  }
}
