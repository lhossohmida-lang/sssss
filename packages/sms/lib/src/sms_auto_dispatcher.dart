import 'dart:async';

import 'sms_dispatch_worker.dart';
import 'sms_queue_service.dart';

/// حالة الإرسال التلقائي كما تعرضها شاشة الرسائل.
enum SmsAutoState {
  /// لم يبدأ أو أُوقف (هذا الجهاز لا يرسل: ليس هاتف Android أو لا صلاحية).
  stopped,

  /// يعمل ولا رسائل تنتظر.
  idle,

  /// يرسل الآن.
  sending,

  /// رسائل مؤجلة (ساعات الهدوء أو إعادة محاولة) حتى [SmsAutoStatus.until].
  waiting,

  /// جهاز إدارة آخر هو المعيَّن للإرسال.
  otherDevice,

  /// متوقف بسبب مشكلة تحتاج تدخلاً (إذن الرسائل أو الشريحة)، وسببها في الرسالة.
  blocked,
}

class SmsAutoStatus {
  const SmsAutoStatus(this.state, {this.until, this.message});

  final SmsAutoState state;
  final DateTime? until;
  final String? message;

  @override
  bool operator ==(Object other) =>
      other is SmsAutoStatus &&
      other.state == state &&
      other.until == until &&
      other.message == message;

  @override
  int get hashCode => Object.hash(state, until, message);

  @override
  String toString() => 'SmsAutoStatus($state, $until, $message)';
}

typedef SmsTimerFactory = Timer Function(Duration delay, void Function() run);

/// يرسل طابور الرسائل تلقائياً من هاتف Android الإدارة دون أن يضغط أحد زراً.
///
/// يراقب عدد الرسائل المنتظرة، فكلما ظهرت رسالة جاهزة (من هذا الجهاز أو وصلت بالمزامنة
/// من الحاسوب) شغّل [run]. الرسائل المؤجلة (ساعات الهدوء 21:00–07:00 أو إعادة محاولة)
/// يستأنفها بمؤقّت عند موعدها، ويستأنف أيضاً عند عودة التطبيق إلى الواجهة ([kick]).
/// لا يعمل إلا على الجهاز الذي يعيده [isSender] بـ`true`، فلا تُرسل رسالة من جهازين.
class SmsAutoDispatcher {
  SmsAutoDispatcher({
    required this._pendingCounts,
    required this._isSender,
    required this._run,
    this._stop,
    DateTime Function()? now,
    SmsTimerFactory? timer,
    this.blockedRetry = const Duration(minutes: 20),
  }) : _now = now ?? DateTime.now,
       _timer = timer ?? Timer.new;

  /// بعد هذه المدة يُعاد الإرسال إن توقف لعطل مؤقت.
  final Duration blockedRetry;

  final Stream<int> _pendingCounts;
  final Future<bool> Function() _isSender;
  final Future<SmsDispatchReport> Function() _run;
  final Future<void> Function()? _stop;
  final DateTime Function() _now;
  final SmsTimerFactory _timer;
  final StreamController<SmsAutoStatus> _statuses =
      StreamController<SmsAutoStatus>.broadcast();

  StreamSubscription<int>? _pending;
  Timer? _wake;
  SmsAutoStatus _status = const SmsAutoStatus(SmsAutoState.stopped);
  bool _running = false;
  bool _again = false;
  bool _disposed = false;
  Future<void>? _drain;

  /// الحالة الحالية، وتُبَث التغييرات في [statuses].
  SmsAutoStatus get status => _status;

  Stream<SmsAutoStatus> get statuses => _statuses.stream;

  /// يبدأ المراقبة ويفرّغ ما هو جاهز الآن.
  void start() {
    if (_disposed || _pending != null) return;
    _pending = _pendingCounts.listen((count) {
      if (count > 0) kick();
    }, onError: (Object _) {});
    kick();
  }

  /// يطلب جولة إرسال الآن (عند عودة التطبيق إلى الواجهة أو بزر «أرسل الآن»).
  void kick() {
    if (_disposed) return;
    _again = true;
    if (_running) return;
    _running = true;
    _drain = _loop();
  }

  Future<void> _loop() async {
    try {
      while (_again && !_disposed) {
        _again = false;
        await _once();
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _once() async {
    _cancelWake();
    try {
      if (!await _isSender()) {
        _emit(const SmsAutoStatus(SmsAutoState.otherDevice));
        return;
      }
      _emit(const SmsAutoStatus(SmsAutoState.sending));
      final report = await _run();
      final until = report.deferredUntil;
      if (until != null) {
        _emit(SmsAutoStatus(SmsAutoState.waiting, until: until));
        _wakeAfter(until.difference(_now()) + const Duration(seconds: 1));
      } else {
        _emit(const SmsAutoStatus(SmsAutoState.idle));
      }
    } on SmsTransportException catch (error) {
      _emit(SmsAutoStatus(SmsAutoState.blocked, message: error.message));
      // نقص الإذن أو الشريحة يحتاج المستخدم: لا نكرّر طلب الإذن بمؤقّت.
      if (error.retryable) _wakeAfter(blockedRetry);
    } on Object catch (error) {
      _emit(SmsAutoStatus(SmsAutoState.blocked, message: '$error'));
      _wakeAfter(blockedRetry);
    }
  }

  void _wakeAfter(Duration delay) {
    if (_disposed) return;
    _cancelWake();
    _wake = _timer(delay.isNegative ? Duration.zero : delay, () {
      _wake = null;
      kick();
    });
  }

  void _cancelWake() {
    _wake?.cancel();
    _wake = null;
  }

  void _emit(SmsAutoStatus next) {
    if (_disposed || next == _status) return;
    _status = next;
    _statuses.add(next);
  }

  /// يوقف المراقبة والمؤقّتات وأي إرسال جارٍ بعد الرسالة الحالية.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _cancelWake();
    await _pending?.cancel();
    _pending = null;
    final stop = _stop;
    if (stop != null) await stop();
    await _drain;
    _status = const SmsAutoStatus(SmsAutoState.stopped);
    await _statuses.close();
  }
}
