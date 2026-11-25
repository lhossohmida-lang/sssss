import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_ui/src/shell/web_error_view.dart';

void main() {
  testWidgets('a failure shows its message and the failing provider', (
    tester,
  ) async {
    WebFailureLog.record('provider: exampleProvider\nUnsupported operation');
    await tester.pumpWidget(
      WebErrorView(
        details: FlutterErrorDetails(
          exception: UnsupportedError('Platform._operatingSystem'),
          stack: StackTrace.current,
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final report = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(report.data, contains('Platform._operatingSystem'));
    expect(report.data, contains('exampleProvider'));
  });
}
