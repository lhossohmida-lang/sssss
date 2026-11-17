import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../domain/phone.dart';
import 'school_pairing.dart';

/// عنوان دليل المدارس ومفتاحه العام: يُضمَّنان وقت البناء بـ `--dart-define`
/// (`DIRECTORY_URL` و`DIRECTORY_KEY`) في النسخة العامة وحدها.
///
/// دليل المدارس مشروع Supabase واحد للمطوّر لا يحمل بيانات أي مدرسة؛ يعرف منه
/// التطبيق أي خادم يتصل به فلا يلصق أحد رمز ربط. دونه (بناء تطوير) تبقى شاشة
/// الربط القديمة.
class DirectoryConfig {
  const DirectoryConfig({this.url = '', this.key = ''});

  factory DirectoryConfig.fromEnvironment() => const DirectoryConfig(
    url: String.fromEnvironment('DIRECTORY_URL'),
    key: String.fromEnvironment('DIRECTORY_KEY'),
  );

  final String url;

  /// المفتاح العام للدليل (`sb_publishable_…`)؛ المفتاح السرّي يُرفض.
  final String key;

  bool get isConfigured =>
      url.startsWith('https://') &&
      Uri.tryParse(url)?.hasAuthority == true &&
      key.isNotEmpty &&
      !key.startsWith('sb_secret_');
}

/// مدرسة في الدليل: اسمها وعنوان خادمها ومفتاحه العام.
class DirectorySchool {
  const DirectorySchool({
    required this.id,
    required this.name,
    required this.url,
    required this.key,
  });

  /// يقرأ صفاً أعاده الدليل، أو يعيد `null` إن كان تالفاً (عنوان أو مفتاح غير
  /// مقبول، مثل مفتاح سرّي) فيُتجاهل ولا يُوصل التطبيق بخادم مشبوه.
  static DirectorySchool? tryParse(Object? row) {
    if (row is! Map) return null;
    final id = row['id'];
    final name = row['name'];
    final url = row['url'];
    final key = row['publishable_key'];
    if (id is! String || name is! String || url is! String || key is! String) {
      return null;
    }
    try {
      // التحقق نفسه الذي يجريه رمز الربط: https دون مسار، ومفتاح عام فقط.
      final pairing = SchoolPairing.fromJson({
        'v': 1,
        'u': url,
        'k': key,
        'n': name.trim(),
      });
      return DirectorySchool(
        id: id,
        name: pairing.name.isEmpty ? pairing.url : pairing.name,
        url: pairing.url,
        key: pairing.key,
      );
    } on PairingException {
      return null;
    }
  }

  final String id;
  final String name;
  final String url;
  final String key;

  /// الربط الذي يحفظه الجهاز لهذه المدرسة.
  SchoolPairing toPairing() => SchoolPairing(url: url, key: key, name: name);

  @override
  bool operator ==(Object other) =>
      other is DirectorySchool &&
      other.id == id &&
      other.name == name &&
      other.url == url &&
      other.key == key;

  @override
  int get hashCode => Object.hash(id, name, url, key);

  @override
  String toString() => 'DirectorySchool($id, $name)';
}

/// سبب تعذّر الاتصال بالدليل.
enum DirectoryFailure {
  offline('تعذّر الاتصال بدليل المدارس، تحقق من الإنترنت ثم أعد المحاولة'),
  rateLimited('محاولات كثيرة، انتظر قليلاً ثم أعد المحاولة'),
  unavailable('دليل المدارس غير متاح الآن، أعد المحاولة بعد قليل');

  const DirectoryFailure(this.message);

  final String message;
}

class DirectoryException implements Exception {
  const DirectoryException(this.failure);

  final DirectoryFailure failure;

  String get message => failure.message;

  @override
  String toString() => 'DirectoryException(${failure.name})';
}

/// قراءة الدليل: قائمة المدارس المُعلنة، والمدارس التي لطاقمها رقم هاتف.
abstract interface class SchoolDirectory {
  /// المدارس المُعلنة بترتيب الاسم (تطبيقا الأستاذ والتلميذ).
  ///
  /// يرمي [DirectoryException] عند تعذّر الاتصال.
  Future<List<DirectorySchool>> listSchools();

  /// المدارس التي يستعمل مالكها أو عمالها هذا الرقم (حتى خمس)، أو قائمة فارغة
  /// إن لم يُعرف، وكذلك للرقم غير الصالح (تطبيق الإدارة).
  ///
  /// يرمي [DirectoryException] عند تعذّر الاتصال.
  Future<List<DirectorySchool>> resolveByPhone(String phone);
}

/// الدليل الحقيقي عبر REST: دالتا `list_schools` و`resolve_school` بالمفتاح العام.
class HttpSchoolDirectory implements SchoolDirectory {
  HttpSchoolDirectory(
    this.config, {
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client();

  final DirectoryConfig config;
  final Duration timeout;
  final http.Client _client;

  @override
  Future<List<DirectorySchool>> listSchools() => _rpc('list_schools', const {});

  @override
  Future<List<DirectorySchool>> resolveByPhone(String phone) {
    final local = PhoneNumbers.normalize(phone);
    if (!PhoneNumbers.isValid(local)) return Future.value(const []);
    return _rpc('resolve_school', {'p_phone': local});
  }

  Future<List<DirectorySchool>> _rpc(
    String name,
    Map<String, Object?> body,
  ) async {
    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse(
              '${config.url.replaceAll(RegExp(r'/+$'), '')}/rest/v1/rpc/$name',
            ),
            headers: {
              'apikey': config.key,
              if (config.key.startsWith('eyJ'))
                'Authorization': 'Bearer ${config.key}',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const DirectoryException(DirectoryFailure.offline);
    } on SocketException {
      throw const DirectoryException(DirectoryFailure.offline);
    } on http.ClientException {
      throw const DirectoryException(DirectoryFailure.offline);
    }
    if (response.statusCode == 429 || response.body.contains('rate_limited')) {
      throw const DirectoryException(DirectoryFailure.rateLimited);
    }
    if (response.statusCode != 200) {
      throw const DirectoryException(DirectoryFailure.unavailable);
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const DirectoryException(DirectoryFailure.unavailable);
    }
    if (decoded is! List) {
      throw const DirectoryException(DirectoryFailure.unavailable);
    }
    return [for (final row in decoded) ?DirectorySchool.tryParse(row)];
  }

  void close() => _client.close();
}
