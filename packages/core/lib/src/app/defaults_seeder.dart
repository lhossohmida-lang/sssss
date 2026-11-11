import 'dart:async';

import '../auth/auth_service.dart';
import '../auth/auth_session.dart';
import '../data/remote/sync_coordinator.dart';
import '../domain/enums.dart';
import '../domain/settings_service.dart';

/// يضيف البيانات الأولية (المستويات الدراسية) في تطبيق الإدارة.
///
/// - الوضع المحلي: فور دخول صاحب المدرسة.
/// - مع الخادم: بعد أول مزامنة ناجحة، حتى لا يُعاد إنشاء مستوى حذفه المدير من
///   جهاز آخر (الجهاز الجديد لم يسحب حذفه بعد).
///
/// إن تعذّر الإضافة تُعاد المحاولة عند الدخول التالي؛ والعملية متكررة الأمان.
class DefaultsSeeder {
  DefaultsSeeder({
    required this.auth,
    required this.levels,
    required this.isLocalMode,
    required this.coordinator,
  }) {
    _subscription = auth.changes.listen(_onSession);
    _onSession(auth.current);
  }

  final AuthService auth;
  final LevelService levels;
  final bool isLocalMode;

  /// المنسّق الحالي (يتغير مع الجلسة)؛ `null` دون جلسة أو دون خادم.
  final SyncCoordinator? Function() coordinator;

  late final StreamSubscription<AuthSession?> _subscription;
  StreamSubscription<SyncStatus>? _syncWatch;
  String? _seededFor;

  void _onSession(AuthSession? session) {
    if (session == null || session.role != UserRole.owner) return;
    if (session.mustChangePassword || _seededFor == session.accountId) return;
    _seededFor = session.accountId;
    if (isLocalMode) {
      unawaited(_seed());
      return;
    }
    final sync = coordinator();
    if (sync == null) return;
    if (sync.status.lastSuccessAt != null) {
      unawaited(_seed());
      return;
    }
    unawaited(_syncWatch?.cancel());
    _syncWatch = sync.statusStream.listen((status) {
      if (status.lastSuccessAt == null) return;
      unawaited(_syncWatch?.cancel());
      unawaited(_seed());
    });
  }

  Future<void> _seed() async {
    try {
      await levels.ensureDefaults();
    } on Object {
      // تُعاد المحاولة عند الدخول التالي؛ لا يتعطل التطبيق بسببها.
      _seededFor = null;
    }
  }

  Future<void> dispose() async {
    await _subscription.cancel();
    await _syncWatch?.cancel();
  }
}
