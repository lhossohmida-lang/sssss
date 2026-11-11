import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_identity.dart';
import '../auth/account_directory.dart';
import '../auth/auth_gateway.dart';
import '../auth/auth_service.dart';
import '../auth/auth_session.dart';
import '../auth/local_auth_gateway.dart';
import '../auth/session_store.dart';
import '../auth/supabase_auth_gateway.dart';
import '../data/local/app_database.dart';
import '../data/local/open_database.dart';
import '../data/local/sync_writer.dart';
import '../data/remote/supabase_backend.dart';
import '../data/remote/sync_coordinator.dart';
import '../data/remote/sync_engine.dart';
import '../data/remote/sync_profile.dart';
import '../data/remote/upload_worker.dart';
import 'app_config.dart';

/// يبني منسّق المزامنة لجلسة مسجَّلة. يُمرَّر في الاختبارات بنسخة وهمية.
typedef SyncFactory = SyncCoordinator Function(AuthSession session);

/// يربط المزامنة بدورة حياة الجلسة: تبدأ بعد الدخول وتتوقف عند الخروج أو
/// تغيّر الحساب، ولا تُعاد عند مجرد تغيّر الصلاحيات أو الاسم.
class SyncLifecycle {
  SyncLifecycle(this.auth, this._factory) {
    _subscription = auth.changes.listen(_onSession);
    _onSession(auth.current);
  }

  final AuthService auth;
  final SyncFactory _factory;
  late final StreamSubscription<AuthSession?> _subscription;

  SyncCoordinator? _coordinator;
  String? _accountId;

  /// المنسّق الحالي، أو `null` دون جلسة.
  SyncCoordinator? get coordinator => _coordinator;

  void _onSession(AuthSession? session) {
    if (session?.accountId == _accountId) return;
    final old = _coordinator;
    _coordinator = null;
    _accountId = session?.accountId;
    if (old != null) unawaited(old.stop());
    // لا مزامنة قبل تغيير كلمة السر الأول: الجهاز ما زال في مرحلة الإعداد.
    if (session == null) return;
    _coordinator = _factory(session)..start();
  }

  Future<void> dispose() async {
    await _subscription.cancel();
    final old = _coordinator;
    _coordinator = null;
    await old?.stop();
  }
}

/// كل ما يلزم تطبيقاً من التطبيقات الثلاثة: القاعدة المحلية، المصادقة،
/// كاتب العمليات، والمزامنة في الخلفية.
///
/// - إعدادات الخادم موجودة: Supabase (دخول ومزامنة).
/// - غائبة في تطبيق الإدارة: الوضع المحلي ([isLocalMode]) للمعاينة.
/// - غائبة في تطبيقي الأستاذ والوليّ: الدخول مرفوض برسالة واضحة.
class AppRuntime {
  AppRuntime._({
    required this.app,
    required this.config,
    required this.db,
    required this.auth,
    required this.writer,
    required this.localGateway,
    required SyncLifecycle? syncLifecycle,
  }) : _sync = syncLifecycle;

  final AppIdentity app;
  final AppConfig config;
  final AppDatabase db;
  final AuthService auth;

  /// نقطة الكتابة الموحّدة، منسوبة إلى المستخدم المسجَّل.
  final SyncWriter writer;

  /// بوابة الوضع المحلي؛ `null` في وضع الخادم.
  final LocalAuthGateway? localGateway;
  final SyncLifecycle? _sync;

  /// هل يعمل التطبيق بلا خادم (معاينة)؟
  bool get isLocalMode => localGateway != null;

  /// منسّق المزامنة الحالي؛ `null` دون جلسة أو دون خادم.
  SyncCoordinator? get sync => _sync?.coordinator;

  /// يهيّئ التطبيق ويستعيد الجلسة المحفوظة.
  ///
  /// الوسائط الاختيارية للاختبارات: قاعدة جاهزة، بوابة مصادقة، ومصنع
  /// مزامنة؛ دونها تُبنى الحقيقية من [config].
  static Future<AppRuntime> start({
    required AppIdentity app,
    AppConfig? config,
    AppDatabase? database,
    AuthGateway? gateway,
    SyncFactory? syncFactory,
  }) async {
    final settings = config ?? AppConfig.fromEnvironment();
    final db = database ?? await _openDatabase(app);

    SupabaseClient? client;
    if (gateway == null && settings.isConfigured) {
      await Supabase.initialize(
        url: settings.supabaseUrl,
        publishableKey: settings.supabaseAnonKey,
      );
      client = Supabase.instance.client;
    }

    LocalAuthGateway? local;
    final AuthGateway chosen;
    if (gateway != null) {
      chosen = gateway;
    } else if (client != null) {
      chosen = SupabaseAuthGateway(client);
    } else if (app == AppIdentity.admin) {
      chosen = local = await LocalAuthGateway.open(db);
    } else {
      chosen = const UnconfiguredAuthGateway();
    }

    late final AuthService auth;
    final writer = SyncWriter(
      db,
      actor: () {
        final session = auth.current;
        if (session == null) {
          throw StateError('لا كتابة في القاعدة قبل تسجيل الدخول');
        }
        return session.actor;
      },
    );
    auth = AuthService(
      gateway: chosen,
      store: DatabaseSessionStore(db),
      directories: [
        LocalAccountDirectory(db),
        if (client != null) RemoteAccountDirectory(_remoteQuery(client)),
      ],
      writer: () => writer,
      app: app,
    );
    await auth.restore();

    final SyncFactory? factory =
        syncFactory ??
        (client == null
            ? null
            : (session) => _supabaseSync(db, writer, client!, session));
    return AppRuntime._(
      app: app,
      config: settings,
      db: db,
      auth: auth,
      writer: writer,
      localGateway: local,
      syncLifecycle: factory == null ? null : SyncLifecycle(auth, factory),
    );
  }

  /// يوقف المزامنة ويغلق القاعدة.
  Future<void> dispose() async {
    await _sync?.dispose();
    await auth.dispose();
    await db.close();
  }

  static Future<AppDatabase> _openDatabase(AppIdentity app) async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return openAppDatabase(File(p.join(dir.path, 'school_${app.name}.sqlite')));
  }

  static RemoteRowQuery _remoteQuery(SupabaseClient client) =>
      (table, column, value) async {
        try {
          final rows = await client.from(table).select().eq(column, value);
          return [for (final row in rows) Map<String, Object?>.from(row)];
        } on SocketException {
          throw const AuthFailureException(AuthFailure.network);
        } on PostgrestException catch (e) {
          throw AuthFailureException(
            AuthFailure.unknown,
            message: 'تعذّر قراءة الحساب من الخادم: ${e.message}',
          );
        }
      };

  static SyncCoordinator _supabaseSync(
    AppDatabase db,
    SyncWriter writer,
    SupabaseClient client,
    AuthSession session,
  ) {
    final backend = SupabaseBackend(client, db: db);
    final engine = SyncEngine(
      db,
      backend.remote,
      tables: SyncProfile.forRole(session.role),
    );
    return SyncCoordinator(
      db,
      engine,
      realtime: backend.realtime,
      uploads: UploadWorker(db, writer, backend.files),
    );
  }
}
