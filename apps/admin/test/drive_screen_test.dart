import 'package:admin/screens/drive_screen.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

class _FakeDriveController implements DriveController {
  @override
  bool isConfigured = false;

  @override
  String ownerEmail = '';

  /// آخر بريد حُفظ عبر الشاشة (`null` إن لم يُحفظ شيء).
  String? saved;

  @override
  Future<void> setOwnerEmail(String email) async {
    saved = email;
    ownerEmail = email;
  }

  @override
  bool get canCreateBackup => false;

  @override
  String get configurationMessage => 'تُضبط بيانات الحساب لاحقاً';

  @override
  Stream<DriveAccount?> get accountChanges => Stream.value(null);

  @override
  Stream<List<UploadQueueRow>> get queueChanges => Stream.value([]);

  @override
  Stream<String?> get backupStatusChanges => Stream.value(null);

  @override
  Future<void> initialize() async {}

  @override
  Future<void> signIn() async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<int> addFiles(List<PlatformFile> files, DriveUploadKind kind) async =>
      files.length;

  @override
  Future<int> uploadPending() async => 0;

  @override
  Future<int> retryFailed() async => 0;

  @override
  Future<bool> createBackup() async => false;

  @override
  Future<List<DriveFileInfo>> listBackups() async => const [];

  @override
  Future<void> restoreBackup(DriveFileInfo backup) async {}

  @override
  Future<void> dispose() async {}
}

Future<void> _pumpScreen(
  WidgetTester tester,
  _FakeDriveController controller,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [driveControllerProvider.overrideWithValue(controller)],
      child: const MaterialApp(home: DriveScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('يتيح وضع الملفات في الطابور قبل تجهيز OAuth', (tester) async {
    final controller = _FakeDriveController();
    await _pumpScreen(tester, controller);

    expect(find.text('تُضبط بيانات الحساب لاحقاً'), findsOneWidget);
    expect(find.text('تسجيل الدخول'), findsOneWidget);
    expect(find.text('اختيار ملفات'), findsOneWidget);
    expect(find.text('النسخ الاحتياطية'), findsOneWidget);
    expect(find.text('عرض النسخ للاستعادة'), findsOneWidget);
    expect(find.text('إنشاء نسخة اليوم'), findsOneWidget);
    final signIn = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('تسجيل الدخول'),
        matching: find.byType(FilledButton),
      ),
    );
    final pickFiles = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('اختيار ملفات'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(signIn.onPressed, isNull);
    expect(pickFiles.onPressed, isNotNull);
  });

  group('بريد المالك', () {
    testWidgets('غير مضبوط: يُعرض الزر، والحفظ ينظّف البريد ويعرضه', (
      tester,
    ) async {
      final controller = _FakeDriveController();
      await _pumpScreen(tester, controller);
      expect(find.text('بريد المالك غير مضبوط'), findsOneWidget);

      await tester.tap(find.text('ضبط البريد'));
      await tester.pumpAndSettle();
      expect(find.text('بريد حساب Google المالك'), findsOneWidget);
      await tester.enterText(find.byType(TextField), ' Owner@Gmail.com ');
      await tester.tap(find.text('حفظ'));
      await tester.pumpAndSettle();

      expect(controller.saved, 'owner@gmail.com');
      expect(find.text('بريد حساب Google المالك'), findsNothing);
      expect(find.text('بريد المالك المعتمد: owner@gmail.com'), findsOneWidget);
      expect(find.text('تغيير البريد'), findsOneWidget);
    });

    testWidgets('بريد غير صالح: خطأ داخل النافذة ولا حفظ', (tester) async {
      final controller = _FakeDriveController();
      await _pumpScreen(tester, controller);

      await tester.tap(find.text('ضبط البريد'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'not-an-email');
      await tester.tap(find.text('حفظ'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('أدخل بريد حساب Google صالحاً'),
        findsOneWidget,
      );
      expect(find.text('بريد حساب Google المالك'), findsOneWidget);
      expect(controller.saved, isNull);
    });

    testWidgets('الإلغاء لا يغيّر شيئاً', (tester) async {
      final controller = _FakeDriveController()..ownerEmail = 'a@gmail.com';
      await _pumpScreen(tester, controller);
      expect(find.text('بريد المالك المعتمد: a@gmail.com'), findsOneWidget);

      await tester.tap(find.text('تغيير البريد'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'a@gmail.com'), findsOneWidget);
      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();

      expect(controller.saved, isNull);
      expect(find.text('بريد المالك المعتمد: a@gmail.com'), findsOneWidget);
    });

    testWidgets('مسح الحقل يزيل البريد المحفوظ', (tester) async {
      final controller = _FakeDriveController()..ownerEmail = 'a@gmail.com';
      await _pumpScreen(tester, controller);

      await tester.tap(find.text('تغيير البريد'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.text('حفظ'));
      await tester.pumpAndSettle();

      expect(controller.saved, '');
      expect(find.text('بريد المالك غير مضبوط'), findsOneWidget);
    });
  });
}
