import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:school_sms/school_sms.dart';

/// يمرّ عبر قائمة الأحداث عدة مرات ليصل أثر كل ما أُطلق.
Future<void> settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _FakeTimer implements Timer {
  _FakeTimer(this.delay, this.callback);

  final Duration delay;
  final void Function() callback;
  bool cancelled = false;
  bool fired = false;

  @override
  void cancel() => cancelled = true;

  @override
  bool get isActive => !cancelled && !fired;

  @override
  int get tick => fired ? 1 : 0;

  void fire() {
    if (cancelled) return;
    fired = true;
    callback();
  }
}

class _Rig {
  _Rig({this.sender = true}) {
    dispatcher = SmsAutoDispatcher(
      pendingCounts: counts.stream,
      isSender: () async => sender,
      run: _run,
      stop: () async => stops++,
      now: () => now,
      timer: (delay, callback) {
        final timer = _FakeTimer(delay, callback);
        timers.add(timer);
        return timer;
      },
    );
  }

  final StreamController<int> counts = StreamController<int>.broadcast(
    sync: true,
  );
  final List<_FakeTimer> timers = [];
  final List<SmsAutoStatus> seen = [];
  DateTime now = DateTime(2026, 11, 17, 10);
  bool sender;
  int runs = 0;
  int stops = 0;
  Completer<void>? gate;
  Object? failWith;
  DateTime? deferredUntil;
  late final SmsAutoDispatcher dispatcher;

  Future<SmsDispatchReport> _run() async {
    runs++;
    final wait = gate;
    if (wait != null) await wait.future;
    final error = failWith;
    if (error != null) throw error;
    return SmsDispatchReport(sent: 1, deferredUntil: deferredUntil);
  }

  void listen() => dispatcher.statuses.listen(seen.add);

  List<_FakeTimer> get active => [
    for (final timer in timers)
      if (timer.isActive) timer,
  ];

  Future<void> dispose() async {
    await dispatcher.dispose();
    await counts.close();
  }
}

void main() {
  group('SmsAutoDispatcher', () {
    test('يرسل فور ظهور رسائل منتظرة دون أن يضغط أحد زراً', () async {
      final rig = _Rig()..listen();
      rig.dispatcher.start();
      await settle();
      final startRuns = rig.runs;
      expect(startRuns, greaterThanOrEqualTo(1));

      rig.counts.add(3);
      await settle();
      expect(rig.runs, greaterThan(startRuns));
      expect(rig.dispatcher.status.state, SmsAutoState.idle);
      expect(
        rig.seen.map((status) => status.state),
        containsAllInOrder([SmsAutoState.sending, SmsAutoState.idle]),
      );
      await rig.dispose();
    });

    test('عدد صفر لا يشغّل جولة جديدة', () async {
      final rig = _Rig();
      rig.dispatcher.start();
      await settle();
      final before = rig.runs;
      rig.counts.add(0);
      await settle();
      expect(rig.runs, before);
      await rig.dispose();
    });

    test('جهاز غير معيَّن للإرسال لا يرسل، ثم يعمل بعد التعيين', () async {
      final rig = _Rig(sender: false);
      rig.dispatcher.start();
      rig.counts.add(2);
      await settle();
      expect(rig.runs, 0);
      expect(rig.dispatcher.status.state, SmsAutoState.otherDevice);

      rig.sender = true;
      rig.dispatcher.kick();
      await settle();
      expect(rig.runs, 1);
      expect(rig.dispatcher.status.state, SmsAutoState.idle);
      await rig.dispose();
    });

    test('نداءات كثيرة أثناء الإرسال تتجمّع في جولة إضافية واحدة', () async {
      final rig = _Rig();
      rig.gate = Completer<void>();
      rig.dispatcher.start();
      await settle();
      expect(rig.runs, 1);
      for (var i = 0; i < 10; i++) {
        rig.dispatcher.kick();
      }
      rig.counts.add(5);
      await settle();
      expect(rig.runs, 1, reason: 'لا جولة موازية');

      rig.gate!.complete();
      await settle();
      expect(rig.runs, 2, reason: 'جولة واحدة تلتقط ما وصل أثناء الإرسال');
      expect(rig.dispatcher.status.state, SmsAutoState.idle);
      await rig.dispose();
    });

    test('الرسائل المؤجلة: مؤقّت عند موعدها ثم يستأنف', () async {
      final rig = _Rig();
      rig.deferredUntil = rig.now.add(const Duration(hours: 2));
      rig.dispatcher.start();
      await settle();
      expect(
        rig.dispatcher.status,
        SmsAutoStatus(SmsAutoState.waiting, until: rig.deferredUntil),
      );
      expect(rig.active, hasLength(1));
      expect(rig.active.single.delay, const Duration(hours: 2, seconds: 1));

      rig.deferredUntil = null;
      final before = rig.runs;
      rig.now = rig.now.add(const Duration(hours: 2));
      rig.active.single.fire();
      await settle();
      expect(rig.runs, greaterThan(before));
      expect(rig.dispatcher.status.state, SmsAutoState.idle);
      expect(rig.active, isEmpty);
      await rig.dispose();
    });

    test('موعد مضى يستأنف فوراً', () async {
      final rig = _Rig();
      rig.deferredUntil = rig.now.subtract(const Duration(minutes: 5));
      rig.dispatcher.start();
      await settle();
      expect(rig.active.single.delay, Duration.zero);
      await rig.dispose();
    });

    test(
      'نقص الإذن يوقف الإرسال دون مؤقّت، والعودة للواجهة تعيد المحاولة',
      () async {
        final rig = _Rig();
        rig.failWith = const SmsTransportException(
          'يلزم السماح بإرسال الرسائل',
          retryable: false,
        );
        rig.dispatcher.start();
        await settle();
        expect(
          rig.dispatcher.status,
          const SmsAutoStatus(
            SmsAutoState.blocked,
            message: 'يلزم السماح بإرسال الرسائل',
          ),
        );
        expect(rig.active, isEmpty, reason: 'لا تكرار لطلب الإذن بمؤقّت');

        // المستخدم منح الإذن ثم عاد إلى التطبيق.
        rig.failWith = null;
        final before = rig.runs;
        rig.dispatcher.kick();
        await settle();
        expect(rig.runs, greaterThan(before));
        expect(rig.dispatcher.status.state, SmsAutoState.idle);
        await rig.dispose();
      },
    );

    test('عطل مؤقت يُعاد بعد مهلة', () async {
      final rig = _Rig();
      rig.failWith = const SmsTransportException('انقطاع مؤقت');
      rig.dispatcher.start();
      await settle();
      expect(rig.dispatcher.status.state, SmsAutoState.blocked);
      expect(rig.active.single.delay, rig.dispatcher.blockedRetry);

      rig.failWith = null;
      rig.active.single.fire();
      await settle();
      expect(rig.dispatcher.status.state, SmsAutoState.idle);
      await rig.dispose();
    });

    test('خطأ غير متوقع لا يكسر المراقبة', () async {
      final rig = _Rig();
      rig.failWith = StateError('عطل');
      rig.dispatcher.start();
      await settle();
      expect(rig.dispatcher.status.state, SmsAutoState.blocked);
      expect(rig.active, hasLength(1));

      rig.failWith = null;
      rig.counts.add(1);
      await settle();
      expect(rig.dispatcher.status.state, SmsAutoState.idle);
      expect(rig.active, isEmpty, reason: 'النجاح يلغي مؤقّت الإعادة');
      await rig.dispose();
    });

    test('الإيقاف يلغي المؤقّتات والمراقبة ويوقف الإرسال الجاري', () async {
      final rig = _Rig();
      rig.deferredUntil = rig.now.add(const Duration(hours: 1));
      rig.dispatcher.start();
      await settle();
      expect(rig.active, hasLength(1));
      final before = rig.runs;

      await rig.dispatcher.dispose();
      expect(rig.stops, 1);
      expect(rig.active, isEmpty);
      expect(rig.dispatcher.status.state, SmsAutoState.stopped);

      rig.counts.add(4);
      rig.dispatcher.kick();
      await settle();
      expect(rig.runs, before);
      await rig.counts.close();
    });
  });
}
