import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:school_core/school_core.dart';

void main() {
  late Directory directory;
  late File localFile;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('drive_store_test');
    localFile = File('${directory.path}/attendance.xlsx')
      ..writeAsBytesSync([1, 2, 3, 4]);
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('ينشئ شجرة المجلدات ويرفع الملف برفع قابل للاستئناف', () async {
    var createdFolders = 0;
    Map<String, Object?>? uploadMetadata;
    final client = MockClient((request) async {
      expect(request.headers['authorization'], 'Bearer access-token');
      if (request.method == 'GET' && request.url.path == '/drive/v3/files') {
        return http.Response('{"files":[]}', 200);
      }
      if (request.method == 'POST' && request.url.path == '/drive/v3/files') {
        createdFolders++;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['mimeType'], 'application/vnd.google-apps.folder');
        expect(body['parents'], isA<List<dynamic>>());
        expect(
          (body['appProperties'] as Map<String, dynamic>).keys,
          contains('schoolFolder'),
        );
        return http.Response('{"id":"folder-$createdFolders"}', 200);
      }
      if (request.method == 'POST' &&
          request.url.path == '/upload/drive/v3/files') {
        uploadMetadata = jsonDecode(request.body) as Map<String, Object?>;
        expect(request.url.queryParameters['uploadType'], 'resumable');
        expect(
          request.headers['x-upload-content-type'],
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        );
        return http.Response(
          '',
          200,
          headers: {
            'location': 'https://www.googleapis.com/upload/session/one',
          },
        );
      }
      if (request.method == 'PUT' &&
          request.url.path == '/upload/session/one') {
        expect(request.bodyBytes, [1, 2, 3, 4]);
        expect(request.contentLength, 4);
        return http.Response('{"id":"file-1"}', 200);
      }
      fail('طلب غير متوقع: ${request.method} ${request.url}');
    });
    final store = GoogleDriveFileStore(
      accessToken: () async => 'access-token',
      client: client,
    );
    addTearDown(store.dispose);

    final id = await store.upload(
      bucket: 'drive',
      remotePath: 'Excel/الحضور/2026/11/attendance.xlsx',
      localPath: localFile.path,
    );

    expect(id, 'file-1');
    expect(createdFolders, 5, reason: 'جذر المدرسة + 4 مستويات');
    expect(uploadMetadata!['name'], 'attendance.xlsx');
    expect(uploadMetadata!['mimeType'], contains('spreadsheetml'));
    expect(uploadMetadata!['parents'], ['folder-5']);
    expect(
      (uploadMetadata!['appProperties'] as Map).keys,
      contains('schoolPath'),
    );
  });

  test('المسار المنطقي نفسه يحدّث الملف الموجود دون إنشاء نسخة', () async {
    var createFileCalls = 0;
    var replaceCalls = 0;
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/drive/v3/files') {
        final query = request.url.queryParameters['q']!;
        if (query.contains("key='schoolPath'")) {
          return http.Response(
            '{"files":[{"id":"file-old","parents":["old-parent"]}]}',
            200,
          );
        }
        return http.Response('{"files":[]}', 200);
      }
      if (request.method == 'POST' && request.url.path == '/drive/v3/files') {
        return http.Response('{"id":"folder"}', 200);
      }
      if (request.method == 'POST' &&
          request.url.path == '/upload/drive/v3/files') {
        createFileCalls++;
        return http.Response(
          '',
          200,
          headers: {
            'location': 'https://www.googleapis.com/upload/session/duplicate',
          },
        );
      }
      if (request.method == 'PATCH' &&
          request.url.path == '/drive/v3/files/file-old') {
        replaceCalls++;
        expect(request.url.queryParameters['removeParents'], 'old-parent');
        expect(request.url.queryParameters['addParents'], 'folder');
        expect(
          (jsonDecode(request.body) as Map<String, dynamic>)['name'],
          'attendance.xlsx',
        );
        return http.Response('{"id":"file-old"}', 200);
      }
      if (request.method == 'PUT' &&
          request.url.path == '/upload/drive/v3/files/file-old') {
        expect(request.bodyBytes, [1, 2, 3, 4]);
        return http.Response('{}', 200);
      }
      fail('طلب غير متوقع: ${request.method} ${request.url}');
    });
    final store = GoogleDriveFileStore(
      accessToken: () async => 'access-token',
      client: client,
    );
    addTearDown(store.dispose);

    final id = await store.upload(
      bucket: 'drive',
      remotePath: 'Excel/الحضور/2026/11/attendance.xlsx',
      localPath: localFile.path,
    );

    expect(id, 'file-old');
    expect(replaceCalls, 1);
    expect(createFileCalls, 0);
  });

  test('لا يطلب نقل الملف عندما يكون في المجلد المقصود بالفعل', () async {
    var metadataQuery = <String, String>{};
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/drive/v3/files') {
        final query = request.url.queryParameters['q']!;
        if (query.contains("key='schoolPath'")) {
          return http.Response(
            '{"files":[{"id":"file-1","parents":["folder"]}]}',
            200,
          );
        }
        return http.Response('{"files":[]}', 200);
      }
      if (request.method == 'POST' && request.url.path == '/drive/v3/files') {
        return http.Response('{"id":"folder"}', 200);
      }
      if (request.method == 'PATCH' &&
          request.url.path == '/drive/v3/files/file-1') {
        metadataQuery = request.url.queryParameters;
        return http.Response('{"id":"file-1"}', 200);
      }
      if (request.method == 'PUT' &&
          request.url.path == '/upload/drive/v3/files/file-1') {
        return http.Response('{}', 200);
      }
      fail('طلب غير متوقع: ${request.method} ${request.url}');
    });
    final store = GoogleDriveFileStore(
      accessToken: () async => 'access-token',
      client: client,
    );
    addTearDown(store.dispose);

    await store.upload(
      bucket: 'drive',
      remotePath: 'ملفات/a.xlsx',
      localPath: localFile.path,
    );

    expect(metadataQuery.containsKey('addParents'), isFalse);
    expect(metadataQuery.containsKey('removeParents'), isFalse);
  });

  test('يرفض أقسام الملفات غير التابعة لـ Drive قبل الاتصال', () async {
    var calls = 0;
    final store = GoogleDriveFileStore(
      accessToken: () async => 'access-token',
      client: MockClient((_) async {
        calls++;
        return http.Response('', 200);
      }),
    );
    addTearDown(store.dispose);

    await expectLater(
      store.upload(
        bucket: 'files',
        remotePath: 'a.pdf',
        localPath: localFile.path,
      ),
      throwsA(
        isA<RemoteException>().having((e) => e.permanent, 'permanent', true),
      ),
    );
    expect(calls, 0);
  });

  test('الاستجابة المؤقتة تُعاد ولا تُحوّل إلى رفض دائم', () async {
    final store = GoogleDriveFileStore(
      accessToken: () async => 'access-token',
      client: MockClient((_) async => http.Response('busy', 503)),
    );
    addTearDown(store.dispose);

    await expectLater(
      store.upload(
        bucket: 'drive',
        remotePath: 'ملفات/a.bin',
        localPath: localFile.path,
      ),
      throwsA(
        isA<RemoteException>().having((e) => e.permanent, 'permanent', false),
      ),
    );
  });
}
