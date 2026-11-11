import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Table, TableInfo;
import 'package:http/http.dart' as http;

import '../local/app_database.dart';
import 'remote_store.dart';
import 'synced_tables.dart';

/// تنفيذ [RemoteStore] على واجهة REST لـ Supabase (PostgREST).
///
/// - الدفع: `POST /{table}?on_conflict=…` مع `resolution=merge-duplicates`.
/// - السحب: `GET /{table}?synced_at=gt.N&order=synced_at.asc&limit=M`.
///
/// الأخطاء تُصنَّف: مؤقتة (شبكة، مهلة، 401 رمز منتهٍ، 408، 429، 5xx) تُعاد
/// محاولتها، ونهائية (رفض صلاحيات أو قيد) يُركن صفها.
class PostgrestRemoteStore implements RemoteStore {
  PostgrestRemoteStore({
    required this.restUrl,
    required this.apiKey,
    required this.accessToken,
    required this.primaryKeys,
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
  }) : _client = client ?? http.Client();

  /// عنوان REST، مثل `https://xyz.supabase.co/rest/v1`.
  final String restUrl;

  /// المفتاح العام للمشروع (anon / publishable).
  final String apiKey;

  /// يعيد رمز الدخول الحالي للمستخدم، أو `null` إن لم يسجّل الدخول.
  final Future<String?> Function() accessToken;

  /// أعمدة المفتاح الأساسي لكل جدول (لتحديد التعارض عند الدفع).
  final Map<String, List<String>> primaryKeys;

  final http.Client _client;
  final Duration timeout;

  /// يستخرج أعمدة المفاتيح الأساسية للجداول المزامَنة من القاعدة المحلية.
  static Map<String, List<String>> primaryKeysOf(AppDatabase db) => {
    for (final TableInfo<Table, Object?> table in db.allTables)
      if (!localOnlyTables.contains(table.actualTableName))
        table.actualTableName: [for (final c in table.$primaryKey) c.name],
  };

  @override
  Future<void> upsert(
    String table,
    List<Map<String, Object?>> rows, {
    bool insertOnly = false,
  }) async {
    if (rows.isEmpty) return;
    final keys = primaryKeys[table];
    if (keys == null) {
      throw RemoteException('جدول غير معروف: $table', permanent: true);
    }
    final uri = Uri.parse('$restUrl/$table')
        .replace(queryParameters: {'on_conflict': keys.join(',')});
    final resolution = insertOnly ? 'ignore-duplicates' : 'merge-duplicates';
    final response = await _send(
      () async => _client.post(
        uri,
        headers: {
          ...await _headers(),
          'Content-Type': 'application/json',
          'Prefer': 'resolution=$resolution,return=minimal',
        },
        body: jsonEncode(rows),
      ),
    );
    _check(response);
  }

  @override
  Future<List<Map<String, Object?>>> pull(
    String table, {
    required int afterSyncedAt,
    required int limit,
  }) async {
    final uri = Uri.parse('$restUrl/$table').replace(
      queryParameters: {
        'select': '*',
        'synced_at': 'gt.$afterSyncedAt',
        'order': 'synced_at.asc',
        'limit': '$limit',
      },
    );
    final response = await _send(
      () async => _client.get(uri, headers: await _headers()),
    );
    _check(response);
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const RemoteException('رد غير مفهوم من الخادم', permanent: false);
    }
    if (decoded is! List) {
      throw const RemoteException('رد غير مفهوم من الخادم', permanent: false);
    }
    return [for (final item in decoded) (item as Map).cast<String, Object?>()];
  }

  Future<Map<String, String>> _headers() async {
    final token = await accessToken();
    if (token == null) {
      throw const RemoteException('لم يُسجَّل الدخول', permanent: false);
    }
    return {'apikey': apiKey, 'Authorization': 'Bearer $token'};
  }

  Future<http.Response> _send(Future<http.Response> Function() request) async {
    try {
      return await request().timeout(timeout);
    } on TimeoutException {
      throw const RemoteException('انتهت مهلة الاتصال', permanent: false);
    } on SocketException {
      throw const RemoteException('لا يوجد اتصال بالإنترنت', permanent: false);
    } on http.ClientException {
      throw const RemoteException('لا يوجد اتصال بالإنترنت', permanent: false);
    } on HandshakeException {
      throw const RemoteException('تعذّر الاتصال الآمن', permanent: false);
    }
  }

  static void _check(http.Response response) {
    final status = response.statusCode;
    if (status >= 200 && status < 300) return;
    final transient =
        status == 401 || status == 408 || status == 429 || status >= 500;
    throw RemoteException(
      'الخادم رفض الطلب ($status): ${_message(response)}',
      permanent: !transient,
    );
  }

  static String _message(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map && decoded['message'] is String) {
        return decoded['message'] as String;
      }
    } on FormatException {
      // رد غير JSON: يُعرض رمز الحالة فقط.
    }
    return response.reasonPhrase ?? '';
  }
}
