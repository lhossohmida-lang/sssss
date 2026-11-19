import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

import '../support/fixtures.dart';

void main() {
  late TestEnv env;
  late SubjectService subjects;

  setUp(() async {
    env = TestEnv();
    subjects = SubjectService(env.db, env.writer);
    await env.subject(id: 'gen', price: 2500);
    await env.teacher(id: 't1');
    await env.teacher(id: 't2');
    for (final (id, name, order) in [
      ('lv2', '2 ثانوي', 302),
      ('lv3', '3 ثانوي', 303),
    ]) {
      await env.db
          .into(env.db.levels)
          .insert(
            LevelsCompanion.insert(
              id: id,
              createdAt: 1,
              updatedAt: 1,
              name: name,
              stage: 'secondary',
              sortOrder: order,
            ),
          );
    }
  });
  tearDown(() => env.close());

  Future<void> teaches(String teacher, String subject) => env.db
      .into(env.db.teacherSubjects)
      .insert(
        TeacherSubjectsCompanion.insert(
          teacherId: teacher,
          subjectId: subject,
          updatedAt: 1,
        ),
      );

  Future<Set<String>> teachersOf(String subject) async => {
    for (final row in await (env.db.select(
      env.db.teacherSubjects,
    )..where((t) => t.subjectId.equals(subject) & t.deletedAt.isNull())).get())
      row.teacherId,
  };

  group('ensureForLevel: لكل فوج مادته وسنته', () {
    test(
      'مادة عامة: تُنشأ مادة بالاسم نفسه لسنة الفوج بسعرها وأساتذتها',
      () async {
        await teaches('t1', 'gen');
        final specific = await subjects.ensureForLevel('gen', 'lv3');
        expect(specific.id, isNot('gen'));
        expect(specific.name, 'رياضيات');
        expect(specific.levelId, 'lv3');
        expect(specific.monthlyPrice, 2500);
        expect(await teachersOf(specific.id), {'t1'});
        // المادة العامة تبقى كما هي.
        final general = await (env.db.select(
          env.db.subjects,
        )..where((s) => s.id.equals('gen'))).getSingle();
        expect(general.levelId, isNull);
      },
    );

    test('استدعاء ثانٍ يعيد المادة نفسها، ويلحق ما أُضيف من أساتذة', () async {
      await teaches('t1', 'gen');
      final first = await subjects.ensureForLevel('gen', 'lv3');
      await teaches('t2', 'gen');
      final again = await subjects.ensureForLevel('gen', 'lv3');
      expect(again.id, first.id);
      expect(await teachersOf(again.id), {'t1', 't2'});
      final all = await (env.db.select(
        env.db.subjects,
      )..where((s) => s.deletedAt.isNull())).get();
      expect(all.where((s) => s.levelId == 'lv3'), hasLength(1));
    });

    test('سنة أخرى تعطي مادة أخرى', () async {
      final third = await subjects.ensureForLevel('gen', 'lv3');
      final second = await subjects.ensureForLevel('gen', 'lv2');
      expect(second.id, isNot(third.id));
      expect({third.levelId, second.levelId}, {'lv3', 'lv2'});
    });

    test('مادة لها سنة: تُعاد إن طابقت وإلا يُرفض الطلب', () async {
      final specific = await subjects.ensureForLevel('gen', 'lv3');
      expect(
        (await subjects.ensureForLevel(specific.id, 'lv3')).id,
        specific.id,
      );
      await expectLater(
        subjects.ensureForLevel(specific.id, 'lv2'),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.errors[SubjectService.fieldLevel],
            'message',
            contains('سنة دراسية أخرى'),
          ),
        ),
      );
    });

    test(
      'سنة مجهولة أو محذوفة أو مادة مجهولة: خطأ بحقله ولا مادة جديدة',
      () async {
        await expectLater(
          subjects.ensureForLevel('gen', 'nope'),
          throwsA(
            isA<ValidationException>().having((e) => e.errors.keys, 'keys', [
              SubjectService.fieldLevel,
            ]),
          ),
        );
        await env.db.customStatement(
          'UPDATE levels SET deleted_at = 5 WHERE id = \'lv2\'',
        );
        await expectLater(
          subjects.ensureForLevel('gen', 'lv2'),
          throwsA(isA<ValidationException>()),
        );
        await expectLater(
          subjects.ensureForLevel('missing', 'lv3'),
          throwsA(
            isA<ValidationException>().having((e) => e.errors.keys, 'keys', [
              SubjectService.fieldName,
            ]),
          ),
        );
        expect(await env.db.select(env.db.subjects).get(), hasLength(1));
      },
    );

    test('مادة السنة المحذوفة لا تُستعمل: تُنشأ جديدة', () async {
      final old = await subjects.ensureForLevel('gen', 'lv3');
      await subjects.remove(old.id);
      final fresh = await subjects.ensureForLevel('gen', 'lv3');
      expect(fresh.id, isNot(old.id));
      expect(fresh.deletedAt, isNull);
    });
  });

  group('SubjectItem.offeredFor: ما يُعرض لتلميذ في مستواه', () {
    SubjectItem item(String id, String name, String? level) => SubjectItem(
      subject: SubjectRow(
        id: id,
        createdAt: 1,
        updatedAt: 1,
        name: name,
        levelId: level,
        monthlyPrice: 1000,
      ),
      levelName: level,
    );

    final all = [
      item('math', 'رياضيات', null),
      item('math3', 'رياضيات', 'lv3'),
      item('math2', 'رياضيات', 'lv2'),
      item('phys', 'فيزياء', null),
      item('phys2', 'فيزياء', 'lv2'),
    ];

    test('بلا مستوى: كلها', () {
      expect(SubjectItem.offeredFor(all, null), all);
    });

    test('مواد مستواه، والعامة التي لا مثيل لها في مستواه فقط', () {
      final ids = SubjectItem.offeredFor(all, 'lv3').map((s) => s.id);
      expect(ids, ['math3', 'phys']);
      expect(SubjectItem.offeredFor(all, 'lv2').map((s) => s.id), [
        'math2',
        'phys2',
      ]);
    });
  });

  group('الانتظار: فوج السنة يُخرج التلميذ من قائمة المادة العامة', () {
    test('انتساب إلى فوج مادة السنة يزيله من انتظار مادتها العامة', () async {
      await teaches('t1', 'gen');
      await env.student(id: 's1');
      final dues = DuesService(env.db, env.writer);
      final enrolments = EnrolmentService(
        env.db,
        env.writer,
        dues,
        CycleService(env.db, env.writer),
      );
      await enrolments.addToWaiting(
        studentId: 's1',
        subjectId: 'gen',
        levelId: 'lv3',
      );
      expect(
        (await env.db.select(env.db.waitingEntries).get()).where(
          (e) => e.deletedAt == null,
        ),
        hasLength(1),
      );

      final specific = await subjects.ensureForLevel('gen', 'lv3');
      await env.group(
        id: 'g3',
        subjectId: specific.id,
        price: 2500,
        rate: 1000,
      );
      await enrolments.enrol(studentId: 's1', groupId: 'g3');
      expect(
        (await env.db.select(env.db.waitingEntries).get()).where(
          (e) => e.deletedAt == null,
        ),
        isEmpty,
      );
    });
  });
}
