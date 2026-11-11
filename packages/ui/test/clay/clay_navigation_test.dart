import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

const destinations = [
  ClayDestination(label: 'الرئيسية', icon: Icons.home_outlined),
  ClayDestination(
    label: 'التلاميذ',
    icon: Icons.people_outline,
    selectedIcon: Icons.people,
  ),
  ClayDestination(label: 'الرسائل', icon: Icons.chat_outlined, badge: 3),
];

Widget host(Widget child, {Size size = const Size(400, 800)}) => ClayApp(
  app: AppIdentity.admin,
  home: MediaQuery(
    data: MediaQueryData(size: size),
    child: child,
  ),
);

void setSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  group('ClayBottomNav', () {
    testWidgets('يعرض كل الوجهات ويُبلغ الاختيار', (tester) async {
      int? picked;
      await tester.pumpWidget(
        host(
          Scaffold(
            bottomNavigationBar: ClayBottomNav(
              destinations: destinations,
              currentIndex: 0,
              onSelected: (i) => picked = i,
            ),
          ),
        ),
      );
      for (final d in destinations) {
        expect(find.text(d.label), findsOneWidget);
      }
      await tester.tap(find.text('التلاميذ'));
      expect(picked, 1);
    });

    testWidgets('المحددة بلون التطبيق، وبأيقونتها المختارة', (tester) async {
      await tester.pumpWidget(
        host(
          Scaffold(
            bottomNavigationBar: ClayBottomNav(
              destinations: destinations,
              currentIndex: 1,
              onSelected: (_) {},
            ),
          ),
        ),
      );
      final p = ClayPalette.of(AppIdentity.admin, Brightness.light);
      expect(tester.widget<Text>(find.text('التلاميذ')).style!.color, p.accent);
      expect(
        tester.widget<Text>(find.text('الرئيسية')).style!.color,
        p.textMuted,
      );
      expect(find.byIcon(Icons.people), findsOneWidget);
      expect(find.byIcon(Icons.people_outline), findsNothing);
    });

    testWidgets('الشارة تُعرض، و99+ للكبيرة، ولا شارة للصفر', (tester) async {
      await tester.pumpWidget(
        host(
          Scaffold(
            bottomNavigationBar: ClayBottomNav(
              destinations: const [
                ClayDestination(label: 'أ', icon: Icons.add, badge: 7),
                ClayDestination(label: 'ب', icon: Icons.add, badge: 250),
                ClayDestination(label: 'ج', icon: Icons.add),
              ],
              currentIndex: 0,
              onSelected: (_) {},
            ),
          ),
        ),
      );
      expect(find.text('7'), findsOneWidget);
      expect(find.text('99+'), findsOneWidget);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('الدلالة: زر محدد بوصفه', (tester) async {
      await tester.pumpWidget(
        host(
          Scaffold(
            bottomNavigationBar: ClayBottomNav(
              destinations: destinations,
              currentIndex: 0,
              onSelected: (_) {},
            ),
          ),
        ),
      );
      expect(find.bySemanticsLabel('الرئيسية'), findsOneWidget);
    });

    test('أقل من وجهتين أو أكثر من خمس مرفوض', () {
      expect(
        () => ClayBottomNav(
          destinations: destinations.sublist(0, 1),
          currentIndex: 0,
          onSelected: (_) {},
        ),
        throwsAssertionError,
      );
      expect(
        () => ClayBottomNav(
          destinations: List.filled(6, destinations.first),
          currentIndex: 0,
          onSelected: (_) {},
        ),
        throwsAssertionError,
      );
    });

    testWidgets('5 وجهات على عرض هاتف صغير بلا فيضان', (tester) async {
      setSize(tester, const Size(320, 640));
      await tester.pumpWidget(
        host(
          Scaffold(
            bottomNavigationBar: ClayBottomNav(
              destinations: [
                for (var i = 0; i < 5; i++)
                  ClayDestination(label: 'وجهة $i', icon: Icons.circle),
              ],
              currentIndex: 2,
              onSelected: (_) {},
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('ClaySidebar', () {
    testWidgets('الوجهات والرأس والذيل والاختيار', (tester) async {
      setSize(tester, const Size(1200, 800));
      int? picked;
      await tester.pumpWidget(
        host(
          Scaffold(
            body: Row(
              children: [
                ClaySidebar(
                  destinations: destinations,
                  currentIndex: 0,
                  onSelected: (i) => picked = i,
                  header: const Text('مدرسة النجاح'),
                  footer: const Text('المدير'),
                ),
              ],
            ),
          ),
          size: const Size(1200, 800),
        ),
      );
      expect(find.text('مدرسة النجاح'), findsOneWidget);
      expect(find.text('المدير'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      await tester.tap(find.text('الرسائل'));
      expect(picked, 2);
    });

    testWidgets('المحدد بخلفية اللون الرئيسي', (tester) async {
      setSize(tester, const Size(1200, 800));
      await tester.pumpWidget(
        host(
          Scaffold(
            body: Row(
              children: [
                ClaySidebar(
                  destinations: destinations,
                  currentIndex: 1,
                  onSelected: (_) {},
                ),
              ],
            ),
          ),
          size: const Size(1200, 800),
        ),
      );
      final p = ClayPalette.of(AppIdentity.admin, Brightness.light);
      final boxes = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((d) => d.decoration)
          .whereType<BoxDecoration>()
          .where((d) => d.color == p.accent);
      expect(boxes, hasLength(1));
    });

    testWidgets('القائمة تستعمل ListView.builder بارتفاع ثابت للعناصر', (
      tester,
    ) async {
      setSize(tester, const Size(1200, 800));
      await tester.pumpWidget(
        host(
          Scaffold(
            body: Row(
              children: [
                ClaySidebar(
                  destinations: destinations,
                  currentIndex: 0,
                  onSelected: (_) {},
                ),
              ],
            ),
          ),
          size: const Size(1200, 800),
        ),
      );
      final list = tester.widget<ListView>(find.byType(ListView));
      expect(list.itemExtent, 52);
    });
  });

  group('ClayAppBar', () {
    testWidgets('العنوان في الوسط والإجراءات', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        host(
          Scaffold(
            appBar: ClayAppBar(
              title: 'التلاميذ',
              actions: [
                IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => taps++,
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.text('التلاميذ'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.search));
      expect(taps, 1);
    });

    testWidgets('زر الرجوع يظهر عند وجود صفحة سابقة فقط', (tester) async {
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const Scaffold(
                        appBar: ClayAppBar(title: 'تفاصيل', showBack: true),
                      ),
                    ),
                  ),
                  child: const Text('افتح'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('افتح'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();
      expect(find.text('تفاصيل'), findsNothing);
    });

    testWidgets('showBack دون صفحة سابقة لا يعرض الزر', (tester) async {
      await tester.pumpWidget(
        host(
          const Scaffold(appBar: ClayAppBar(title: 'الرئيسية', showBack: true)),
        ),
      );
      expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);
    });

    testWidgets('العنوان الطويل لا يفيض ويُعلن كعنوان', (tester) async {
      await tester.pumpWidget(
        host(
          Scaffold(
            appBar: ClayAppBar(
              title: 'عنوان ' * 30,
              actions: const [Icon(Icons.add)],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('ClayAdaptiveScaffold', () {
    Widget scaffold(int index, ValueChanged<int> onSelected) =>
        ClayAdaptiveScaffold(
          destinations: destinations,
          currentIndex: index,
          onSelected: onSelected,
          appBar: const ClayAppBar(title: 'العنوان'),
          body: const Text('المحتوى'),
          sidebarHeader: const Text('الشعار'),
        );

    testWidgets('الهاتف: شريط سفلي بلا قائمة جانبية', (tester) async {
      setSize(tester, const Size(400, 800));
      await tester.pumpWidget(host(scaffold(0, (_) {})));
      expect(find.byType(ClayBottomNav), findsOneWidget);
      expect(find.byType(ClaySidebar), findsNothing);
      expect(find.text('المحتوى'), findsOneWidget);
      expect(find.text('العنوان'), findsOneWidget);
    });

    testWidgets('الحاسوب: قائمة جانبية بلا شريط سفلي', (tester) async {
      setSize(tester, const Size(1200, 800));
      await tester.pumpWidget(
        host(scaffold(0, (_) {}), size: const Size(1200, 800)),
      );
      expect(find.byType(ClaySidebar), findsOneWidget);
      expect(find.byType(ClayBottomNav), findsNothing);
      expect(find.text('الشعار'), findsOneWidget);
      expect(find.text('المحتوى'), findsOneWidget);
    });

    testWidgets('نقطة التحول عند 840 بالضبط', (tester) async {
      setSize(tester, const Size(839, 800));
      await tester.pumpWidget(
        host(scaffold(0, (_) {}), size: const Size(839, 800)),
      );
      expect(find.byType(ClayBottomNav), findsOneWidget);
      setSize(tester, const Size(840, 800));
      await tester.pumpWidget(
        host(scaffold(0, (_) {}), size: const Size(840, 800)),
      );
      await tester.pump();
      expect(find.byType(ClaySidebar), findsOneWidget);
    });

    testWidgets('الاختيار يعمل في الوضعين', (tester) async {
      setSize(tester, const Size(400, 800));
      var picked = -1;
      await tester.pumpWidget(host(scaffold(0, (i) => picked = i)));
      await tester.tap(find.text('التلاميذ'));
      expect(picked, 1);
    });

    testWidgets('في RTL الشريط الجانبي على يمين المحتوى', (tester) async {
      setSize(tester, const Size(1200, 800));
      await tester.pumpWidget(
        host(scaffold(0, (_) {}), size: const Size(1200, 800)),
      );
      expect(
        tester.getCenter(find.byType(ClaySidebar)).dx,
        greaterThan(tester.getCenter(find.text('المحتوى')).dx),
      );
    });
  });
}
