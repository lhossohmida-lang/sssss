import 'package:flutter_test/flutter_test.dart';
import 'package:school_ui/school_ui.dart';

/// فوج في قائمة أفواج مادة وسنة: «فوج 1» (لا «الفوج 1» في صفحات أخرى).
final Finder _groupTile = find.textContaining(RegExp(r'^فوج \d+$'));

/// من شاشة الأفواج: يدخل المادة ثم سنتها حتى تظهر أفواجها مرقَّمة (المادة العامة بلا سنة تظهر
/// سنتها «كل المستويات»؛ وإن لم تُوجد السنة المطلوبة دخل أول سنة، فمن أنشأ فوجاً بنموذج الإنشاء له سنة
/// واحدة). لا يفعل شيئاً إن كانت قائمة الأفواج ظاهرة.
Future<void> openGroupList(
  WidgetTester tester, {
  String subject = 'رياضيات',
  String level = 'كل المستويات',
}) async {
  if (_groupTile.evaluate().isNotEmpty) return;
  await tester.tap(find.text(subject).first);
  await tester.pumpAndSettle();
  if (_groupTile.evaluate().isNotEmpty) return;
  final year = find.text(level);
  await tester.tap(
    year.evaluate().isNotEmpty ? year.first : find.byType(ClayListTile).first,
  );
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
