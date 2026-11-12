import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';
import 'package:school_ui/testing.dart';

import 'home_screens_test.dart' hide main;

class Opened {
  Opened(this.runtime, this.source, this.presenter);

  final AppRuntime runtime;
  final FakeFileSource source;
  final FakePdfPresenter presenter;
}

Future<Opened> openFiles(WidgetTester tester, {PickedFile? picked}) async {
  final source = FakeFileSource(picked);
  final presenter = FakePdfPresenter();
  final runtime = await openTeacher(
    tester,
    fileSource: source,
    pdfPresenter: presenter,
  );
  await tester.tap(find.text('مجموعاتي').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('المجموعة 1 · رياضيات'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(ClayButton, 'الملفات'));
  await tester.pumpAndSettle();
  return Opened(runtime, source, presenter);
}

/// ينتظر عملية فعلية (كتابة ملف) بزمن حقيقي ويدفع إطارات بينها؛ مؤشر الحفظ
/// يمنع pumpAndSettle من الاستقرار قبل انتهاء العملية.
Future<void> settleIo(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump(const Duration(milliseconds: 60));
  }
  await tester.pumpAndSettle();
}

Future<void> refresh(WidgetTester tester) async {
  ProviderScope.containerOf(tester.element(find.byType(Scaffold).first))
      .invalidate(groupFilesProvider);
  await settleIo(tester);
}

PickedFile pdfFile({String name = 'tamarin.pdf', int size = 3000}) =>
    PickedFile(name: name, bytes: Uint8List.fromList(List.filled(size, 9)));

Future<void> addFile(WidgetTester tester, {String? title}) async {
  await tester.tap(find.widgetWithText(ClayButton, 'إضافة ملف'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(ClayButton, 'اختيار ملف'));
  await tester.pumpAndSettle();
  if (title != null) {
    await tester.enterText(find.byType(TextField).first, title);
  }
  await tester.tap(find.widgetWithText(ClayButton, 'حفظ ورفع'));
  await tester.pump();
  await settleIo(tester);
}

void main() {
  appTest('لا ملفات: رسالة وزر إضافة', (tester) async {
    await openFiles(tester);
    expect(find.text('لا ملفات بعد'), findsOneWidget);
    expect(find.text('ملفات المجموعة 1'), findsOneWidget);
    expect(find.widgetWithText(ClayButton, 'إضافة ملف'), findsOneWidget);
  });

  appTest('إضافة ملف: عنوان افتراضي من اسمه ويظهر «في الانتظار»', (
    tester,
  ) async {
    final o = await openFiles(tester, picked: pdfFile());
    await tester.tap(find.widgetWithText(ClayButton, 'إضافة ملف'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'اختيار ملف'));
    await tester.pumpAndSettle();
    expect(o.source.requests.single, containsAll(['pdf', 'png']));
    expect(find.textContaining('tamarin.pdf'), findsOneWidget);
    expect(find.widgetWithText(ClayButton, 'تغيير الملف'), findsOneWidget);
    await tester.tap(find.widgetWithText(ClayButton, 'حفظ ورفع'));
    await tester.pump();
    await settleIo(tester);
    await refresh(tester);

    expect(find.text('tamarin'), findsOneWidget);
    expect(find.textContaining('2.9 ك.ب'), findsOneWidget);
    expect(find.text('في الانتظار'), findsOneWidget);
    final rows = await runDb(
      tester,
      () => o.runtime.db.select(o.runtime.db.groupFiles).get(),
    );
    expect(rows.single.groupId, 'g1');
    expect(rows.single.uploadedBy, 't1');
    expect(File(rows.single.localPath!).existsSync(), isTrue);
    final queue = await runDb(
      tester,
      () => o.runtime.db.select(o.runtime.db.uploadQueue).get(),
    );
    expect(queue.single.targetTable, 'group_files');
  });

  appTest('أخطاء: بلا ملف، ثم نوع غير مقبول وعنوان فارغ', (tester) async {
    final o = await openFiles(tester);
    await tester.tap(find.widgetWithText(ClayButton, 'إضافة ملف'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'حفظ ورفع'));
    await tester.pumpAndSettle();
    expect(find.text('اختر الملف أولاً'), findsOneWidget);

    // إلغاء الاختيار لا يغيّر شيئاً.
    await tester.tap(find.widgetWithText(ClayButton, 'اختيار ملف'));
    await tester.pumpAndSettle();
    expect(find.text('اختر الملف أولاً'), findsOneWidget);

    o.source.file = pdfFile(name: 'virus.exe');
    await tester.tap(find.widgetWithText(ClayButton, 'اختيار ملف'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '');
    await tester.tap(find.widgetWithText(ClayButton, 'حفظ ورفع'));
    await tester.pumpAndSettle();
    expect(find.textContaining('نوع الملف غير مقبول'), findsOneWidget);
    expect(find.text('أدخل عنوان الملف'), findsOneWidget);
    expect(
      await runDb(
        tester,
        () => o.runtime.db.select(o.runtime.db.groupFiles).get(),
      ),
      isEmpty,
    );
  });

  appTest('فتح ملف PDF يعرضه بنسخته المحلية', (tester) async {
    final o = await openFiles(tester, picked: pdfFile());
    await addFile(tester, title: 'تمارين الفصل');
    await refresh(tester);
    await tester.tap(find.text('تمارين الفصل'));
    await settleIo(tester);
    expect(o.presenter.shown, hasLength(1));
    expect(o.presenter.shown.single.title, 'تمارين الفصل');
    expect(o.presenter.shown.single.fileName, 'tamarin.pdf');
    expect(o.presenter.shown.single.bytes.length, 3000);
  });

  appTest('إعادة تسمية الملف من حوار', (tester) async {
    final o = await openFiles(tester, picked: pdfFile());
    await addFile(tester, title: 'قديم');
    await refresh(tester);
    await tester.tap(find.byTooltip('تعديل العنوان'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'جديد');
    await tester.tap(find.widgetWithText(ClayButton, 'حفظ'));
    await tester.pumpAndSettle();
    await refresh(tester);
    expect(find.text('جديد'), findsOneWidget);
    expect(find.text('قديم'), findsNothing);
    final rows = await runDb(
      tester,
      () => o.runtime.db.select(o.runtime.db.groupFiles).get(),
    );
    expect(rows.single.title, 'جديد');
  });

  appTest('الحذف بتأكيد: يختفي الملف ويبقى سجله محذوفاً حذفاً ناعماً', (
    tester,
  ) async {
    final o = await openFiles(tester, picked: pdfFile());
    await addFile(tester, title: 'للحذف');
    await refresh(tester);
    await tester.tap(find.byTooltip('حذف الملف'));
    await tester.pumpAndSettle();
    expect(find.text('حذف الملف'), findsOneWidget);
    await tester.tap(find.widgetWithText(ClayButton, 'حذف'));
    await settleIo(tester);
    await refresh(tester);
    expect(find.text('للحذف'), findsNothing);
    expect(find.text('لا ملفات بعد'), findsOneWidget);
    final rows = await runDb(
      tester,
      () => o.runtime.db.select(o.runtime.db.groupFiles).get(),
    );
    expect(rows.single.deletedAt, isNotNull);
  });
}
