import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

UpdateRelease release(String tag, {int size = 95 * 1024 * 1024}) =>
    UpdateRelease(
      version: ReleaseVersion.tryParse(tag)!,
      assetName: 'school-admin.apk',
      url: Uri.parse(
        'https://github.com/o/r/releases/download/$tag/school-admin.apk',
      ),
      size: size,
      sha256: 'a' * 64,
    );

class _Source implements UpdateSource {
  UpdateRelease? result;

  @override
  Future<UpdateRelease?> latest() async => result;
}

class _Downloader extends UpdateDownloader {
  _Downloader(Directory directory) : super(directory: directory);

  final List<String> downloads = [];

  @override
  Future<File?> existing(UpdateRelease release) async => null;

  @override
  Future<File> download(
    UpdateRelease release, {
    void Function(int received, int total)? onProgress,
  }) async {
    downloads.add(release.tag);
    return fileFor(release);
  }
}

class _Installer implements UpdateInstaller {
  final List<String> installed = [];

  /// يُبقي التثبيت «جارياً» حتى يُكمَل لاختبار الحالة المتوسطة.
  Completer<void>? gate;

  @override
  Future<void> install(File file, UpdateRelease release) async {
    installed.add(release.tag);
    await gate?.future;
  }
}

void main() {
  group('updateAssetName', () {
    test('Android apps look for their own APK', () {
      for (final app in AppIdentity.values) {
        expect(
          updateAssetName(app, platform: TargetPlatform.android),
          'school-${app.name}.apk',
        );
      }
    });

    test(
      'only the admin app updates itself on Windows, through the installer',
      () {
        expect(
          updateAssetName(AppIdentity.admin, platform: TargetPlatform.windows),
          'school-admin-setup.exe',
        );
        expect(
          updateAssetName(
            AppIdentity.teacher,
            platform: TargetPlatform.windows,
          ),
          isNull,
        );
        expect(
          updateAssetName(
            AppIdentity.student,
            platform: TargetPlatform.windows,
          ),
          isNull,
        );
      },
    );

    test('other systems have no in-app update', () {
      for (final platform in [
        TargetPlatform.iOS,
        TargetPlatform.linux,
        TargetPlatform.macOS,
      ]) {
        expect(updateAssetName(AppIdentity.admin, platform: platform), isNull);
      }
    });
  });

  group('UpdateBanner and UpdateSection', () {
    late Directory dir;
    late _Source source;
    late _Downloader downloader;
    late _Installer installer;
    var unmetered = true;
    late UpdateController controller;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('uiupd');
      source = _Source();
      downloader = _Downloader(dir);
      installer = _Installer();
      unmetered = true;
      controller = UpdateController(
        currentTag: 'preview-7',
        source: source,
        downloader: downloader,
        installer: installer,
        canDownloadAutomatically: () async => unmetered,
      );
    });

    tearDown(() {
      controller.dispose();
      dir.deleteSync(recursive: true);
    });

    Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
      ProviderScope(
        // بلا متحكم افتراضي (لا إعداد بناء في الاختبارات)؛ ما يحتاجه الاختبار يمرَّر صراحةً.
        overrides: [updateControllerProvider.overrideWithValue(null)],
        child: MaterialApp(
          theme: ClayThemeData.light(AppIdentity.admin),
          locale: AppIdentity.locale,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: SingleChildScrollView(child: child)),
          ),
        ),
      ),
    );

    testWidgets(
      'nothing shows without a controller or while idle or up to date',
      (tester) async {
        await pump(tester, const UpdateBanner());
        expect(find.byType(Card), findsNothing);
        expect(find.text('تثبيت الآن'), findsNothing);

        await pump(tester, UpdateBanner(controller: controller));
        expect(find.text('تثبيت الآن'), findsNothing);
        await controller.checkNow(manual: true);
        await tester.pump();
        expect(controller.state.value, isA<UpdateUpToDate>());
        expect(find.textContaining('نسخة جديدة'), findsNothing);
      },
    );

    testWidgets(
      'a downloaded release is offered for installation and hands the file over on tap',
      (tester) async {
        source.result = release('preview-8');
        await pump(tester, UpdateBanner(controller: controller));
        await tester.runAsync(controller.checkNow);
        await tester.pump();

        expect(
          find.text('نسخة جديدة (preview-8) جاهزة للتثبيت'),
          findsOneWidget,
        );
        expect(find.text('تثبيت الآن'), findsOneWidget);
        expect(downloader.downloads, ['preview-8']);

        installer.gate = Completer<void>();
        await tester.tap(find.text('تثبيت الآن'));
        await tester.pump();
        expect(installer.installed, ['preview-8']);
        expect(find.text('جارٍ بدء التثبيت…'), findsOneWidget);
        // نافذة النظام أُغلقت دون تثبيت: يعود الزر.
        installer.gate!.complete();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
        expect(find.text('تثبيت الآن'), findsOneWidget);
      },
    );

    testWidgets(
      'progress is shown as a bar and a percentage while downloading',
      (tester) async {
        await pump(tester, UpdateBanner(controller: controller));
        controller.state.value = UpdateDownloading(
          release('preview-8', size: 1000),
          420,
        );
        await tester.pump();
        expect(
          find.text('جارٍ تنزيل النسخة الجديدة preview-8'),
          findsOneWidget,
        );
        expect(find.text('42٪'), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        expect(
          tester
              .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator),
              )
              .value,
          closeTo(0.42, 1e-9),
        );
      },
    );

    testWidgets('on a metered network the user decides: download or later', (
      tester,
    ) async {
      unmetered = false;
      source.result = release('preview-8');
      await pump(tester, UpdateBanner(controller: controller));
      await tester.runAsync(controller.checkNow);
      await tester.pump();

      expect(find.text('نسخة جديدة (preview-8) متاحة'), findsOneWidget);
      expect(find.textContaining('95 ميغابايت'), findsOneWidget);
      expect(downloader.downloads, isEmpty);

      await tester.tap(find.text('لاحقاً'));
      await tester.pump();
      expect(find.textContaining('متاحة'), findsNothing);

      controller.state.value = UpdateAvailable(release('preview-8'));
      await tester.pump();
      await tester.tap(find.text('تنزيل'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      expect(downloader.downloads, ['preview-8']);
      expect(find.text('تثبيت الآن'), findsOneWidget);
    });

    testWidgets('a failed download shows the reason with retry and hide', (
      tester,
    ) async {
      await pump(tester, UpdateBanner(controller: controller));
      controller.state.value = UpdateFailed(
        'انقطع تنزيل التحديث',
        release: release('preview-8'),
      );
      await tester.pump();
      expect(find.text('انقطع تنزيل التحديث'), findsOneWidget);
      expect(find.text('إعادة المحاولة'), findsOneWidget);

      await tester.tap(find.text('إخفاء'));
      await tester.pump();
      expect(find.text('انقطع تنزيل التحديث'), findsNothing);
    });

    testWidgets(
      'a failure without a release (a manual check) is not a banner',
      (tester) async {
        await pump(tester, UpdateBanner(controller: controller));
        controller.state.value = const UpdateFailed(
          'تعذّر الاتصال بخادم التحديثات',
        );
        await tester.pump();
        expect(find.text('تعذّر الاتصال بخادم التحديثات'), findsNothing);
      },
    );

    testWidgets(
      'the account section reports the build, runs a manual check and says it is up to date',
      (tester) async {
        await pump(tester, UpdateSection(controller: controller));
        expect(find.text('الإصدار الحالي: preview-7'), findsOneWidget);
        expect(
          find.textContaining('تُفحص النسخ الجديدة تلقائياً'),
          findsOneWidget,
        );

        await tester.tap(find.text('التحقق من وجود تحديث'));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
        expect(find.text('أنت على أحدث نسخة'), findsOneWidget);
      },
    );

    testWidgets(
      'the account section shows a found release and an error in plain words',
      (tester) async {
        source.result = release('preview-9');
        await pump(tester, UpdateSection(controller: controller));
        await tester.tap(find.text('التحقق من وجود تحديث'));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
        expect(
          find.text('نسخة جديدة جاهزة للتثبيت: preview-9'),
          findsOneWidget,
        );

        controller.state.value = const UpdateFailed('تعذّر فحص التحديثات');
        await tester.pump();
        expect(find.text('تعذّر فحص التحديثات'), findsOneWidget);
      },
    );

    testWidgets(
      'without a controller the section only reports that updating is off',
      (tester) async {
        await pump(tester, const UpdateSection());
        expect(
          find.text('التحديث التلقائي غير مفعّل في هذا البناء'),
          findsOneWidget,
        );
        expect(find.text('التحقق من وجود تحديث'), findsNothing);
      },
    );
  });
}
