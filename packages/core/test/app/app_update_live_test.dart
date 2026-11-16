import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:school_core/school_core.dart';

/// فحص حيّ للمحدِّث على الإصدار المنشور فعلاً في GitHub (نفس شيفرة التطبيق، لا بدائل).
///
/// لا يعمل إلا مع `UPDATE_LIVE=1` لأنه يتصل بالشبكة وينزّل ملف المثبّت (نحو 17 ميغابايت)؛ يشغّله مسار
/// `release-smoke`. متغيرات اختيارية: `UPDATE_LIVE_REPO` (الافتراضي مستودع المشروع)، و`GITHUB_TOKEN`
/// (يُرسل لعناوين الواجهة وحدها لتفادي حدّ الطلبات المجهولة على عناوين المشغّلات المشتركة)،
/// و`UPDATE_LIVE_SUMMARY` مسار ملف يُكتب فيه ملخص النتيجة.
void main() {
  final live = Platform.environment['UPDATE_LIVE'] == '1';
  final repo =
      Platform.environment['UPDATE_LIVE_REPO'] ?? 'lhossohmida-lang/sssss';
  final token = Platform.environment['GITHUB_TOKEN'] ?? '';
  final summaryPath = Platform.environment['UPDATE_LIVE_SUMMARY'];
  const assets = <String>[
    'school-admin-setup.exe',
    'school-admin.apk',
    'school-teacher.apk',
    'school-student.apk',
  ];

  test(
    'المحدِّث يجد الإصدار المنشور وينزّله ويتحقق من بصمته',
    () async {
      // flutter test قد يستبدل عميل HTTP بآخر يردّ 400؛ هنا نريد الشبكة الحقيقية.
      HttpOverrides.global = null;

      final found = <String, UpdateRelease>{};
      for (final name in assets) {
        final release = await GitHubUpdateSource(
          repo: repo,
          assetName: name,
          client: _ApiClient(token),
        ).latest();
        expect(release, isNotNull, reason: '$name غير موجود في أي إصدار منشور');
        found[name] = release!;
        expect(release.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
        expect(
          release.size,
          greaterThan(5 * 1024 * 1024),
          reason: '$name أصغر من أن يكون تطبيقاً كاملاً',
        );
        expect(release.url.host, 'github.com');
      }
      final tags = {for (final r in found.values) r.tag};
      expect(tags, hasLength(1), reason: 'ملفات الإصدار من وسوم مختلفة: $tags');

      // ملف Windows يُنزَّل كاملاً بالشيفرة نفسها ويُتحقق من بصمته وحجمه.
      final setup = found['school-admin-setup.exe']!;
      final dir = await Directory.systemTemp.createTemp('update_live_');
      addTearDown(() => dir.delete(recursive: true));
      final downloader = UpdateDownloader(directory: dir);
      var progressed = 0;
      final file = await downloader.download(
        setup,
        onProgress: (received, total) => progressed = received,
      );
      expect(await file.length(), setup.size);
      expect(progressed, setup.size);
      expect((await downloader.existing(setup))?.path, file.path);

      // المتحكّم الكامل على الخادم الحقيقي: نسخة قديمة تجد الإصدار وتنزّله وتجهّزه للتثبيت.
      final cleanDir = await Directory.systemTemp.createTemp('update_live_c_');
      addTearDown(() => cleanDir.delete(recursive: true));
      final installer = _RecordingInstaller();
      final controller = UpdateController(
        currentTag: 'preview-0',
        source: GitHubUpdateSource(
          repo: repo,
          assetName: setup.assetName,
          client: _ApiClient(token),
        ),
        downloader: UpdateDownloader(directory: cleanDir),
        installer: installer,
      );
      addTearDown(controller.dispose);
      await controller.checkNow(manual: true);
      final state = controller.state.value;
      expect(state, isA<UpdateReady>(), reason: 'الحالة: $state');
      final ready = state as UpdateReady;
      expect(ready.release.tag, setup.tag);
      expect(await ready.file.length(), setup.size);
      await controller.install();
      expect(installer.installed, ready.file.path);

      final summary =
          'إصدار ${setup.tag}: '
          '${found.entries.map((e) => '${e.key}=${e.value.size}').join(' ')} '
          '(نُزّل ${setup.assetName} وتحقّقت بصمته)';
      if (summaryPath != null && summaryPath.isNotEmpty) {
        File(summaryPath).writeAsStringSync(summary);
      }
      // ignore: avoid_print
      print(summary);
    },
    skip: live ? false : 'يعمل مع UPDATE_LIVE=1 فقط (يتصل بـGitHub)',
    timeout: const Timeout(Duration(minutes: 8)),
  );
}

/// يضيف رمز GitHub (إن وُجد) لطلبات الواجهة وحدها، ولا يرسله لأي مضيف آخر.
class _ApiClient extends http.BaseClient {
  _ApiClient(this._token);

  final String _token;
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (_token.isNotEmpty && request.url.host == 'api.github.com') {
      request.headers['Authorization'] = 'Bearer $_token';
    }
    return _inner.send(request);
  }
}

/// مثبّت لا يفعل شيئاً سوى تسجيل الملف الذي طُلب تثبيته.
class _RecordingInstaller implements UpdateInstaller {
  String? installed;

  @override
  Future<void> install(File file, UpdateRelease release) async {
    installed = file.path;
  }
}
