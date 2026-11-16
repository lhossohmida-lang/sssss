import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:school_core/school_core.dart';

const String repo = 'owner/school';
const String assetName = 'school-admin.apk';

String hex(List<int> bytes) => sha256.convert(bytes).toString();

Map<String, Object?> asset({
  String name = assetName,
  int size = 1000,
  Object? digest,
  String? url,
  String tag = 'preview-7',
}) => {
  'name': name,
  'size': size,
  'digest': digest ?? 'sha256:${'a' * 64}',
  'browser_download_url':
      url ?? 'https://github.com/$repo/releases/download/$tag/$name',
};

Map<String, Object?> release(
  String tag, {
  bool draft = false,
  bool prerelease = true,
  List<Map<String, Object?>>? assets,
}) => {
  'tag_name': tag,
  'draft': draft,
  'prerelease': prerelease,
  'assets': assets ?? [asset(tag: tag)],
};

UpdateRelease sample(String tag, {List<int> bytes = const [1, 2, 3]}) =>
    UpdateRelease(
      version: ReleaseVersion.tryParse(tag)!,
      assetName: assetName,
      url: Uri.parse(
        'https://github.com/$repo/releases/download/$tag/$assetName',
      ),
      size: bytes.length,
      sha256: hex(bytes),
    );

void main() {
  group('ReleaseVersion', () {
    test('preview tags compare by number, not as text', () {
      final nine = ReleaseVersion.tryParse('preview-9')!;
      final ten = ReleaseVersion.tryParse('preview-10')!;
      expect(ten > nine, isTrue);
      expect(nine > ten, isFalse);
      expect(
        ReleaseVersion.tryParse('preview-7'),
        ReleaseVersion.tryParse('preview-7'),
      );
    });

    test('a stable release is newer than any preview, and stable tags compare by parts', () {
      expect(
        ReleaseVersion.tryParse('v1.0.0')! >
            ReleaseVersion.tryParse('preview-99')!,
        isTrue,
      );
      expect(
        ReleaseVersion.tryParse('1.2.10')! > ReleaseVersion.tryParse('v1.2.9')!,
        isTrue,
      );
      expect(
        ReleaseVersion.tryParse('v2.0.0')! > ReleaseVersion.tryParse('v1.9.9')!,
        isTrue,
      );
    });

    test('unknown tags are not versions', () {
      for (final tag in [
        '',
        'latest',
        'preview',
        'preview-x',
        'v1.2',
        'release-3',
        'preview-1.5',
      ]) {
        expect(ReleaseVersion.tryParse(tag), isNull, reason: tag);
      }
      expect(ReleaseVersion.tryParse(' preview-4 ')!.tag, 'preview-4');
    });
  });

  group('GitHubUpdateSource', () {
    GitHubUpdateSource source([http.Client? client]) =>
        GitHubUpdateSource(repo: repo, assetName: assetName, client: client);

    UpdateRelease? parse(List<Map<String, Object?>> releases) =>
        source().parseReleases(jsonEncode(releases));

    test(
      'picks the newest release that has the app file (pre-releases included)',
      () {
        final found = parse([
          release('preview-6'),
          release('preview-8'),
          release('preview-7'),
        ])!;
        expect(found.tag, 'preview-8');
        expect(found.size, 1000);
        expect(found.sha256, 'a' * 64);
        expect(
          found.url.toString(),
          'https://github.com/$repo/releases/download/preview-8/$assetName',
        );
      },
    );

    test('skips drafts, unknown tags, other apps files and releases without the file', () {
      final found = parse([
        release('preview-9', draft: true),
        release('nightly-1'),
        release(
          'preview-8',
          assets: [asset(name: 'school-teacher.apk', tag: 'preview-8')],
        ),
        release('preview-7'),
      ])!;
      expect(found.tag, 'preview-7');
    });

    test(
      'rejects assets without a valid SHA-256 digest or a positive size',
      () {
        for (final bad in [
          asset(digest: null)
              .map((k, v) => MapEntry(k, k == 'digest' ? null : v)),
          asset(digest: 'sha1:${'a' * 40}'),
          asset(digest: 'sha256:short'),
          asset(digest: 'sha256:${'z' * 64}'),
          asset(size: 0),
        ]) {
          expect(
            parse([
              release('preview-8', assets: [bad]),
            ]),
            isNull,
            reason: '$bad',
          );
        }
      },
    );

    test('only accepts download links under github.com/<repo>/releases/download/', () {
      for (final url in [
        'http://github.com/$repo/releases/download/preview-8/$assetName',
        'https://evil.example/$repo/releases/download/preview-8/$assetName',
        'https://github.com/other/repo/releases/download/preview-8/$assetName',
        'https://github.com/$repo/raw/main/$assetName',
        'https://github.com.evil.example/$repo/releases/download/preview-8/$assetName',
      ]) {
        expect(
          parse([
            release('preview-8', assets: [asset(url: url)]),
          ]),
          isNull,
          reason: url,
        );
      }
    });

    test('the digest is normalised to lower case', () {
      final found = parse([
        release('preview-8', assets: [asset(digest: 'sha256:${'AB' * 32}')]),
      ])!;
      expect(found.sha256, 'ab' * 32);
    });

    test('a stable release wins over a newer-numbered preview', () {
      expect(
        parse([release('preview-50'), release('v1.0.0', prerelease: false)])!
            .tag,
        'v1.0.0',
      );
    });

    test('malformed JSON and non-list answers are reported in Arabic', () {
      for (final body in ['not json', '{"message":"x"}']) {
        expect(
          () => source().parseReleases(body),
          throwsA(
            isA<UpdateException>().having(
              (e) => e.message,
              'message',
              contains('غير مفهوم'),
            ),
          ),
        );
      }
    });

    test(
      'latest() asks the releases list of the repo with the GitHub headers',
      () async {
        late http.Request seen;
        final client = MockClient((request) async {
          seen = request;
          return http.Response(jsonEncode([release('preview-8')]), 200);
        });
        final found = await source(client).latest();
        expect(found!.tag, 'preview-8');
        expect(seen.url.host, 'api.github.com');
        expect(seen.url.path, '/repos/$repo/releases');
        expect(seen.url.queryParameters['per_page'], '15');
        expect(seen.headers['Accept'], 'application/vnd.github+json');
        expect(seen.headers['User-Agent'], isNotEmpty);
      },
    );

    test('network failures and HTTP errors become UpdateException', () async {
      await expectLater(
        source(MockClient((_) async => throw const SocketException('down')))
            .latest(),
        throwsA(isA<UpdateException>()),
      );
      await expectLater(
        source(MockClient((_) async => http.Response('rate limited', 403)))
            .latest(),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.message,
            'message',
            contains('403'),
          ),
        ),
      );
    });
  });

  group('UpdateDownloader', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('updates'));
    tearDown(() => dir.deleteSync(recursive: true));

    final bytes = List<int>.generate(5000, (i) => i % 251);
    UpdateRelease release0() => sample('preview-8', bytes: bytes);

    MockClient serving(
      List<int> body, {
      int status = 200,
      List<int>? seenCalls,
    }) {
      return MockClient.streaming((request, _) async {
        seenCalls?.add(1);
        // يرسل الجسم أجزاء صغيرة ليُختبر التقدّم.
        Stream<List<int>> chunks() async* {
          for (var i = 0; i < body.length; i += 1000) {
            yield body.sublist(i, (i + 1000).clamp(0, body.length));
          }
        }

        return http.StreamedResponse(chunks(), status);
      });
    }

    test('downloads, verifies size and digest, reports progress, leaves one clean file', () async {
      final progress = <int>[];
      final downloader = UpdateDownloader(
        directory: dir,
        client: serving(bytes),
      );
      final file = await downloader.download(
        release0(),
        onProgress: (received, total) {
          progress.add(received);
          expect(total, bytes.length);
        },
      );
      expect(await file.readAsBytes(), bytes);
      expect(file.path, downloader.fileFor(release0()).path);
      expect(progress.last, bytes.length);
      expect(progress, orderedEquals([...progress]..sort()));
      expect(dir.listSync().map((e) => e.path), [file.path]);
    });

    test('a corrupted download is deleted and reported', () async {
      final tampered = List<int>.of(bytes)..[100] ^= 0xFF;
      final downloader = UpdateDownloader(
        directory: dir,
        client: serving(tampered),
      );
      await expectLater(
        downloader.download(release0()),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.message,
            'message',
            contains('تالف'),
          ),
        ),
      );
      expect(dir.listSync(), isEmpty);
    });

    test('a truncated download is rejected', () async {
      final downloader = UpdateDownloader(
        directory: dir,
        client: serving(bytes.sublist(0, 3000)),
      );
      await expectLater(
        downloader.download(release0()),
        throwsA(isA<UpdateException>()),
      );
      expect(dir.listSync(), isEmpty);
    });

    test('an HTTP error leaves nothing behind', () async {
      final downloader = UpdateDownloader(
        directory: dir,
        client: serving(const [], status: 404),
      );
      await expectLater(
        downloader.download(release0()),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.message,
            'message',
            contains('404'),
          ),
        ),
      );
      expect(dir.listSync(), isEmpty);
    });

    test('a connection that breaks halfway leaves nothing behind', () async {
      final client = MockClient.streaming((request, _) async {
        Stream<List<int>> broken() async* {
          yield bytes.sublist(0, 1000);
          throw const SocketException('reset');
        }

        return http.StreamedResponse(broken(), 200);
      });
      await expectLater(
        UpdateDownloader(directory: dir, client: client).download(release0()),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.message,
            'message',
            contains('انقطع'),
          ),
        ),
      );
      expect(dir.listSync(), isEmpty);
    });

    test('a verified file from before is reused without any request', () async {
      final calls = <int>[];
      final downloader = UpdateDownloader(
        directory: dir,
        client: serving(bytes, seenCalls: calls),
      );
      await downloader.download(release0());
      expect(calls, hasLength(1));
      final again = await downloader.download(release0());
      expect(calls, hasLength(1));
      expect(await downloader.existing(release0()), isNotNull);
      expect(again.existsSync(), isTrue);
    });

    test(
      'a damaged file with the right name is not trusted and is replaced',
      () async {
        final downloader = UpdateDownloader(
          directory: dir,
          client: serving(bytes),
        );
        downloader.fileFor(release0()).writeAsBytesSync([1, 2, 3]);
        expect(await downloader.existing(release0()), isNull);
        final file = await downloader.download(release0());
        expect(await file.readAsBytes(), bytes);
      },
    );

    test(
      'clear removes every downloaded file and tolerates a missing folder',
      () async {
        final downloader = UpdateDownloader(
          directory: dir,
          client: serving(bytes),
        );
        await downloader.download(release0());
        File('${dir.path}/stray.part').writeAsBytesSync([1]);
        await downloader.clear();
        expect(dir.listSync(), isEmpty);
        await UpdateDownloader(directory: Directory('${dir.path}/none'))
            .clear();
      },
    );

    test(
      'older versions and half-finished downloads are cleaned after a success',
      () async {
        File('${dir.path}/preview-6-$assetName').writeAsBytesSync([9]);
        File('${dir.path}/preview-7-$assetName.part').writeAsBytesSync([9]);
        final downloader = UpdateDownloader(
          directory: dir,
          client: serving(bytes),
        );
        final file = await downloader.download(release0());
        expect(dir.listSync().map((e) => e.path), [file.path]);
      },
    );
  });

  group('UpdateController', () {
    late Directory dir;
    late FakeSource source;
    late FakeDownloader downloader;
    late FakeInstaller installer;
    var unmetered = true;
    late List<UpdateState> seen;

    UpdateController build({
      String current = 'preview-7',
      Duration first = const Duration(seconds: 5),
    }) {
      final controller = UpdateController(
        currentTag: current,
        source: source,
        downloader: downloader,
        installer: installer,
        canDownloadAutomatically: () async => unmetered,
        firstCheckDelay: first,
        checkEvery: const Duration(hours: 6),
      );
      seen = [];
      controller.state.addListener(() => seen.add(controller.state.value));
      return controller;
    }

    setUp(() {
      dir = Directory.systemTemp.createTempSync('updctl');
      source = FakeSource();
      downloader = FakeDownloader(dir);
      installer = FakeInstaller();
      unmetered = true;
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('a build without a release tag never touches the network', () async {
      for (final tag in ['', 'dev', 'local-build']) {
        final controller = build(current: tag);
        expect(controller.enabled, isFalse);
        controller.start();
        await controller.checkNow(manual: true);
        expect(controller.state.value, isA<UpdateIdle>());
        controller.dispose();
      }
      expect(source.calls, 0);
    });

    test('downloads a newer release on its own and then waits for the user to install', () async {
      source.result = sample('preview-8');
      final controller = build();
      await controller.checkNow();
      expect(controller.state.value, isA<UpdateReady>());
      expect((controller.state.value as UpdateReady).release.tag, 'preview-8');
      expect(seen.whereType<UpdateDownloading>(), isNotEmpty);
      expect(downloader.downloads, ['preview-8']);
      expect(installer.installed, isEmpty);
      controller.dispose();
    });

    test('a release that is not newer changes nothing, and says so after a manual check', () async {
      for (final tag in ['preview-7', 'preview-3']) {
        source.result = sample(tag);
        final controller = build();
        await controller.checkNow();
        expect(controller.state.value, isA<UpdateIdle>(), reason: tag);
        await controller.checkNow(manual: true);
        expect(controller.state.value, isA<UpdateUpToDate>(), reason: tag);
        controller.dispose();
      }
      source.result = null;
      final controller = build();
      await controller.checkNow(manual: true);
      expect(controller.state.value, isA<UpdateUpToDate>());
      expect(downloader.downloads, isEmpty);
      controller.dispose();
    });

    test('on a metered network it asks first; the user can then start the download', () async {
      unmetered = false;
      source.result = sample('preview-8');
      final controller = build();
      await controller.checkNow();
      expect(controller.state.value, isA<UpdateAvailable>());
      expect(downloader.downloads, isEmpty);
      await controller.downloadNow();
      expect(controller.state.value, isA<UpdateReady>());
      expect(downloader.downloads, ['preview-8']);
      controller.dispose();
    });

    test('a manual check downloads even on a metered network', () async {
      unmetered = false;
      source.result = sample('preview-8');
      final controller = build();
      await controller.checkNow(manual: true);
      expect(controller.state.value, isA<UpdateReady>());
      controller.dispose();
    });

    test(
      'dismiss hides a waiting release or a failure until the next check',
      () async {
        unmetered = false;
        source.result = sample('preview-8');
        final controller = build();
        await controller.checkNow();
        controller.dismiss();
        expect(controller.state.value, isA<UpdateIdle>());
        source.failure = const UpdateException('x');
        await controller.checkNow(manual: true);
        expect(controller.state.value, isA<UpdateFailed>());
        controller.dismiss();
        expect(controller.state.value, isA<UpdateIdle>());
        controller.dispose();
      },
    );

    test('a background failure is silent, a manual one is shown', () async {
      source.failure = const UpdateException('لا اتصال');
      final controller = build();
      await controller.checkNow();
      expect(controller.state.value, isA<UpdateIdle>());
      await controller.checkNow(manual: true);
      expect((controller.state.value as UpdateFailed).message, 'لا اتصال');
      source.failure = StateError('boom');
      await controller.checkNow(manual: true);
      expect(
        (controller.state.value as UpdateFailed).message,
        contains('تعذّر'),
      );
      controller.dispose();
    });

    test('a failed download can be retried from the failure, and the next check retries too', () async {
      source.result = sample('preview-8');
      downloader.failure = const UpdateException('انقطع');
      final controller = build();
      await controller.checkNow();
      expect(controller.state.value, isA<UpdateFailed>());
      expect(
        (controller.state.value as UpdateFailed).release!.tag,
        'preview-8',
      );
      downloader.failure = null;
      await controller.downloadNow();
      expect(controller.state.value, isA<UpdateReady>());
      controller.dispose();
    });

    test('a file already downloaded and verified is used without downloading again', () async {
      source.result = sample('preview-8');
      downloader.cached = {'preview-8'};
      final controller = build();
      await controller.checkNow();
      expect(controller.state.value, isA<UpdateReady>());
      expect(downloader.downloads, isEmpty);
      controller.dispose();
    });

    test('a ready release is kept on later checks, and replaced when a newer one appears', () async {
      source.result = sample('preview-8');
      final controller = build();
      await controller.checkNow();
      final first = controller.state.value as UpdateReady;
      await controller.checkNow();
      expect(identical(controller.state.value, first), isTrue);
      expect(downloader.downloads, ['preview-8']);
      source.result = sample('preview-9');
      await controller.checkNow();
      expect((controller.state.value as UpdateReady).release.tag, 'preview-9');
      expect(downloader.downloads, ['preview-8', 'preview-9']);
      controller.dispose();
    });

    test('install hands the verified file to the platform installer, only when ready', () async {
      source.result = sample('preview-8');
      final controller = build();
      await controller.install();
      expect(installer.installed, isEmpty);
      await controller.checkNow();
      await controller.install();
      expect(installer.installed, ['preview-8']);
      expect(seen.whereType<UpdateInstalling>(), isNotEmpty);
      // عاد المثبّت (نافذة النظام أُغلقت دون تثبيت): يبقى الزر متاحاً لمحاولة أخرى.
      expect(controller.state.value, isA<UpdateReady>());
      await controller.install();
      expect(installer.installed, ['preview-8', 'preview-8']);
      controller.dispose();
    });

    test('the downloaded files are cleaned once the installed version is the newest', () async {
      source.result = sample('preview-7');
      final controller = build();
      await controller.checkNow();
      await Future<void>.delayed(Duration.zero);
      expect(downloader.cleared, 1);
      source.result = sample('preview-8');
      await controller.checkNow();
      expect(controller.state.value, isA<UpdateReady>());
      expect(downloader.cleared, 1);
      controller.dispose();
    });

    test(
      'an installer error returns to a failure that keeps the release',
      () async {
        source.result = sample('preview-8');
        installer.failure = const UpdateException('ارفض التثبيت');
        final controller = build();
        await controller.checkNow();
        await controller.install();
        expect(controller.state.value, isA<UpdateFailed>());
        expect(
          (controller.state.value as UpdateFailed).message,
          'ارفض التثبيت',
        );
        controller.dispose();
      },
    );

    test('overlapping checks are ignored while one runs', () async {
      final gate = Completer<UpdateRelease?>();
      source.pending = gate.future;
      final controller = build();
      final first = controller.checkNow();
      final second = controller.checkNow();
      await second;
      expect(source.calls, 1);
      gate.complete(null);
      await first;
      controller.dispose();
    });

    test('start() checks once after the delay and then every few hours', () {
      fakeAsync((async) {
        source.result = null;
        final controller = build(first: const Duration(seconds: 20));
        controller.start();
        controller.start();
        async.elapse(const Duration(seconds: 19));
        expect(source.calls, 0);
        async.elapse(const Duration(seconds: 2));
        expect(source.calls, 1);
        async.elapse(const Duration(hours: 6));
        expect(source.calls, 2);
        async.elapse(const Duration(hours: 12));
        expect(source.calls, 4);
        controller.dispose();
        async.elapse(const Duration(hours: 12));
        expect(source.calls, 4);
      });
    });

    test('a disposed controller ignores late results', () async {
      final gate = Completer<UpdateRelease?>();
      source.pending = gate.future;
      final controller = build();
      final check = controller.checkNow();
      controller.dispose();
      gate.complete(sample('preview-8'));
      await check;
      expect(downloader.downloads, isEmpty);
    });
  });
}

class FakeSource implements UpdateSource {
  UpdateRelease? result;
  Object? failure;
  Future<UpdateRelease?>? pending;
  int calls = 0;

  @override
  Future<UpdateRelease?> latest() async {
    calls++;
    if (failure != null) throw failure!;
    return pending ?? result;
  }
}

class FakeDownloader extends UpdateDownloader {
  FakeDownloader(Directory directory) : super(directory: directory);

  final List<String> downloads = [];
  Set<String> cached = {};
  UpdateException? failure;
  int cleared = 0;

  @override
  Future<void> clear() async {
    cleared++;
  }

  @override
  Future<File?> existing(UpdateRelease release) async =>
      cached.contains(release.tag) ? fileFor(release) : null;

  @override
  Future<File> download(
    UpdateRelease release, {
    void Function(int received, int total)? onProgress,
  }) async {
    if (failure != null) throw failure!;
    downloads.add(release.tag);
    onProgress?.call(release.size ~/ 2, release.size);
    onProgress?.call(release.size, release.size);
    return fileFor(release);
  }
}

class FakeInstaller implements UpdateInstaller {
  final List<String> installed = [];
  Object? failure;

  @override
  Future<void> install(File file, UpdateRelease release) async {
    if (failure != null) throw failure!;
    installed.add(release.tag);
  }
}
