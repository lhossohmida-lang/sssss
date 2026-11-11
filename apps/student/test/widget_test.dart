import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student/main.dart';

void main() {
  testWidgets('التطبيق يفتح بالعربية ومن اليمين إلى اليسار', (tester) async {
    await tester.pumpWidget(const StudentApp());
    await tester.pumpAndSettle();

    expect(find.text('وليّ التلميذ'), findsOneWidget);
    final context = tester.element(find.text('وليّ التلميذ'));
    expect(Directionality.of(context), TextDirection.rtl);
  });
}
