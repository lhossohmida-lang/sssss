import 'dart:async';

import 'sms_platform.dart';
import 'sms_queue_service.dart';
import 'sms_settings.dart';

class SmsDispatchReport {
  const SmsDispatchReport({
    this.sent = 0,
    this.failed = 0,
    this.retried = 0,
    this.deferredUntil,
    this.stopped = false,
    this.alreadyRunning = false,
  });

  final int sent;
  final int failed;
  final int retried;
  final DateTime? deferredUntil;
  final bool stopped;
  final bool alreadyRunning;
}

/// يفرغ الطابور على Android مع إبقاء خدمة مرئية وتشغيل فاصل 3 ثوانٍ.
class SmsDispatchWorker {
  SmsDispatchWorker({
    required this.queue,
    required this.settings,
    required this.platform,
    DateTime Function()? now,
    Future<void> Function(Duration)? delay,
    this.sendInterval = const Duration(seconds: 3),
    this.maxScheduledWait = const Duration(hours: 10),
  }) : _now = now ?? DateTime.now,
       _delay = delay ?? Future<void>.delayed;

  final SmsQueueService queue;
  final SmsSettingsService settings;
  final SmsDispatchPlatform platform;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _delay;
  final Duration sendInterval;
  final Duration maxScheduledWait;

  Future<SmsDispatchReport>? _activeRun;
  Completer<void>? _stopSignal;

  /// Starts one drain. A concurrent call joins the existing run.
  Future<SmsDispatchReport> start() {
    final active = _activeRun;
    if (active != null) {
      return active.then(
        (report) => SmsDispatchReport(
          sent: report.sent,
          failed: report.failed,
          retried: report.retried,
          deferredUntil: report.deferredUntil,
          stopped: report.stopped,
          alreadyRunning: true,
        ),
      );
    }
    _stopSignal = Completer<void>();
    final run = _drain();
    _activeRun = run;
    return run.whenComplete(() {
      _activeRun = null;
      _stopSignal = null;
    });
  }

  /// يوقف الدفعة بعد الرسالة الحالية أو أثناء الانتظار المبرمج.
  Future<void> stop() async {
    final signal = _stopSignal;
    if (signal != null && !signal.isCompleted) signal.complete();
    final active = _activeRun;
    if (active != null) await active;
  }

  Future<SmsDispatchReport> _drain() async {
    var serviceStarted = false;
    var sent = 0;
    var failed = 0;
    var retried = 0;
    DateTime? deferredUntil;
    var stopped = false;
    try {
      await queue.recoverInterruptedSends();
      if (await queue.pendingCount() == 0) return const SmsDispatchReport();
      if (!await platform.requestPermissions()) {
        throw const SmsTransportException(
          'يلزم السماح بإرسال الرسائل وقراءة شرائح SIM',
          retryable: false,
        );
      }
      final sims = await platform.availableSimCards();
      if (sims.isEmpty) {
        throw const SmsTransportException(
          'لا توجد شريحة SIM نشطة تدعم إرسال الرسائل',
          retryable: false,
        );
      }
      final configuredSlot = await settings.simSlotIndex();
      final selectedSim = _selectSim(sims, configuredSlot);
      await platform.startForegroundService();
      serviceStarted = true;

      while (true) {
        if (_stopSignal?.isCompleted ?? true) {
          stopped = true;
          break;
        }
        final result = await queue.processNext(
          (message) =>
              platform.send(message, simSlotIndex: selectedSim.slotIndex),
        );
        switch (result.kind) {
          case SmsProcessKind.empty:
            break;
          case SmsProcessKind.busy:
            stopped = true;
            break;
          case SmsProcessKind.sent:
            sent++;
            break;
          case SmsProcessKind.failed:
            failed++;
            break;
          case SmsProcessKind.retryScheduled:
            retried++;
            break;
          case SmsProcessKind.deferred:
            final at = result.scheduledAt;
            if (at == null) {
              stopped = true;
              break;
            }
            final wait = at.difference(_now());
            if (wait.isNegative || wait == Duration.zero) continue;
            if (wait > maxScheduledWait) {
              deferredUntil = at;
              break;
            }
            await _waitOrStop(wait);
            if (_stopSignal?.isCompleted ?? true) {
              stopped = true;
              break;
            }
            continue;
        }
        if (result.kind == SmsProcessKind.empty ||
            result.kind == SmsProcessKind.busy ||
            deferredUntil != null ||
            stopped) {
          break;
        }
        if (await queue.pendingCount() == 0) break;
        await _waitOrStop(sendInterval);
      }
      return SmsDispatchReport(
        sent: sent,
        failed: failed,
        retried: retried,
        deferredUntil: deferredUntil,
        stopped: stopped,
      );
    } finally {
      if (serviceStarted) await platform.stopForegroundService();
    }
  }

  SmsSimCard _selectSim(List<SmsSimCard> sims, int? configuredSlot) {
    if (configuredSlot != null) {
      for (final sim in sims) {
        if (sim.slotIndex == configuredSlot) return sim;
      }
      throw const SmsTransportException(
        'الشريحة المختارة غير متاحة؛ اختر شريحة نشطة من الإعدادات',
        retryable: false,
      );
    }
    if (sims.length == 1) return sims.single;
    throw const SmsTransportException(
      'اختر شريحة الإرسال من إعدادات الرسائل',
      retryable: false,
    );
  }

  Future<void> _waitOrStop(Duration duration) async {
    final signal = _stopSignal;
    if (signal == null || signal.isCompleted) return;
    await Future.any([_delay(duration), signal.future]);
  }
}
