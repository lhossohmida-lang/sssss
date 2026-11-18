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
    this.maintenance,
  }) {
    _subscription = auth.changes.listen(_onSession);
    _onSession(auth.current);
  }

  final AuthService auth;
  final LevelService levels;
  final bool isLocalMode;

  /// المنسّق الحالي (يتغير مع الجلسة)؛ `null` دون جلسة أو دون خادم.
  final SyncCoordinator? Function() coordinator;

  /// صيانة بيانات تلحق البذر بعد كل مزامنة ناجحة (مثل إعادة ترقيم الأفواج المقطعي). فشلها لا يعطّل
  /// شيئاً وتُعاد بعد المزامنة التالية.
  final Future<void> Function()? maintenance;

  late final StreamSubscription<AuthSession?> _subscription;
  StreamSubscription<SyncStatus>? _syncWatch;
  String? _seededFor;
  int? _lastSuccess;
  bool _busy = false;
  bool _again = false;

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
    // بعد كل مزامنة ناجحة لا بعد أولى فقط: إعادة تعيين المدرسة من جهاز آخر تمسح المستويات والعلامة
    // معاً فتُبذَر من جديد، و`ensureDefaults` فحص واحد رخيص حين لا جديد.
    _lastSuccess = sync.status.lastSuccessAt;
    if (_lastSuccess != null) unawaited(_seed());
    unawaited(_syncWatch?.cancel());
    _syncWatch = sync.statusStream.listen((status) {
      final at = status.lastSuccessAt;
      if (at == null || at == _lastSuccess) return;
      _lastSuccess = at;
      unawaited(_seed());
    });
  }

  Future<void> _seed() async {
    // جولتان متداخلتان تُجمَعان في ما بعدها.
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    try {
      do {
        _again = false;
        await levels.ensureDefaults();
        await maintenance?.call();
      } while (_again);
    } on Object {
      // تُعاد المحاولة بعد المزامنة التالية أو عند الدخول التالي؛ لا يتعطل التطبيق بسببها.
      _seededFor = null;
    } finally {
      _busy = false;
    }
  }

  Future<void> dispose() async {
    await _subscription.cancel();
    await _syncWatch?.cancel();
  }
}
