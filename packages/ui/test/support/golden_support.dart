import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

/// مقارنة صور golden بتسامح يعتمد على المنصة.
///
/// اللقطات الأصلية تُولَّد على Windows، فتُقارَن هناك بتسامح ضئيل. وعلى
/// Linux (مسار `check` في Actions) يختلف تنعيم النص والحواف قليلاً (قِيس
/// نحو 1.3٪ إلى 1.9٪ في اللقطات النصية)، فيُسمح بـ 2.5٪؛ وأي تغيير حقيقي في
/// التصميم (لون، حجم، موضع) يتجاوز ذلك.
class TolerantGoldenComparator extends LocalFileComparator {
  TolerantGoldenComparator(super.testFile, {double? tolerance})
    : tolerance = tolerance ?? (Platform.isWindows ? 0.002 : 0.025);

  /// أكبر نسبة اختلاف مسموحة بين الصورتين (0.01 = 1٪).
  final double tolerance;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (result.passed || result.diffPercent <= tolerance) return true;
    final error = await generateFailureOutput(result, golden, basedir);
    throw FlutterError(error);
  }
}

/// يضبط مقارنة golden المتسامحة ويحمّل خط Cairo ليظهر النص كما في التطبيق.
Future<void> setUpGoldens() async {
  final comparator = goldenFileComparator;
  if (comparator is LocalFileComparator) {
    goldenFileComparator = TolerantGoldenComparator(
      comparator.basedir.resolve('golden_test.dart'),
    );
  }
  // أيقونات Material من الـ SDK، وإلا ظهرت مربعات في اللقطات.
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) {
    final icons = File(
      '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (icons.existsSync()) {
      await (FontLoader('MaterialIcons')..addFont(
            Future.value(ByteData.sublistView(icons.readAsBytesSync())),
          ))
          .load();
    }
  }
  final font = File('assets/fonts/Cairo.ttf').readAsBytesSync();
  final loader = FontLoader('packages/$clayFontPackage/$clayFontFamily')
    ..addFont(Future.value(ByteData.sublistView(font)));
  await loader.load();
}

/// يعرض [child] داخل تطبيق Clay بعرض ثابت ووضع محدد، ثم يلتقط golden.
///
/// الحركات الدائمة (مؤشرات التحميل والنبض) تُجمَّد عند اللقطة الأولى.
Future<void> expectGolden(
  WidgetTester tester,
  String name, {
  required Widget child,
  required Brightness brightness,
  double width = 400,
  double height = 600,
  AppIdentity app = AppIdentity.admin,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ClayApp(
      app: app,
      themeMode: brightness == Brightness.dark
          ? ThemeMode.dark
          : ThemeMode.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: RepaintBoundary(
            key: const ValueKey('golden'),
            child: ColoredBox(color: context.palette.background, child: child),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await expectLater(
    find.byKey(const ValueKey('golden')),
    matchesGoldenFile('goldens/${name}_${brightness.name}.png'),
  );
}
