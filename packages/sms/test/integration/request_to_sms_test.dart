import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_sms/school_sms.dart';

/// رحلة كاملة عبر الخدمات الحقيقية: الأستاذ يطلب تغيير موعد حصة ← الإدارة
/// توافق (أو ترفض) فيُحدَّث الجدول ← رسائل SMS في الطابور (رسالة واحدة لكل
/// رقم وليّ) ← عامل الإرسال يفرغ الطابور على هاتف الإدارة.
void main() {
  late AppDatabase db;
  late SyncWriter writer;
  late CycleService cycles;
  late RequestService requests;
  late SmsQueueService queue;
  late SmsSettingsService settings;
  late GroupRow group;
  late SessionRow target;
  var ids = 0;
  // «الآن»: السبت 2026-11-14 الساعة 12:00 (خارج ساعات الهدوء الليلية)؛
  // ينتقل مع تأجيل عامل الإرسال فتنتهي مهلة إعادة المحاولة.
  var clock = DateTime(2026, 11, 14, 12);

  Future<void> insertParent(String id, String phone) => db
      .into(db.parents)
      .insert(
        ParentsCompanion.insert(
          id: id,
          createdAt: 1,
          updatedAt: 1,
          phone: phone,
          email: '$phone@school.local',
        ),
      );

  Future<void> insertAccount(String id, String role, String entityId) => db
      .into(db.userAccounts)
      .insert(
        UserAccountsCompanion.insert(
          id: id,
          createdAt: 1,
          updatedAt: 1,
          email: '$id@school.local',
          role: role,
          entityId: Value(entityId),
          displayName: Value(id),
        ),
      );

  Future<void> insertStudent(
    String id,
    String first,
    String parentId,
    String phone,
  ) async {
    await db
        .into(db.students)
        .insert(
          StudentsCompanion.insert(
            id: id,
            createdAt: 1,
            updatedAt: 1,
            firstName: first,
            lastName: 'بن علي',
            parentPhone: phone,
            qrCode: 'S-$id',
            parentAccountId: Value(parentId),
          ),
        );
    await db
        .into(db.groupStudents)
        .insert(
          GroupStudentsCompanion.insert(
            id: 'gs-$id',
            createdAt: 1,
            updatedAt: 1,
            groupId: group.id,
            studentId: id,
            joinedAt: 1,
            monthlyPrice: 2000,
          ),
        );
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    writer = SyncWriter(
      db,
      actor: () => const Actor(userId: 'u-owner', userName: 'المدير'),
      clock: () => clock.toUtc().millisecondsSinceEpoch,
      idGenerator: () => 'id-${++ids}',
    );
    cycles = CycleService(db, writer);
    requests = RequestService(db, writer, ScheduleService(db), cycles);
    settings = SmsSettingsService(db, writer);
    clock = DateTime(2026, 11, 14, 12);
    queue = SmsQueueService(db, writer, settings: settings, now: () => clock);
    // الهاتف ذو شريحتين: الإدارة تختار الشريحة قبل أول إرسال.
    await settings.saveSimSlotIndex(1);

    await SettingsService(
      db,
      writer,
    ).save(const SchoolSettings(schoolName: 'مدرسة النجاح'));
    await db
        .into(db.subjects)
        .insert(
          SubjectsCompanion.insert(
            id: 'math',
            createdAt: 1,
            updatedAt: 1,
            name: 'رياضيات',
            monthlyPrice: const Value(2000),
          ),
        );
    await db
        .into(db.teachers)
        .insert(
          TeachersCompanion.insert(
            id: 't1',
            createdAt: 1,
            updatedAt: 1,
            name: 'كمال',
            phone: '0660000001',
            email: 't1@school.local',
            qrCode: 'T-t1',
          ),
        );
    await db
        .into(db.teacherSubjects)
        .insert(
          TeacherSubjectsCompanion.insert(
            teacherId: 't1',
            subjectId: 'math',
            updatedAt: 1,
          ),
        );
    await db
        .into(db.rooms)
        .insert(
          RoomsCompanion.insert(
            id: 'r1',
            createdAt: 1,
            updatedAt: 1,
            name: 'القاعة 1',
          ),
        );
    group = await GroupService(db, writer, ScheduleService(db), cycles).create(
      subjectId: 'math',
      teacherId: 't1',
      roomId: 'r1',
      sessionsPerCycle: 4,
      slots: [
        const GroupSlotInput(weekday: 6, startMinutes: 600, endMinutes: 690),
      ],
      startDate: '2026-11-14',
    );
    target = (await cycles.cycleSessions(group.id, 1))[1]; // 2026-11-21
    // وليّان: الأول لتلميذين (رقم واحد)، والثاني لتلميذ.
    await insertParent('p1', '0550000001');
    await insertParent('p2', '0550000002');
    await insertStudent('s1', 'أحمد', 'p1', '0550000001');
    await insertStudent('s2', 'نور', 'p1', '0550000001');
    await insertStudent('s3', 'ياسين', 'p2', '0550000002');
    await insertAccount('u-p1', 'parent', 'p1');
    await insertAccount('u-p2', 'parent', 'p2');
    await insertAccount('u-teacher', 'teacher', 't1');
  });
  tearDown(() => db.close());

  Future<SessionRequestRow> submitReschedule() => requests.submit(
    teacherId: 't1',
    groupId: group.id,
    type: SessionRequestType.reschedule,
    sessionId: target.id,
    newDate: '2026-11-22',
    newStartMinutes: 840,
    newEndMinutes: 930,
    reason: 'ظرف عائلي',
  );

  Future<List<SmsQueueRow>> smsRows() => (db.select(
    db.smsQueue,
  )..orderBy([(r) => OrderingTerm(expression: r.phone)])).get();

  Future<SmsDispatchReport> dispatch(_FakePlatform platform) {
    final worker = SmsDispatchWorker(
      queue: queue,
      settings: settings,
      platform: platform,
      now: () => clock,
      delay: (duration) async => clock = clock.add(duration),
    );
    return worker.start();
  }

  test('الموافقة: يتحدث الجدول وتُوضع رسالة لكل رقم وليّ ثم تُرسل', () async {
    final request = await submitReschedule();
    expect(request.status, SessionRequestStatus.pending.code);
    // قبل الموافقة لا رسائل ولا تغيير في الجدول.
    expect(await smsRows(), isEmpty);
    expect(
      (await (db.select(
        db.sessions,
      )..where((s) => s.id.equals(target.id))).getSingle()).date,
      '2026-11-21',
    );

    final approval = await requests.approve(request.id, reviewerId: 'u-owner');
    expect(approval.request.status, SessionRequestStatus.approved.code);
    expect(approval.smsQueued, 2, reason: 'رقمان للوليّين لا ثلاث رسائل');

    // الجدول انتقل إلى الموعد الجديد.
    final moved = await (db.select(
      db.sessions,
    )..where((s) => s.id.equals(target.id))).getSingle();
    expect(moved.date, '2026-11-22');
    expect(moved.startMinutes, 840);
    expect(moved.endMinutes, 930);

    // الرسائل: نص القالب بالمتغيرات، ورقم دولي، وأسماء أبناء الوليّ معاً.
    final messages = await smsRows();
    expect(messages.map((m) => m.phone), ['+213550000001', '+213550000002']);
    expect(messages.every((m) => m.status == SmsStatus.pending.code), isTrue);
    expect(
      messages.every((m) => m.kind == SmsTemplateKeys.requestApproved),
      isTrue,
    );
    final first = messages.first.message;
    expect(first, contains('مدرسة النجاح'));
    expect(first, contains('رياضيات'));
    expect(first, contains('المجموعة ${group.number}'));
    expect(first, contains('2026-11-22'));
    expect(first, contains('أحمد بن علي'));
    expect(first, contains('نور بن علي'));
    expect(messages.last.message, contains('ياسين بن علي'));
    expect(messages.last.message, isNot(contains('أحمد')));

    // إشعار لكل وليّ وللأستاذ، مع بقاء كل شيء في طابور المزامنة.
    final notifications = await db.select(db.notifications).get();
    expect(
      notifications
          .where((n) => n.kind == RequestService.notifyScheduleChange)
          .map((n) => n.userId)
          .toSet(),
      {'u-p1', 'u-p2'},
    );
    expect(
      notifications
          .where((n) => n.kind == RequestService.notifyApproved)
          .map((n) => n.userId),
      ['u-teacher'],
    );
    final outbox = await db.select(db.outbox).get();
    expect(outbox.where((o) => o.targetTable == 'sms_queue'), hasLength(2));
    expect(
      outbox.where((o) => o.targetTable == 'session_requests'),
      isNotEmpty,
    );

    // عامل الإرسال يفرغ الطابور على الشريحة المختارة.
    final platform = _FakePlatform();
    final report = await dispatch(platform);
    expect(report.sent, 2);
    expect(report.failed, 0);
    expect(platform.sentTo, ['+213550000001', '+213550000002']);
    expect(platform.slots, [1, 1]);
    final after = await smsRows();
    expect(after.every((m) => m.status == SmsStatus.sent.code), isTrue);
    expect(after.every((m) => m.sentAt != null), isTrue);
    expect(platform.started, 1);
    expect(platform.stopped, 1);

    // إعادة الموافقة لا تكرر شيئاً.
    await expectLater(
      requests.approve(request.id, reviewerId: 'u-owner'),
      throwsA(isA<InvalidRequestException>()),
    );
    expect(await smsRows(), hasLength(2));
  });

  test('طلب ثانٍ بعد الإرسال: رسائله وحدها دون المساس بالمرسَلة', () async {
    final request = await submitReschedule();
    await requests.approve(request.id, reviewerId: 'u-owner');
    await dispatch(_FakePlatform());
    // طلب ثانٍ لحصة أخرى يُنشئ رسائله الخاصة، والأولى تبقى مرسلة.
    final second = await requests.submit(
      teacherId: 't1',
      groupId: group.id,
      type: SessionRequestType.cancel,
      sessionId: (await cycles.cycleSessions(group.id, 1))[2].id,
      reason: 'مرض',
    );
    final approval = await requests.approve(second.id, reviewerId: 'u-owner');
    expect(approval.smsQueued, 2);
    final all = await smsRows();
    expect(all, hasLength(4));
    expect(all.where((m) => m.status == SmsStatus.sent.code), hasLength(2));
    expect(all.where((m) => m.status == SmsStatus.pending.code), hasLength(2));
    expect(all.where((m) => m.message.contains('أُلغيت حصة')), hasLength(2));
  });

  test(
    'الرفض: رسالة واحدة إلى هاتف الأستاذ بملاحظة الإدارة، والجدول كما هو',
    () async {
      final request = await submitReschedule();
      final rejected = await requests.reject(
        request.id,
        reviewerId: 'u-owner',
        note: 'الموعد غير مناسب',
      );
      expect(rejected.status, SessionRequestStatus.rejected.code);
      expect(
        (await (db.select(
          db.sessions,
        )..where((s) => s.id.equals(target.id))).getSingle()).date,
        '2026-11-21',
      );
      final messages = await smsRows();
      expect(messages, hasLength(1));
      expect(messages.single.phone, '+213660000001');
      expect(messages.single.kind, SmsTemplateKeys.requestRejected);
      expect(messages.single.message, contains('كمال'));
      expect(messages.single.message, contains('تغيير موعد'));
      expect(messages.single.message, contains('الموعد غير مناسب'));

      final report = await dispatch(_FakePlatform());
      expect(report.sent, 1);
      expect((await smsRows()).single.status, SmsStatus.sent.code);
      // لا إشعار «تغيير في الجدول» للأولياء عند الرفض.
      expect(
        (await db.select(db.notifications).get()).where(
          (n) => n.kind == RequestService.notifyScheduleChange,
        ),
        isEmpty,
      );
    },
  );

  test(
    'انقطاع الإرسال: الرسالة تبقى وتُعاد المحاولة بعد مهلتها ثم تُرسل',
    () async {
      final request = await submitReschedule();
      await requests.approve(request.id, reviewerId: 'u-owner');
      final flaky = _FakePlatform(failuresRemaining: 1);
      final report = await dispatch(flaky);
      // الأولى فشلت مرة فجُدولت بعد دقيقة، ثم أُرسلت الرسالتان.
      expect(report.retried, 1);
      expect(report.sent, 2);
      expect(report.failed, 0);
      final all = await smsRows();
      expect(all.every((m) => m.status == SmsStatus.sent.code), isTrue);
      expect(all.map((m) => m.attempts).reduce((a, b) => a + b), 3);
      expect(flaky.sentTo, hasLength(2));
    },
  );
}

class _FakePlatform implements SmsDispatchPlatform {
  _FakePlatform({this.failuresRemaining = 0});

  int failuresRemaining;
  int started = 0;
  int stopped = 0;
  final List<String> sentTo = [];
  final List<int> slots = [];

  @override
  Future<List<SmsSimCard>> availableSimCards() async => const [
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
  ];

  @override
  Future<bool> requestPermissions() async => true;

  @override
  Future<void> send(SmsQueueRow message, {required int simSlotIndex}) async {
    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw StateError('انقطاع مؤقت');
    }
    sentTo.add(message.phone);
    slots.add(simSlotIndex);
  }

  @override
  Future<void> startForegroundService() async => started++;

  @override
  Future<void> stopForegroundService() async => stopped++;
}
