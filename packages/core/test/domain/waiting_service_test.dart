import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

import '../support/fixtures.dart';

void main() {
  late TestEnv env;
  late WaitingService waiting;
  late EnrolmentService enrolments;

  setUp(() async {
    env = TestEnv();
    waiting = WaitingService(env.db, env.writer);
    enrolments = EnrolmentService(
      env.db,
      env.writer,
      DuesService(env.db, env.writer),
      CycleService(env.db, env.writer),
    );
    await env.subject();
    await env.teacher();
    await env.db
        .into(env.db.userAccounts)
        .insert(
          UserAccountsCompanion.insert(
            id: 'owner1',
            createdAt: 1,
            updatedAt: 1,
            email: 'owner@school.local',
            role: UserRole.owner.code,
          ),
        );
    await env.db
        .into(env.db.userAccounts)
        .insert(
          UserAccountsCompanion.insert(
            id: 'worker1',
            createdAt: 1,
            updatedAt: 1,
            email: 'worker@school.local',
            role: UserRole.worker.code,
          ),
        );
  });
  tearDown(() => env.close());

  Future<String> wait(String studentId, {String? levelId}) async {
    if (!await _exists(env, studentId)) await env.student(id: studentId);
    return enrolments.addToWaiting(
      studentId: studentId,
      subjectId: 'sub',
      levelId: levelId,
      preferredTeacherId: 't1',
    );
  }

  Future<List<NotificationRow>> notifications() => env.db
      .select(env.db.notifications)
      .get()
      .then(
        (rows) => rows.where((n) => n.kind == 'waiting_threshold').toList(),
      );

  test('لا قوائم: فارغ، والقائمة بلا منتظرين لا تظهر', () async {
    expect(await waiting.lists(), isEmpty);
    final id = await wait('s1');
    await waiting.remove(listId: id, studentId: 's1');
    expect(await waiting.lists(), isEmpty);
  });

  test('القوائم بعدد منتظريها وأستاذها المفضّل وحدّها الافتراضي', () async {
    await wait('s1');
    await wait('s2');
    final list = (await waiting.lists()).single;
    expect(list.count, 2);
    expect(list.subjectName, 'رياضيات');
    expect(list.preferredTeacherName, 'الأستاذ t1');
    expect(list.threshold, 10);
    expect(list.reachedThreshold, isFalse);
    expect(list.title, 'رياضيات');
  });

  test('عنوان القائمة يتضمن المستوى، وكل مستوى قائمة', () async {
    await env.db
        .into(env.db.levels)
        .insert(
          LevelsCompanion.insert(
            id: 'lv',
            createdAt: 1,
            updatedAt: 1,
            name: '3 متوسط',
            stage: 'middle',
            sortOrder: 203,
          ),
        );
    await wait('s1');
    await wait('s2', levelId: 'lv');
    final titles = (await waiting.lists()).map((l) => l.title).toList();
    expect(titles, unorderedEquals(['رياضيات', 'رياضيات · 3 متوسط']));
  });

  test('المنتظرون بالأقدم أولاً، وتلميذ محذوف لا يظهر', () async {
    final id = await wait('s1');
    env.time += 10;
    await wait('s2');
    env.time += 10;
    await wait('s3');
    await env.db.customStatement(
      "UPDATE students SET deleted_at = 9 WHERE id = 's2'",
    );
    final students = await waiting.students(id);
    expect(students.map((s) => s.studentId), ['s1', 's3']);
    expect(students.first.parentPhone, '0550123456');
    expect(students.first.name, 'تلميذ s1');
    expect((await waiting.lists()).single.count, 2);
  });

  test('ضبط الحد: حدود مقبولة ومرفوضة وقائمة مجهولة', () async {
    final id = await wait('s1');
    await waiting.setThreshold(id, 3);
    expect((await waiting.lists()).single.threshold, 3);
    for (final bad in [0, -1, 501]) {
      await expectLater(
        waiting.setThreshold(id, bad),
        throwsA(isA<ValidationException>()),
      );
    }
    await expectLater(
      waiting.setThreshold('nope', 3),
      throwsA(isA<ValidationException>()),
    );
  });

  test('بلوغ الحد ينبّه المالك وحده مرة واحدة', () async {
    final id = await wait('s1');
    await waiting.setThreshold(id, 3);
    await wait('s2');
    expect(await notifications(), isEmpty);
    await wait('s3');
    final sent = await notifications();
    expect(sent, hasLength(1));
    expect(sent.single.userId, 'owner1');
    expect(sent.single.entity, 'waiting_lists');
    expect(sent.single.entityId, id);
    expect(sent.single.body, contains('رياضيات'));
    expect(sent.single.body, contains('3'));
    expect((await waiting.lists()).single.reachedThreshold, isTrue);

    // منتظر رابع فوق الحد لا يكرر التنبيه.
    await wait('s4');
    expect(await notifications(), hasLength(1));
  });

  test('نزول العدد دون الحد ثم بلوغه ثانية ينبّه من جديد', () async {
    final id = await wait('s1');
    await waiting.setThreshold(id, 2);
    await wait('s2');
    expect(await notifications(), hasLength(1));

    await waiting.remove(listId: id, studentId: 's2');
    expect(
      (await env.db.select(env.db.waitingLists).get())
          .single
          .thresholdNotifiedAt,
      isNull,
    );
    await wait('s2');
    expect(await notifications(), hasLength(2));
  });

  test(
    'رفع الحد بعد التنبيه ثم بلوغه ينبّه من جديد، وخفضه ينبّه فوراً',
    () async {
      final id = await wait('s1');
      await wait('s2');
      await waiting.setThreshold(id, 2);
      expect(await notifications(), hasLength(1));
      await waiting.setThreshold(id, 5);
      expect(await notifications(), hasLength(1));
      await waiting.setThreshold(id, 1);
      expect(await notifications(), hasLength(2));
    },
  );

  test('انتساب التلميذ إلى مجموعة يخرجه من القائمة ويعيد فحص الحد', () async {
    final id = await wait('s1');
    await wait('s2');
    await waiting.setThreshold(id, 2);
    expect(await notifications(), hasLength(1));
    await env.group();
    await enrolments.enrol(studentId: 's1', groupId: 'g1', monthlyPrice: 2000);
    expect((await waiting.lists()).single.count, 1);
    expect(
      (await env.db.select(env.db.waitingLists).get())
          .single
          .thresholdNotifiedAt,
      isNull,
    );
  });

  test('إخراج تلميذ غير موجود لا يفعل شيئاً', () async {
    final id = await wait('s1');
    await waiting.remove(listId: id, studentId: 'nobody');
    expect((await waiting.lists()).single.count, 1);
  });

  test('watchLists يتحدث عند إضافة منتظر', () async {
    await wait('s1');
    final seen = <int>[];
    final sub = waiting.watchLists().listen((l) => seen.add(l.single.count));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await wait('s2');
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await sub.cancel();
    expect(seen.first, 1);
    expect(seen.last, 2);
  });
}

Future<bool> _exists(TestEnv env, String id) async =>
    (await (env.db.select(
      env.db.students,
    )..where((s) => s.id.equals(id))).getSingleOrNull()) !=
    null;
