import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:school_core/school_core.dart';

/// يغلق الحصص المنتهية دورياً: من لم يُسجَّل حضوره يصير غائباً (مهمة 2.12).
///
/// يعمل عند فتح التطبيق ثم كل [period]؛ فإن كان التطبيق مغلقاً وقت نهاية
/// الحصة فُرّغ ما فات عند أول فتح. لا يتداخل تشغيلان، ولا يوقفه خطأ طارئ.
class SessionCloser {
  SessionCloser(
    this.service, {
    this.period = const Duration(minutes: 1),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AttendanceService service;
  final Duration period;
  final DateTime Function() _clock;

  Timer? _timer;
  bool _running = false;
  bool _disposed = false;

  /// آخر خطأ طرأ أثناء الإغلاق (للتشخيص).
  Object? lastError;

  /// يبدأ العمل: تشغيل فوري ثم دوري.
  void start() {
    if (_timer != null || _disposed) return;
    unawaited(runOnce());
    _timer = Timer.periodic(period, (_) => unawaited(runOnce()));
  }

  /// يغلق ما استحق الآن. يعيد عدد الحصص المغلقة.
  Future<int> runOnce() async {
    if (_running || _disposed) return 0;
    _running = true;
    try {
      final closed = await service.closeDueSessions(_clock());
      lastError = null;
      return closed;
    } on Object catch (error) {
      lastError = error;
      debugPrint('تعذّر إغلاق الحصص المنتهية: $error');
      return 0;
    } finally {
      _running = false;
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}
