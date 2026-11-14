import 'dart:async';

import 'package:drift/drift.dart';

import '../local/app_database.dart';
import 'file_store.dart';
import 'sync_engine.dart';
import 'upload_worker.dart';

/// حالة المزامنة كما تُعرض للمستخدم.
enum SyncPhase {
  /// كل شيء متزامن أو ينتظر الجولة التالية.
  idle,

  /// جولة مزامنة جارية.
  syncing,

  /// آخر جولة تعذّرت (لا إنترنت أو عطل في الخادم)، وستُعاد تلقائياً.
  offline,
}

class SyncStatus {
  const SyncStatus({
    this.phase = SyncPhase.idle,
    this.pending = 0,
    this.rejected = 0,
    this.message,
    this.lastSuccessAt,
  });

  final SyncPhase phase;

  /// عمليات محلية لم تصل الخادم بعد.
  final int pending;

  /// عمليات رفضها الخادم نهائياً وتحتاج مراجعة.
  final int rejected;

  /// سبب آخر تعذّر، إن وُجد.
  final String? message;

  /// وقت آخر جولة ناجحة (ميلي ثانية).
  final int? lastSuccessAt;
}

/// ينسّق المزامنة في الخلفية دون أن تنتظرها أي شاشة:
///
/// - كل كتابة محلية تطلب جولة بعد مهلة قصيرة (لتجميع الكتابات المتتالية).
/// - جولة دورية تسحب ما فات البث اللحظي.
/// - البث اللحظي يطبّق تغييرات الأجهزة الأخرى فور وصولها.
/// - الملفات المنتظرة تُرفع بعد كل جولة ناجحة.
///
/// لا تتداخل جولتان: الطلب أثناء جولة جارية يُسجَّل وتُعاد جولة بعدها.
class SyncCoordinator {
  SyncCoordinator(
    this.db,
    this.engine, {
    this.realtime,
    this.uploads,
    this.debounce = const Duration(milliseconds: 400),
    this.interval = const Duration(minutes: 2),
    int Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().toUtc().millisecondsSinceEpoch);

  final AppDatabase db;
  final SyncEngine engine;
  final RealtimeSource? realtime;
  final UploadWorker? uploads;
  final Duration debounce;
  final Duration interval;
  final int Function() _clock;

  final StreamController<SyncStatus> _status =
      StreamController<SyncStatus>.broadcast();
  SyncStatus _current = const SyncStatus();

  StreamSubscription<Object?>? _writes;
  StreamSubscription<RemoteChange>? _remoteChanges;
  Timer? _debounceTimer;
  Timer? _periodic;
  Future<void>? _running;
  bool _again = false;
  bool _started = false;

  /// آخر حالة معروفة.
  SyncStatus get status => _current;

  /// تدفق حالة المزامنة لعرضها في الواجهة.
  Stream<SyncStatus> get statusStream => _status.stream;

  /// يبدأ المزامنة في الخلفية ويطلب جولة أولى.
  void start() {
    if (_started) return;
    _started = true;
    _writes = db
        .tableUpdates(
          TableUpdateQuery.onTable(
            db.outbox,
            limitUpdateKind: UpdateKind.insert,
          ),
        )
        .listen((_) => requestSync());
    _remoteChanges = realtime?.changes().listen(
      (change) => engine.applyRemoteChange(change.table, change.row),
      onError: (Object _) => requestSync(),
    );
    _periodic = Timer.periodic(interval, (_) => requestSync());
    requestSync();
  }

  /// يطلب جولة مزامنة قريبة (تُجمَّع الطلبات المتتالية في جولة واحدة).
  void requestSync() {
    if (!_started) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () => unawaited(syncNow()));
  }

  /// ينفّذ جولة الآن وينتظرها. إن كانت جولة جارية تُعاد جولة بعدها.
  Future<void> syncNow() {
    final running = _running;
    if (running != null) {
      _again = true;
      return running;
    }
    final run = _runLoop().whenComplete(() => _running = null);
    _running = run;
    return run;
  }

  Future<void> _runLoop() async {
    do {
      _again = false;
      _emit(
        SyncStatus(
          phase: SyncPhase.syncing,
          pending: _current.pending,
          rejected: _current.rejected,
          lastSuccessAt: _current.lastSuccessAt,
        ),
      );
      final report = await engine.syncOnce();
      final rejected = await engine.rejectedCount();
      if (report.error != null) {
        _emit(
          SyncStatus(
            phase: SyncPhase.offline,
            pending: report.pending,
            rejected: rejected,
            message: report.error,
            lastSuccessAt: _current.lastSuccessAt,
          ),
        );
        return;
      }
      // هذا المنسّق يرفع مخازن Supabase فقط. طابور Drive له اعتماد OAuth
      // ومخزن مستقل، ويعالجه تطبيق الإدارة بعد التحقق من حساب المالك.
      await uploads?.processPending(buckets: const {'photos', 'files'});
      _emit(
        SyncStatus(
          pending: report.pending,
          rejected: rejected,
          lastSuccessAt: _clock(),
        ),
      );
    } while (_again && _started);
  }

  void _emit(SyncStatus status) {
    _current = status;
    if (!_status.isClosed) _status.add(status);
  }

  /// يوقف المزامنة وينتظر انتهاء الجولة الجارية.
  Future<void> stop() async {
    _started = false;
    _debounceTimer?.cancel();
    _periodic?.cancel();
    await _writes?.cancel();
    await _remoteChanges?.cancel();
    await _running;
    await _status.close();
  }
}
