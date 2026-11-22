/// اختبار دخان على جهاز أو محاكٍ (iPhone في مسار `ios`): يشغّل التطبيق الحقيقي
/// بإضافاته الأصلية ويتحقق أنه يصل شاشته الأولى بلا انهيار. لا يُستعمل في كود
/// الإنتاج.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

/// شاشة رمز الربط: الشاشة الأولى لبناء بلا دليل مدارس مضمَّن.
const String pairingFirstScreen = 'ربط التطبيق بمدرستك';

/// الشاشة الأولى لكل تطبيق في بناء يضمّن دليل المدارس (كما في `tool/apk_smoke.py`).
const Map<AppIdentity, String> directoryFirstScreens = {
  AppIdentity.admin: 'أدخل رقم هاتفك وكلمة السر',
  AppIdentity.teacher: 'اختر مدرستك',
  AppIdentity.student: 'اختر مدرستك',
};

/// الشاشات الأولى المقبولة: مع دليل مضمَّن ([directory] = true) شاشة الدليل، ودونه
/// شاشة رمز الربط، ودون علم (null) كلتاهما.
List<String> smokeFirstScreens(AppIdentity app, {bool? directory}) {
  final withDirectory = directoryFirstScreens[app]!;
  if (directory == true) return [withDirectory];
  if (directory == false) return const [pairingFirstScreen];
  return [pairingFirstScreen, withDirectory];
}

/// `SMOKE_DIRECTORY=1` البناء يضمّن الدليل، و`=0` دونه، وغير ذلك يُقبل الاثنان.
bool? smokeDirectoryExpectation(String value) =>
    const {'1': true, '0': false}[value.trim()];

/// النصوص الظاهرة الآن بترتيب ظهورها دون تكرار.
List<String> visibleTexts() {
  final seen = <String>{};
  for (final element in find.byType(RichText).evaluate()) {
    final text = (element.widget as RichText).text.toPlainText().trim();
    if (text.isNotEmpty) seen.add(text);
  }
  for (final element in find.byType(EditableText).evaluate()) {
    final text = (element.widget as EditableText).controller.text.trim();
    if (text.isNotEmpty) seen.add(text);
  }
  return seen.toList();
}

/// يضخّ الإطارات حتى يظهر نص يحوي أحد [expected] فيعيده، أو `null` بعد [timeout].
Future<String?> waitForAnyText(
  WidgetTester tester,
  List<String> expected, {
  Duration timeout = const Duration(seconds: 60),
  Duration step = const Duration(milliseconds: 500),
}) async {
  final watch = Stopwatch()..start();
  while (watch.elapsed < timeout) {
    await tester.pump(step);
    for (final text in visibleTexts()) {
      for (final wanted in expected) {
        if (text.contains(wanted)) return wanted;
      }
    }
  }
  return null;
}

/// يشغّل [main] التطبيق ثم يتحقق أنه وصل إحدى شاشاته الأولى المقبولة، وإلا فشل
/// الاختبار بالنصوص الظاهرة فيُعرف أين توقف.
Future<void> expectAppReachesFirstScreen(
  WidgetTester tester, {
  required AppIdentity app,
  required Future<void> Function() main,
  String directory = const String.fromEnvironment('SMOKE_DIRECTORY'),
}) async {
  await main();
  final expected = smokeFirstScreens(
    app,
    directory: smokeDirectoryExpectation(directory),
  );
  final found = await waitForAnyText(tester, expected);
  if (found == null) {
    final shown = visibleTexts().take(20).join(' | ');
    fail(
      'لم تظهر الشاشة الأولى لتطبيق ${app.name} '
      '(المتوقع: ${expected.join(' أو ')})؛ الظاهر: ${shown.isEmpty ? 'لا نص' : shown}',
    );
  }
  // ignore: avoid_print
  print('smoke-ok ${app.name}: $found');
}
