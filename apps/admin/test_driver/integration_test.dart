import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

/// سائق قياس الإطارات: يكتب ما أبلغ به الاختبار في `build/frame_timings.json`
/// فيحوّله `tool/perf_report.py` إلى جدول في ملخص التشغيل.
Future<void> main() {
  return integrationDriver(
    responseDataCallback: (data) async {
      if (data == null) return;
      final file = File('build/frame_timings.json');
      await file.parent.create(recursive: true);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(data),
      );
    },
  );
}
