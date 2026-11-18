import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

Widget host(Widget child, {ThemeMode mode = ThemeMode.light}) => ClayApp(
  app: AppIdentity.admin,
  themeMode: mode,
  home: Scaffold(
    body: Center(child: SizedBox(width: 320, child: child)),
  ),
);

void main() {
  group('ClayTextField', () {
    testWidgets('يكتب ويُبلغ التغيير ويقرأ المتحكم', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final changes = <String>[];
      await tester.pumpWidget(
        host(
          ClayTextField(
            controller: controller,
            label: 'الاسم',
            hint: 'اكتب الاسم',
            onChanged: changes.add,
          ),
        ),
      );
      expect(find.text('الاسم'), findsOneWidget);
      expect(find.text('اكتب الاسم'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'أحمد');
      expect(controller.text, 'أحمد');
      expect(changes, ['أحمد']);
    });

    testWidgets('الخطأ يظهر تحت الحقل بدل النص المساعد', (tester) async {
      await tester.pumpWidget(
        host(const ClayTextField(error: 'رقم غير صالح', helper: 'مساعدة')),
      );
      expect(find.text('رقم غير صالح'), findsOneWidget);
      expect(find.text('مساعدة'), findsNothing);
      final style = tester.widget<Text>(find.text('رقم غير صالح')).style!;
      expect(
        style.color,
        ClayPalette.of(AppIdentity.admin, Brightness.light).status.danger,
      );
    });

    testWidgets('النص المساعد يظهر دون خطأ', (tester) async {
      await tester.pumpWidget(host(const ClayTextField(helper: '10 أرقام')));
      expect(find.text('10 أرقام'), findsOneWidget);
    });

    testWidgets('الهاتف: اتجاه يسار-يمين ومحاذاة لليسار', (tester) async {
      await tester.pumpWidget(
        host(
          const ClayTextField(
            textDirection: TextDirection.ltr,
            keyboardType: TextInputType.phone,
          ),
        ),
      );
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.textDirection, TextDirection.ltr);
      expect(field.textAlign, TextAlign.left);
      expect(field.keyboardType, TextInputType.phone);
    });

    testWidgets('كلمة السر: مخفية وسطر واحد', (tester) async {
      await tester.pumpWidget(
        host(const ClayTextField(obscureText: true, maxLines: 5)),
      );
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.obscureText, isTrue);
      expect(field.maxLines, 1);
    });

    testWidgets('المعطّل لا يقبل الكتابة', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        host(ClayTextField(controller: controller, enabled: false)),
      );
      await tester.enterText(find.byType(TextField), 'x');
      expect(controller.text, isEmpty);
    });

    testWidgets('المنسِّقات تُطبَّق (أرقام فقط)', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        host(
          ClayTextField(
            controller: controller,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), '05a5b0');
      expect(controller.text, '0550');
    });

    testWidgets('الأيقونة واللاحقة تظهران، والارتفاع 48 على الأقل', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const ClayTextField(
            prefixIcon: Icons.search,
            suffix: Icon(Icons.clear),
          ),
        ),
      );
      expect(find.byIcon(Icons.search), findsOneWidget);
      expect(find.byIcon(Icons.clear), findsOneWidget);
      expect(
        tester.getSize(find.byType(TextField)).height,
        greaterThanOrEqualTo(48),
      );
    });

    testWidgets('onSubmitted و onTap', (tester) async {
      String? submitted;
      var taps = 0;
      await tester.pumpWidget(
        host(
          ClayTextField(
            onSubmitted: (v) => submitted = v,
            onTap: () => taps++,
            readOnly: true,
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      expect(taps, 1);
      await tester.pumpWidget(
        host(ClayTextField(onSubmitted: (v) => submitted = v)),
      );
      await tester.enterText(find.byType(TextField), 'ok');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      expect(submitted, 'ok');
    });

    testWidgets('الوضع الداكن بلا أخطاء', (tester) async {
      await tester.pumpWidget(
        host(
          const ClayTextField(label: 'ل', error: 'خطأ'),
          mode: ThemeMode.dark,
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('ClayDropdown', () {
    const options = [
      ClayOption(value: 1, label: 'ابتدائي'),
      ClayOption(value: 2, label: 'متوسط'),
      ClayOption(value: 3, label: 'ثانوي'),
    ];

    testWidgets('يعرض التلميحة ثم القيمة المختارة', (tester) async {
      int? picked;
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (context, setState) => ClayDropdown<int>(
              label: 'المستوى',
              hint: 'اختر',
              options: options,
              value: picked,
              onChanged: (v) => setState(() => picked = v),
            ),
          ),
        ),
      );
      expect(find.text('المستوى'), findsOneWidget);
      expect(find.text('اختر'), findsOneWidget);
      await tester.tap(find.byType(DropdownButton<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('متوسط').last);
      await tester.pumpAndSettle();
      expect(picked, 2);
      expect(find.text('متوسط'), findsOneWidget);
      expect(find.text('اختر'), findsNothing);
    });

    testWidgets('قيمة غير موجودة في الخيارات تُعرض كأنها بلا اختيار', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          ClayDropdown<int>(
            hint: 'اختر',
            options: options,
            value: 99,
            onChanged: (_) {},
          ),
        ),
      );
      expect(find.text('اختر'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('بلا onChanged أو بلا خيارات: معطّلة', (tester) async {
      await tester.pumpWidget(
        host(const ClayDropdown<int>(options: options, onChanged: null)),
      );
      expect(
        tester
            .widget<DropdownButton<int>>(find.byType(DropdownButton<int>))
            .onChanged,
        isNull,
      );
      await tester.pumpWidget(
        host(ClayDropdown<int>(options: const [], onChanged: (_) {})),
      );
      expect(
        tester
            .widget<DropdownButton<int>>(find.byType(DropdownButton<int>))
            .onChanged,
        isNull,
      );
    });

    testWidgets('الخطأ يظهر تحتها', (tester) async {
      await tester.pumpWidget(
        host(
          ClayDropdown<int>(
            options: options,
            onChanged: (_) {},
            error: 'اختر مستوى',
          ),
        ),
      );
      expect(find.text('اختر مستوى'), findsOneWidget);
    });

    group('البحث في خانات الأسماء', () {
      const names = [
        ClayOption<String?>(value: null, label: 'كل الأساتذة'),
        ClayOption<String?>(
          value: 't1',
          label: 'أحمد بن علي',
          subtitle: 'رياضيات',
        ),
        ClayOption<String?>(value: 't2', label: 'فاطمة الزهراء'),
        ClayOption<String?>(value: 't3', label: 'عبد الرحمن'),
      ];

      // نتائج الورقة وحدها: النص المختار يظهر أيضاً في الحقل خلفها.
      Finder inList(String label) => find.descendant(
        of: find.byType(ListView),
        matching: find.text(label),
      );

      Future<List<String?>> open(
        WidgetTester tester, {
        String? value = 't2',
        bool searchable = true,
      }) async {
        final picks = <String?>[];
        await tester.pumpWidget(
          host(
            StatefulBuilder(
              builder: (context, setState) => ClayDropdown<String?>(
                label: 'الأستاذ',
                options: names,
                value: value,
                searchable: searchable,
                onChanged: (v) => setState(() {
                  value = v;
                  picks.add(v);
                }),
              ),
            ),
          ),
        );
        await tester.tap(find.byType(DropdownButton<String?>));
        await tester.pumpAndSettle();
        return picks;
      }

      testWidgets('تفتح ورقة فيها خانة بحث وكل الخيارات والمختار معلَّم', (
        tester,
      ) async {
        await open(tester);
        expect(find.byType(TextField), findsOneWidget);
        expect(find.text('ابحث بالاسم'), findsOneWidget);
        for (final label in [
          'كل الأساتذة',
          'أحمد بن علي',
          'فاطمة الزهراء',
          'عبد الرحمن',
        ]) {
          expect(find.text(label), findsWidgets, reason: label);
        }
        // المختار بعلامة صح.
        expect(find.byIcon(Icons.check_rounded), findsOneWidget);
        expect(find.text('رياضيات'), findsOneWidget);
      });

      testWidgets('تُصفّي أثناء الكتابة وتُهمل الهمزة والتاء المربوطة', (
        tester,
      ) async {
        await open(tester);
        await tester.enterText(find.byType(TextField), 'احمد');
        await tester.pump();
        expect(inList('أحمد بن علي'), findsOneWidget);
        expect(inList('فاطمة الزهراء'), findsNothing);

        await tester.enterText(find.byType(TextField), 'فاطمه');
        await tester.pump();
        expect(inList('فاطمة الزهراء'), findsOneWidget);
        expect(inList('أحمد بن علي'), findsNothing);

        // كلمات من الاسم بأي ترتيب، ويُبحث في السطر الثاني أيضاً.
        await tester.enterText(find.byType(TextField), 'علي احمد');
        await tester.pump();
        expect(inList('أحمد بن علي'), findsOneWidget);
        await tester.enterText(find.byType(TextField), 'رياضيات');
        await tester.pump();
        expect(inList('أحمد بن علي'), findsOneWidget);
        expect(inList('عبد الرحمن'), findsNothing);
      });

      testWidgets('لا نتائج مطابقة، ومسح البحث يعيد القائمة', (tester) async {
        await open(tester);
        await tester.enterText(find.byType(TextField), 'زززز');
        await tester.pump();
        expect(find.text('لا نتائج مطابقة للبحث'), findsOneWidget);
        await tester.tap(find.byTooltip('مسح البحث'));
        await tester.pump();
        expect(find.text('لا نتائج مطابقة للبحث'), findsNothing);
        expect(find.text('عبد الرحمن'), findsOneWidget);
      });

      testWidgets('النقر على نتيجة يختارها ويغلق الورقة', (tester) async {
        final picks = await open(tester);
        await tester.enterText(find.byType(TextField), 'عبد');
        await tester.pump();
        await tester.tap(find.text('عبد الرحمن'));
        await tester.pumpAndSettle();
        expect(picks, ['t3']);
        expect(find.byType(TextField), findsNothing, reason: 'أُغلقت الورقة');
        expect(find.text('عبد الرحمن'), findsOneWidget, reason: 'في الخانة');
      });

      testWidgets('Enter يختار الخيار الوحيد المطابق', (tester) async {
        final picks = await open(tester);
        await tester.enterText(find.byType(TextField), 'فاطمة');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();
        expect(picks, ['t2']);
        expect(find.byType(TextField), findsNothing, reason: 'أُغلقت الورقة');
      });

      testWidgets('Enter مع عدة نتائج لا يختار شيئاً', (tester) async {
        final picks = await open(tester);
        await tester.enterText(find.byType(TextField), 'ا');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();
        expect(picks, isEmpty);
        expect(find.byType(TextField), findsOneWidget, reason: 'الورقة مفتوحة');
      });

      testWidgets('قيمة null (مثل «الكل») اختيار صحيح', (tester) async {
        final picks = await open(tester);
        await tester.tap(find.text('كل الأساتذة').last);
        await tester.pumpAndSettle();
        expect(picks, [null]);
      });

      testWidgets('إغلاق الورقة دون اختيار لا يغيّر شيئاً', (tester) async {
        final picks = await open(tester);
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();
        expect(find.byType(TextField), findsNothing);
        expect(picks, isEmpty);
      });

      testWidgets('searchable: false تُبقي القائمة المنسدلة العادية', (
        tester,
      ) async {
        final picks = await open(tester, searchable: false);
        expect(find.byType(TextField), findsNothing);
        await tester.tap(find.text('عبد الرحمن').last);
        await tester.pumpAndSettle();
        expect(picks, ['t3']);
      });

      testWidgets('المعطّلة لا تفتح شيئاً', (tester) async {
        await tester.pumpWidget(
          host(
            const ClayDropdown<String?>(
              label: 'الأستاذ',
              options: names,
              onChanged: null,
            ),
          ),
        );
        await tester.tap(find.byType(DropdownButton<String?>));
        await tester.pumpAndSettle();
        expect(find.byType(TextField), findsNothing);
      });

      testWidgets('الخانة تُعلن زراً باسمها وقيمتها', (tester) async {
        final semantics = tester.ensureSemantics();
        await open(tester);
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();
        final node = tester.getSemantics(find.byType(InkWell).first);
        expect(node.label, 'الأستاذ');
        expect(node.value, 'فاطمة الزهراء');
        semantics.dispose();
      });
    });
  });

  group('ClayChip', () {
    testWidgets('النقر يستدعي onTap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        host(ClayChip(label: 'رياضيات', onTap: () => taps++)),
      );
      await tester.tap(find.text('رياضيات'));
      expect(taps, 1);
    });

    testWidgets('المحدّدة بلون التطبيق الرئيسي وتُعلن محدّدة', (tester) async {
      await tester.pumpWidget(
        host(ClayChip(label: 'رياضيات', selected: true, onTap: () {})),
      );
      final p = ClayPalette.of(AppIdentity.admin, Brightness.light);
      final surface = tester.widget<ClayContainer>(find.byType(ClayContainer));
      expect(surface.color, p.accent);
      final data = tester
          .getSemantics(find.byType(ClayChip))
          .getSemanticsData();
      expect(data.flagsCollection.isSelected.name, 'isTrue');
      expect(data.flagsCollection.isButton, isTrue);
    });

    testWidgets('بلا onTap: وسم للعرض بلا نقر', (tester) async {
      await tester.pumpWidget(host(const ClayChip(label: 'وسم')));
      expect(find.byType(GestureDetector), findsNothing);
    });

    testWidgets('مساحة اللمس 48 والأيقونة اختيارية', (tester) async {
      await tester.pumpWidget(
        host(ClayChip(label: 'ن', icon: Icons.star, onTap: () {})),
      );
      expect(find.byIcon(Icons.star), findsOneWidget);
      expect(
        tester.getSize(find.byType(ClayChip)).height,
        greaterThanOrEqualTo(48),
      );
    });

    testWidgets('اللون المخصص لا يملأ الشريحة', (tester) async {
      await tester.pumpWidget(
        host(const ClayChip(label: 'غائب', selected: true, color: Colors.red)),
      );
      expect(
        tester.widget<ClayContainer>(find.byType(ClayContainer)).color,
        isNull,
      );
    });
  });

  group('ClayToggle', () {
    testWidgets('النقر يعكس القيمة المرسلة', (tester) async {
      bool? last;
      await tester.pumpWidget(
        host(ClayToggle(value: false, onChanged: (v) => last = v)),
      );
      await tester.tap(find.byType(ClayToggle));
      expect(last, isTrue);
      await tester.pumpWidget(
        host(ClayToggle(value: true, onChanged: (v) => last = v)),
      );
      await tester.tap(find.byType(ClayToggle));
      expect(last, isFalse);
    });

    testWidgets('المعطّل لا يستجيب', (tester) async {
      await tester.pumpWidget(
        host(const ClayToggle(value: true, onChanged: null)),
      );
      await tester.tap(find.byType(ClayToggle));
      final data = tester
          .getSemantics(find.byType(ClayToggle))
          .getSemanticsData();
      expect(data.hasAction(SemanticsAction.tap), isFalse);
    });

    testWidgets('الدلالة: مشغّل ووصف', (tester) async {
      await tester.pumpWidget(
        host(
          ClayToggle(value: true, onChanged: (_) {}, semanticLabel: 'تنبيهات'),
        ),
      );
      final data = tester
          .getSemantics(find.byType(ClayToggle))
          .getSemanticsData();
      expect(data.label, 'تنبيهات');
      expect(data.flagsCollection.isToggled.name, 'isTrue');
    });

    testWidgets('المقبض في RTL: مشغّل نحو اليسار، مطفأ نحو اليمين', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(ClayToggle(value: false, onChanged: (_) {})),
      );
      final off = tester.getCenter(find.byType(DecoratedBox).last).dx;
      await tester.pumpWidget(host(ClayToggle(value: true, onChanged: (_) {})));
      await tester.pumpAndSettle();
      final on = tester.getCenter(find.byType(DecoratedBox).last).dx;
      expect(on, lessThan(off));
    });

    testWidgets('مساحة اللمس 48 ارتفاعاً', (tester) async {
      await tester.pumpWidget(
        host(ClayToggle(value: false, onChanged: (_) {})),
      );
      expect(tester.getSize(find.byType(ClayToggle)).height, 48);
    });
  });

  group('ClayCheckbox', () {
    testWidgets('النقر يعكس القيمة وتظهر علامة الصح عند التفعيل', (
      tester,
    ) async {
      bool? last;
      await tester.pumpWidget(
        host(ClayCheckbox(value: false, onChanged: (v) => last = v)),
      );
      expect(find.byIcon(Icons.check_rounded), findsNothing);
      await tester.tap(find.byType(ClayCheckbox));
      expect(last, isTrue);
      await tester.pumpWidget(
        host(ClayCheckbox(value: true, onChanged: (v) => last = v)),
      );
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      await tester.tap(find.byType(ClayCheckbox));
      expect(last, isFalse);
    });

    testWidgets('المعطّل لا يستجيب', (tester) async {
      await tester.pumpWidget(
        host(const ClayCheckbox(value: false, onChanged: null)),
      );
      await tester.tap(find.byType(ClayCheckbox));
      final data = tester
          .getSemantics(find.byType(ClayCheckbox))
          .getSemanticsData();
      expect(data.hasAction(SemanticsAction.tap), isFalse);
    });

    testWidgets('الدلالة ومساحة اللمس', (tester) async {
      await tester.pumpWidget(
        host(
          Align(
            child: ClayCheckbox(
              value: true,
              onChanged: (_) {},
              semanticLabel: 'حاضر',
            ),
          ),
        ),
      );
      final data = tester
          .getSemantics(find.byType(ClayCheckbox))
          .getSemanticsData();
      expect(data.label, 'حاضر');
      expect(data.flagsCollection.isChecked.name, 'isTrue');
      expect(tester.getSize(find.byType(ClayCheckbox)), const Size(48, 48));
    });
  });
}
