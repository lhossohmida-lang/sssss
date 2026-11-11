import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teacher/main.dart';

void main() {
  testWidgets('التطبيق يفتح بالعربية ومن اليمين إلى اليسار', (tester) async {
    await tester.pumpWidget(const TeacherApp());
    await tester.pumpAndSettle();

    expect(find.text('الأستاذ'), findsOneWidget);
    final context = tester.element(find.text('الأستاذ'));
    expect(Directionality.of(context), TextDirection.rtl);
  });
}
