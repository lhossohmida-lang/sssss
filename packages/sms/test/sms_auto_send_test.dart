import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_sms/school_sms.dart';

class _Platform implements SmsDispatchPlatform {
  final List<SmsQueueRow> sent = [];
  bool granted = true;
  int permissionRequests = 0;

  @override
  Future<bool> requestPermissions() async {
    permissionRequests++;
    return granted;
  }

  @override
  Future<List<SmsSimCard>> availableSimCards() async => const [
    SmsSimCard(
      slotIndex: 0,
      subscriptionId: 1,
      displayName: 'SIM',
      carrierName: 'Carrier',
    ),
  ];

  @override
  Future<void> startForegroundService() async {}

  @override
  Future<void> stopForegroundService() async {}

  @override
  Future<void> send(SmsQueueRow message, {required int simSlotIndex}) async {
    sent.add(message);
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
    fired = true;
    callback();
  }
}

class _Device {
  _Device(this.clock) : db = AppDatabase(NativeDatabase.memory()) {
    writer = SyncWriter(
      db,
      actor: () => const Actor(userId: 'owner', userName: 'المدير'),
      clock: () => clock().toUtc().millisecondsSinceEpoch,
    );
    queue = SmsQueueService(db, writer, now: clock);
    sender = SmsSenderDevice(db, writer);
  }

  final AppDatabase db;
  final DateTime Function() clock;
  late final SyncWriter writer;
  late final SmsQueueService queue;
  late final SmsSenderDevice sender;

  Future<void> close() => db.close();
}

Future<void> waitFor(bool Function() condition) async {
  for (var i = 0; i < 300; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('انتهت المهلة قبل تحقق الشرط');
}

void main() {
  group('SmsSenderDevice', () {
    test('معرّف الجهاز ثابت له ومختلف عن جهاز آخر', () async {
      final a = _Device(() => DateTime(2026, 11, 17, 10));
      final b = _Device(() => DateTime(2026, 11, 17, 10));
      addTearDown(a.close);
      addTearDown(b.close);

      final first = await a.sender.deviceId();
      expect(await a.sender.deviceId(), first);
      expect(
        await SmsSenderDevice(a.db, a.writer).deviceId(),
        first,
        reason: 'يُقرأ من التفضيلات المحلية بعد إنشائه',
      );
      expect(await b.sender.deviceId(), isNot(first));
    });

    test('أول جهاز يطالب بالإرسال يصير المرسل، ولا يسلبه غيره', () async {
      final a = _Device(() => DateTime(2026, 11, 17, 10));
      final b = _Device(() => DateTime(2026, 11, 17, 10));
      addTearDown(a.close);
      addTearDown(b.close);

      expect(await a.sender.designated(), isNull);
      expect(await a.sender.isThisDevice(), isFalse);
      expect(await a.sender.claimIfUnassigned(), isTrue);
      expect(await a.sender.designated(), await a.sender.deviceId());

      // المزامنة تنقل الإعداد إلى الجهاز الآخر.
      final synced = await (a.db.select(
        a.db.settings,
      )..where((s) => s.key.equals(SettingKeys.smsSenderDevice))).getSingle();
      await b.db.into(b.db.settings).insert(synced);

      expect(await b.sender.isThisDevice(), isFalse);
      expect(await b.sender.claimIfUnassigned(), isFalse);
      expect(await a.sender.isThisDevice(), isTrue);

      await b.sender.claim();
      expect(await b.sender.isThisDevice(), isTrue);
    });

    test('الإعداد يُكتب عبر SyncWriter فيصل بقية الأجهزة', () async {
      final a = _Device(() => DateTime(2026, 11, 17, 10));
      addTearDown(a.close);
      await a.sender.claim();
      final queued = await (a.db.select(
        a.db.outbox,
      )..where((item) => item.targetTable.equals('settings'))).get();
      expect(queued, isNotEmpty);
    });

    test('الإزالة تُبقي الإعداد فارغاً فلا يرسل جهاز', () async {
      final a = _Device(() => DateTime(2026, 11, 17, 10));
      addTearDown(a.close);
      await a.sender.claim();
      await a.sender.release();
      expect(await a.sender.designated(), isNull);
      expect(await a.sender.isThisDevice(), isFalse);
    });

    test('المراقبة تعكس التعيين لحظياً', () async {
      final a = _Device(() => DateTime(2026, 11, 17, 10));
      addTearDown(a.close);
      final seen = <bool>[];
      final sub = a.sender.watchIsThisDevice().listen(seen.add);
      await waitFor(() => seen.isNotEmpty);
      expect(seen.last, isFalse);

      await a.sender.claim();
      await waitFor(() => seen.last);
      await a.sender.release();
      await waitFor(() => !seen.last);
      await sub.cancel();
    });
  });

  group('الإرسال التلقائي مع الطابور الحقيقي', () {
    test('رسائل الطابور تُرسل وحدها دون أي استدعاء للإرسال', () async {
      final device = _Device(() => DateTime(2026, 11, 17, 10));
      addTearDown(device.close);
      final platform = _Platform();
      final worker = SmsDispatchWorker(
        queue: device.queue,
        settings: SmsSettingsService(device.db, device.writer),
        platform: platform,
        now: device.clock,
        delay: (_) async {},
        sendInterval: Duration.zero,
        maxScheduledWait: Duration.zero,
      );
      final dispatcher = SmsAutoDispatcher(
        pendingCounts: device.queue.watchPendingCount(),
        isSender: device.sender.claimIfUnassigned,
        run: worker.start,
        stop: worker.stop,
      )..start();
      addTearDown(dispatcher.dispose);

      await device.queue.enqueue(phone: '0550123456', message: 'أولى');
      await device.queue.enqueue(phone: '0550123457', message: 'ثانية');

      await waitFor(() => platform.sent.length == 2);
      expect(platform.sent.map((row) => row.message), ['أولى', 'ثانية']);
      await waitFor(() => dispatcher.status.state == SmsAutoState.idle);
      expect(await device.queue.pendingCount(), 0);
    });

    test('رسالة ليلية تنتظر الصباح ثم تُرسل عند موعدها', () async {
      var now = DateTime(2026, 11, 17, 22, 30);
      final device = _Device(() => now);
      addTearDown(device.close);
      final platform = _Platform();
      final timers = <_FakeTimer>[];
      final worker = SmsDispatchWorker(
        queue: device.queue,
        settings: SmsSettingsService(device.db, device.writer),
        platform: platform,
        now: () => now,
        delay: (_) async {},
        sendInterval: Duration.zero,
        maxScheduledWait: Duration.zero,
      );
      final dispatcher = SmsAutoDispatcher(
        pendingCounts: device.queue.watchPendingCount(),
        isSender: device.sender.claimIfUnassigned,
        run: worker.start,
        stop: worker.stop,
        now: () => now,
        timer: (delay, callback) {
          final timer = _FakeTimer(delay, callback);
          timers.add(timer);
          return timer;
        },
      )..start();
      addTearDown(dispatcher.dispose);

      await device.queue.enqueue(phone: '0550123456', message: 'تنبيه الغياب');
      await waitFor(() => dispatcher.status.state == SmsAutoState.waiting);
      expect(platform.sent, isEmpty, reason: 'ساعات الهدوء');
      expect(dispatcher.status.until, DateTime(2026, 11, 18, 7));
      final wake = timers.lastWhere((timer) => timer.isActive);

      now = DateTime(2026, 11, 18, 7, 0, 5);
      wake.fire();
      await waitFor(() => platform.sent.length == 1);
      expect(platform.sent.single.message, 'تنبيه الغياب');
      await waitFor(() => dispatcher.status.state == SmsAutoState.idle);
    });

    test('نقص إذن الرسائل يظهر حالةً ولا تضيع الرسائل', () async {
      final device = _Device(() => DateTime(2026, 11, 17, 10));
      addTearDown(device.close);
      final platform = _Platform()..granted = false;
      final worker = SmsDispatchWorker(
        queue: device.queue,
        settings: SmsSettingsService(device.db, device.writer),
        platform: platform,
        now: device.clock,
        delay: (_) async {},
        sendInterval: Duration.zero,
        maxScheduledWait: Duration.zero,
      );
      final dispatcher = SmsAutoDispatcher(
        pendingCounts: device.queue.watchPendingCount(),
        isSender: device.sender.claimIfUnassigned,
        run: worker.start,
        stop: worker.stop,
      )..start();
      addTearDown(dispatcher.dispose);

      await device.queue.enqueue(phone: '0550123456', message: 'رسالة');
      await waitFor(() => dispatcher.status.state == SmsAutoState.blocked);
      expect(dispatcher.status.message, contains('السماح بإرسال الرسائل'));
      expect(await device.queue.pendingCount(), 1);

      // يمنح المستخدم الإذن ويعود إلى التطبيق.
      platform.granted = true;
      dispatcher.kick();
      await waitFor(() => platform.sent.length == 1);
      expect(await device.queue.pendingCount(), 0);
    });
  });

  group('watchPendingCount', () {
    test('يتغير مع الإضافة والإرسال ولا يكرر القيمة نفسها', () async {
      final device = _Device(() => DateTime(2026, 11, 17, 10));
      addTearDown(device.close);
      final counts = <int>[];
      final sub = device.queue.watchPendingCount().listen(counts.add);
      await waitFor(() => counts.isNotEmpty);
      expect(counts, [0]);

      await device.queue.enqueue(phone: '0550123456', message: 'واحدة');
      await waitFor(() => counts.last == 1);
      await device.queue.processNext((_) async {});
      await waitFor(() => counts.last == 0);
      expect(counts, [0, 1, 0]);
      await sub.cancel();
    });
  });
}
