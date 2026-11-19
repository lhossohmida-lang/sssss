import 'dart:async';

import 'package:drift/drift.dart' hide Column, isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';
import 'package:school_ui/testing.dart';

import 'groups_screens_test.dart' hide main;
import 'support/groups_nav.dart';

const _noneForAll = 'لا يوجد فوج لكل المستويات: لكل فوج مادته وسنته الدراسية';

/// مادة بسنة («فيزياء (3 متوسط)») وأستاذ يدرّسها، وسنة ثانية «4 متوسط» لمادة عامة.
Future<void> seedYears(WidgetTester tester, AppRuntime runtime) =>
    runDb(tester, () async {
      final db = runtime.db;
      await db
          .into(db.levels)
          .insert(
            LevelsCompanion.insert(
              id: 'lv4',
              createdAt: 1,
              updatedAt: 1,
              name: '4 متوسط',
              stage: 'middle',
              sortOrder: 204,
            ),
          );
      await db
          .into(db.subjects)
          .insert(
            SubjectsCompanion.insert(
              id: 'phys3',
              createdAt: 1,
              updatedAt: 1,
              name: 'فيزياء',
              levelId: const Value('lv3'),
              monthlyPrice: const Value(3000),
            ),
          );
      await db
          .into(db.teacherSubjects)
          .insert(
            TeacherSubjectsCompanion.insert(
              teacherId: 't1',
              subjectId: 'phys3',
              updatedAt: 1,
            ),
          );
    });

void main() {
  appTest(
    'مادة عامة: تظهر خانة السنة بعد اختيارها وتُلزَم، ولا يُنشأ شيء بدونها',
    (tester) async {
      final runtime = await openGroups(tester);
      await openForm(tester);
      expect(find.text(yearLabel), findsNothing);
      await pick(tester, 'المادة', 'رياضيات');
      expect(find.text(yearLabel), findsOneWidget);
      expect(find.text(_noneForAll), findsOneWidget);

      await pick(tester, 'الأستاذ', 'كمال');
      await submit(tester);
      expect(find.text('اختر السنة الدراسية لهذا الفوج'), findsOneWidget);
      final db = runtime.db;
      expect(await runDb(tester, () => db.select(db.groups).get()), isEmpty);
      expect(
        await runDb(tester, () => db.select(db.subjects).get()),
        hasLength(1),
        reason: 'لا مادة جديدة قبل اختيار السنة',
      );

      // اختيار السنة يزيل الخطأ.
      await pick(tester, yearLabel, '3 متوسط');
      expect(find.text('اختر السنة الدراسية لهذا الفوج'), findsNothing);
    },
  );

  appTest('اختيار السنة: يُنشأ الفوج على مادة السنة بسعر العامة وأساتذتها', (
    tester,
  ) async {
    final runtime = await openGroups(tester);
    await openForm(tester);
    await fillBasics(tester);
    await submit(tester);
    expect(find.text('رياضيات (3 متوسط) · الفوج 1'), findsOneWidget);
    await finishSetup(tester);

    final db = runtime.db;
    final subjects = await runDb(tester, () => db.select(db.subjects).get());
    final general = subjects.singleWhere((s) => s.id == 'math');
    final specific = subjects.singleWhere((s) => s.id != 'math');
    expect(general.levelId, isNull, reason: 'المادة العامة تبقى كما هي');
    expect((specific.name, specific.levelId), ('رياضيات', 'lv3'));
    expect(specific.monthlyPrice, 2000);
    final group = (await runDb(
      tester,
      () => db.select(db.groups).get(),
    )).single;
    expect(group.subjectId, specific.id);
    // أساتذة المادة العامة يدرّسون مادة السنة كذلك.
    final links = await runDb(
      tester,
      () => db.select(db.teacherSubjects).get(),
    );
    expect(
      links.where((l) => l.subjectId == specific.id).map((l) => l.teacherId),
      unorderedEquals(['t1', 't2']),
    );

    // القائمة: رياضيات › 3 متوسط › فوج 1.
    await openGroupList(tester, level: '3 متوسط');
    expect(find.text('فوج 1'), findsOneWidget);
  });

  appTest('مادة لها سنة أصلاً: لا خانة سنة والفوج على مادتها نفسها', (
    tester,
  ) async {
    final runtime = await openGroups(tester);
    await seedYears(tester, runtime);
    await openForm(tester);
    await pick(tester, 'المادة', 'فيزياء (3 متوسط)');
    expect(find.text(yearLabel), findsNothing);
    await pick(tester, 'الأستاذ', 'كمال');
    await typeIn(tester, rateLabel, '800');
    await submit(tester);
    await finishSetup(tester);
    final db = runtime.db;
    final group = (await runDb(
      tester,
      () => db.select(db.groups).get(),
    )).single;
    expect(group.subjectId, 'phys3');
    expect(
      await runDb(tester, () => db.select(db.subjects).get()),
      hasLength(2),
      reason: 'لا مادة جديدة: رياضيات العامة وفيزياء السنة',
    );
  });

  appTest('فوجان من مادة عامة بسنتين: لكل سنة مادتها وترقيمها', (tester) async {
    final runtime = await openGroups(tester);
    await seedYears(tester, runtime);
    for (final year in ['3 متوسط', '4 متوسط']) {
      await openForm(tester);
      await pick(tester, 'المادة', 'رياضيات');
      await pick(tester, yearLabel, year);
      await pick(tester, 'الأستاذ', 'كمال');
      await pick(tester, 'القاعة الافتراضية', 'القاعة 1 (30)');
      await pick(tester, 'اليوم', year == '3 متوسط' ? 'الثلاثاء' : 'الأربعاء');
      await submit(tester);
      await finishSetup(tester);
    }
    final db = runtime.db;
    final subjects = await runDb(tester, () => db.select(db.subjects).get());
    final years = subjects
        .where((s) => s.name == 'رياضيات' && s.levelId != null)
        .map((s) => s.levelId);
    expect(years, unorderedEquals(['lv3', 'lv4']));
    final groups = await runDb(tester, () => db.select(db.groups).get());
    expect(groups.map((g) => g.number), [
      1,
      1,
    ], reason: 'يبدأ ترقيم كل سنة من 1');
    expect(groups.map((g) => g.subjectId).toSet(), hasLength(2));
  });

  appTest('الإنشاء من قائمة انتظار: السنة تُقترح من مستواها', (tester) async {
    await openGroups(tester);
    final context = tester.element(find.byType(Scaffold).first);
    unawaited(
      GoRouter.of(context)
          .push('/groups/new?subject=math&teacher=t1&level=lv3'),
    );
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(420, 3200);
    await tester.pumpAndSettle();
    expect(find.text(yearLabel), findsOneWidget);
    // السنة المقترحة معروضة في خانتها.
    expect(find.text('3 متوسط'), findsOneWidget);
  });

  group('حصة المراجعة من مادة عامة', () {
    Future<void> openReview(WidgetTester tester) async {
      await tester.tap(
        find.widgetWithText(ClayButton, 'حصة مراجعة (حصة واحدة)'),
      );
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(420, 3200);
      await tester.pumpAndSettle();
    }

    appTest('السنة لازمة وتُنشأ الحصة على مادة السنة', (tester) async {
      final runtime = await openGroups(tester);
      await openReview(tester);
      await pick(tester, 'المادة', 'رياضيات');
      expect(find.text(yearLabel), findsOneWidget);
      await pick(tester, 'الأستاذ', 'كمال');
      await typeIn(tester, 'ثمن الحصة (دج)', '500');
      await tester.tap(find.widgetWithText(ClayButton, 'إنشاء حصة المراجعة'));
      await tester.pumpAndSettle();
      expect(find.text('اختر السنة الدراسية لحصة المراجعة'), findsOneWidget);
      final db = runtime.db;
      expect(await runDb(tester, () => db.select(db.groups).get()), isEmpty);

      await pick(tester, yearLabel, '3 متوسط');
      await tester.tap(find.widgetWithText(ClayButton, 'إنشاء حصة المراجعة'));
      await tester.pumpAndSettle();
      final group = (await runDb(
        tester,
        () => db.select(db.groups).get(),
      )).single;
      expect(group.isReview, isTrue);
      final subject = await runDb(
        tester,
        () => (db.select(
          db.subjects,
        )..where((s) => s.id.equals(group.subjectId))).getSingle(),
      );
      expect((subject.name, subject.levelId), ('رياضيات', 'lv3'));
    });
  });
}
