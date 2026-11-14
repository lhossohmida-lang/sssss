import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'file_store.dart';
import 'remote_store.dart';

/// مخزن Google Drive لملفات تطبيق الإدارة.
///
/// لا يحتفظ برمز OAuth؛ يطلب رمزاً صالحاً عند كل عملية كي يستطيع مزوّد
/// المنصة تجديده دون حفظه في القاعدة المحلية. الملفات تُعنون بمسار منطقي
/// وتُعلَّم في Drive بـ `appProperties`، لذلك إعادة المحاولة أو جهاز آخر
/// يحدّث الملف نفسه بدلاً من إنشاء نسخة مكررة.
class GoogleDriveFileStore implements FileStore {
  GoogleDriveFileStore({
    required this.accessToken,
    http.Client? client,
    this.rootFolderName = 'مدرسة الدروس الخصوصية',
    this.timeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client();

  final Future<String?> Function() accessToken;
  final http.Client _client;
  final String rootFolderName;
  final Duration timeout;

  static const String driveBucket = 'drive';
  static const String _api = 'www.googleapis.com';
  static const String _folderMime = 'application/vnd.google-apps.folder';

  @override
  Future<String> upload({
    required String bucket,
    required String remotePath,
    required String localPath,
  }) async {
    if (bucket != driveBucket) {
      throw RemoteException(
        'مخزن Drive لا يقبل القسم $bucket',
        permanent: true,
      );
    }
    final file = File(localPath);
    if (!await file.exists()) {
      throw const RemoteException('الملف المحلي غير موجود', permanent: true);
    }
    final fileLength = await _fileLength(file);
    final parts = _pathParts(remotePath);
    if (parts.isEmpty) {
      throw const RemoteException('مسار ملف Drive غير صالح', permanent: true);
    }

    final token = await accessToken();
    if (token == null || token.isEmpty) {
      throw const RemoteException(
        'سجّل الدخول إلى حساب Google المالك',
        permanent: false,
      );
    }

    final parentId = await _ensureParent(parts.take(parts.length - 1), token);
    final pathKey = sha256.convert(utf8.encode(parts.join('/'))).toString();
    final existing = await _findByPath(pathKey, token);
    final mimeType = _mimeType(parts.last);
    final fileId = existing == null
        ? await _createFile(
            name: parts.last,
            parentId: parentId,
            pathKey: pathKey,
            mimeType: mimeType,
            file: file,
            fileLength: fileLength,
            token: token,
          )
        : await _replaceFile(
            existing,
            name: parts.last,
            parentId: parentId,
            mimeType: mimeType,
            file: file,
            fileLength: fileLength,
            token: token,
          );
    return fileId;
  }

  @override
  Future<Uint8List> download({
    required String bucket,
    required String remotePath,
  }) async {
    if (bucket != driveBucket) {
      throw RemoteException(
        'مخزن Drive لا يقبل القسم $bucket',
        permanent: true,
      );
    }
    final token = await accessToken();
    if (token == null || token.isEmpty) {
      throw const RemoteException(
        'سجّل الدخول إلى حساب Google المالك',
        permanent: false,
      );
    }
    final response = await _request(
      () => _client.get(
        Uri.https(_api, '/drive/v3/files/${Uri.encodeComponent(remotePath)}', {
          'alt': 'media',
        }),
        headers: _authHeaders(token),
      ),
    );
    _check(response);
    return response.bodyBytes;
  }

  Future<String> _ensureParent(Iterable<String> folders, String token) async {
    var parent = await _ensureFolder(
      name: rootFolderName,
      parentId: 'root',
      folderKey: 'root',
      token: token,
    );
    var path = '';
    for (final name in folders) {
      path = path.isEmpty ? name : '$path/$name';
      parent = await _ensureFolder(
        name: name,
        parentId: parent,
        folderKey: sha256.convert(utf8.encode(path)).toString(),
        token: token,
      );
    }
    return parent;
  }

  Future<String> _ensureFolder({
    required String name,
    required String parentId,
    required String folderKey,
    required String token,
  }) async {
    final query =
        "appProperties has { key='schoolFolder' and value='$folderKey' } "
        "and mimeType='$_folderMime' and trashed=false";
    final found = await _listFiles(query, token);
    if (found.isNotEmpty) return found.first['id']! as String;

    final response = await _request(
      () => _client.post(
        Uri.https(_api, '/drive/v3/files', const {'fields': 'id'}),
        headers: _jsonHeaders(token),
        body: jsonEncode({
          'name': name,
          'mimeType': _folderMime,
          'parents': [parentId],
          'appProperties': {'schoolFolder': folderKey},
        }),
      ),
    );
    _check(response);
    final id = _decodeMap(response.body)['id'];
    if (id is! String || id.isEmpty) {
      throw const RemoteException(
        'رد إنشاء مجلد Drive غير مكتمل',
        permanent: false,
      );
    }
    return id;
  }

  Future<Map<String, Object?>?> _findByPath(
    String pathKey,
    String token,
  ) async {
    final query =
        "appProperties has { key='schoolPath' and value='$pathKey' } "
        'and trashed=false';
    final files = await _listFiles(query, token);
    return files.isEmpty ? null : files.first;
  }

  Future<List<Map<String, Object?>>> _listFiles(
    String query,
    String token,
  ) async {
    final response = await _request(
      () => _client.get(
        Uri.https(_api, '/drive/v3/files', {
          'q': query,
          'spaces': 'drive',
          'pageSize': '100',
          'fields': 'files(id,name,mimeType,parents)',
        }),
        headers: _authHeaders(token),
      ),
    );
    _check(response);
    final files = _decodeMap(response.body)['files'];
    if (files is! List) return const [];
    return files
        .whereType<Map<String, dynamic>>()
        .map(Map<String, Object?>.from)
        .toList();
  }

  Future<String> _createFile({
    required String name,
    required String parentId,
    required String pathKey,
    required String mimeType,
    required File file,
    required int fileLength,
    required String token,
  }) async {
    final response = await _request(
      () => _client.post(
        Uri.https(_api, '/upload/drive/v3/files', {
          'uploadType': 'resumable',
          'fields': 'id',
        }),
        headers: {
          ..._jsonHeaders(token),
          'X-Upload-Content-Type': mimeType,
          'X-Upload-Content-Length': '$fileLength',
        },
        body: jsonEncode({
          'name': name,
          'mimeType': mimeType,
          'parents': [parentId],
          'appProperties': {'schoolPath': pathKey},
        }),
      ),
    );
    _check(response);
    final location = response.headers['location'];
    if (location == null || location.isEmpty) {
      throw const RemoteException(
        'لم يُرجع Drive رابط رفع الملف',
        permanent: false,
      );
    }
    final uploaded = await _putMedia(
      Uri.parse(location),
      file,
      mimeType,
      token,
      fileLength,
    );
    _check(uploaded);
    final id = _decodeMap(uploaded.body)['id'];
    if (id is! String || id.isEmpty) {
      throw const RemoteException('رد رفع Drive غير مكتمل', permanent: false);
    }
    return id;
  }

  Future<String> _replaceFile(
    Map<String, Object?> existing, {
    required String name,
    required String parentId,
    required String mimeType,
    required File file,
    required int fileLength,
    required String token,
  }) async {
    final id = existing['id'];
    if (id is! String || id.isEmpty) {
      throw const RemoteException('معرّف ملف Drive غير صالح', permanent: false);
    }
    final oldParents = existing['parents'];
    final query = <String, String>{'fields': 'id'};
    final currentParents = oldParents is List
        ? oldParents.whereType<String>().toSet()
        : <String>{};
    final parentsToRemove = currentParents.where((value) => value != parentId);
    if (parentsToRemove.isNotEmpty) {
      query['removeParents'] = parentsToRemove.join(',');
    }
    if (!currentParents.contains(parentId)) {
      query['addParents'] = parentId;
    }
    final metadata = await _request(
      () => _client.patch(
        Uri.https(_api, '/drive/v3/files/${Uri.encodeComponent(id)}', query),
        headers: _jsonHeaders(token),
        body: jsonEncode({'name': name, 'mimeType': mimeType}),
      ),
    );
    _check(metadata);

    final uploaded = await _putMedia(
      Uri.https(_api, '/upload/drive/v3/files/${Uri.encodeComponent(id)}', {
        'uploadType': 'media',
      }),
      file,
      mimeType,
      token,
      fileLength,
    );
    _check(uploaded);
    return id;
  }

  Future<http.Response> _putMedia(
    Uri uri,
    File file,
    String mimeType,
    String token,
    int fileLength,
  ) async {
    final request = http.StreamedRequest('PUT', uri)
      ..headers['authorization'] = 'Bearer $token'
      ..headers['content-type'] = mimeType
      ..contentLength = fileLength;
    final responseFuture = _request(
      () => _client.send(request),
      requestTimeout: const Duration(minutes: 2),
    );
    try {
      await request.sink.addStream(file.openRead());
      await request.sink.close();
    } on FileSystemException {
      await request.sink.close();
      throw const RemoteException('تعذّر فتح الملف المحلي', permanent: true);
    } on SocketException {
      await request.sink.close();
      throw const RemoteException(
        'انقطع الاتصال بـ Google Drive',
        permanent: false,
      );
    } on http.ClientException {
      await request.sink.close();
      throw const RemoteException(
        'انقطع الاتصال بـ Google Drive',
        permanent: false,
      );
    }
    final streamed = await responseFuture;
    return http.Response.fromStream(streamed);
  }

  Future<T> _request<T>(
    Future<T> Function() send, {
    Duration? requestTimeout,
  }) async {
    try {
      return await send().timeout(requestTimeout ?? timeout);
    } on RemoteException {
      rethrow;
    } on SocketException {
      throw const RemoteException(
        'تعذّر الاتصال بـ Google Drive',
        permanent: false,
      );
    } on http.ClientException {
      throw const RemoteException(
        'تعذّر الاتصال بـ Google Drive',
        permanent: false,
      );
    } on HttpException {
      throw const RemoteException(
        'تعذّر الاتصال بـ Google Drive',
        permanent: false,
      );
    } on TimeoutException {
      throw const RemoteException(
        'انتهت مهلة الاتصال بـ Google Drive',
        permanent: false,
      );
    }
  }

  Map<String, String> _authHeaders(String token) => {
    'authorization': 'Bearer $token',
    'accept': 'application/json',
  };

  Map<String, String> _jsonHeaders(String token) => {
    ..._authHeaders(token),
    'content-type': 'application/json; charset=utf-8',
  };

  void _check(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    final body = _decodeMap(response.body);
    final error = body['error'];
    final message = error is Map ? error['message'] : null;
    final details = error is Map ? error['errors'] : null;
    final reason = details is List && details.isNotEmpty && details.first is Map
        ? (details.first as Map)['reason']
        : null;
    final permanent =
        response.statusCode == 400 ||
        response.statusCode == 401 ||
        (response.statusCode == 403 &&
            reason != 'rateLimitExceeded' &&
            reason != 'userRateLimitExceeded');
    throw RemoteException(
      message is String && message.isNotEmpty
          ? 'Google Drive: $message'
          : 'تعذّر الرفع إلى Google Drive (${response.statusCode})',
      permanent: permanent,
    );
  }

  Map<String, dynamic> _decodeMap(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // يعرض الفشل رسالة عامة ولا يكشف استجابة HTML للواجهة.
    }
    return const {};
  }

  Future<int> _fileLength(File file) async {
    try {
      return await file.length();
    } on FileSystemException {
      throw const RemoteException('تعذّر فتح الملف المحلي', permanent: true);
    }
  }

  List<String> _pathParts(String value) => [
    for (final segment in value.replaceAll('\\', '/').split('/'))
      if (segment.trim().isNotEmpty && segment != '.' && segment != '..')
        segment.trim(),
  ];

  String _mimeType(String name) => switch (name.split('.').last.toLowerCase()) {
    'xlsx' =>
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'xls' => 'application/vnd.ms-excel',
    'pdf' => 'application/pdf',
    'zip' => 'application/zip',
    'json' => 'application/json',
    'csv' => 'text/csv',
    _ => 'application/octet-stream',
  };

  void dispose() => _client.close();
}
