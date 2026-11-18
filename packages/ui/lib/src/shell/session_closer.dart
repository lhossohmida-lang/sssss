import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:school_core/school_core.dart';

/// يغلق الحصص المنتهية دورياً: من لم يُسجَّل حضوره يصير غائباً (مهمة 2.12)، ثم تُنسخ سجلاتها PDF
/// إن ضُبط مجلد الأرشيف.
///
/// يعمل عند فتح التطبيق ثم كل [period]؛ فإن كان التطبيق مغلقاً وقت نهاية
/// الحصة فُرّغ ما فات عند أول فتح. لا يتداخل تشغيلان، ولا يوقفه خطأ طارئ.
class SessionCloser {
  SessionCloser(
    this.service, {
    this.period = const Duration(minutes: 1),
    this.afterClosing,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AttendanceService service;
  final Duration period;

  /// يُستدعى بعد كل جولة إغلاق (حتى إن لم تُغلق حصة): أرشفة سجلات الحضور. فشله لا يوقف الإغلاق.
  final Future<AttendanceArchiveReport> Function()? afterClosing;
  final DateTime Function() _clock;

  Timer? _timer;
  bool _running = false;
  bool _disposed = false;

  /// آخر خطأ طرأ أثناء الإغلاق (للتشخيص).
  Object? lastError;

  /// آخر خطأ في أرشفة PDF (للتشخيص وللعرض في الإعدادات).
  Object? lastArchiveError;

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
      await _archive();
      return closed;
    } on Object catch (error) {
      lastError = error;
      debugPrint('تعذّر إغلاق الحصص المنتهية: $error');
      return 0;
    } finally {
      _running = false;
    }
  }

  Future<void> _archive() async {
    final archive = afterClosing;
    if (archive == null) return;
    try {
      final report = await archive();
      lastArchiveError = report.error;
      if (report.error != null) {
        debugPrint('تعذّرت أرشفة سجل الحضور: ${report.error}');
      }
    } on Object catch (error) {
      lastArchiveError = error;
      debugPrint('تعذّرت أرشفة سجل الحضور: $error');
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}
