import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

import '../support/fixtures.dart';

void main() {
  late TestEnv env;
  late Directory directory;
  late DriveQueueService queue;

  setUp(() async {
    env = TestEnv();
    directory = await Directory.systemTemp.createTemp('drive_queue_test');
    queue = DriveQueueService(
      env.db,
      env.writer,
      stagingDirectory: Directory('${directory.path}/staged'),
      clock: () => DateTime(2026, 11, 14, 9).millisecondsSinceEpoch,
    );
  });

  tearDown(() async {
    await env.close();
    await directory.delete(recursive: true);
  });

  test('ينسخ الملف إلى تخزين دائم ويمنع تكراره محلياً', () async {
    final source = File('${directory.path}/attendance.xlsx')
      ..writeAsBytesSync([8, 9, 10]);

    expect(
      await queue.enqueueFile(
        sourcePath: source.path,
        fileName: 'كشف الحضور.xlsx',
        kind: DriveUploadKind.attendanceExcel,
      ),
      isTrue,
    );
    expect(
      await queue.enqueueFile(
        sourcePath: source.path,
        fileName: 'كشف الحضور.xlsx',
        kind: DriveUploadKind.attendanceExcel,
      ),
      isFalse,
    );
    final secondMonth = DriveQueueService(
      env.db,
      env.writer,
      stagingDirectory: Directory('${directory.path}/staged'),
      clock: () => DateTime(2027, 3, 1).millisecondsSinceEpoch,
    );
    expect(
      await secondMonth.enqueueFile(
        sourcePath: source.path,
        fileName: 'كشف الحضور.xlsx',
        kind: DriveUploadKind.attendanceExcel,
      ),
      isFalse,
      reason: 'نفس الملف لا يأخذ مساراً جديداً عند رفعه في شهر آخر',
    );

    final rows = await env.db.select(env.db.uploadQueue).get();
    expect(rows, hasLength(1));
    expect(rows.single.bucket, 'drive');
    expect(rows.single.kind, 'attendance_excel');
    expect(rows.single.remotePath, 'Excel/الحضور/كشف الحضور.xlsx');
    expect(rows.single.localPath, isNot(source.path));
    expect(File(rows.single.localPath).readAsBytesSync(), [8, 9, 10]);
    expect(source.existsSync(), isTrue);
  });

  test('اسم الملف لا يستطيع الخروج من مجلد Drive المحدد', () async {
    final source = File('${directory.path}/source.bin')..writeAsStringSync('x');

    await queue.enqueueFile(
      sourcePath: source.path,
      fileName: '../bad?.xlsx',
      kind: DriveUploadKind.file,
    );

    final row = await env.db.select(env.db.uploadQueue).getSingle();
    expect(row.remotePath, 'ملفات/bad_.xlsx');
    expect(row.remotePath, isNot(contains('..')));
  });

  test('إعادة المحاولة محصورة بعناصر Drive', () async {
    final drive = File('${directory.path}/drive.bin')..writeAsStringSync('d');
    final photo = File('${directory.path}/photo.bin')..writeAsStringSync('p');
    for (final item in [
      (bucket: 'drive', path: drive.path, key: 'drive'),
      (bucket: 'photos', path: photo.path, key: 'photo'),
    ]) {
      await env.db
          .into(env.db.uploadQueue)
          .insert(
            UploadQueueCompanion.insert(
              id: item.key,
              kind: 'test',
              bucket: Value(item.bucket),
              localPath: item.path,
              remotePath: '${item.key}.bin',
              dedupeKey: item.key,
              status: const Value(UploadWorker.statusFailed),
              attempts: const Value(3),
              lastError: const Value('تعذّر الرفع'),
              nextAttemptAt: const Value(100),
              createdAt: 1,
            ),
          );
    }

    expect(await queue.retryFailed(), 1);
    final rows = await env.db.select(env.db.uploadQueue).get();
    final driveRow = rows.singleWhere((row) => row.bucket == 'drive');
    final photoRow = rows.singleWhere((row) => row.bucket == 'photos');
    expect(driveRow.status, UploadWorker.statusPending);
    expect(driveRow.attempts, 0);
    expect(photoRow.status, UploadWorker.statusFailed);
    expect(photoRow.attempts, 3);
  });
}
