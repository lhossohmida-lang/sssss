import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_sms/school_sms.dart';

void main() {
  late _Harness h;

  setUp(() {
    h = _Harness(DateTime(2026, 11, 13, 10));
  });
  tearDown(() => h.close());

  group('SmsQueueService', () {
    test('normalizes Algerian numbers and queues through SyncWriter', () async {
      final row = await h.queue.enqueue(
        phone: '0550 123 456',
        message: '  رسالة قصيرة  ',
      );

      expect(row.phone, '+213550123456');
      expect(row.message, 'رسالة قصيرة');
      expect(row.status, SmsStatus.pending.code);
      expect(row.notBefore, isNull);
      expect(row.createdBy, 'owner');
      expect(
        await (h.db.select(
          h.db.outbox,
        )..where((item) => item.targetTable.equals('sms_queue'))).get(),
        hasLength(1),
      );
    });

    test('rejects invalid numbers and empty messages', () async {
      await expectLater(
        h.queue.enqueue(phone: '021123456', message: 'رسالة'),
        throwsFormatException,
      );
      await expectLater(
        h.queue.enqueue(phone: '0550123456', message: '   '),
        throwsArgumentError,
      );
      expect(await h.db.select(h.db.smsQueue).get(), isEmpty);
    });

    test(
      'queue views are bounded and status counts include the full queue',
      () async {
        await h.queue.enqueue(phone: '0550123456', message: 'رسالة 1');
        await h.queue.enqueue(phone: '0550123457', message: 'رسالة 2');
        await h.insertSent(h.now);

        expect(await h.queue.loadQueue(limit: 1), hasLength(1));
        expect(await h.queue.watchQueue(limit: 1).first, hasLength(1));
        expect(await h.queue.watchStatusCounts().first, {
          SmsStatus.pending.code: 2,
          SmsStatus.sent.code: 1,
        });
      },
    );

    test('defers a message enqueued during night quiet hours', () async {
      h.now = DateTime(2026, 11, 13, 22, 15);
      final row = await h.queue.enqueue(
        phone: '0550123456',
        message: 'رسالة ليلية',
      );

      expect(_local(row.notBefore!), DateTime(2026, 11, 14, 7));
      var called = false;
      final result = await h.queue.processNext((_) async => called = true);
      expect(result.kind, SmsProcessKind.deferred);
      expect(result.messageId, isNull);
      expect(called, isFalse);
    });

    test('defers messages received before 07:00 until that morning', () async {
      h.now = DateTime(2026, 11, 13, 6, 59);
      final row = await h.queue.enqueue(
        phone: '0550123456',
        message: 'رسالة صباحية',
      );
      expect(_local(row.notBefore!), DateTime(2026, 11, 13, 7));
    });

    test('sends a due message and records the sent time', () async {
      final row = await h.queue.enqueue(
        phone: '0550123456',
        message: 'وصل الدفع',
      );
      final result = await h.queue.processNext((message) async {
        expect(message.id, row.id);
        expect(message.phone, '+213550123456');
        expect(message.message, 'وصل الدفع');
      });

      final saved = await h.message(row.id);
      expect(result.kind, SmsProcessKind.sent);
      expect(saved.status, SmsStatus.sent.code);
      expect(saved.attempts, 1);
      expect(_local(saved.sentAt!), h.now);
      expect(saved.lastError, isNull);
    });

    test('clears account credentials after successful delivery', () async {
      final row = await h.queue.enqueue(
        phone: '0550123456',
        message: 'البريد: a@school.local، كلمة السر: secret',
        kind: SmsTemplateKeys.accountCreated,
      );

      await h.queue.processNext((_) async {});

      final saved = await h.message(row.id);
      expect(saved.status, SmsStatus.sent.code);
      expect(saved.message, isEmpty);
    });

    test(
      'defers messages when the configured monthly cap is reached',
      () async {
        await h.settings.saveMonthlyLimit(1);
        await h.insertSent(h.now.subtract(const Duration(days: 1)));
        final row = await h.queue.enqueue(
          phone: '0550123456',
          message: 'وصل آخر',
        );
        var called = false;

        final result = await h.queue.processNext((_) async => called = true);

        expect(result.kind, SmsProcessKind.deferred);
        expect(result.messageId, row.id);
        expect(result.scheduledAt, DateTime(2026, 12, 1, 7));
        expect(
          _local((await h.message(row.id)).notBefore!),
          result.scheduledAt,
        );
        expect(called, isFalse);
      },
    );

    test('counts only sent messages in the current calendar month', () async {
      await h.settings.saveMonthlyLimit(1);
      await h.insertSent(DateTime(2026, 10, 31, 23));
      final row = await h.queue.enqueue(
        phone: '0550123456',
        message: 'تُرسل في نوفمبر',
      );

      final result = await h.queue.processNext((_) async {});

      expect(result.kind, SmsProcessKind.sent);
      expect((await h.message(row.id)).status, SmsStatus.sent.code);
    });

    test(
      'retries transient failures with increasing delays then fails',
      () async {
        final row = await h.queue.enqueue(
          phone: '0550123456',
          message: 'إشعار',
        );
        final expectedMinutes = [1, 5, 15, 60];

        for (final minutes in expectedMinutes) {
          final before = h.now;
          final result = await h.queue.processNext((_) async {
            h.now = h.now.add(const Duration(seconds: 30));
            throw StateError('انقطاع مؤقت');
          });
          final saved = await h.message(row.id);
          expect(result.kind, SmsProcessKind.retryScheduled);
          expect(saved.status, SmsStatus.pending.code);
          expect(saved.attempts, expectedMinutes.indexOf(minutes) + 1);
          expect(saved.lastError, contains('انقطاع مؤقت'));
          expect(
            saved.notBefore,
            _epoch(
              before.add(
                const Duration(seconds: 30) + Duration(minutes: minutes),
              ),
            ),
          );
          h.now = _local(saved.notBefore!);
        }

        final finalResult = await h.queue.processNext(
          (_) async => throw StateError('فشل نهائي بعد المحاولات'),
        );
        final saved = await h.message(row.id);
        expect(finalResult.kind, SmsProcessKind.failed);
        expect(saved.status, SmsStatus.failed.code);
        expect(saved.attempts, SmsQueueService.maxAttempts);
        expect(saved.notBefore, isNull);
      },
    );

    test('permanent transport failures do not retry', () async {
      final row = await h.queue.enqueue(phone: '0550123456', message: 'إشعار');

      final result = await h.queue.processNext(
        (_) async => throw const SmsTransportException(
          'رقم غير مدعوم',
          retryable: false,
        ),
      );

      final saved = await h.message(row.id);
      expect(result.kind, SmsProcessKind.failed);
      expect(saved.status, SmsStatus.failed.code);
      expect(saved.attempts, 1);
      expect(saved.lastError, 'رقم غير مدعوم');
    });

    test(
      'manual retry resets a failed row and preserves its message',
      () async {
        final row = await h.queue.enqueue(
          phone: '0550123456',
          message: 'إشعار',
        );
        await h.writer.patch(
          h.db.smsQueue,
          key: {'id': row.id},
          values: {
            'status': SmsStatus.failed.code,
            'attempts': 5,
            'last_error': 'فشل',
          },
        );

        expect(await h.queue.retry(row.id), isTrue);
        final saved = await h.message(row.id);
        expect(saved.status, SmsStatus.pending.code);
        expect(saved.attempts, 0);
        expect(saved.lastError, isNull);
        expect(saved.notBefore, isNull);
        expect(saved.message, 'إشعار');
        expect(await h.queue.retry('missing'), isFalse);
      },
    );

    test('does not send again while another call is in progress', () async {
      await h.queue.enqueue(phone: '0550123456', message: 'إشعار');
      final started = Completer<void>();
      final finish = Completer<void>();
      final first = h.queue.processNext((_) async {
        started.complete();
        await finish.future;
      });
      await started.future;

      final concurrent = await h.queue.processNext((_) async {});
      finish.complete();
      final sent = await first;

      expect(concurrent.kind, SmsProcessKind.busy);
      expect(sent.kind, SmsProcessKind.sent);
    });

    test(
      'marks stale sends uncertain without automatically retrying',
      () async {
        final interrupted = await h.queue.enqueue(
          phone: '0550123456',
          message: 'بيانات الدخول',
          kind: SmsTemplateKeys.accountCreated,
        );
        await h.writer.patch(
          h.db.smsQueue,
          key: {'id': interrupted.id},
          values: {'status': SmsStatus.sending.code, 'attempts': 1},
        );
        h.now = h.now.add(const Duration(minutes: 3));

        final recovered = await h.queue.recoverInterruptedSends();
        final saved = await h.message(interrupted.id);

        expect(recovered, 1);
        expect(saved.status, SmsStatus.failed.code);
        expect(saved.attempts, 1);
        expect(saved.message, 'بيانات الدخول');
        expect(saved.lastError, SmsQueueService.interruptedSendMessage);
        expect(saved.notBefore, isNull);
        expect(await h.queue.pendingCount(), 0);
      },
    );

    test('does not recover a send that is still within its timeout', () async {
      final row = await h.queue.enqueue(phone: '0550123456', message: 'رسالة');
      await h.writer.patch(
        h.db.smsQueue,
        key: {'id': row.id},
        values: {'status': SmsStatus.sending.code, 'attempts': 1},
      );

      expect(await h.queue.recoverInterruptedSends(), 0);
      expect((await h.message(row.id)).status, SmsStatus.sending.code);
    });
  });

  group('SmsSettingsService', () {
    test(
      'missing and zero limits mean unlimited; positive limits persist',
      () async {
        expect(await h.settings.monthlyLimit(), isNull);
        await h.settings.saveMonthlyLimit(0);
        expect(await h.settings.monthlyLimit(), isNull);
        await h.settings.saveMonthlyLimit(120);
        expect(await h.settings.monthlyLimit(), 120);
      },
    );

    test('rejects a negative limit and malformed stored value', () async {
      await expectLater(h.settings.saveMonthlyLimit(-1), throwsArgumentError);
      await h.writer.save(
        h.db.settings,
        SettingsCompanion.insert(
          key: SettingKeys.smsMonthlyLimit,
          value: 'unlimited-ish',
          updatedAt: h.writer.now(),
        ),
        key: {'key': SettingKeys.smsMonthlyLimit},
      );
      await expectLater(h.settings.monthlyLimit(), throwsFormatException);
    });

    test('stores the chosen SIM slot and clears it explicitly', () async {
      expect(await h.settings.simSlotIndex(), isNull);
      await h.settings.saveSimSlotIndex(1);
      expect(await h.settings.simSlotIndex(), 1);
      await h.settings.saveSimSlotIndex(null);
      expect(await h.settings.simSlotIndex(), isNull);
      await expectLater(h.settings.saveSimSlotIndex(-1), throwsArgumentError);
    });
  });

  group('SmsDispatchWorker', () {
    test(
      'uses selected SIM and waits three seconds between messages',
      () async {
        await h.settings.saveSimSlotIndex(1);
        await h.queue.enqueue(phone: '0550123456', message: 'الأولى');
        await h.queue.enqueue(phone: '0550123456', message: 'الثانية');
        final platform = _FakeSmsPlatform();
        final delays = <Duration>[];
        final worker = SmsDispatchWorker(
          queue: h.queue,
          settings: h.settings,
          platform: platform,
          now: () => h.now,
          delay: (duration) async {
            delays.add(duration);
            h.now = h.now.add(duration);
          },
        );

        final report = await worker.start();

        expect(report.sent, 2);
        expect(report.failed, 0);
        expect(platform.sentSlots, [1, 1]);
        expect(platform.started, 1);
        expect(platform.stopped, 1);
        expect(delays, [const Duration(seconds: 3)]);
      },
    );

    test(
      'requires an explicit SIM choice when multiple SIMs are active',
      () async {
        await h.queue.enqueue(phone: '0550123456', message: 'رسالة');
        final platform = _FakeSmsPlatform();
        final worker = SmsDispatchWorker(
          queue: h.queue,
          settings: h.settings,
          platform: platform,
          now: () => h.now,
          delay: (_) async {},
        );

        await expectLater(
          worker.start(),
          throwsA(isA<SmsTransportException>()),
        );
        expect(platform.started, 0);
        expect(platform.sentRows, isEmpty);
      },
    );

    test(
      'automatically uses the only SIM and waits through a retry delay',
      () async {
        await h.queue.enqueue(phone: '0550123456', message: 'رسالة');
        final platform = _FakeSmsPlatform(
          sims: const [
            SmsSimCard(
              slotIndex: 0,
              subscriptionId: 12,
              displayName: 'SIM 1',
              carrierName: 'Carrier',
            ),
          ],
          failuresRemaining: 1,
        );
        final delays = <Duration>[];
        final worker = SmsDispatchWorker(
          queue: h.queue,
          settings: h.settings,
          platform: platform,
          now: () => h.now,
          delay: (duration) async {
            delays.add(duration);
            h.now = h.now.add(duration);
          },
        );

        final report = await worker.start();

        expect(report.sent, 1);
        expect(report.retried, 1);
        expect(platform.sentSlots, [0, 0]);
        expect(delays, [
          const Duration(seconds: 3),
          const Duration(seconds: 57),
        ]);
      },
    );

    test('does not start Android components when the queue is empty', () async {
      final platform = _FakeSmsPlatform();
      final worker = SmsDispatchWorker(
        queue: h.queue,
        settings: h.settings,
        platform: platform,
      );

      final report = await worker.start();

      expect(report.sent, 0);
      expect(platform.permissionRequests, 0);
      expect(platform.started, 0);
    });

    test(
      'recovers a stale send before requesting Android permissions',
      () async {
        final row = await h.queue.enqueue(
          phone: '0550123456',
          message: 'رسالة',
        );
        await h.writer.patch(
          h.db.smsQueue,
          key: {'id': row.id},
          values: {'status': SmsStatus.sending.code, 'attempts': 1},
        );
        h.now = h.now.add(const Duration(minutes: 3));
        final platform = _FakeSmsPlatform();
        final worker = SmsDispatchWorker(
          queue: h.queue,
          settings: h.settings,
          platform: platform,
        );

        final report = await worker.start();

        expect(report.sent, 0);
        expect((await h.message(row.id)).status, SmsStatus.failed.code);
        expect(platform.permissionRequests, 0);
        expect(platform.started, 0);
      },
    );
  });

  group('SmsTemplateService', () {
    test(
      'lists defaults and renders variables while preserving unknown ones',
      () async {
        final templates = SmsTemplateService(h.db, h.writer);
        final listed = await templates.load();
        expect(listed, hasLength(SmsTemplateCatalog.definitions.length));
        expect({
          for (final item in listed) item.definition.key,
        }, SmsTemplateKeys.defaults.keys.toSet());
        expect(
          listed
              .firstWhere(
                (item) => item.definition.key == SmsTemplateKeys.accountCreated,
              )
              .isCustomized,
          isFalse,
        );

        await templates.save(
          SmsTemplateKeys.attendanceAbsent,
          'إشعار إلى {name}: {unknown}',
        );
        final view = await templates.get(SmsTemplateKeys.attendanceAbsent);
        expect(view.isCustomized, isTrue);
        expect(view.definition.variables, contains('name'));
        expect(
          await templates.render(SmsTemplateKeys.attendanceAbsent, {
            'name': 'أمين',
          }),
          'إشعار إلى أمين: {unknown}',
        );
      },
    );

    test(
      'requires known templates and non-empty text; reset restores default',
      () async {
        final templates = SmsTemplateService(h.db, h.writer);
        await expectLater(templates.save('unknown', 'نص'), throwsArgumentError);
        await expectLater(
          templates.save(SmsTemplateKeys.groupCreated, '   '),
          throwsArgumentError,
        );
        await templates.save(SmsTemplateKeys.groupCreated, 'نص معدل');
        await templates.reset(SmsTemplateKeys.groupCreated);
        final view = await templates.get(SmsTemplateKeys.groupCreated);
        expect(
          view.body,
          SmsTemplateKeys.defaults[SmsTemplateKeys.groupCreated],
        );
        expect(view.isCustomized, isFalse);
      },
    );
  });

  group('SmsBroadcastService', () {
    test(
      'deduplicates parents, groups siblings, and skips invalid contacts',
      () async {
        await h.db.batch((batch) {
          batch.insertAll(h.db.students, [
            _student('s1', 'سمير', 'بن علي', '0550123456'),
            _student('s2', 'نور', 'بن علي', '+213550123456'),
            _student('s3', 'أمين', 'بن علي', '021123456'),
            _student('s4', 'محذوف', 'بن علي', '0550123457', deletedAt: 10),
          ]);
        });
        final service = SmsBroadcastService(
          h.db,
          h.queue,
          SmsTemplateService(h.db, h.writer),
        );

        final result = await service.preview(SmsBroadcastAudience.parents);

        expect(result.recipients, hasLength(1));
        expect(result.recipients.single.phone, '+213550123456');
        expect(result.recipients.single.name, 'سمير بن علي، نور بن علي');
        expect(result.invalidContacts, 1);
      },
    );

    test('renders personalized broadcast messages before queueing', () async {
      await h.db
          .into(h.db.teachers)
          .insert(
            TeachersCompanion.insert(
              id: 't1',
              createdAt: 1,
              updatedAt: 1,
              name: 'الأستاذة ليلى',
              phone: '0660123456',
              email: 'laila@school.local',
              qrCode: 'T1',
            ),
          );
      final templates = SmsTemplateService(h.db, h.writer);
      await templates.save(
        SmsTemplateKeys.broadcast,
        '{school}: مرحباً {name}',
      );
      final service = SmsBroadcastService(h.db, h.queue, templates);

      final result = await service.enqueue(
        audience: SmsBroadcastAudience.teachers,
        schoolName: 'مدرسة النجاح',
      );
      final queued = await h.db.select(h.db.smsQueue).getSingle();

      expect(result.queued, 1);
      expect(result.failed, 0);
      expect(queued.phone, '+213660123456');
      expect(queued.kind, SmsTemplateKeys.broadcast);
      expect(queued.message, 'مدرسة النجاح: مرحباً الأستاذة ليلى');
    });
  });
}

StudentsCompanion _student(
  String id,
  String firstName,
  String lastName,
  String phone, {
  int? deletedAt,
}) => StudentsCompanion.insert(
  id: id,
  createdAt: 1,
  updatedAt: 1,
  firstName: firstName,
  lastName: lastName,
  parentPhone: phone,
  qrCode: 'QR-$id',
  deletedAt: Value(deletedAt),
);

class _Harness {
  _Harness(this.now) : db = AppDatabase(NativeDatabase.memory()) {
    writer = SyncWriter(
      db,
      actor: () => const Actor(userId: 'owner', userName: 'المدير'),
      clock: () => _epoch(now),
      idGenerator: () => 'sms-${++_ids}',
    );
    settings = SmsSettingsService(db, writer);
    queue = SmsQueueService(db, writer, settings: settings, now: () => now);
  }

  final AppDatabase db;
  late final SyncWriter writer;
  late final SmsSettingsService settings;
  late final SmsQueueService queue;
  DateTime now;
  int _ids = 0;

  Future<SmsQueueRow> message(String id) =>
      (db.select(db.smsQueue)..where((row) => row.id.equals(id))).getSingle();

  Future<void> insertSent(DateTime sentAt) async {
    await db
        .into(db.smsQueue)
        .insert(
          SmsQueueCompanion.insert(
            id: 'sent-${++_ids}',
            createdAt: 1,
            updatedAt: 1,
            phone: '+213550123456',
            message: 'أُرسلت سابقاً',
            status: Value(SmsStatus.sent.code),
            attempts: const Value(1),
            sentAt: Value(_epoch(sentAt)),
          ),
        );
  }

  Future<void> close() => db.close();
}

class _FakeSmsPlatform implements SmsDispatchPlatform {
  _FakeSmsPlatform({
    this.sims = const [
      SmsSimCard(
        slotIndex: 0,
        subscriptionId: 11,
        displayName: 'SIM 1',
        carrierName: 'Carrier',
      ),
      SmsSimCard(
        slotIndex: 1,
        subscriptionId: 22,
        displayName: 'SIM 2',
        carrierName: 'Carrier',
      ),
    ],
    this.failuresRemaining = 0,
  });

  final List<SmsSimCard> sims;
  int failuresRemaining;
  int permissionRequests = 0;
  int started = 0;
  int stopped = 0;
  final List<SmsQueueRow> sentRows = [];
  final List<int> sentSlots = [];

  @override
  Future<List<SmsSimCard>> availableSimCards() async => sims;

  @override
  Future<bool> requestPermissions() async {
    permissionRequests++;
    return true;
  }

  @override
  Future<void> send(SmsQueueRow message, {required int simSlotIndex}) async {
    sentRows.add(message);
    sentSlots.add(simSlotIndex);
    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw StateError('انقطاع مؤقت');
    }
  }

  @override
  Future<void> startForegroundService() async {
    started++;
  }

  @override
  Future<void> stopForegroundService() async {
    stopped++;
  }
}

int _epoch(DateTime local) => local.toUtc().millisecondsSinceEpoch;

DateTime _local(int stamp) =>
    DateTime.fromMillisecondsSinceEpoch(stamp, isUtc: true).toLocal();
