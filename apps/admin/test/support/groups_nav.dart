import 'package:flutter_test/flutter_test.dart';

/// فوج في قائمة أفواج مادة وسنة: «فوج 1» (لا «الفوج 1» في صفحات أخرى).
final Finder _groupTile = find.textContaining(RegExp(r'^فوج \d+$'));

/// من شاشة الأفواج: يدخل المادة ثم سنتها حتى تظهر أفواجها مرقَّمة (المادة العامة بلا سنة تظهر
/// سنتها «كل المستويات»). لا يفعل شيئاً إن كانت قائمة الأفواج ظاهرة.
Future<void> openGroupList(
  WidgetTester tester, {
  String subject = 'رياضيات',
  String level = 'كل المستويات',
}) async {
  if (_groupTile.evaluate().isNotEmpty) return;
  await tester.tap(find.text(subject).first);
  await tester.pumpAndSettle();
  if (_groupTile.evaluate().isNotEmpty) return;
  await tester.tap(find.text(level).first);
  await tester.pumpAndSettle();
}

/// يفتح تفاصيل فوج برقمه من شاشة الأفواج (بعد المادة والسنة).
Future<void> tapGroup(
  WidgetTester tester, {
  int number = 1,
  String subject = 'رياضيات',
  String level = 'كل المستويات',
}) async {
  await openGroupList(tester, subject: subject, level: level);
  await tester.tap(find.text('فوج $number'));
  await tester.pumpAndSettle();
}
