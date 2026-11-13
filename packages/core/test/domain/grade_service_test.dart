import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

import '../support/fixtures.dart';

void main() {
  late TestEnv env;
  late GradeService grades;

  setUp(() async {
    env = TestEnv();
    grades = GradeService(env.db, env.writer);
    await env.subject();
    await env.teacher();
    await env.teacher(id: 't2');
    await env.group();
    await env.student();
    await env.student(id: 's2');
    await env.student(id: 's3');
    await env.enroll(id: 'e1', studentId: 's1');
    await env.enroll(id: 'e2', studentId: 's2');
  });
  tearDown(() => env.close());

  Future<int> save(
    Map<String, GradeInput> results, {
    String title = 'اختبار الفصل',
    String date = '2026-11-14',
    double max = 20,
    String? teacher = 't1',
    String? oldTitle,
    String? oldDate,
  }) => grades.saveAssessment(
    groupId: 'g1',
    title: title,
    date: date,
    results: results,
    maxScore: max,
    teacherId: teacher,
    originalTitle: oldTitle,
    originalDate: oldDate,
  );

  test('حفظ اختبار: نتيجة لمن أُدخلت علامته وبلا غيره', () async {
    final saved = await save({
      's1': (score: 15.5, note: 'جيد'),
      's2': (score: null, note: ''),
    });
    expect(saved, 1);
    final rows = await env.db.select(env.db.grades).get();
    expect(rows, hasLength(1));
    expect(rows.single.studentId, 's1');
    expect(rows.single.score, 15.5);
    expect(rows.single.maxScore, 20);
    expect(rows.single.note, 'جيد');
    expect(rows.single.title, 'اختبار الفصل');
  });

  test('الكتابة عبر SyncWriter: سجل عمليات وطابور مزامنة', () async {
    await save({'s1': (score: 12.0, note: '')});
    expect(await env.db.select(env.db.auditLog).get(), isNotEmpty);
    final outbox = await env.db.select(env.db.outbox).get();
    expect(outbox.where((o) => o.targetTable == 'grades'), hasLength(1));
  });

  test(
    'إعادة الحفظ تعدّل السجل نفسه ولا تكرر، وإفراغ العلامة يحذفها',
    () async {
      await save({'s1': (score: 10.0, note: ''), 's2': (score: 8.0, note: '')});
      final firstId = (await env.db.select(env.db.grades).get())
          .firstWhere((g) => g.studentId == 's1')
          .id;
      await save({
        's1': (score: 14.0, note: 'تحسّن'),
        's2': (score: null, note: ''),
      });
      final live = (await env.db.select(env.db.grades).get())
          .where((g) => g.deletedAt == null)
          .toList();
      expect(live, hasLength(1));
      expect(live.single.id, firstId);
      expect(live.single.score, 14);
      expect(live.single.note, 'تحسّن');
    },
  );

  test('إعادة تسمية الاختبار أو تأريخه تنقل نتائجه', () async {
    await save({'s1': (score: 10.0, note: '')});
    await save(
      {'s1': (score: 11.0, note: '')},
      title: 'اختبار معدَّل',
      date: '2026-11-21',
      oldTitle: 'اختبار الفصل',
      oldDate: '2026-11-14',
    );
    final live = (await env.db.select(env.db.grades).get())
        .where((g) => g.deletedAt == null)
        .toList();
    expect(live, hasLength(1));
    expect(live.single.title, 'اختبار معدَّل');
    expect(live.single.date, '2026-11-21');
    expect(live.single.score, 11);
  });

  group('التحقق', () {
    test('عنوان وتاريخ وسلّم وعلامة خارج السلّم', () async {
      await expectLater(
        save(
          {'s1': (score: 25.0, note: ''), 's2': (score: -1.0, note: '')},
          title: ' ',
          date: 'غدا',
          max: 0,
        ),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.errors.keys.toSet(),
            'حقول',
            containsAll([
              GradeService.fieldTitle,
              GradeService.fieldDate,
              GradeService.fieldMax,
              GradeService.fieldScore('s1'),
              GradeService.fieldScore('s2'),
            ]),
          ),
        ),
      );
      expect(await env.db.select(env.db.grades).get(), isEmpty);
    });

    test('علامة بسلّم مخصص: حتى السلّم نفسه مقبولة', () async {
      await save({'s1': (score: 100.0, note: '')}, max: 100);
      expect((await env.db.select(env.db.grades).get()).single.maxScore, 100);
    });

    test('مجموعة أستاذ آخر أو مجهولة: مرفوضة', () async {
      await expectLater(
        save({'s1': (score: 10.0, note: '')}, teacher: 't2'),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.errors[GradeService.fieldGroup],
            'group',
            contains('ليست من'),
          ),
        ),
      );
      await expectLater(
        grades.saveAssessment(
          groupId: 'nope',
          title: 'ت',
          date: '2026-11-14',
          results: const {},
        ),
        throwsA(isA<ValidationException>()),
      );
    });
  });

  group('القراءة', () {
    test('الاختبارات الأحدث أولاً بمتوسطها وعدد نتائجها', () async {
      await save({
        's1': (score: 10.0, note: ''),
        's2': (score: 14.0, note: ''),
      });
      await save(
        {'s1': (score: 18.0, note: '')},
        title: 'فرض',
        date: '2026-11-21',
      );
      final list = await grades.assessments('g1');
      expect(list.map((a) => a.title), ['فرض', 'اختبار الفصل']);
      expect(list.last.count, 2);
      expect(list.last.average, 12);
      expect(list.first.average, 18);
      expect(list.first.maxScore, 20);
      expect(await grades.assessments('other'), isEmpty);
    });

    test('تلاميذ الاختبار بنتائجهم: المنتسبون ومن له نتيجة وإن غادر', () async {
      await save({'s1': (score: 10.0, note: 'ملاحظة')});
      await env.db.customStatement(
        "UPDATE group_students SET left_at = 5 WHERE id = 'e1'",
      );
      final list = await grades.entries(
        'g1',
        title: 'اختبار الفصل',
        date: '2026-11-14',
      );
      expect(list.map((e) => e.studentId), ['s1', 's2']);
      expect(list.first.score, 10);
      expect(list.first.note, 'ملاحظة');
      expect(list.first.gradeId, isNotNull);
      expect(list.last.score, isNull);
      // اختبار جديد: كل المنتسبين الحاليين بلا علامات.
      final fresh = await grades.entries(
        'g1',
        title: 'جديد',
        date: '2026-12-01',
      );
      expect(fresh.map((e) => e.studentId), ['s2']);
      expect(fresh.single.score, isNull);
    });

    test('حذف اختبار ناعم بكل نتائجه، ولأستاذه فقط', () async {
      await save({
        's1': (score: 10.0, note: ''),
        's2': (score: 14.0, note: ''),
      });
      await expectLater(
        grades.deleteAssessment(
          'g1',
          title: 'اختبار الفصل',
          date: '2026-11-14',
          teacherId: 't2',
        ),
        throwsA(isA<ValidationException>()),
      );
      expect(
        await grades.deleteAssessment(
          'g1',
          title: 'اختبار الفصل',
          date: '2026-11-14',
          teacherId: 't1',
        ),
        2,
      );
      expect(await grades.assessments('g1'), isEmpty);
      expect(await env.db.select(env.db.grades).get(), hasLength(2));
    });

    test('تنسيق العلامة', () {
      expect(GradeService.format(15.0), '15');
      expect(GradeService.format(15.5), '15.5');
    });

    test(
      'نتائج تلميذ في مجموعة: الأحدث أولاً بسلّمها ومتوسطها من 20',
      () async {
        await save({
          's1': (score: 15.0, note: 'جيد'),
          's2': (score: 9.0, note: ''),
        });
        await save(
          {'s1': (score: 40.0, note: '')},
          title: 'فرض',
          date: '2026-11-21',
          max: 50,
        );
        final list = await grades.forStudent('s1', 'g1');
        expect(list.map((g) => g.title), ['فرض', 'اختبار الفصل']);
        expect(list.first.score, 40);
        expect(list.first.maxScore, 50);
        expect(list.first.outOf20, 16);
        expect(list.last.note, 'جيد');
        // (16 + 15) / 2
        expect(GradeService.averageOutOf20(list), 15.5);
        expect(GradeService.averageOutOf20(const []), isNull);
        // تلميذ آخر ومجموعة أخرى ومحذوف.
        expect((await grades.forStudent('s2', 'g1')).single.score, 9);
        expect(await grades.forStudent('s1', 'other'), isEmpty);
        await grades.deleteAssessment(
          'g1',
          title: 'فرض',
          date: '2026-11-21',
          teacherId: 't1',
        );
        expect(
          (await grades.forStudent('s1', 'g1')).single.title,
          'اختبار الفصل',
        );
      },
    );

    test('watchAssessments يتحدث بعد الحفظ', () async {
      final seen = <int>[];
      final sub = grades
          .watchAssessments('g1')
          .listen((l) => seen.add(l.length));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await save({'s1': (score: 10.0, note: '')});
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await sub.cancel();
      expect(seen.first, 0);
      expect(seen.last, 1);
    });
  });
}
