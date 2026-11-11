import 'package:admin/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('التطبيق يفتح بالعربية ومن اليمين إلى اليسار', (tester) async {
    await tester.pumpWidget(const AdminApp());
    await tester.pumpAndSettle();

    expect(find.text('الإدارة'), findsOneWidget);
    final context = tester.element(find.text('الإدارة'));
    expect(Directionality.of(context), TextDirection.rtl);
  });
}
