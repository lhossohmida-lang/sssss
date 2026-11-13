import 'dart:io';
import 'dart:ui' show Size;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';
import 'package:school_ui/testing.dart';

import 'home_test.dart' hide main;

/// يفتح مادة الرياضيات لنور من الرئيسية: له اختباران (14/20 بملاحظة و40/50)
/// في مجموعتها، وللمجموعة ملف PDF محلي وآخر بلا نسخة محلية؛ ولمجموعة
/// الفيزياء ملف لا يظهر هنا.
Future<({AppRuntime runtime, FakePdfPresenter presenter})> openSubject(
  WidgetTester tester, {
  String subject = 'رياضيات',
}) async {
  final presenter = FakePdfPresenter();
  final runtime = await openParent(tester, pdfPresenter: presenter);
  final dir = Directory.systemTemp.createTempSync('student_files_');
  addTearDown(() => dir.deleteSync(recursive: true));
  final local = File('${dir.path}/tamarin.pdf')
    ..writeAsBytesSync(List.filled(3000, 7));
  await runDb(tester, () async {
    final db = runtime.db;
    for (final (id, title, date, score, max, note) in [
      ('gr1', 'اختبار الفصل', '2026-11-05', 14.0, 20.0, 'جيد'),
      ('gr2', 'فرض', '2026-11-12', 40.0, 50.0, ''),
    ]) {
      await db
          .into(db.grades)
          .insert(
            GradesCompanion.insert(
              id: id,
              createdAt: 1,
              updatedAt: 1,
              studentId: 's1',
              groupId: 'g1',
              title: title,
              score: score,
              maxScore: Value(max),
              note: Value(note),
              date: date,
            ),
          );
    }
    Future<void> file(
      String id,
      String group,
      String title,
      String name, {
      String? path,
      String? url,
    }) => db
        .into(db.groupFiles)
        .insert(
          GroupFilesCompanion.insert(
            id: id,
            createdAt: id == 'f1' ? 1 : 2,
            updatedAt: 1,
            groupId: group,
            title: title,
            fileName: name,
            sizeBytes: const Value(3000),
            localPath: Value(path),
            fileUrl: Value(url),
            uploadedBy: 't1',
          ),
        );
    await file('f1', 'g1', 'تمارين الفصل', 'tamarin.pdf', path: local.path);
    await file(
      'f2',
      'g1',
      'درس بعيد',
      'lesson.pdf',
      url: 'files/groups/g1/f2.pdf',
    );
    await file('f3', 'g2', 'ملف الفيزياء', 'phys.pdf', path: local.path);
  });
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(ClayChip, 'نور'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(subject));
  await tester.pumpAndSettle();
  return (runtime: runtime, presenter: presenter);
}

void main() {
  appTest('بطاقة المادة تفتح صفحتها: الأستاذ والمجموعة', (tester) async {
    await openSubject(tester);
    expect(find.text('المجموعة 1 · الأستاذ كمال'), findsOneWidget);
    expect(find.text('النتائج'), findsOneWidget);
    expect(find.text('الملفات'), findsOneWidget);
  });

  appTest('النتائج: الأحدث أولاً بسلّمها وملاحظتها ومتوسطها من 20', (
    tester,
  ) async {
    await openSubject(tester);
    expect(find.text('فرض'), findsOneWidget);
    expect(find.text('40/50'), findsOneWidget);
    expect(find.text('اختبار الفصل'), findsOneWidget);
    expect(find.text('14/20'), findsOneWidget);
    expect(find.text('2026-11-05 · جيد'), findsOneWidget);
    // (16 + 14) / 2 = 15
    expect(find.text('المتوسط 15/20'), findsOneWidget);
    final newer = tester.getTopLeft(find.text('فرض'));
    final older = tester.getTopLeft(find.text('اختبار الفصل'));
    expect(newer.dy, lessThan(older.dy));
  });

  appTest('الملفات: ملفات مجموعة المادة وحدها، والضغط يفتح PDF', (
    tester,
  ) async {
    final o = await openSubject(tester);
    tester.view.physicalSize = const Size(420, 3000);
    await tester.pumpAndSettle();
    expect(find.text('تمارين الفصل'), findsOneWidget);
    expect(find.text('درس بعيد'), findsOneWidget);
    expect(find.text('ملف الفيزياء'), findsNothing);
    expect(find.textContaining('tamarin.pdf'), findsOneWidget);
    await tester.tap(find.text('تمارين الفصل'));
    for (var i = 0; i < 20 && o.presenter.shown.isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(o.presenter.shown, hasLength(1));
    expect(o.presenter.shown.single.fileName, 'tamarin.pdf');
    expect(o.presenter.shown.single.bytes.length, 3000);
  });

  appTest('ملف بلا نسخة محلية ولا اتصال: رسالة', (tester) async {
    final o = await openSubject(tester);
    tester.view.physicalSize = const Size(420, 3000);
    await tester.pumpAndSettle();
    await tester.tap(find.text('درس بعيد'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('تعذّر فتح الملف الآن'), findsOneWidget);
    expect(o.presenter.shown, isEmpty);
  });

  appTest('مادة بلا نتائج ولا ملفات: رسالتان', (tester) async {
    await openSubject(tester, subject: 'فيزياء');
    expect(find.text('لم تُدخل نتائج لهذه المادة بعد'), findsOneWidget);
    // ملف الفيزياء الوحيد يظهر لا ملفات الرياضيات.
    expect(find.text('ملف الفيزياء'), findsOneWidget);
    expect(find.text('تمارين الفصل'), findsNothing);
  });
}
