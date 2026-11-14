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
  String get configurationMessage => 'تُضبط بيانات الحساب لاحقاً';

  @override
  Stream<DriveAccount?> get accountChanges => Stream.value(null);

  @override
  Stream<List<UploadQueueRow>> get queueChanges => Stream.value([]);

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
  Future<void> dispose() async {}
}

void main() {
  testWidgets('يتيح وضع الملفات في الطابور قبل تجهيز OAuth', (tester) async {
    final controller = _FakeDriveController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [driveControllerProvider.overrideWithValue(controller)],
        child: const MaterialApp(home: DriveScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('تُضبط بيانات الحساب لاحقاً'), findsOneWidget);
    expect(find.text('تسجيل الدخول'), findsOneWidget);
    expect(find.text('اختيار ملفات'), findsOneWidget);
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
}
