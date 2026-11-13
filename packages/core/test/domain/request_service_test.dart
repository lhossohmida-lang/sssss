import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

import '../support/fixtures.dart';

void main() {
  late TestEnv env;
  late CycleService cycles;
  late RequestService requests;

  // 2026-11-14 سبت، 2026-11-16 اثنين، 2026-11-17 ثلاثاء.
  const saturday = '2026-11-14';

  Future<void> account(String id, UserRole role, {String? entityId}) => env.db
      .into(env.db.userAccounts)
      .insert(
        UserAccountsCompanion.insert(
          id: id,
          createdAt: 1,
          updatedAt: 1,
          email: '$id@school.local',
          role: role.code,
          entityId: Value(entityId),
        ),
      );

  setUp(() async {
    env = TestEnv();
    cycles = CycleService(env.db, env.writer);
    requests = RequestService(
      env.db,
      env.writer,
      ScheduleService(env.db),
      cycles,
    );
    await env.subject();
    await env.teacher(id: 't1');
    await env.teacher(id: 't2');
    await env.room(id: 'r1');
    await env.room(id: 'r2');
    await env.group(
      id: 'g1',
      teacherId: 't1',
      roomId: 'r1',
      sessionsPerCycle: 4,
    );
    await env.slot(id: 'sl1', weekday: 6); // السبت 10:00–11:30
    await cycles.topUp('g1', fromDate: saturday);

    // وليّ له ابنان في المجموعة، ووليّ آخر له ابن واحد.
    await env.db
        .into(env.db.parents)
        .insert(
          ParentsCompanion.insert(
            id: 'p1',
            createdAt: 1,
            updatedAt: 1,
            phone: '0550123456',
            email: '0550123456@school.local',
          ),
        );
    for (final id in ['s1', 's2', 's3']) {
      await env.student(id: id);
      await env.enroll(id: 'gs-$id', studentId: id);
    }
    await (env.db.update(env.db.students)
          ..where((s) => s.id.isIn(['s1', 's2'])))
        .write(const StudentsCompanion(parentAccountId: Value('p1')));
    await (env.db.update(env.db.students)..where((s) => s.id.equals('s3')))
        .write(const StudentsCompanion(parentPhone: Value('0661112233')));

    await account('acc-owner', UserRole.owner);
    await account('acc-t1', UserRole.teacher, entityId: 't1');
    await account('acc-p1', UserRole.parent, entityId: 'p1');
  });

  tearDown(() => env.close());

  Future<SessionRow> firstSession() async =>
      (await cycles.cycleSessions('g1', 1)).first;

  Future<List<NotificationRow>> notifications(String userId) => (env.db.select(
    env.db.notifications,
  )..where((n) => n.userId.equals(userId))).get();

  Future<SessionRequestRow> reschedule({
    String date = '2026-11-16',
    int start = 900,
    int end = 990,
    String? room,
  }) async => requests.submit(
    teacherId: 't1',
    groupId: 'g1',
    type: SessionRequestType.reschedule,
    sessionId: (await firstSession()).id,
    newDate: date,
    newStartMinutes: start,
    newEndMinutes: end,
    newRoomId: room,
    reason: 'ظرف عائلي',
  );

  group('أرقام الهاتف', () {
    test('التحقق والتحويل إلى الصيغة الدولية', () {
      expect(PhoneNumbers.isValid('0550123456'), isTrue);
      expect(PhoneNumbers.isValid('06 61 11 22 33'), isTrue);
      expect(PhoneNumbers.isValid('+213770000000'), isTrue);
      expect(PhoneNumbers.isValid('00213770000000'), isTrue);
      expect(PhoneNumbers.isValid('0450123456'), isFalse);
      expect(PhoneNumbers.isValid('055012345'), isFalse);
      expect(PhoneNumbers.isValid('abc'), isFalse);
      expect(PhoneNumbers.toInternational('0550-12-34-56'), '+213550123456');
      expect(PhoneNumbers.toInternational('+213550123456'), '+213550123456');
      expect(() => PhoneNumbers.toInternational('123'), throwsFormatException);
    });
  });

  group('إرسال الطلب', () {
    test('يُحفظ قيد الانتظار، تُقترح قاعة، ويُشعَر صاحب المدرسة', () async {
      final request = await reschedule();
      expect(request.status, 'pending');
      expect(request.newRoomId, 'r1', reason: 'قاعة المجموعة متاحة فتُقترح');
      expect(request.reason, 'ظرف عائلي');
      expect(await requests.pendingCount(), 1);

      final ownerInbox = await notifications('acc-owner');
      expect(ownerInbox.single.kind, RequestService.notifyPending);
      expect(ownerInbox.single.title, contains('الأستاذ t1'));
      expect(ownerInbox.single.entityId, request.id);

      final session = await firstSession();
      expect(session.date, saturday, reason: 'لا يتغير شيء قبل الموافقة');
    });

    test('إن كانت قاعة المجموعة محجوزة تُقترح قاعة أخرى', () async {
      await env.group(id: 'g2', teacherId: 't2', roomId: 'r1');
      await env.slot(
        id: 'sl2',
        groupId: 'g2',
        weekday: 1,
        start: 900,
        end: 990,
      );
      final request = await reschedule();
      expect(request.newRoomId, 'r2');
    });

    test('تعارض الأستاذ يرفض الطلب فوراً', () async {
      await env.group(id: 'g2', teacherId: 't1', roomId: 'r2');
      await env.slot(
        id: 'sl2',
        groupId: 'g2',
        weekday: 1,
        start: 900,
        end: 990,
      );
      await expectLater(
        reschedule(),
        throwsA(
          isA<ScheduleConflictException>().having(
            (e) => e.conflicts.single.kind,
            'kind',
            ConflictKind.teacher,
          ),
        ),
      );
      expect(await requests.pendingCount(), 0);
    });

    test('قاعة محددة ومحجوزة ترفض الطلب', () async {
      await env.group(id: 'g2', teacherId: 't2', roomId: 'r2');
      await env.slot(
        id: 'sl2',
        groupId: 'g2',
        weekday: 1,
        start: 900,
        end: 990,
      );
      await expectLater(
        reschedule(room: 'r2'),
        throwsA(isA<ScheduleConflictException>()),
      );
    });

    test('بيانات ناقصة أو غير صالحة تُرفض برسالة واضحة', () async {
      final session = await firstSession();
      Future<void> bad(Future<Object?> Function() run) =>
          expectLater(run(), throwsA(isA<InvalidRequestException>()));

      await bad(
        () => requests.submit(
          teacherId: 't2',
          groupId: 'g1',
          type: SessionRequestType.cancel,
          sessionId: session.id,
        ),
      );
      await bad(
        () => requests.submit(
          teacherId: 't1',
          groupId: 'g1',
          type: SessionRequestType.cancel,
        ),
      );
      await bad(
        () => requests.submit(
          teacherId: 't1',
          groupId: 'g1',
          type: SessionRequestType.reschedule,
          sessionId: session.id,
        ),
      );
      await bad(
        () => requests.submit(
          teacherId: 't1',
          groupId: 'g1',
          type: SessionRequestType.advance,
          sessionId: session.id,
          newDate: '2026-11-20',
          newStartMinutes: 600,
          newEndMinutes: 690,
        ),
      );
      await cycles.closeSession(session.id);
      await bad(
        () => requests.submit(
          teacherId: 't1',
          groupId: 'g1',
          type: SessionRequestType.cancel,
          sessionId: session.id,
        ),
      );
    });
  });

  group('الموافقة', () {
    test('تغيير موعد: يُحدَّث الجدول وتُرسل SMS وإشعارات', () async {
      final request = await reschedule();
      final result = await requests.approve(
        request.id,
        reviewerId: 'acc-owner',
      );

      expect(result.request.status, 'approved');
      expect(result.request.reviewedBy, 'acc-owner');
      expect(result.request.reviewedAt, isNotNull);

      final moved = await (env.db.select(
        env.db.sessions,
      )..where((s) => s.id.equals(request.sessionId!))).getSingle();
      expect(moved.date, '2026-11-16');
      expect(moved.startMinutes, 900);
      expect(moved.roomId, 'r1');

      // وليّ بابنين يستلم رسالة واحدة، والوليّ الثاني رسالة.
      expect(result.smsQueued, 2);
      final sms = await env.db.select(env.db.smsQueue).get();
      expect(sms.map((m) => m.phone).toSet(), {
        '+213550123456',
        '+213661112233',
      });
      expect(sms.first.status, 'pending');
      final parentMessage = sms.firstWhere(
        (message) => message.phone == '+213550123456',
      );
      expect(parentMessage.kind, SmsTemplateKeys.requestApproved);
      expect(parentMessage.message, contains('المجموعة 1'));
      expect(parentMessage.message, contains('تلميذ s1، تلميذ s2'));
      expect(parentMessage.message, contains('نُقلت إلى الاثنين 2026-11-16'));

      expect(
        (await notifications('acc-p1')).single.kind,
        RequestService.notifyScheduleChange,
      );
      expect(
        (await notifications('acc-t1')).single.kind,
        RequestService.notifyApproved,
      );
      expect(await requests.pendingCount(), 0);
    });

    test('المدير يعدّل الوقت والقاعة عند الموافقة', () async {
      final request = await reschedule();
      final result = await requests.approve(
        request.id,
        reviewerId: 'acc-owner',
        date: '2026-11-17',
        startMinutes: 480,
        endMinutes: 570,
        roomId: 'r2',
        note: 'القاعة 1 مشغولة',
      );
      expect(result.request.newDate, '2026-11-17');
      expect(result.request.newRoomId, 'r2');
      expect(result.request.adminNote, 'القاعة 1 مشغولة');
      final moved = await (env.db.select(
        env.db.sessions,
      )..where((s) => s.id.equals(request.sessionId!))).getSingle();
      expect(
        (moved.date, moved.startMinutes, moved.roomId),
        ('2026-11-17', 480, 'r2'),
      );
      expect(
        (await notifications('acc-t1')).single.body,
        contains('القاعة 1 مشغولة'),
      );
    });

    test('إضافة حصة: تُنشأ حصة مضافة تُحسب في الدورة', () async {
      final request = await requests.submit(
        teacherId: 't1',
        groupId: 'g1',
        type: SessionRequestType.addSession,
        newDate: '2026-11-16',
        newStartMinutes: 900,
        newEndMinutes: 990,
      );
      expect(request.sessionId, isNull);
      final result = await requests.approve(
        request.id,
        reviewerId: 'acc-owner',
      );

      final sessions = await cycles.cycleSessions('g1', 1);
      final added = sessions.firstWhere((s) => s.status == 'added');
      expect(added.date, '2026-11-16');
      expect(added.sessionNumber, 2);
      expect(await cycles.countedSessions('g1', 1), 5);
      final sms = await env.db.select(env.db.smsQueue).get();
      expect(sms.first.message, contains('حصة إضافية يوم الاثنين 2026-11-16'));
      expect(sms.first.kind, SmsTemplateKeys.requestApproved);
      expect(result.smsQueued, 2);
    });

    test('تسبيق حصة إلى موعد أبكر', () async {
      final sessions = await cycles.cycleSessions('g1', 1);
      final second = sessions[1]; // 2026-11-21
      final request = await requests.submit(
        teacherId: 't1',
        groupId: 'g1',
        type: SessionRequestType.advance,
        sessionId: second.id,
        newDate: '2026-11-17',
        newStartMinutes: 600,
        newEndMinutes: 690,
      );
      await requests.approve(request.id, reviewerId: 'acc-owner');
      final moved = await (env.db.select(
        env.db.sessions,
      )..where((s) => s.id.equals(second.id))).getSingle();
      expect(moved.date, '2026-11-17');
      final sms = await env.db.select(env.db.smsQueue).get();
      expect(sms.first.message, contains('سُبّقت'));
    });

    test('إلغاء حصة: تُلغى وتُبرمج بديلة في آخر الدورة', () async {
      final session = await firstSession();
      final request = await requests.submit(
        teacherId: 't1',
        groupId: 'g1',
        type: SessionRequestType.cancel,
        sessionId: session.id,
        reason: 'مرض',
      );
      expect(request.newDate, isNull);
      await requests.approve(request.id, reviewerId: 'acc-owner');

      final cancelled = await (env.db.select(
        env.db.sessions,
      )..where((s) => s.id.equals(session.id))).getSingle();
      expect(cancelled.status, 'cancelled');
      expect(cancelled.sessionNumber, isNull);
      expect(await cycles.countedSessions('g1', 1), 4);
      final sms = await env.db.select(env.db.smsQueue).get();
      expect(
        sms.first.message,
        contains('أُلغيت حصة السبت 2026-11-14 على 10:00'),
      );
    });

    test('يُعاد فحص التعارض عند الموافقة إن تغيّر الجدول', () async {
      final request = await reschedule(room: 'r1');
      await env.group(id: 'g2', teacherId: 't2', roomId: 'r1');
      await env.slot(
        id: 'sl2',
        groupId: 'g2',
        weekday: 1,
        start: 900,
        end: 990,
      );

      await expectLater(
        requests.approve(request.id, reviewerId: 'acc-owner'),
        throwsA(isA<ScheduleConflictException>()),
      );
      expect(await requests.pendingCount(), 1, reason: 'الطلب يبقى معلّقاً');
      expect((await firstSession()).date, saturday);
      expect(await env.db.select(env.db.smsQueue).get(), isEmpty);

      final result = await requests.approve(
        request.id,
        reviewerId: 'acc-owner',
        roomId: 'r2',
      );
      expect(result.request.newRoomId, 'r2');
    });

    test('من غادر المجموعة لا يستلم وليّه رسالة', () async {
      await (env.db.update(env.db.groupStudents)
            ..where((gs) => gs.studentId.equals('s3')))
          .write(const GroupStudentsCompanion(leftAt: Value(5)));
      final request = await reschedule();
      final result = await requests.approve(
        request.id,
        reviewerId: 'acc-owner',
      );
      expect(result.smsQueued, 1);
    });
  });

  group('الرفض', () {
    test('يُشعَر الأستاذ بالسبب ولا يتغير شيء', () async {
      final request = await reschedule();
      final rejected = await requests.reject(
        request.id,
        reviewerId: 'acc-owner',
        note: 'القاعات كلها محجوزة',
      );
      expect(rejected.status, 'rejected');
      expect(rejected.adminNote, 'القاعات كلها محجوزة');
      expect((await firstSession()).date, saturday);
      final sms = await env.db.select(env.db.smsQueue).get();
      expect(sms, hasLength(1));
      expect(sms.single.kind, SmsTemplateKeys.requestRejected);
      expect(sms.single.phone, '+213770000000');
      expect(sms.single.message, contains('القاعات كلها محجوزة'));
      expect(await notifications('acc-p1'), isEmpty);

      final teacherInbox = await notifications('acc-t1');
      expect(teacherInbox.single.kind, RequestService.notifyRejected);
      expect(teacherInbox.single.body, 'القاعات كلها محجوزة');
      expect(await requests.pendingCount(), 0);
    });

    test('الطلب المراجَع لا يُراجَع مرتين', () async {
      final request = await reschedule();
      await requests.reject(request.id, reviewerId: 'acc-owner', note: 'لا');
      await expectLater(
        requests.approve(request.id, reviewerId: 'acc-owner'),
        throwsA(isA<InvalidRequestException>()),
      );
      await expectLater(
        requests.reject(request.id, reviewerId: 'acc-owner', note: 'لا'),
        throwsA(isA<InvalidRequestException>()),
      );
    });
  });

  test('الأستاذ يرى حالة كل طلباته', () async {
    final a = await reschedule();
    await requests.reject(a.id, reviewerId: 'acc-owner', note: 'لا');
    final b = await reschedule(date: '2026-11-17');
    await requests.approve(b.id, reviewerId: 'acc-owner');
    await requests.submit(
      teacherId: 't1',
      groupId: 'g1',
      type: SessionRequestType.addSession,
      newDate: '2026-11-18',
      newStartMinutes: 600,
      newEndMinutes: 690,
    );
    final mine =
        await (env.db.select(env.db.sessionRequests)
              ..where((r) => r.teacherId.equals('t1'))
              ..orderBy([(r) => OrderingTerm(expression: r.createdAt)]))
            .get();
    expect(mine.map((r) => r.status), ['rejected', 'approved', 'pending']);
  });

  group('معاينة الطلب وقوائمه', () {
    Future<RequestPreview> preview({
      SessionRequestType type = SessionRequestType.reschedule,
      String? date = '2026-11-16',
      int? start = 900,
      int? end = 990,
      String? room,
      bool withSession = true,
      String teacher = 't1',
    }) async => requests.preview(
      teacherId: teacher,
      groupId: 'g1',
      type: type,
      sessionId: withSession ? (await firstSession()).id : null,
      newDate: date,
      newStartMinutes: start,
      newEndMinutes: end,
      newRoomId: room,
    );

    test('موعد خال: صالح وتُقترح قاعة المجموعة ولا يُكتب شيء', () async {
      final result = await preview();
      expect(result.ok, isTrue);
      expect(result.suggestedRoom?.id, 'r1');
      expect(await env.db.select(env.db.sessionRequests).get(), isEmpty);
    });

    test('قاعة محددة محجوزة: تعارض بنوعه ورسالته', () async {
      final first = await firstSession();
      final clash = await preview(
        date: first.date,
        start: first.startMinutes,
        end: first.endMinutes,
        room: 'r1',
        withSession: false,
        type: SessionRequestType.addSession,
      );
      expect(clash.ok, isFalse);
      expect(clash.conflicts, isNotEmpty);
      expect(clash.conflicts.first.message, contains('المجموعة 1'));
    });

    test('أستاذ مشغول يمنع الطلب حتى بلا قاعة', () async {
      final first = await firstSession();
      final clash = await preview(
        date: first.date,
        start: first.startMinutes,
        end: first.endMinutes,
        withSession: false,
        type: SessionRequestType.addSession,
      );
      expect(clash.ok, isFalse);
      expect(
        clash.conflicts.any((c) => c.kind == ConflictKind.teacher),
        isTrue,
      );
    });

    test('أخطاء: بيانات ناقصة ونهاية قبل البداية وتسبيق لموعد متأخر', () async {
      expect((await preview(date: null)).error, contains('حدّد'));
      expect(
        (await preview(start: 990, end: 900)).error,
        contains('بعد بدايتها'),
      );
      final later = await preview(
        type: SessionRequestType.advance,
        date: '2026-12-30',
      );
      expect(later.error, contains('قبل موعدها'));
      expect(later.ok, isFalse);
    });

    test('مجموعة ليست للأستاذ، وحصة غير مختارة', () async {
      expect((await preview(teacher: 't2')).error, contains('ليست من'));
      expect((await preview(withSession: false)).error, contains('اختر الحصة'));
    });

    test('الإلغاء لا يحتاج موعداً وهو صالح', () async {
      final result = await preview(
        type: SessionRequestType.cancel,
        date: null,
        start: null,
        end: null,
      );
      expect(result.ok, isTrue);
    });

    test('الحصص المفتوحة من تاريخ: غير المنعقدة والملغاة فقط', () async {
      final sessions = await cycles.cycleSessions('g1', 1);
      await cycles.closeSession(sessions[0].id);
      await cycles.cancelSession(sessions[1].id);
      final open = await requests.openSessions('g1', fromDate: '2026-11-01');
      expect(open.map((s) => s.id), isNot(contains(sessions[0].id)));
      expect(open.map((s) => s.id), isNot(contains(sessions[1].id)));
      expect(open, isNotEmpty);
      final dates = open.map((s) => s.date).toList();
      expect([...dates]..sort(), dates, reason: 'الأقرب أولاً');
      expect(
        await requests.openSessions('g1', fromDate: '2099-01-01'),
        isEmpty,
      );
    });

    test('طلباتي: الأحدث أولاً بوصف مجموعتها وحصتها، ولأستاذها فقط', () async {
      final a = await reschedule();
      env.time += 10;
      final b = await requests.submit(
        teacherId: 't1',
        groupId: 'g1',
        type: SessionRequestType.cancel,
        sessionId: (await cycles.cycleSessions('g1', 1))[1].id,
      );
      final mine = await requests.mine('t1');
      expect(mine.map((r) => r.id), [b.id, a.id]);
      expect(mine.last.groupLabel, 'المجموعة 1 · رياضيات');
      expect(mine.last.type, SessionRequestType.reschedule);
      expect(mine.last.status, SessionRequestStatus.pending);
      expect(mine.last.sessionDate, isNotNull);
      expect(await requests.mine('t2'), isEmpty);
    });

    test('watchMine يتحدث بعد إرسال طلب', () async {
      final seen = <int>[];
      final sub = requests.watchMine('t1').listen((l) => seen.add(l.length));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await reschedule();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await sub.cancel();
      expect(seen.first, 0);
      expect(seen.last, 1);
    });
  });

  group('قائمة الإدارة', () {
    test('كل الطلبات بأساتذتها، وبحصر الحالة، وطلب واحد، والعدّاد', () async {
      final a = await reschedule();
      env.time += 10;
      final b = await requests.submit(
        teacherId: 't1',
        groupId: 'g1',
        type: SessionRequestType.cancel,
        sessionId: (await cycles.cycleSessions('g1', 1))[1].id,
      );
      await requests.reject(a.id, reviewerId: 'acc-owner', note: 'مرفوض');
      final all = await requests.all();
      expect(all.map((r) => r.id), [b.id, a.id]);
      expect(all.first.teacherName, 'الأستاذ t1');
      expect(
        (await requests.all(status: SessionRequestStatus.pending))
            .map((r) => r.id),
        [b.id],
      );
      expect(
        (await requests.all(status: SessionRequestStatus.rejected)).single.id,
        a.id,
      );
      expect((await requests.find(a.id))!.request.adminNote, 'مرفوض');
      expect(await requests.find('nope'), isNull);
      expect(await requests.watchPendingCount().first, 1);
    });
  });
}
