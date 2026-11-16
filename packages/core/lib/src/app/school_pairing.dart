import 'dart:convert';
import 'dart:io';

import 'app_config.dart';

/// سبب رفض رمز ربط المدرسة.
enum PairingFailure {
  /// لا نصّ.
  empty('الصق رمز الربط الذي سلّمته لك إدارة المدرسة'),

  /// ليس رمز ربط (بداية خاطئة أو ترميز تالف).
  malformed('هذا ليس رمز ربط صحيحاً، انسخه كاملاً دون حذف شيء منه'),

  /// رمز من إصدار أحدث من هذا التطبيق.
  unsupportedVersion('هذا الرمز من إصدار أحدث، حدّث التطبيق ثم أعد المحاولة'),

  /// عنوان الخادم ليس https صالحاً.
  badUrl('عنوان خادم المدرسة في الرمز غير صالح'),

  /// المفتاح ناقص أو غير مقبول.
  badKey('مفتاح الاتصال في الرمز غير صالح'),

  /// المفتاح سرّي (لا يُوضع في التطبيقات أبداً).
  secretKey(
    'هذا الرمز يحوي مفتاحاً سرياً لا مفتاحاً عاماً، لا تستعمله وأبلغ من أعطاك إياه',
  );

  const PairingFailure(this.message);

  /// رسالة عربية للمستخدم.
  final String message;
}

/// يُرمى عند رفض رمز ربط.
class PairingException implements Exception {
  const PairingException(this.failure);

  final PairingFailure failure;

  String get message => failure.message;

  @override
  String toString() => 'PairingException(${failure.name})';
}

/// ما يربط تطبيقاً واحداً بمدرسة واحدة: عنوان خادمها ومفتاحه العام واسمها.
///
/// المفتاح العام مصمَّم ليُضمَّن في التطبيقات (يحمي الصلاحيات RLS وحسابات
/// الدخول لا سرّيته)، لكن مفتاحاً سرياً (`sb_secret_…` أو `service_role`)
/// يُرفض هنا دائماً حتى لو لُصق بالخطأ.
class SchoolPairing {
  const SchoolPairing({required this.url, required this.key, this.name = ''});

  /// يقرأ رمزاً أعطته الإدارة (نصّاً أو من رمز QR) ويتحقق منه.
  ///
  /// يرمي [PairingException] بسبب عربي واضح عند أي خلل.
  factory SchoolPairing.parse(String code) {
    final cleaned = code.replaceAll(RegExp(r'\s+'), '');
    if (cleaned.isEmpty) throw const PairingException(PairingFailure.empty);
    if (!cleaned.toLowerCase().startsWith(_prefix.toLowerCase())) {
      throw const PairingException(PairingFailure.malformed);
    }
    final Object? decoded;
    try {
      final body = cleaned.substring(_prefix.length);
      decoded = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(body))),
      );
    } on FormatException {
      throw const PairingException(PairingFailure.malformed);
    }
    if (decoded is! Map) {
      throw const PairingException(PairingFailure.malformed);
    }
    return SchoolPairing._fromMap(decoded);
  }

  /// يقرأ ما حُفظ على الجهاز بـ [toJson].
  factory SchoolPairing.fromJson(Map<String, Object?> json) =>
      SchoolPairing._fromMap(json);

  factory SchoolPairing._fromMap(Map<Object?, Object?> map) {
    final version = map['v'];
    if (version is! int) {
      throw const PairingException(PairingFailure.malformed);
    }
    if (version != _version) {
      throw const PairingException(PairingFailure.unsupportedVersion);
    }
    final url = _normalizeUrl(map['u']);
    final key = _checkKey(map['k']);
    final rawName = map['n'];
    final name = rawName is String ? rawName.trim() : '';
    if (name.length > _maxName) {
      throw const PairingException(PairingFailure.malformed);
    }
    return SchoolPairing(url: url, key: key, name: name);
  }

  static const String _prefix = 'SCH1.';
  static const int _version = 1;
  static const int _maxName = 80;

  /// عنوان مشروع Supabase، مثل `https://xxxx.supabase.co`.
  final String url;

  /// المفتاح العام (`sb_publishable_…` أو مفتاح anon القديم).
  final String key;

  /// اسم المدرسة للعرض قبل أن تصل إعداداتها من الخادم؛ قد يكون فارغاً.
  final String name;

  /// الرمز القابل للنسخ أو للتحويل إلى QR.
  String get code {
    final payload = jsonEncode(toJson());
    return '$_prefix${base64Url.encode(utf8.encode(payload)).replaceAll('=', '')}';
  }

  Map<String, Object?> toJson() => {
    'v': _version,
    'u': url,
    'k': key,
    if (name.isNotEmpty) 'n': name,
  };

  /// إعدادات الاتصال المقابلة.
  AppConfig toConfig() =>
      AppConfig(supabaseUrl: url, supabaseAnonKey: key, schoolName: name);

  @override
  bool operator ==(Object other) =>
      other is SchoolPairing &&
      other.url == url &&
      other.key == key &&
      other.name == name;

  @override
  int get hashCode => Object.hash(url, key, name);

  @override
  String toString() => 'SchoolPairing(${AppConfig.schoolKeyOf(url)})';

  static String _normalizeUrl(Object? raw) {
    if (raw is! String) throw const PairingException(PairingFailure.badUrl);
    final uri = Uri.tryParse(raw.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw const PairingException(PairingFailure.badUrl);
    }
    final port = uri.hasPort && uri.port != 443 ? ':${uri.port}' : '';
    return 'https://${uri.host.toLowerCase()}$port';
  }

  static String _checkKey(Object? raw) {
    if (raw is! String) throw const PairingException(PairingFailure.badKey);
    final key = raw.trim();
    if (key.length < 20 || key.length > 600 || key.contains(RegExp(r'\s'))) {
      throw const PairingException(PairingFailure.badKey);
    }
    if (key.startsWith('sb_secret_')) {
      throw const PairingException(PairingFailure.secretKey);
    }
    final parts = key.split('.');
    if (parts.length == 3) {
      // مفتاح قديم بصيغة JWT: لا يُقبل إلا دور anon.
      try {
        final claims = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
        );
        if (claims is Map && claims['role'] != 'anon') {
          throw const PairingException(PairingFailure.secretKey);
        }
      } on FormatException {
        throw const PairingException(PairingFailure.badKey);
      }
    }
    return key;
  }
}

/// مكان حفظ ما اختاره الجهاز: مدرسة بخادمها، أو معاينة محلية بلا خادم
/// (تطبيق الإدارة وحده).
abstract interface class PairingStore {
  /// الربط المحفوظ، أو `null` إن لم يُربط الجهاز أو كان المحفوظ تالفاً.
  Future<SchoolPairing?> load();

  /// هل اختار هذا الجهاز المعاينة المحلية بدل مدرسة؟
  Future<bool> isLocalPreview();

  /// يحفظ ربطاً بمدرسة (ويلغي اختيار المعاينة المحلية).
  Future<void> save(SchoolPairing pairing);

  /// يحفظ اختيار المعاينة المحلية (ويفك أي ربط).
  Future<void> chooseLocalPreview();

  /// يفك الربط واختيار المعاينة معاً (لا يمسّ قاعدة المدرسة المحلية فتعود كما
  /// كانت عند إعادة الربط بالمدرسة نفسها).
  Future<void> clear();
}

/// يحفظ الاختيار في ملف JSON صغير بجانب قاعدة التطبيق.
class FilePairingStore implements PairingStore {
  FilePairingStore(this.file);

  final File file;

  Future<Map<String, Object?>?> _read() async {
    try {
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  @override
  Future<SchoolPairing?> load() async {
    final map = await _read();
    if (map == null || !map.containsKey('u')) return null;
    try {
      return SchoolPairing.fromJson(map);
    } on PairingException {
      return null;
    }
  }

  @override
  Future<bool> isLocalPreview() async {
    final map = await _read();
    return map != null && map['local'] == true && !map.containsKey('u');
  }

  @override
  Future<void> save(SchoolPairing pairing) => _write(pairing.toJson());

  @override
  Future<void> chooseLocalPreview() => _write({'v': 1, 'local': true});

  @override
  Future<void> clear() async {
    if (await file.exists()) await file.delete();
  }

  Future<void> _write(Map<String, Object?> json) async {
    await file.parent.create(recursive: true);
    // كتابة ملف مؤقت ثم إعادة تسميته: انقطاع التيار لا يترك ملفاً نصف مكتوب.
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(json), flush: true);
    await temp.rename(file.path);
  }
}

/// إعدادات المدرسة المعتمدة في هذا التشغيل: المضمَّنة وقت البناء إن وُجدت
/// (بناء تطوير أو بناء مخصَّص لمدرسة)، وإلا ما ربط به الجهاز نفسه.
///
/// `null` حين لا يوجد أيٌّ منهما، أي جهاز لم يُربط بعد.
Future<AppConfig?> resolveSchoolConfig(
  PairingStore store, {
  AppConfig? baked,
}) async {
  final built = baked ?? AppConfig.fromEnvironment();
  if (built.isConfigured) return built;
  return (await store.load())?.toConfig();
}
