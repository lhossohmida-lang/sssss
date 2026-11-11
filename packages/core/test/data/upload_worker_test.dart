import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

import '../support/fixtures.dart';

class FakeFileStore implements FileStore {
  final Map<String, Uint8List> stored = {};
  RemoteException? failure;
  int calls = 0;

  @override
  Future<String> upload({
    required String bucket,
    required String remotePath,
    required String localPath,
  }) async {
    calls++;
    final error = failure;
    if (error != null) throw error;
    stored['$bucket/$remotePath'] = File(localPath).readAsBytesSync();
    return '$bucket/$remotePath';
  }

  @override
  Future<Uint8List> download({
    required String bucket,
    required String remotePath,
  }) async => stored['$bucket/$remotePath']!;
}

void main() {
  late TestEnv env;
  late FakeFileStore files;
  late UploadWorker worker;
  late Directory dir;

  setUp(() async {
    env = TestEnv();
    files = FakeFileStore();
    worker = UploadWorker(
      env.db,
      env.writer,
      files,
      clock: () => env.time,
      maxAttempts: 3,
    );
    dir = Directory.systemTemp.createTempSync('upload_test');
    await env.student();
  });

  tearDown(() async {
    await env.close();
    dir.deleteSync(recursive: true);
  });

  String localFile(String name, {String content = 'صورة'}) {
    final file = File('${dir.path}/$name')..writeAsStringSync(content);
    return file.path;
  }

  Future<bool> enqueuePhoto({String key = 'student-photo:s1'}) =>
      worker.enqueue(
        kind: 'photo',
        bucket: 'photos',
        localPath: localFile('s1.jpg'),
        remotePath: 'students/s1.jpg',
        dedupeKey: key,
        targetTable: 'students',
        targetRowId: 's1',
        targetColumn: 'photo_url',
      );

  test('الرفع يكتب مسار الملف في السجل ويدخله طابور المزامنة', () async {
    expect(await enqueuePhoto(), isTrue);
    expect(await worker.processPending(), 1);

    expect(files.stored.keys, ['photos/students/s1.jpg']);
    final student = await env.db.select(env.db.students).getSingle();
    expect(student.photoUrl, 'photos/students/s1.jpg');
    expect(student.updatedAt, env.time);

    final item = await env.db.select(env.db.uploadQueue).getSingle();
    expect(item.status, 'done');
    expect(item.doneAt, isNotNull);

    final pending = await (env.db.select(
      env.db.outbox,
    )..where((o) => o.targetTable.equals('students'))).getSingle();
    expect(pending.payload, contains('photos/students/s1.jpg'));

    expect(await worker.processPending(), 0, reason: 'لا يُرفع مرتين');
    expect(files.calls, 1);
  });

  test('نفس الملف لا يدخل الطابور مرتين', () async {
    expect(await enqueuePhoto(), isTrue);
    expect(await enqueuePhoto(), isFalse);
    expect(await env.db.select(env.db.uploadQueue).get(), hasLength(1));
  });

  test('انقطاع الإنترنت: يؤجَّل بتأخير متزايد ثم ينجح', () async {
    await enqueuePhoto();
    files.failure = const RemoteException('لا اتصال', permanent: false);

    expect(await worker.processPending(), 0);
    var item = await env.db.select(env.db.uploadQueue).getSingle();
    expect(item.status, 'pending');
    expect(item.attempts, 1);
    expect(item.nextAttemptAt, env.time + 5000);
    expect(item.lastError, 'لا اتصال');

    files.failure = null;
    expect(await worker.processPending(), 0, reason: 'لم يحن وقته بعد');
    env.time += 5000;
    expect(await worker.processPending(), 1);
    item = await env.db.select(env.db.uploadQueue).getSingle();
    expect(item.status, 'done');
    expect(item.lastError, isNull);
  });

  test('بعد استنفاد المحاولات يُعلَّم فاشلاً، وتُعاد محاولته يدوياً', () async {
    await enqueuePhoto();
    files.failure = const RemoteException('لا اتصال', permanent: false);
    for (var i = 0; i < 3; i++) {
      await worker.processPending();
      env.time += 60000;
    }
    var item = await env.db.select(env.db.uploadQueue).getSingle();
    expect(item.status, 'failed');
    expect(item.attempts, 3);

    files.failure = null;
    expect(await worker.processPending(), 0);
    await worker.retryFailed();
    expect(await worker.processPending(), 1);
    item = await env.db.select(env.db.uploadQueue).getSingle();
    expect(item.status, 'done');
  });

  test('الرفض النهائي يفشل الملف وحده ويكمل الباقي', () async {
    await enqueuePhoto();
    await worker.enqueue(
      kind: 'group_file',
      bucket: 'files',
      localPath: localFile('a.pdf'),
      remotePath: 'groups/g1/a.pdf',
      dedupeKey: 'file:a',
    );
    var first = true;
    final picky = _PickyStore(() {
      if (first) {
        first = false;
        return const RemoteException('ممنوع', permanent: true);
      }
      return null;
    });
    final other = UploadWorker(
      env.db,
      env.writer,
      picky,
      clock: () => env.time,
    );
    expect(await other.processPending(), 1);
    final items = await env.db.select(env.db.uploadQueue).get();
    expect(items.map((i) => i.status).toSet(), {'failed', 'done'});
  });

  test('ملف محلي مفقود يُعلَّم فاشلاً دون محاولة رفع', () async {
    await worker.enqueue(
      kind: 'photo',
      bucket: 'photos',
      localPath: '${dir.path}/missing.jpg',
      remotePath: 'students/x.jpg',
      dedupeKey: 'missing',
    );
    expect(await worker.processPending(), 0);
    final item = await env.db.select(env.db.uploadQueue).getSingle();
    expect(item.status, 'failed');
    expect(item.lastError, 'الملف المحلي غير موجود');
    expect(files.calls, 0);
  });

  test('ملف دون سجل مرتبط يُرفع فقط', () async {
    await worker.enqueue(
      kind: 'attachment',
      bucket: 'files',
      localPath: localFile('b.pdf'),
      remotePath: 'chat/b.pdf',
      dedupeKey: 'chat:b',
    );
    expect(await worker.processPending(), 1);
    expect(files.stored.containsKey('files/chat/b.pdf'), isTrue);
  });

  test('الحصر بمخزن معيّن', () async {
    await enqueuePhoto();
    expect(await worker.processPending(buckets: {'drive'}), 0);
    expect(await worker.processPending(buckets: {'photos'}), 1);
  });

  group('SyncWriter.patch', () {
    test('يغيّر الأعمدة المطلوبة فقط ويسجّل العملية', () async {
      expect(
        await env.writer.patch(
          env.db.students,
          key: const {'id': 's1'},
          values: const {'photo_url': 'photos/x.jpg'},
        ),
        isTrue,
      );
      final student = await env.db.select(env.db.students).getSingle();
      expect(student.photoUrl, 'photos/x.jpg');
      expect(student.firstName, 'تلميذ');
      expect(student.createdAt, 1, reason: 'وقت الإنشاء لا يتغير');
      final audit = await env.db.select(env.db.auditLog).getSingle();
      expect(audit.action, 'update');
    });

    test('يمسح عموداً بقيمة فارغة', () async {
      await env.writer.patch(
        env.db.students,
        key: const {'id': 's1'},
        values: const {'photo_url': 'x'},
      );
      await env.writer.patch(
        env.db.students,
        key: const {'id': 's1'},
        values: const {'photo_url': null},
      );
      expect(
        (await env.db.select(env.db.students).getSingle()).photoUrl,
        isNull,
      );
    });

    test('سجل غير موجود أو عمود مجهول أو قائمة فارغة', () async {
      expect(
        await env.writer.patch(
          env.db.students,
          key: const {'id': 'missing'},
          values: const {'photo_url': 'x'},
        ),
        isFalse,
      );
      expect(
        () => env.writer.patch(
          env.db.students,
          key: const {'id': 's1'},
          values: const {'nope': 1},
        ),
        throwsArgumentError,
      );
      expect(
        () => env.writer.patch(
          env.db.students,
          key: const {'id': 's1'},
          values: const {},
        ),
        throwsArgumentError,
      );
    });
  });
}

class _PickyStore implements FileStore {
  _PickyStore(this.next);

  final RemoteException? Function() next;

  @override
  Future<String> upload({
    required String bucket,
    required String remotePath,
    required String localPath,
  }) async {
    final error = next();
    if (error != null) throw error;
    return '$bucket/$remotePath';
  }

  @override
  Future<Uint8List> download({
    required String bucket,
    required String remotePath,
  }) async => Uint8List(0);
}
