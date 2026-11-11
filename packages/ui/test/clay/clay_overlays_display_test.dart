import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

Widget host(Widget child, {ThemeMode mode = ThemeMode.light}) => ClayApp(
  app: AppIdentity.admin,
  themeMode: mode,
  home: Scaffold(body: child),
);

double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// صورة PNG شفافة 1×1 صالحة.
final Uint8List onePixelPng = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xFF, 0xFF, 0x3F,
  0x00, 0x05, 0xFE, 0x02, 0xFE, 0xA7, 0x35, 0x81, 0x84, 0x00, 0x00, 0x00,
  0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

void main() {
  group('ClayDialog', () {
    testWidgets('عنوان ونص وأزرار', (tester) async {
      await tester.pumpWidget(
        host(
          const ClayDialog(
            title: 'حذف التلميذ',
            message: 'لا يمكن التراجع',
            actions: [Text('زر')],
          ),
        ),
      );
      expect(find.text('حذف التلميذ'), findsOneWidget);
      expect(find.text('لا يمكن التراجع'), findsOneWidget);
      expect(find.text('زر'), findsOneWidget);
    });

    test('message و content معاً مرفوض', () {
      expect(
        () => ClayDialog(title: 'ع', message: 'م', content: const SizedBox()),
        throwsAssertionError,
      );
    });

    testWidgets('محتوى طويل يتمرّر ولا يفيض', (tester) async {
      await tester.pumpWidget(
        host(
          ClayDialog(
            title: 'ع',
            content: Column(
              children: [for (var i = 0; i < 60; i++) Text('سطر $i')],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('showClayDialog يعيد قيمة الإغلاق', (tester) async {
      String? result;
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await showClayDialog<String>(
                context,
                title: 'اختر',
                actions: [
                  Builder(
                    builder: (context) => TextButton(
                      onPressed: () => Navigator.of(context).pop('تم'),
                      child: const Text('موافق'),
                    ),
                  ),
                ],
              ),
              child: const Text('افتح'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('افتح'));
      await tester.pumpAndSettle();
      expect(find.byType(ClayDialog), findsOneWidget);
      await tester.tap(find.text('موافق'));
      await tester.pumpAndSettle();
      expect(result, 'تم');
      expect(find.byType(ClayDialog), findsNothing);
    });
  });

  group('showClayConfirm', () {
    Future<bool?> open(
      WidgetTester tester, {
      required String tap,
      bool danger = false,
      bool dismissOutside = false,
    }) async {
      bool? result;
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await showClayConfirm(
                context,
                title: 'تأكيد الحذف',
                message: 'هل أنت متأكد؟',
                confirmLabel: 'احذف',
                danger: danger,
              ),
              child: const Text('افتح'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('افتح'));
      await tester.pumpAndSettle();
      if (dismissOutside) {
        await tester.tapAt(const Offset(5, 5));
      } else {
        await tester.tap(find.text(tap));
      }
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('التأكيد يعيد true', (tester) async {
      expect(await open(tester, tap: 'احذف'), isTrue);
    });

    testWidgets('الإلغاء يعيد false', (tester) async {
      expect(await open(tester, tap: 'إلغاء'), isFalse);
    });

    testWidgets('الإغلاق بالنقر خارج الحوار يعيد false', (tester) async {
      expect(await open(tester, tap: '', dismissOutside: true), isFalse);
    });

    testWidgets('الخطر يلوّن زر التأكيد بالأحمر', (tester) async {
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showClayConfirm(
                context,
                title: 'ت',
                message: 'م',
                danger: true,
              ),
              child: const Text('افتح'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('افتح'));
      await tester.pumpAndSettle();
      final confirm = tester.widget<ClayButton>(
        find.widgetWithText(ClayButton, 'تأكيد'),
      );
      expect(confirm.kind, ClayButtonKind.danger);
    });
  });

  group('ClayBottomSheet', () {
    testWidgets('showClayBottomSheet يعرض المحتوى والعنوان ويعيد القيمة', (
      tester,
    ) async {
      int? result;
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await showClayBottomSheet<int>(
                context,
                title: 'اختيار',
                builder: (context) => TextButton(
                  onPressed: () => Navigator.of(context).pop(7),
                  child: const Text('سبعة'),
                ),
              ),
              child: const Text('افتح'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('افتح'));
      await tester.pumpAndSettle();
      expect(find.text('اختيار'), findsOneWidget);
      await tester.tap(find.text('سبعة'));
      await tester.pumpAndSettle();
      expect(result, 7);
    });

    testWidgets('لوحة المفاتيح تدفع الورقة للأعلى', (tester) async {
      await tester.pumpWidget(
        const ClayApp(
          app: AppIdentity.admin,
          home: MediaQuery(
            data: MediaQueryData(viewInsets: EdgeInsets.only(bottom: 300)),
            child: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: ClayBottomSheet(child: Text('نموذج')),
              ),
            ),
          ),
        ),
      );
      final bottom = tester.getBottomLeft(find.byType(ClayContainer)).dy;
      expect(bottom, lessThanOrEqualTo(600 - 300));
    });
  });

  group('ClayBadge', () {
    testWidgets('كل الدلالات بنص مقروء (4.5) في الوضعين', (tester) async {
      for (final mode in [Brightness.light, Brightness.dark]) {
        final p = ClayPalette.of(AppIdentity.admin, mode);
        for (final tone in ClayTone.values) {
          expect(
            contrast(p.onAccent, ClayBadge.colorOf(p, tone)),
            greaterThanOrEqualTo(4.5),
            reason: '${mode.name} ${tone.name}',
          );
        }
      }
    });

    testWidgets('يعرض النص والأيقونة', (tester) async {
      await tester.pumpWidget(
        host(
          const ClayBadge(
            label: 'حاضر',
            tone: ClayTone.success,
            icon: Icons.check,
          ),
        ),
      );
      expect(find.text('حاضر'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('اللون يتبع الدلالة', (tester) async {
      await tester.pumpWidget(
        host(const ClayBadge(label: 'غائب', tone: ClayTone.danger)),
      );
      final p = ClayPalette.of(AppIdentity.admin, Brightness.light);
      final box = tester.widget<DecoratedBox>(find.byType(DecoratedBox).first);
      expect((box.decoration as BoxDecoration).color, p.status.danger);
    });
  });

  group('ClayAvatar', () {
    test('الأحرف الأولى', () {
      expect(ClayAvatar.initialsOf('محمد أمين بن علي'), 'مأ');
      expect(ClayAvatar.initialsOf('  سارة  '), 'س');
      expect(ClayAvatar.initialsOf(''), '؟');
      expect(ClayAvatar.initialsOf('   '), '؟');
      expect(ClayAvatar.initialsOf('Ali Ben'), 'AB');
    });

    testWidgets('بلا صورة: الأحرف داخل دائرة بالحجم المطلوب', (tester) async {
      await tester.pumpWidget(
        host(const Center(child: ClayAvatar(name: 'محمد أمين', size: 60))),
      );
      expect(find.text('مأ'), findsOneWidget);
      expect(tester.getSize(find.byType(ClayAvatar)), const Size(60, 60));
      expect(find.byType(ClipOval), findsOneWidget);
    });

    testWidgets('مع صورة: تُصغَّر بـ ResizeImage وتُعلن باسم صاحبها', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          Center(
            child: ClayAvatar(name: 'محمد', image: MemoryImage(onePixelPng)),
          ),
        ),
      );
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, isA<ResizeImage>());
      expect(find.bySemanticsLabel('محمد'), findsOneWidget);
    });

    testWidgets('فشل تحميل الصورة يعرض الأحرف', (tester) async {
      await tester.pumpWidget(
        host(
          Center(
            child: ClayAvatar(
              name: 'محمد',
              image: MemoryImage(Uint8List.fromList(const [1, 2, 3])),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.errorBuilder, isNotNull);
      tester.takeException();
    });
  });

  group('ClayProgress', () {
    Future<double> fraction(WidgetTester tester, double value) async {
      await tester.pumpWidget(host(Center(child: ClayProgress(value: value))));
      return tester
          .widget<FractionallySizedBox>(find.byType(FractionallySizedBox))
          .widthFactor!;
    }

    testWidgets('التعبئة بنسبة القيمة', (tester) async {
      expect(await fraction(tester, 0.25), 0.25);
      expect(await fraction(tester, 1), 1);
      expect(await fraction(tester, 0), 0);
    });

    testWidgets('القيم خارج المدى وNaN تُقصّ', (tester) async {
      expect(await fraction(tester, -3), 0);
      expect(await fraction(tester, 7), 1);
      expect(await fraction(tester, double.nan), 0);
    });

    testWidgets('الدلالة تعلن النسبة', (tester) async {
      await tester.pumpWidget(
        host(
          const Center(
            child: ClayProgress(value: 0.5, semanticLabel: 'الدورة'),
          ),
        ),
      );
      final data = tester
          .getSemantics(find.byType(ClayProgress))
          .getSemanticsData();
      expect(data.value, '50%');
      expect(data.label, 'الدورة');
    });

    testWidgets('تبدأ من يمين الشريط في RTL', (tester) async {
      await tester.pumpWidget(
        host(
          const Center(
            child: SizedBox(width: 200, child: ClayProgress(value: 0.5)),
          ),
        ),
      );
      final bar = tester.getRect(find.byType(ClayProgress));
      final fill = tester.getRect(find.byType(FractionallySizedBox));
      expect(fill.right, bar.right);
    });
  });

  group('ClaySkeleton', () {
    testWidgets('بلا ClayPulse ثابت بلا حركة', (tester) async {
      await tester.pumpWidget(
        host(const Center(child: ClaySkeleton(width: 80))),
      );
      expect(
        find.descendant(
          of: find.byType(ClaySkeleton),
          matching: find.byType(FadeTransition),
        ),
        findsNothing,
      );
      expect(tester.getSize(find.byType(ClaySkeleton)).width, 80);
    });

    testWidgets('داخل ClayPulse ينبض', (tester) async {
      await tester.pumpWidget(
        host(const ClayPulse(child: Center(child: ClaySkeleton(width: 80)))),
      );
      expect(find.byType(FadeTransition), findsWidgets);
      final before = tester
          .widget<FadeTransition>(find.byType(FadeTransition).last)
          .opacity
          .value;
      await tester.pump(const Duration(milliseconds: 450));
      final after = tester
          .widget<FadeTransition>(find.byType(FadeTransition).last)
          .opacity
          .value;
      expect(after, isNot(before));
    });

    testWidgets('تعطيل الحركة يوقف النبض', (tester) async {
      await tester.pumpWidget(
        const ClayApp(
          app: AppIdentity.admin,
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: ClayPulse(child: Center(child: ClaySkeleton(width: 80))),
            ),
          ),
        ),
      );
      final a = tester
          .widget<FadeTransition>(find.byType(FadeTransition).last)
          .opacity
          .value;
      await tester.pump(const Duration(milliseconds: 300));
      final b = tester
          .widget<FadeTransition>(find.byType(FadeTransition).last)
          .opacity
          .value;
      expect(a, b);
    });

    testWidgets('قائمة الهياكل: ListView.builder بارتفاع ثابت ومتحكم واحد', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(const ClaySkeletonList(count: 4, itemExtent: 80)),
      );
      final list = tester.widget<ListView>(find.byType(ListView));
      expect(list.itemExtent, 80);
      expect(find.byType(ClaySkeleton), findsNWidgets(12));
      expect(find.byType(ClayPulse), findsOneWidget);
      expect(find.bySemanticsLabel('جارٍ التحميل'), findsOneWidget);
    });

    testWidgets('الدائرة', (tester) async {
      await tester.pumpWidget(
        host(const Center(child: ClaySkeleton.circle(size: 40))),
      );
      expect(tester.getSize(find.byType(ClaySkeleton)), const Size(40, 40));
    });
  });

  group('حالات الشاشة', () {
    testWidgets('التحميل: مؤشر ورسالة', (tester) async {
      await tester.pumpWidget(host(const ClayLoadingView(message: 'لحظة')));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('لحظة'), findsOneWidget);
    });

    testWidgets('الفارغة: عنوان ورسالة وزر إجراء', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        host(
          ClayEmptyView(
            title: 'لا تلاميذ بعد',
            message: 'أضف أول تلميذ',
            actionLabel: 'إضافة تلميذ',
            onAction: () => taps++,
          ),
        ),
      );
      expect(find.text('لا تلاميذ بعد'), findsOneWidget);
      expect(find.text('أضف أول تلميذ'), findsOneWidget);
      await tester.tap(find.text('إضافة تلميذ'));
      expect(taps, 1);
    });

    testWidgets('الفارغة بلا إجراء لا تعرض زراً', (tester) async {
      await tester.pumpWidget(host(const ClayEmptyView(title: 'فارغ')));
      expect(find.byType(ClayButton), findsNothing);
    });

    testWidgets('الخطأ: رسالة وإعادة المحاولة', (tester) async {
      var retries = 0;
      await tester.pumpWidget(
        host(ClayErrorView(message: 'لا يوجد اتصال', onRetry: () => retries++)),
      );
      expect(find.text('تعذّر التحميل'), findsOneWidget);
      expect(find.text('لا يوجد اتصال'), findsOneWidget);
      await tester.tap(find.text('إعادة المحاولة'));
      expect(retries, 1);
    });

    testWidgets('الخطأ دون onRetry بلا زر', (tester) async {
      await tester.pumpWidget(host(const ClayErrorView(message: 'خطأ')));
      expect(find.byType(ClayButton), findsNothing);
    });

    testWidgets('شاشة صغيرة بنص طويل لا تفيض', (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        host(ClayErrorView(message: 'نص طويل ' * 40, onRetry: () {})),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
