import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_ui/school_ui.dart';

import 'support/golden_support.dart';

/// لقطات golden لكل مكوّن في الوضعين الفاتح والداكن.
///
/// أي تغيير في الشكل يفشل الاختبار؛ لتحديث اللقطات عمداً:
/// `flutter test --update-goldens test/components_golden_test.dart`
/// وتُرفع الصور (والفروقات عند الفشل) كـ artifacts من مسار `check`.
void main() {
  setUpAll(setUpGoldens);

  Widget section(List<Widget> children) => SingleChildScrollView(
    physics: const NeverScrollableScrollPhysics(),
    padding: const EdgeInsets.all(ClaySpacing.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final child in children) ...[
          child,
          const SizedBox(height: ClaySpacing.md),
        ],
      ],
    ),
  );

  void golden(
    String name,
    Widget Function() build, {
    double width = 400,
    double height = 600,
  }) {
    for (final brightness in Brightness.values) {
      testWidgets('$name (${brightness.name})', (tester) async {
        await expectGolden(
          tester,
          name,
          child: build(),
          brightness: brightness,
          width: width,
          height: height,
        );
      });
    }
  }

  golden(
    'surfaces_buttons',
    () => section([
      const Row(
        children: [
          Expanded(child: ClayContainer(height: 70)),
          SizedBox(width: ClaySpacing.md),
          Expanded(child: ClayContainer(height: 70, depth: ClayDepth.pressed)),
        ],
      ),
      const ClayContainer.flat(
        height: 56,
        child: Center(child: Text('صف قائمة')),
      ),
      const ClayCard(child: Text('بطاقة تلميذ: محمد أمين')),
      ClayButton(label: 'حفظ', icon: ClayIcons.check, onPressed: () {}),
      ClayButton(
        label: 'إلغاء',
        kind: ClayButtonKind.secondary,
        onPressed: () {},
      ),
      ClayButton(label: 'حذف', kind: ClayButtonKind.danger, onPressed: () {}),
      ClayButton(label: 'جارٍ الحفظ', loading: true, onPressed: () {}),
      const ClayButton(label: 'معطّل', onPressed: null),
    ]),
    height: 760,
  );

  golden(
    'inputs',
    () => section([
      const ClayTextField(label: 'الاسم الكامل', hint: 'اكتب الاسم'),
      const ClayTextField(
        label: 'الهاتف',
        hint: '0550123456',
        textDirection: TextDirection.ltr,
        prefixIcon: ClayIcons.search,
        helper: '10 أرقام',
      ),
      const ClayTextField(
        label: 'البريد',
        error: 'البريد غير مكتوب بصيغة صحيحة',
      ),
      const ClayTextField(label: 'معطّل', hint: 'غير متاح', enabled: false),
      ClayDropdown<int>(
        label: 'المستوى',
        value: 2,
        options: const [
          ClayOption(value: 1, label: 'ابتدائي'),
          ClayOption(value: 2, label: 'متوسط'),
        ],
        onChanged: (_) {},
      ),
      ClayDropdown<int>(
        label: 'المادة',
        hint: 'اختر مادة',
        options: const [ClayOption(value: 1, label: 'رياضيات')],
        onChanged: (_) {},
      ),
    ]),
    height: 640,
  );

  golden(
    'selection',
    () => section([
      Wrap(
        spacing: ClaySpacing.sm,
        children: [
          const ClayChip(label: 'الكل', selected: true),
          ClayChip(label: 'رياضيات', onTap: () {}),
          ClayChip(label: 'فيزياء', icon: ClayIcons.subjects, onTap: () {}),
          const ClayChip(label: 'غائب', color: Color(0xFFC62F3A)),
        ],
      ),
      Row(
        children: [
          ClayToggle(value: true, onChanged: (_) {}),
          ClayToggle(value: false, onChanged: (_) {}),
          const ClayToggle(value: true, onChanged: null),
          const SizedBox(width: ClaySpacing.lg),
          ClayCheckbox(value: true, onChanged: (_) {}),
          ClayCheckbox(value: false, onChanged: (_) {}),
          const ClayCheckbox(value: true, onChanged: null),
        ],
      ),
    ]),
    height: 240,
  );

  const destinations = [
    ClayDestination(label: 'الرئيسية', icon: ClayIcons.home),
    ClayDestination(label: 'التلاميذ', icon: ClayIcons.students, badge: 3),
    ClayDestination(label: 'المدفوعات', icon: ClayIcons.payments),
    ClayDestination(label: 'المزيد', icon: ClayIcons.more),
  ];

  golden(
    'navigation_mobile',
    () => Column(
      children: [
        const ClayAppBar(title: 'التلاميذ', actions: [Icon(ClayIcons.search)]),
        const Spacer(),
        ClayBottomNav(
          destinations: destinations,
          currentIndex: 1,
          onSelected: (_) {},
        ),
      ],
    ),
    height: 420,
  );

  golden(
    'navigation_sidebar',
    () => Align(
      alignment: AlignmentDirectional.centerStart,
      child: ClaySidebar(
        destinations: destinations,
        currentIndex: 0,
        onSelected: (_) {},
        header: const Text('مدرسة النجاح'),
        footer: const Text('المدير'),
      ),
    ),
    width: 300,
    height: 460,
  );

  golden(
    'overlays',
    () => Column(
      children: [
        ClayDialog(
          title: 'حذف التلميذ',
          message: 'سيُحذف التلميذ من القوائم ويبقى سجله المالي.',
          actions: [
            ClayButton(
              label: 'حذف',
              kind: ClayButtonKind.danger,
              onPressed: () {},
            ),
            ClayButton(
              label: 'إلغاء',
              kind: ClayButtonKind.secondary,
              onPressed: () {},
            ),
          ],
        ),
        const Spacer(),
        const ClayBottomSheet(title: 'اختيار المجموعة', child: Text('المحتوى')),
      ],
    ),
    height: 640,
  );

  golden(
    'display',
    () => section([
      const Wrap(
        spacing: ClaySpacing.sm,
        runSpacing: ClaySpacing.sm,
        children: [
          ClayBadge(
            label: 'حاضر',
            tone: ClayTone.success,
            icon: ClayIcons.check,
          ),
          ClayBadge(label: 'غائب', tone: ClayTone.danger),
          ClayBadge(label: 'برخصة', tone: ClayTone.excused),
          ClayBadge(label: 'عليه مستحقات', tone: ClayTone.warning),
          ClayBadge(label: 'قيد الانتظار', tone: ClayTone.info),
          ClayBadge(label: 'عادي'),
        ],
      ),
      const Row(
        children: [
          ClayAvatar(name: 'محمد أمين'),
          SizedBox(width: ClaySpacing.md),
          ClayAvatar(name: 'سارة', size: 56),
          SizedBox(width: ClaySpacing.md),
          ClayAvatar(name: ''),
        ],
      ),
      const ClayProgress(value: 0.25),
      const ClayProgress(value: 0.75, height: 16),
      const SizedBox(height: 180, child: ClaySkeletonList(count: 2)),
    ]),
    height: 520,
  );

  golden(
    'screen_states',
    () => Column(
      children: [
        const Expanded(child: ClayLoadingView(message: 'جارٍ التحميل')),
        Expanded(
          child: ClayEmptyView(
            title: 'لا تلاميذ بعد',
            message: 'أضف أول تلميذ',
            actionLabel: 'إضافة تلميذ',
            onAction: () {},
          ),
        ),
        Expanded(
          child: ClayErrorView(message: 'لا يوجد اتصال', onRetry: () {}),
        ),
      ],
    ),
    height: 900,
  );

  golden(
    'calendar',
    () => section([
      ClayCalendar(
        year: 2026,
        month: 11,
        today: DateTime(2026, 11, 10),
        selectedDay: 12,
        statuses: const {
          1: ClayTone.success,
          2: ClayTone.success,
          3: ClayTone.danger,
          4: ClayTone.excused,
          7: ClayTone.success,
          12: ClayTone.success,
        },
        onMonthChanged: (_, _) {},
        onDayTap: (_) {},
      ),
    ]),
    height: 440,
  );

  golden(
    'table',
    () => section([
      SizedBox(
        height: 360,
        child: ClayTable<(String, int)>(
          columns: [
            ClayColumn(title: 'الاسم', flex: 2, cell: (_, r) => Text(r.$1)),
            ClayColumn(
              title: 'المبلغ',
              numeric: true,
              width: 110,
              cell: (_, r) => Text('${r.$2} دج'),
            ),
          ],
          rows: const [
            ('محمد أمين', 2000),
            ('سارة بن علي', 2500),
            ('ياسين', 1800),
            ('إيمان', 3000),
          ],
        ),
      ),
    ]),
    height: 440,
  );

  golden(
    'charts',
    () => section([
      const ClayChartCard(
        title: 'المداخيل',
        subtitle: 'نوفمبر 2026',
        height: 120,
        legend: [
          ClayLegendItem(label: 'مدفوع', color: Color(0xFF177A41)),
          ClayLegendItem(label: 'متبقٍ', color: Color(0xFFA85300)),
        ],
        chart: ColoredBox(color: Color(0x22000000)),
      ),
      const ClayChartCard(title: 'الحضور', chart: SizedBox(), isEmpty: true),
    ]),
    height: 720,
  );
}
