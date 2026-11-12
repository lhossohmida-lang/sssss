import 'package:flutter_test/flutter_test.dart';
import 'package:school_ui/school_ui.dart';
import 'package:school_ui/testing.dart';

import 'home_test.dart' hide main;

Future<void> openQr(WidgetTester tester, {bool seed = true}) async {
  await openParent(tester, seed: seed);
  if (seed) {
    await tester.tap(find.widgetWithText(ClayButton, 'رمز الدخول QR'));
    await tester.pumpAndSettle();
  }
}

void main() {
  appTest('الرئيسية تفتح رمز الدخول: اسم الابن ورمزه وتعليماته', (
    tester,
  ) async {
    await openQr(tester);
    expect(find.text('رمز الدخول'), findsOneWidget);
    // سمير هو الأول بالاسم.
    expect(find.text('سمير بن علي'), findsOneWidget);
    expect(find.byType(ClayQrCode), findsOneWidget);
    final qr = tester.widget<ClayQrCode>(find.byType(ClayQrCode));
    expect(qr.data, 'S-s2');
    expect(find.text('S-s2'), findsOneWidget);
    expect(find.textContaining('يعرض ابنك هذا الرمز'), findsOneWidget);
  });

  appTest('مبدّل الأبناء يغيّر الرمز', (tester) async {
    await openQr(tester);
    await tester.tap(find.widgetWithText(ClayChip, 'نور'));
    await tester.pumpAndSettle();
    expect(find.text('نور بن علي'), findsOneWidget);
    expect(tester.widget<ClayQrCode>(find.byType(ClayQrCode)).data, 'S-s1');
  });

  appTest('الابن المختار في الرئيسية هو من يظهر رمزه', (tester) async {
    await openParent(tester);
    await tester.tap(find.widgetWithText(ClayChip, 'نور'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'رمز الدخول QR'));
    await tester.pumpAndSettle();
    expect(tester.widget<ClayQrCode>(find.byType(ClayQrCode)).data, 'S-s1');
    // الرجوع يعيد الرئيسية بالابن نفسه.
    await tester.tap(find.byTooltip('رجوع'));
    await tester.pumpAndSettle();
    expect(find.text('نور بن علي'), findsOneWidget);
  });

  appTest('وليّ بلا أبناء: لا زر رمز، ولا أبناء في الرئيسية', (tester) async {
    await openQr(tester, seed: false);
    expect(find.widgetWithText(ClayButton, 'رمز الدخول QR'), findsNothing);
    expect(find.text('لا أبناء مرتبطون بحسابك'), findsOneWidget);
  });
}
