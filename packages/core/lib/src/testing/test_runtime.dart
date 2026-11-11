import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import '../app/app_runtime.dart';
import '../app_identity.dart';
import '../auth/account_provisioner.dart';
import '../data/local/app_database.dart';
import '../domain/enums.dart';
import 'fake_auth_gateway.dart';

/// حساب جاهز في الاختبارات: بريده وكلمة سره ودوره.
class TestAccount {
  const TestAccount({
    required this.id,
    required this.email,
    required this.password,
    required this.role,
    this.entityId,
    this.displayName = '',
    this.mustChangePassword = false,
    this.permissions = '{}',
  });

  final String id;
  final String email;
  final String password;
  final UserRole role;
  final String? entityId;
  final String displayName;
  final bool mustChangePassword;

  /// حقل صلاحيات العامل (JSON)، ويُكتب في جدول العمال إن كان الدور عاملاً.
  final String permissions;
}

/// يبني [AppRuntime] كاملاً على قاعدة في الذاكرة وبوابة مصادقة وهمية، مع
/// الحسابات المطلوبة مكتوبة محلياً كأنها وصلت بالمزامنة. مع [localMode] يعمل
/// تطبيق الإدارة بالوضع المحلي (دخول بلا خادم) بتكرارات اشتقاق قليلة.
Future<AppRuntime> startTestRuntime({
  AppIdentity app = AppIdentity.admin,
  List<TestAccount> accounts = const [],
  FakeAuthGateway? gateway,
  AppDatabase? database,
  SyncFactory? syncFactory,
  bool localMode = false,
  AccountProvisioner? provisioner,
}) async {
  final db = database ?? AppDatabase(NativeDatabase.memory());
  // الوضع المحلي: دون بوابة وهمية، فيبني التطبيق بوابته المحلية (للإدارة).
  final FakeAuthGateway? fake = localMode
      ? null
      : (gateway ??
            FakeAuthGateway({
              for (final a in accounts)
                a.email: (id: a.id, password: a.password),
            }));
  for (final a in accounts) {
    await db
        .into(db.userAccounts)
        .insert(
          UserAccountsCompanion.insert(
            id: a.id,
            createdAt: 1,
            updatedAt: 1,
            email: a.email,
            role: a.role.code,
            entityId: Value(a.entityId),
            displayName: Value(a.displayName),
            mustChangePassword: Value(a.mustChangePassword),
          ),
        );
    if (a.role == UserRole.worker && a.entityId != null) {
      await db
          .into(db.workers)
          .insert(
            WorkersCompanion.insert(
              id: a.entityId!,
              createdAt: 1,
              updatedAt: 1,
              name: a.displayName,
              phone: '0550000000',
              email: a.email,
              qrCode: 'W-${a.entityId}',
              permissions: Value(a.permissions),
            ),
          );
    }
  }
  return AppRuntime.start(
    app: app,
    database: db,
    gateway: fake,
    syncFactory: syncFactory,
    provisioner: provisioner,
    localPasswordIterations: 20,
  );
}
