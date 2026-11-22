import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// رقم إصدار منشور: `preview-N` (التجريبية) أو `vX.Y.Z` (المستقرة، وهي أحدث من كل التجريبية).
@immutable
class ReleaseVersion implements Comparable<ReleaseVersion> {
  const ReleaseVersion._(this.tag, this._rank, this._numbers);

  final String tag;
  final int _rank;
  final List<int> _numbers;

  static final RegExp _preview = RegExp(r'^preview-(\d+)$');
  static final RegExp _stable = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)$');

  /// يحلّل وسم إصدار، ويعيد `null` إن لم يكن بإحدى الصيغتين.
  static ReleaseVersion? tryParse(String tag) {
    final text = tag.trim();
    final preview = _preview.firstMatch(text);
    if (preview != null) {
      return ReleaseVersion._(text, 0, [int.parse(preview.group(1)!)]);
    }
    final stable = _stable.firstMatch(text);
    if (stable != null) {
      return ReleaseVersion._(text, 1, [
        for (var i = 1; i <= 3; i++) int.parse(stable.group(i)!),
      ]);
    }
    return null;
  }

  @override
  int compareTo(ReleaseVersion other) {
    if (_rank != other._rank) return _rank.compareTo(other._rank);
    for (var i = 0; i < _numbers.length && i < other._numbers.length; i++) {
      final order = _numbers[i].compareTo(other._numbers[i]);
      if (order != 0) return order;
    }
    return _numbers.length.compareTo(other._numbers.length);
  }

  bool operator >(ReleaseVersion other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) =>
      other is ReleaseVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(_rank, Object.hashAll(_numbers));

  @override
  String toString() => tag;
}

/// إصدار جديد جاهز للتنزيل: ملف تطبيق هذا النظام وبصمته.
@immutable
class UpdateRelease {
  const UpdateRelease({
    required this.version,
    required this.assetName,
    required this.url,
    required this.size,
    required this.sha256,
  });

  final ReleaseVersion version;
  final String assetName;
  final Uri url;

  /// حجم الملف بالبايت.
  final int size;

  /// بصمة SHA-256 (16 خانة سداسية صغيرة) يتحقق منها التنزيل.
  final String sha256;

  String get tag => version.tag;

  @override
  bool operator ==(Object other) =>
      other is UpdateRelease &&
      other.tag == tag &&
      other.assetName == assetName &&
      other.sha256 == sha256;

  @override
  int get hashCode => Object.hash(tag, assetName, sha256);
}

/// فشل في التحقق من التحديث أو تنزيله؛ رسالته عربية تُعرض للمستخدم.
class UpdateException implements Exception {
  const UpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// مصدر الإصدارات المنشورة.
abstract interface class UpdateSource {
  /// أحدث إصدار فيه ملف هذا التطبيق، أو `null` إن لم يوجد.
  Future<UpdateRelease?> latest();
}

/// يقرأ إصدارات مستودع GitHub العام (التجريبية منها أيضاً، فنقطة `releases/latest` لا تُعيدها).
///
/// لا يقبل إلا ملفات من `github.com/<المستودع>/releases/download/` وبصمة SHA-256 يعلنها GitHub لكل ملف.
class GitHubUpdateSource implements UpdateSource {
  GitHubUpdateSource({
    required this.repo,
    required this.assetName,
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// `المالك/المستودع`.
  final String repo;
  final String assetName;
  final http.Client _client;

  static final RegExp _digest = RegExp(r'^sha256:([0-9a-fA-F]{64})$');

  @override
  Future<UpdateRelease?> latest() async {
    final http.Response response;
    try {
      response = await _client
          .get(
            Uri.https('api.github.com', '/repos/$repo/releases', {
              'per_page': '15',
            }),
            headers: const {
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'school-management-updater',
            },
          )
          .timeout(const Duration(seconds: 20));
    } on Object {
      throw const UpdateException('تعذّر الاتصال بخادم التحديثات');
    }
    if (response.statusCode != 200) {
      throw UpdateException('تعذّر قراءة التحديثات (${response.statusCode})');
    }
    return parseReleases(utf8.decode(response.bodyBytes));
  }

  /// يختار أحدث إصدار (غير المسوّدات) فيه [assetName] ببصمة وعنوان تنزيل سليمين.
  @visibleForTesting
  UpdateRelease? parseReleases(String json) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      throw const UpdateException('ردّ خادم التحديثات غير مفهوم');
    }
    if (decoded is! List) {
      throw const UpdateException('ردّ خادم التحديثات غير مفهوم');
    }
    UpdateRelease? best;
    for (final item in decoded) {
      if (item is! Map || item['draft'] == true) continue;
      final version = ReleaseVersion.tryParse('${item['tag_name']}');
      if (version == null) continue;
      final assets = item['assets'];
      if (assets is! List) continue;
      for (final asset in assets) {
        if (asset is! Map || asset['name'] != assetName) continue;
        final release = _release(version, asset);
        if (release != null && (best == null || version > best.version)) {
          best = release;
        }
      }
    }
    return best;
  }

  UpdateRelease? _release(ReleaseVersion version, Map<dynamic, dynamic> asset) {
    final url = Uri.tryParse('${asset['browser_download_url']}');
    final digest = _digest.firstMatch('${asset['digest']}');
    final size = asset['size'];
    if (url == null || digest == null || size is! int || size <= 0) return null;
    final prefix = '/$repo/releases/download/';
    if (url.scheme != 'https' ||
        url.host != 'github.com' ||
        !url.path.startsWith(prefix)) {
      return null;
    }
    return UpdateRelease(
      version: version,
      assetName: assetName,
      url: url,
      size: size,
      sha256: digest.group(1)!.toLowerCase(),
    );
  }
}

/// ينزّل ملف الإصدار إلى مجلد، ويتحقق من بصمته وحجمه، ولا يترك إلا ملفاً سليماً.
class UpdateDownloader {
  UpdateDownloader({required this.directory, http.Client? client})
    : _client = client ?? http.Client();

  final Directory directory;
  final http.Client _client;

  /// مسار الملف النهائي للإصدار.
  File fileFor(UpdateRelease release) =>
      File(p.join(directory.path, '${release.tag}-${release.assetName}'));

  /// ملف سليم نُزّل سابقاً لهذا الإصدار، أو `null`.
  Future<File?> existing(UpdateRelease release) async {
    final file = fileFor(release);
    if (!await file.exists()) return null;
    if (await file.length() != release.size) return null;
    final digest = await sha256.bind(file.openRead()).first;
    if (digest.toString() == release.sha256) return file;
    return null;
  }

  Future<File> download(
    UpdateRelease release, {
    void Function(int received, int total)? onProgress,
  }) async {
    await directory.create(recursive: true);
    final ready = await existing(release);
    if (ready != null) {
      await _removeOthers(keep: ready);
      return ready;
    }
    final target = fileFor(release);
    final partial = File('${target.path}.part');
    if (await partial.exists()) await partial.delete();
    IOSink? sink;
    try {
      final response = await _client
          .send(http.Request('GET', release.url))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw UpdateException('تعذّر تنزيل التحديث (${response.statusCode})');
      }
      sink = partial.openWrite();
      final digestSink = _DigestSink();
      final hash = sha256.startChunkedConversion(digestSink);
      var received = 0;
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 60),
      )) {
        sink.add(chunk);
        hash.add(chunk);
        received += chunk.length;
        onProgress?.call(received, release.size);
      }
      hash.close();
      await sink.flush();
      await sink.close();
      sink = null;
      if (received != release.size ||
          digestSink.value.toString() != release.sha256) {
        throw const UpdateException('الملف المنزَّل تالف: لم تتطابق بصمته');
      }
      if (await target.exists()) await target.delete();
      await partial.rename(target.path);
    } on UpdateException {
      await _discard(sink, partial);
      rethrow;
    } on Object {
      await _discard(sink, partial);
      throw const UpdateException('انقطع تنزيل التحديث');
    }
    await _removeOthers(keep: target);
    return target;
  }

  Future<void> _discard(IOSink? sink, File partial) async {
    try {
      await sink?.close();
    } on Object {
      // أُغلق من قبل.
    }
    if (await partial.exists()) await partial.delete();
  }

  /// يحذف كل ما نُزِّل: النسخة المثبّتة صارت هي الأحدث فلا حاجة لملف التحديث.
  Future<void> clear() async {
    if (!await directory.exists()) return;
    await for (final entity in directory.list()) {
      if (entity is File) await entity.delete();
    }
  }

  /// يحذف ملفات الإصدارات الأقدم وما تبقى من تنزيل ناقص.
  Future<void> _removeOthers({required File keep}) async {
    await for (final entity in directory.list()) {
      if (entity is File && p.equals(entity.path, keep.path) == false) {
        await entity.delete();
      }
    }
  }
}

/// يستقبل بصمة التجزئة المتدرجة (ناتج وحيد عند الإغلاق).
class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

/// يثبّت الملف المنزَّل (Android: نافذة التثبيت، Windows: مثبّت صامت ثم إعادة تشغيل).
abstract interface class UpdateInstaller {
  /// يبدأ التثبيت. على Windows يُغلق التطبيق نفسه لتحلّ النسخة الجديدة محلّه.
  Future<void> install(File file, UpdateRelease release);
}

@immutable
sealed class UpdateState {
  const UpdateState();
}

/// لا شيء يُعرض (لم يُفحص بعد، أو التحديث غير مفعّل).
class UpdateIdle extends UpdateState {
  const UpdateIdle();
}

class UpdateChecking extends UpdateState {
  const UpdateChecking();
}

/// النسخة المثبّتة هي الأحدث.
class UpdateUpToDate extends UpdateState {
  const UpdateUpToDate();
}

/// إصدار جديد لم يُنزَّل: ينتظر «تنزيل» (حين يمنع [UpdateController] التنزيل التلقائي)، أو على iPhone يُعلَن فقط.
class UpdateAvailable extends UpdateState {
  const UpdateAvailable(this.release);

  final UpdateRelease release;
}

class UpdateDownloading extends UpdateState {
  const UpdateDownloading(this.release, this.received);

  final UpdateRelease release;
  final int received;

  double get fraction =>
      release.size <= 0 ? 0 : (received / release.size).clamp(0, 1).toDouble();
}

/// نُزّل وتحقّق منه، ينتظر التثبيت.
class UpdateReady extends UpdateState {
  const UpdateReady(this.release, this.file);

  final UpdateRelease release;
  final File file;
}

class UpdateInstalling extends UpdateState {
  const UpdateInstalling(this.release);

  final UpdateRelease release;
}

class UpdateFailed extends UpdateState {
  const UpdateFailed(this.message, {this.release});

  final String message;
  final UpdateRelease? release;
}

/// يفحص الإصدارات دورياً وينزّل الجديد تلقائياً (على شبكة غير محدودة) ثم يعرض تثبيته.
///
/// معطَّل (لا يفعل شيئاً) إن كان [currentTag] فارغاً أو غير مفهوم: بناءات التطوير وبناءات المدرسة الخاصة
/// لا تتحدث تلقائياً.
class UpdateController {
  UpdateController({
    required this.currentTag,
    required this._source,
    required this._downloader,
    required this._installer,
    Future<bool> Function()? canDownloadAutomatically,
    this.canDownload = true,
    this.firstCheckDelay = const Duration(seconds: 3),
    this.checkEvery = const Duration(hours: 6),
  }) : _canDownloadAutomatically = canDownloadAutomatically ?? _always,
       _current = ReleaseVersion.tryParse(currentTag);

  static Future<bool> _always() async => true;

  final String currentTag;

  /// هل يُنزَّل الملف ويُثبَّت من التطبيق؟ لا على iPhone: يُعلن الإصدار الجديد فقط (`UpdateAvailable`) ويُثبَّت
  /// من حاسوب (Sideloadly)، فلا يُنزَّل ملف لا يمكن تثبيته.
  final bool canDownload;
  final Duration firstCheckDelay;
  final Duration checkEvery;
  final UpdateSource _source;
  final UpdateDownloader _downloader;
  final UpdateInstaller _installer;
  final Future<bool> Function() _canDownloadAutomatically;
  final ReleaseVersion? _current;

  final ValueNotifier<UpdateState> state = ValueNotifier(const UpdateIdle());

  Timer? _timer;
  bool _busy = false;
  bool _disposed = false;

  /// هل التحديث التلقائي مفعّل لهذا البناء؟
  bool get enabled => _current != null;

  /// يبدأ الفحص بعد [firstCheckDelay] ثم كل [checkEvery].
  void start() {
    if (!enabled || _timer != null || _disposed) return;
    _timer = Timer(firstCheckDelay, () {
      unawaited(checkNow());
      _timer = Timer.periodic(checkEvery, (_) => unawaited(checkNow()));
    });
  }

  /// يفحص الآن. [manual] بطلب المستخدم: ينزّل ولو على شبكة بيانات، ويعرض «أحدث نسخة».
  Future<void> checkNow({bool manual = false}) async {
    final current = _current;
    if (current == null || _busy || _disposed) return;
    if (state.value case UpdateDownloading() || UpdateInstalling()) return;
    _busy = true;
    final before = state.value;
    try {
      if (manual) _set(const UpdateChecking());
      final latest = await _source.latest();
      if (_disposed) return;
      if (latest == null || !(latest.version > current)) {
        // النسخة المثبّتة هي الأحدث: يُنظَّف ما نُزِّل لها سابقاً.
        unawaited(_downloader.clear().catchError((Object _) {}));
        _set(manual ? const UpdateUpToDate() : const UpdateIdle());
        return;
      }
      if (!canDownload) {
        _set(UpdateAvailable(latest));
        return;
      }
      if (before case UpdateReady(:final release) when release == latest) {
        _set(before);
        return;
      }
      final cached = await _downloader.existing(latest);
      if (_disposed) return;
      if (cached != null) {
        _set(UpdateReady(latest, cached));
        return;
      }
      if (manual || await _canDownloadAutomatically()) {
        if (_disposed) return;
        await _download(latest);
      } else {
        _set(UpdateAvailable(latest));
      }
    } on UpdateException catch (error) {
      _set(manual ? UpdateFailed(error.message) : before);
    } on Object {
      _set(manual ? const UpdateFailed('تعذّر فحص التحديثات') : before);
    } finally {
      _busy = false;
    }
  }

  /// تنزيل بطلب المستخدم (إصدار متاح لم يُنزَّل، أو بعد فشل).
  Future<void> downloadNow() async {
    final current = state.value;
    final release = switch (current) {
      UpdateAvailable(:final release) => release,
      UpdateFailed(:final release?) => release,
      _ => null,
    };
    if (release == null || !canDownload || _busy || _disposed) return;
    _busy = true;
    try {
      await _download(release);
    } finally {
      _busy = false;
    }
  }

  Future<void> _download(UpdateRelease release) async {
    _set(UpdateDownloading(release, 0));
    var lastReport = 0;
    try {
      final file = await _downloader.download(
        release,
        onProgress: (received, total) {
          // نحدّث الشريط كل 1% لا مع كل جزء.
          final step = (received * 100 ~/ total);
          if (step != lastReport) {
            lastReport = step;
            _set(UpdateDownloading(release, received));
          }
        },
      );
      _set(UpdateReady(release, file));
    } on UpdateException catch (error) {
      _set(UpdateFailed(error.message, release: release));
    }
  }

  /// يثبّت النسخة الجاهزة (Windows: يُغلق التطبيق).
  Future<void> install() async {
    final current = state.value;
    if (current is! UpdateReady || _disposed) return;
    _set(UpdateInstalling(current.release));
    try {
      await _installer.install(current.file, current.release);
      // أندرويد: عادت نافذة النظام دون تثبيت (ألغاها المستخدم أو منح إذن المصدر): يبقى «تثبيت الآن» متاحاً.
      if (state.value is UpdateInstalling) _set(current);
    } on UpdateException catch (error) {
      _set(UpdateFailed(error.message, release: current.release));
    } on Object {
      _set(UpdateFailed('تعذّر بدء التثبيت', release: current.release));
    }
  }

  /// يخفي رسالة فشل أو إصدار ينتظر موافقة حتى الفحص التالي.
  void dismiss() {
    if (state.value case UpdateFailed() || UpdateAvailable()) {
      _set(const UpdateIdle());
    }
  }

  void _set(UpdateState value) {
    if (!_disposed) state.value = value;
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    state.dispose();
  }
}
