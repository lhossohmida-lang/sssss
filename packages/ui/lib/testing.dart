/// أدوات اختبار الواجهة المشتركة بين التطبيقات الثلاثة. لا تُستعمل في كود
/// الإنتاج.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/testing.dart';

import 'school_ui.dart';

/// يشغّل اختبار واجهة بشاشة هاتف، ثم يفكّ الشجرة ويُفرغ مؤقتات drift
/// المعلّقة (فتح استعلام متدفق يترك مؤقتاً صفرياً عند إغلاقه) قبل أن يتحقق
/// الإطار من المؤقتات.
void appTest(String description, Future<void> Function(WidgetTester) body) {
  testWidgets(description, (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    try {
      await body(tester);
    } finally {
      // يُفكّ التطبيق حتى عند فشل الاختبار، وإلا علّقت الاختبارات التالية.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
    }
  });
}

/// يشغّل تطبيقاً من التطبيقات الثلاثة على وقت تشغيل اختباري ويتجاوز شاشة
/// البداية، فيقف عند شاشة الدخول (أو عند التبويبات إن كانت هناك جلسة).
Future<AppRuntime> bootApp(
  WidgetTester tester,
  List<AppTab> tabs, {
  required AppIdentity app,
  required List<TestAccount> accounts,
  List<AppPage> pages = const [],
  AccountProvisioner? provisioner,
  PhotoSource? photoSource,
  PdfPresenter? pdfPresenter,
}) async {
  final runtime = (await tester.runAsync(
    () => startTestRuntime(
      app: app,
      accounts: accounts,
      provisioner: provisioner,
    ),
  ))!;
  addTearDown(() async {
    await tester.runAsync(() async {
      await runtime.auth.dispose();
      await runtime.db.close();
    });
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        runtimeProvider.overrideWithValue(runtime),
        if (photoSource != null)
          photoSourceProvider.overrideWithValue(photoSource),
        if (pdfPresenter != null)
          pdfPresenterProvider.overrideWithValue(pdfPresenter),
      ],
      child: SchoolApp(tabs: tabs, pages: pages),
    ),
  );
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
  return runtime;
}

/// يملأ شاشة الدخول ويضغط «دخول».
Future<void> loginWith(
  WidgetTester tester,
  String email,
  String password,
) async {
  Finder field(String label) => find.descendant(
    of: find
        .ancestor(of: find.text(label), matching: find.byType(Column))
        .first,
    matching: find.byType(TextField),
  );
  await tester.enterText(field('البريد'), email);
  await tester.enterText(field('كلمة السر'), password);
  await tester.tap(find.widgetWithText(ClayButton, 'دخول'));
  await tester.pumpAndSettle();
}

/// ينفّذ عملية على القاعدة (بذر بيانات أو قراءة) داخل اختبار واجهة.
///
/// تُنفَّذ في منطقة الاختبار الوهمية نفسها (لا `runAsync`)، لأن استعلامات
/// drift المتدفقة في الشاشات تعيش فيها وتحجز المنفّذ حتى تُكمل بإطار؛ فلو
/// انتظرت العملية في منطقة حقيقية لبقيت معلّقة إلى الأبد. ويُدفع إطار بعدها
/// لتصل النتائج الجديدة إلى الشاشة. لا تصلح للعمليات التي تحتاج عزلاً
/// حقيقياً (اشتقاق كلمات السر).
Future<T> runDb<T>(WidgetTester tester, Future<T> Function() action) async {
  final result = await action();
  // إطاران: الأول يطلق إعادة جلب الاستعلامات، والثاني يوصل نتائجها.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return result;
}

/// مصدر صور وهمي: يعيد [bytes] كأن المستخدم التقطها (أو `null` كأنه ألغى).
class FakePhotoSource implements PhotoSource {
  FakePhotoSource(this.bytes);

  Uint8List? bytes;
  int captures = 0;

  @override
  Future<Uint8List?> capture(BuildContext context) async {
    captures++;
    return bytes;
  }
}

/// عارض PDF وهمي: يسجّل ما طُلب عرضه دون معاينة حقيقية.
class FakePdfPresenter implements PdfPresenter {
  final List<({Uint8List bytes, String fileName, String title})> shown = [];

  @override
  Future<void> show(
    BuildContext context, {
    required Uint8List bytes,
    required String fileName,
    required String title,
  }) async {
    shown.add((bytes: bytes, fileName: fileName, title: title));
  }
}
