/// أدوات اختبار الواجهة المشتركة بين التطبيقات الثلاثة. لا تُستعمل في كود
/// الإنتاج.
library;

import 'dart:async';
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
  QrCodeSource Function()? qrCamera,
  QrCodeSource Function()? usbReader,
  ScanFeedback? scanFeedback,
  bool sessionCloser = false,
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
        sessionCloserEnabledProvider.overrideWithValue(sessionCloser),
        if (photoSource != null)
          photoSourceProvider.overrideWithValue(photoSource),
        if (pdfPresenter != null)
          pdfPresenterProvider.overrideWithValue(pdfPresenter),
        if (qrCamera != null)
          qrCameraFactoryProvider.overrideWithValue(qrCamera),
        if (usbReader != null)
          usbReaderFactoryProvider.overrideWithValue(usbReader),
        if (scanFeedback != null)
          scanFeedbackProvider.overrideWithValue(scanFeedback),
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

/// مصدر رموز وهمي: يُدفع إليه الرمز بـ [emit] كأنه مُسح بالكاميرا.
class FakeQrSource implements QrCodeSource {
  final StreamController<String> _controller =
      StreamController<String>.broadcast();

  bool started = false;
  bool disposed = false;

  void emit(String code) => _controller.add(code);

  @override
  Stream<String> get codes => _controller.stream;

  @override
  Widget buildPreview(BuildContext context) =>
      const ColoredBox(color: Colors.black, child: SizedBox.expand());

  @override
  Future<void> start() async => started = true;

  @override
  Future<void> dispose() async {
    disposed = true;
    await _controller.close();
  }
}

/// تغذية راجعة وهمية تسجّل ما نُفّذ منها.
class RecordingScanFeedback implements ScanFeedback {
  final List<String> events = [];

  @override
  Future<void> success() async => events.add('success');

  @override
  Future<void> warning() async => events.add('warning');

  @override
  Future<void> failure() async => events.add('failure');
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

/// يفتح قسماً من قائمة «المزيد»: ينتقل إلى تبويبها ثم يمرّر القائمة حتى
/// يظهر القسم (القائمة أطول من الشاشة) ويضغط عليه.
Future<void> openMoreEntry(WidgetTester tester, String label) async {
  await tester.tap(find.text('المزيد').last);
  await tester.pumpAndSettle();
  final entry = find.text(label);
  if (entry.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      entry,
      200,
      scrollable: find.byType(Scrollable).last,
    );
  }
  await tester.tap(entry);
  await tester.pumpAndSettle();
}
