import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

Widget host(Widget child, {ThemeMode mode = ThemeMode.light}) => ClayApp(
  app: AppIdentity.admin,
  themeMode: mode,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('ClayCalendarMath', () {
    test('عدد أيام الشهر مع السنة الكبيسة', () {
      expect(ClayCalendarMath.daysInMonth(2026, 11), 30);
      expect(ClayCalendarMath.daysInMonth(2026, 12), 31);
      expect(ClayCalendarMath.daysInMonth(2026, 2), 28);
      expect(ClayCalendarMath.daysInMonth(2024, 2), 29);
      expect(ClayCalendarMath.daysInMonth(2100, 2), 28);
    });

    test('الأسبوع يبدأ بالسبت', () {
      expect(ClayCalendarMath.leadingBlanks(2026, 8), 0); // الأول سبت
      expect(ClayCalendarMath.leadingBlanks(2026, 11), 1); // الأول أحد
      expect(ClayCalendarMath.leadingBlanks(2026, 10), 5); // الأول خميس
      expect(ClayCalendarMath.leadingBlanks(2024, 3), 6); // الأول جمعة
    });

    test('عدد الصفوف من 4 إلى 6', () {
      expect(ClayCalendarMath.weekCount(2025, 2), 4);
      expect(ClayCalendarMath.weekCount(2026, 11), 5);
      expect(ClayCalendarMath.weekCount(2026, 10), 6);
    });

    test('ترتيب اليوم في الأسبوع', () {
      expect(ClayCalendarMath.weekdayIndex(DateTime(2026, 11, 7)), 0); // سبت
      expect(ClayCalendarMath.weekdayIndex(DateTime(2026, 11, 8)), 1); // أحد
      expect(ClayCalendarMath.weekdayIndex(DateTime(2026, 11, 13)), 6); // جمعة
    });

    test('العنوان بالأسماء الجزائرية وأرقام لاتينية', () {
      expect(ClayCalendarMath.title(2026, 11), 'نوفمبر 2026');
      expect(ClayCalendarMath.title(2026, 1), 'جانفي 2026');
      expect(ClayCalendarMath.monthNames, hasLength(12));
      expect(ClayCalendarMath.weekdayNames.first, 'السبت');
      expect(ClayCalendarMath.weekdayNames, hasLength(7));
      expect(ClayCalendarMath.weekdayLetters, hasLength(7));
    });
  });

  group('ClayCalendar', () {
    testWidgets('يعرض أيام الشهر كلها مرة واحدة', (tester) async {
      await tester.pumpWidget(
        host(ClayCalendar(year: 2026, month: 11, onMonthChanged: (_, _) {})),
      );
      for (var d = 1; d <= 30; d++) {
        expect(find.text('$d'), findsOneWidget, reason: 'اليوم $d');
      }
      expect(find.text('31'), findsNothing);
      expect(find.text('نوفمبر 2026'), findsOneWidget);
    });

    testWidgets('السبت على اليمين، ويوم 1 تحت الأحد', (tester) async {
      await tester.pumpWidget(
        host(ClayCalendar(year: 2026, month: 11, onMonthChanged: (_, _) {})),
      );
      final saturday = tester.getCenter(find.text('س')).dx;
      final friday = tester.getCenter(find.text('ج')).dx;
      expect(saturday, greaterThan(friday));
      final sunday = tester.getCenter(find.text('ح')).dx;
      expect(tester.getCenter(find.text('1')).dx, closeTo(sunday, 1));
    });

    testWidgets('السهمان ينقلان الشهر وعبر حدود السنة', (tester) async {
      (int, int)? last;
      await tester.pumpWidget(
        host(
          ClayCalendar(
            year: 2026,
            month: 12,
            onMonthChanged: (y, m) => last = (y, m),
          ),
        ),
      );
      await tester.tap(find.byTooltip('الشهر التالي'));
      expect(last, (2027, 1));
      await tester.tap(find.byTooltip('الشهر السابق'));
      expect(last, (2026, 11));
      await tester.pumpWidget(
        host(
          ClayCalendar(
            year: 2026,
            month: 1,
            onMonthChanged: (y, m) => last = (y, m),
          ),
        ),
      );
      await tester.tap(find.byTooltip('الشهر السابق'));
      expect(last, (2025, 12));
    });

    testWidgets('النقر على يوم يُبلغ رقمه ولا تُنقر الخانات الفارغة', (
      tester,
    ) async {
      final taps = <int>[];
      await tester.pumpWidget(
        host(
          ClayCalendar(
            year: 2026,
            month: 11,
            onMonthChanged: (_, _) {},
            onDayTap: taps.add,
          ),
        ),
      );
      await tester.tap(find.text('15'));
      expect(taps, [15]);
    });

    testWidgets('بلا onDayTap الأيام ليست أزراراً', (tester) async {
      await tester.pumpWidget(
        host(ClayCalendar(year: 2026, month: 11, onMonthChanged: (_, _) {})),
      );
      final cell = tester.getSemantics(find.text('15')).getSemanticsData();
      expect(cell.flagsCollection.isButton, isFalse);
    });

    testWidgets('الحالات تظهر كنقاط والمحدد بلون التطبيق', (tester) async {
      await tester.pumpWidget(
        host(
          ClayCalendar(
            year: 2026,
            month: 11,
            onMonthChanged: (_, _) {},
            statuses: const {
              3: ClayTone.success,
              4: ClayTone.danger,
              5: ClayTone.excused,
            },
            selectedDay: 4,
          ),
        ),
      );
      final p = ClayPalette.of(AppIdentity.admin, Brightness.light);
      final dots = tester
          .widgetList<Container>(find.byType(Container))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .where((d) => d.shape == BoxShape.circle && d.color != null)
          .map((d) => d.color)
          .toList();
      expect(dots, contains(p.status.success));
      expect(dots, contains(p.status.excused));
      // اليوم المحدد: نقطته بلون النص فوق اللون الرئيسي لا بلون الحالة.
      expect(dots, isNot(contains(p.status.danger)));
      expect(dots, contains(p.onAccent));
    });

    testWidgets('اليوم الحالي يُميَّز بإطار فقط في شهره', (tester) async {
      Future<int> framed(int year, int month) async {
        await tester.pumpWidget(
          host(
            ClayCalendar(
              year: year,
              month: month,
              onMonthChanged: (_, _) {},
              today: DateTime(2026, 11, 10),
            ),
          ),
        );
        return tester
            .widgetList<DecoratedBox>(find.byType(DecoratedBox))
            .map((d) => d.decoration)
            .whereType<BoxDecoration>()
            .where((d) => d.border != null && d.shape == BoxShape.circle)
            .length;
      }

      expect(await framed(2026, 11), 1);
      expect(await framed(2026, 10), 0);
    });

    testWidgets('شهر من ستة صفوف على شاشة صغيرة بلا فيضان', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        host(ClayCalendar(year: 2026, month: 10, onMonthChanged: (_, _) {})),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('31'), findsOneWidget);
    });
  });

  group('ClayTable', () {
    final columns = [
      ClayColumn<({String name, int amount})>(
        title: 'الاسم',
        flex: 2,
        cell: (_, r) => Text(r.name),
      ),
      ClayColumn<({String name, int amount})>(
        title: 'المبلغ',
        numeric: true,
        width: 120,
        cell: (_, r) => Text('${r.amount} دج'),
      ),
    ];
    final rows = [
      for (var i = 0; i < 200; i++) (name: 'تلميذ $i', amount: 2000 + i),
    ];

    Widget table({
      List<({String name, int amount})>? data,
      ValueChanged<({String name, int amount})>? onTap,
    }) => SizedBox(
      height: 400,
      width: 700,
      child: ClayTable<({String name, int amount})>(
        columns: columns,
        rows: data ?? rows,
        onRowTap: onTap,
      ),
    );

    testWidgets('الرأس والصفوف المرئية فقط (ListView.builder)', (tester) async {
      await tester.pumpWidget(
        ClayApp(
          app: AppIdentity.admin,
          home: Scaffold(body: table()),
        ),
      );
      expect(find.text('الاسم'), findsOneWidget);
      expect(find.text('المبلغ'), findsOneWidget);
      expect(find.text('تلميذ 0'), findsOneWidget);
      expect(find.text('تلميذ 199'), findsNothing);
      final list = tester.widget<ListView>(find.byType(ListView));
      expect(list.itemExtent, 52);
    });

    testWidgets('التمرير يصل إلى آخر صف', (tester) async {
      await tester.pumpWidget(
        ClayApp(
          app: AppIdentity.admin,
          home: Scaffold(body: table()),
        ),
      );
      await tester.dragUntilVisible(
        find.text('تلميذ 199'),
        find.byType(ListView),
        const Offset(0, -300),
      );
      expect(find.text('تلميذ 199'), findsOneWidget);
    });

    testWidgets('نقر الصف يُبلغ بياناته', (tester) async {
      ({String name, int amount})? tapped;
      await tester.pumpWidget(
        ClayApp(
          app: AppIdentity.admin,
          home: Scaffold(body: table(onTap: (r) => tapped = r)),
        ),
      );
      await tester.tap(find.text('تلميذ 2'));
      expect(tapped?.amount, 2002);
    });

    testWidgets('العمود الرقمي بعرضه الثابت ومحاذاته إلى النهاية', (
      tester,
    ) async {
      await tester.pumpWidget(
        ClayApp(
          app: AppIdentity.admin,
          home: Scaffold(body: table()),
        ),
      );
      final amount = tester.getRect(find.text('2000 دج'));
      final header = tester.getRect(find.text('المبلغ'));
      // في RTL «النهاية» هي اليسار: الرقم والعنوان على نفس الحافة.
      expect(amount.left, closeTo(header.left, 1));
    });

    testWidgets('بلا صفوف: حالة فارغة بدل القائمة', (tester) async {
      await tester.pumpWidget(
        ClayApp(
          app: AppIdentity.admin,
          home: Scaffold(body: table(data: const [])),
        ),
      );
      expect(find.text('لا توجد بيانات'), findsOneWidget);
      expect(find.byType(ListView), findsNothing);
    });

    test('ارتفاع صف أقل من 40 مرفوض', () {
      expect(
        () => ClayTable<int>(columns: const [], rows: const [], rowHeight: 30),
        throwsAssertionError,
      );
    });
  });

  group('ClayChartCard', () {
    Widget card({
      bool loading = false,
      bool isEmpty = false,
      String? error,
      VoidCallback? onRetry,
    }) => ClayChartCard(
      title: 'المداخيل',
      subtitle: 'نوفمبر 2026',
      chart: const Text('الرسم'),
      legend: const [ClayLegendItem(label: 'مدفوع', color: Colors.green)],
      loading: loading,
      isEmpty: isEmpty,
      error: error,
      onRetry: onRetry,
      height: 160,
    );

    testWidgets('يعرض الرسم والعنوان والدليل بارتفاع ثابت', (tester) async {
      await tester.pumpWidget(host(card()));
      expect(find.text('المداخيل'), findsOneWidget);
      expect(find.text('نوفمبر 2026'), findsOneWidget);
      expect(find.text('الرسم'), findsOneWidget);
      expect(find.text('مدفوع'), findsOneWidget);
      expect(
        tester
            .getSize(
              find
                  .ancestor(
                    of: find.text('الرسم'),
                    matching: find.byType(SizedBox),
                  )
                  .first,
            )
            .height,
        160,
      );
    });

    testWidgets('التحميل والفراغ والخطأ تحجب الرسم والدليل', (tester) async {
      await tester.pumpWidget(host(card(loading: true)));
      expect(find.text('الرسم'), findsNothing);
      expect(find.text('مدفوع'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpWidget(host(card(isEmpty: true)));
      expect(find.text('لا توجد بيانات للفترة'), findsOneWidget);
      expect(find.text('الرسم'), findsNothing);

      var retries = 0;
      await tester.pumpWidget(
        host(card(error: 'تعذّر الحساب', onRetry: () => retries++)),
      );
      expect(find.text('تعذّر الحساب'), findsOneWidget);
      await tester.tap(find.text('إعادة المحاولة'));
      expect(retries, 1);
    });
  });

  group('ClayChartColors', () {
    test('ألوان السلاسل مقروءة ومختلفة في الوضعين', () {
      for (final mode in Brightness.values) {
        final p = ClayPalette.of(AppIdentity.admin, mode);
        final colors = ClayChartColors.series(p);
        expect(colors.toSet().length, colors.length);
        for (final c in colors) {
          expect(contrast(c, p.surface), greaterThanOrEqualTo(3));
        }
        expect(ClayChartColors.at(p, colors.length), colors.first);
        expect(ClayChartColors.at(p, 1), p.status.success);
      }
    });
  });

  group('ClayIcons', () {
    test('الأيقونات معرَّفة ومختلفة بعضها عن بعض', () {
      const icons = [
        ClayIcons.home,
        ClayIcons.students,
        ClayIcons.teachers,
        ClayIcons.payments,
        ClayIcons.scan,
        ClayIcons.add,
        ClayIcons.logout,
      ];
      for (final icon in icons) {
        expect(icon.fontFamily, 'MaterialIcons');
      }
      expect(icons.toSet().length, icons.length);
    });
  });
}
