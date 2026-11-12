import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

import '../support/fixtures.dart';

void main() {
  late TestEnv env;
  late Directory dir;
  late GroupFileService service;
  final pdf = Uint8List.fromList(List<int>.filled(2048, 7));

  setUp(() async {
    env = TestEnv();
    dir = Directory.systemTemp.createTempSync('group_files_test');
    service = GroupFileService(env.db, env.writer, directory: dir);
    await env.subject();
    await env.teacher();
    await env.teacher(id: 't2');
    await env.group();
  });

  tearDown(() async {
    await env.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<GroupFileRow> add({
    String title = 'تمارين الفصل الأول',
    String fileName = 'tamarin.pdf',
    Uint8List? bytes,
    String teacher = 't1',
  }) => service.add(
    groupId: 'g1',
    teacherId: teacher,
    title: title,
    fileName: fileName,
    bytes: bytes ?? pdf,
  );

  test('إضافة ملف: نسخة محلية وصف مزامَن وعنصر في طابور الرفع', () async {
    final row = await add();
    expect(row.title, 'تمارين الفصل الأول');
    expect(row.fileName, 'tamarin.pdf');
    expect(row.sizeBytes, 2048);
    expect(row.uploadedBy, 't1');
    expect(File(row.localPath!).existsSync(), isTrue);
    expect(File(row.localPath!).lengthSync(), 2048);

    final queue = await env.db.select(env.db.uploadQueue).get();
    expect(queue, hasLength(1));
    expect(queue.single.bucket, 'files');
    expect(queue.single.targetTable, 'group_files');
    expect(queue.single.targetRowId, row.id);
    expect(queue.single.targetColumn, 'file_url');
    expect(queue.single.remotePath, 'groups/g1/${row.id}.pdf');

    final outbox = await env.db.select(env.db.outbox).get();
    expect(outbox.where((o) => o.targetTable == 'group_files'), hasLength(1));
    expect(await env.db.select(env.db.auditLog).get(), isNotEmpty);
  });

  test('القراءة: الأحدث أولاً وحالة الرفع من وجود الرابط', () async {
    await add(title: 'الأول');
    env.time += 10;
    final second = await add(title: 'الثاني', fileName: 'Cours.PNG');
    final list = await service.files('g1');
    expect(list.map((f) => f.title), ['الثاني', 'الأول']);
    expect(list.first.isImage, isTrue);
    expect(list.first.extension, 'png');
    expect(list.last.isPdf, isTrue);
    expect(list.any((f) => f.uploaded), isFalse);

    await env.writer.patch(
      env.db.groupFiles,
      key: {'id': second.id},
      values: {'file_url': 'files/groups/g1/${second.id}.png'},
    );
    final after = await service.files('g1');
    expect(after.first.uploaded, isTrue);
    expect(await service.files('other'), isEmpty);
  });

  group('التحقق', () {
    test('عنوان فارغ ونوع غير مقبول', () async {
      await expectLater(
        add(title: '  ', fileName: 'virus.exe'),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.errors.keys.toSet(),
            'حقول',
            {GroupFileService.fieldTitle, GroupFileService.fieldFile},
          ),
        ),
      );
      expect(await env.db.select(env.db.groupFiles).get(), isEmpty);
      expect(dir.listSync(), isEmpty);
    });

    test('مستند Office غير مقبول (لا يُعرض داخل التطبيق)', () async {
      await expectLater(
        add(fileName: 'cours.docx'),
        throwsA(isA<ValidationException>()),
      );
    });

    test('ملف فارغ أو أكبر من الحد', () async {
      await expectLater(
        add(bytes: Uint8List(0)),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.errors[GroupFileService.fieldFile],
            'file',
            contains('فارغ'),
          ),
        ),
      );
      await expectLater(
        add(bytes: Uint8List(GroupFileService.maxBytes + 1)),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.errors[GroupFileService.fieldFile],
            'file',
            contains('10'),
          ),
        ),
      );
      // الحد نفسه مقبول.
      await add(bytes: Uint8List(GroupFileService.maxBytes));
    });

    test('مجموعة أستاذ آخر أو مجهولة: مرفوضة', () async {
      await expectLater(
        add(teacher: 't2'),
        throwsA(isA<ValidationException>()),
      );
      await expectLater(
        service.add(
          groupId: 'nope',
          teacherId: 't1',
          title: 'ت',
          fileName: 'a.pdf',
          bytes: pdf,
        ),
        throwsA(isA<ValidationException>()),
      );
      expect(await env.db.select(env.db.groupFiles).get(), isEmpty);
    });
  });

  test('إعادة التسمية لأستاذ المجموعة فقط وبعنوان غير فارغ', () async {
    final row = await add();
    await service.rename(row.id, title: ' عنوان جديد ', teacherId: 't1');
    expect((await service.files('g1')).single.title, 'عنوان جديد');
    await expectLater(
      service.rename(row.id, title: 'x', teacherId: 't2'),
      throwsA(isA<ValidationException>()),
    );
    await expectLater(
      service.rename(row.id, title: ' ', teacherId: 't1'),
      throwsA(isA<ValidationException>()),
    );
    await expectLater(
      service.rename('nope', title: 'x', teacherId: 't1'),
      throwsA(isA<ValidationException>()),
    );
  });

  test('الحذف ناعم: يختفي من القائمة وتُزال النسخة ويُلغى الرفع', () async {
    final row = await add();
    await expectLater(
      service.remove(row.id, teacherId: 't2'),
      throwsA(isA<ValidationException>()),
    );
    await service.remove(row.id, teacherId: 't1');
    expect(await service.files('g1'), isEmpty);
    expect(File(row.localPath!).existsSync(), isFalse);
    expect(await env.db.select(env.db.groupFiles).get(), hasLength(1));
    final queue = await env.db.select(env.db.uploadQueue).get();
    expect(queue.single.status, 'failed');
  });

  test('قراءة النسخة المحلية: بياناتها أو null إن غابت', () async {
    final row = await add();
    expect(await service.readLocal(row), pdf);
    File(row.localPath!).deleteSync();
    expect(await service.readLocal(row), isNull);
  });

  test('الرفع إلى الخادم يكتب الرابط في الصف', () async {
    final row = await add();
    final store = _RecordingStore();
    final worker = UploadWorker(env.db, env.writer, store);
    expect(await worker.processPending(), 1);
    expect(store.uploads.single, 'files/groups/g1/${row.id}.pdf');
    final saved = (await service.files('g1')).single;
    expect(saved.uploaded, isTrue);
    expect(saved.file.fileUrl, 'files/groups/g1/${row.id}.pdf');
  });

  test('watchFiles يتحدث بعد الإضافة', () async {
    final seen = <int>[];
    final sub = service.watchFiles('g1').listen((l) => seen.add(l.length));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await add();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await sub.cancel();
    expect(seen.first, 0);
    expect(seen.last, 1);
  });

  test('امتداد الملف', () {
    expect(GroupFileService.extensionOf('A.B.PDF'), 'pdf');
    expect(GroupFileService.extensionOf('noext'), '');
  });
}

class _RecordingStore implements FileStore {
  final List<String> uploads = [];

  @override
  Future<String> upload({
    required String bucket,
    required String remotePath,
    required String localPath,
  }) async {
    uploads.add('$bucket/$remotePath');
    return '$bucket/$remotePath';
  }

  @override
  Future<Uint8List> download({
    required String bucket,
    required String remotePath,
  }) async => Uint8List(0);
}
