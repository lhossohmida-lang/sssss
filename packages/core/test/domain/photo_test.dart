import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:school_core/school_core.dart';

import '../support/fixtures.dart';
import '../support/remote_files.dart';

/// صورة اختبار بحجم معيّن بألوان متدرجة (فلا تُضغط إلى لا شيء).
Uint8List testImage(int width, int height, {bool png = true}) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgb(x, y, x % 256, y % 256, (x + y) % 256);
    }
  }
  return Uint8List.fromList(png ? img.encodePng(image) : img.encodeJpg(image));
}

img.Image decode(Uint8List bytes) => img.decodeImage(bytes)!;

void main() {
  group('PhotoProcessor', () {
    test('الصورة الكبيرة تُصغَّر إلى 600 بكسل لأطول ضلع وتصير JPEG', () async {
      final out = await PhotoProcessor.compress(testImage(2400, 1800));
      // بداية ملف JPEG.
      expect(out.sublist(0, 2), [0xFF, 0xD8]);
      final image = decode(out);
      expect(image.width, 600);
      expect(image.height, 450);
    });

    test('صورة طولية: الارتفاع هو 600', () async {
      final image = decode(await PhotoProcessor.compress(testImage(900, 1800)));
      expect(image.height, 600);
      expect(image.width, 300);
    });

    test('الصورة الأصغر لا تُكبَّر', () async {
      final image = decode(await PhotoProcessor.compress(testImage(300, 200)));
      expect(image.width, 300);
      expect(image.height, 200);
    });

    test('الناتج بحجم صغير (أقل من 200KB لصورة 600×450)', () async {
      final out = await PhotoProcessor.compress(testImage(1200, 900));
      // أقل بكثير من حجم البكسلات الخام (600×450×3 = 810KB).
      expect(out.length, lessThan(200 * 1024));
    });

    test('جودة أعلى تعطي ملفاً أكبر', () async {
      final source = testImage(800, 600);
      final low = await PhotoProcessor.compress(source, quality: 30);
      final high = await PhotoProcessor.compress(source, quality: 95);
      expect(high.length, greaterThan(low.length));
    });

    test('يقبل JPEG مدخلاً أيضاً', () async {
      final out = await PhotoProcessor.compress(
        testImage(1000, 1000, png: false),
      );
      expect(decode(out).width, 600);
    });

    test('اتجاه EXIF يُصحَّح', () {
      final image = img.Image(width: 400, height: 200)
        ..exif.imageIfd.orientation = 6; // يدور 90°
      final source = Uint8List.fromList(img.encodeJpg(image));
      final out = decode(PhotoProcessor.compressSync(source, 600, 70));
      expect(out.width, 200);
      expect(out.height, 400);
    });

    test('بيانات غير صورة أو فارغة أو ضخمة: FormatException', () async {
      await expectLater(
        PhotoProcessor.compress(Uint8List.fromList([1, 2, 3, 4])),
        throwsFormatException,
      );
      await expectLater(
        PhotoProcessor.compress(Uint8List(0)),
        throwsFormatException,
      );
      await expectLater(
        PhotoProcessor.compress(Uint8List(PhotoProcessor.maxInputBytes + 1)),
        throwsFormatException,
      );
    });
  });

  group('PhotoService', () {
    late TestEnv env;
    late Directory dir;
    late PhotoService service;

    setUp(() async {
      env = TestEnv();
      dir = await Directory.systemTemp.createTemp('school_photos_');
      service = PhotoService(env.db, env.writer, directory: dir);
      await env.teacher(id: 't1');
      await env.student(id: 's1');
    });

    tearDown(() async {
      await env.close();
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    Future<String?> localPath(String table, String id) async {
      final row = await env.db
          .customSelect(
            'SELECT photo_local_path AS p FROM $table WHERE id = ?',
            variables: [Variable<String>(id)],
          )
          .getSingle();
      return row.read<String?>('p');
    }

    test('يضغط ويحفظ الملف ويسجّل المسار ويضع الرفع في الطابور', () async {
      final path = await service.attach(
        PhotoOwner.student,
        's1',
        testImage(2000, 1500),
      );
      expect(path.startsWith(dir.path), isTrue);
      expect(await File(path).exists(), isTrue);
      expect(decode(await File(path).readAsBytes()).width, 600);
      expect(await localPath('students', 's1'), path);

      final queue = await env.db.select(env.db.uploadQueue).getSingle();
      expect(queue.kind, 'photo');
      expect(queue.bucket, 'photos');
      expect(queue.localPath, path);
      expect(queue.remotePath, startsWith('students/s1-'));
      expect(queue.targetTable, 'students');
      expect(queue.targetRowId, 's1');
      expect(queue.targetColumn, 'photo_url');
      expect(queue.status, 'pending');
    });

    test('تغيير الصورة: مسار جديد، والقديمة تُحذف، ورفعان منفصلان', () async {
      final first = await service.attach(
        PhotoOwner.student,
        's1',
        testImage(800, 600),
      );
      env.time += 5;
      final second = await service.attach(
        PhotoOwner.student,
        's1',
        testImage(800, 600),
      );
      expect(second, isNot(first));
      expect(await File(first).exists(), isFalse);
      expect(await File(second).exists(), isTrue);
      expect(await localPath('students', 's1'), second);
      expect(await env.db.select(env.db.uploadQueue).get(), hasLength(2));
    });

    test('صورة الأستاذ في جدول الأساتذة', () async {
      final path = await service.attach(
        PhotoOwner.teacher,
        't1',
        testImage(700, 700),
      );
      expect(await localPath('teachers', 't1'), path);
      final queue = await env.db.select(env.db.uploadQueue).getSingle();
      expect(queue.targetTable, 'teachers');
      expect(queue.remotePath, startsWith('teachers/t1-'));
    });

    test('صورة الفاتورة تحفظ بدقة أعلى وترتبط بسجل المصروف', () async {
      final expenses = ExpenseService(env.db, env.writer);
      final category = await expenses.addCategory('صيانة');
      final expenseId = await expenses.addExpense(
        categoryId: category,
        amount: 1250,
        date: '2026-05-04',
      );
      final path = await service.attach(
        PhotoOwner.expenseInvoice,
        expenseId,
        testImage(2400, 1800),
      );
      final photo = decode(await File(path).readAsBytes());
      expect(photo.width, 1800);
      expect(photo.height, 1350);
      final row = await env.db
          .customSelect(
            'SELECT invoice_photo_local_path AS p FROM expenses WHERE id = ?',
            variables: [Variable<String>(expenseId)],
          )
          .getSingle();
      expect(row.read<String?>('p'), path);
      final queue = await env.db.select(env.db.uploadQueue).getSingle();
      expect(queue.bucket, 'photos');
      expect(queue.remotePath, startsWith('expenses/$expenseId-'));
      expect(queue.targetTable, 'expenses');
      expect(queue.targetRowId, expenseId);
      expect(queue.targetColumn, 'invoice_photo_url');
    });

    test(
      'صورة فاتورة رفعها جهاز آخر تُنزّل وتُخزّن محلياً مرة واحدة',
      () async {
        final expenses = ExpenseService(env.db, env.writer);
        final category = await expenses.addCategory('صيانة');
        final expenseId = await expenses.addExpense(
          categoryId: category,
          amount: 1250,
          date: '2026-05-04',
        );
        final remotePath = 'expenses/$expenseId-remote.jpg';
        final remote = RecordingFileStore()
          ..stored['photos/$remotePath'] = testImage(800, 600, png: false);
        await env.writer.patch(
          env.db.expenses,
          key: {'id': expenseId},
          values: {
            'invoice_photo_local_path': '${dir.path}/another-device.jpg',
            'invoice_photo_url': 'photos/$remotePath',
          },
        );
        final photos = PhotoService(
          env.db,
          env.writer,
          directory: dir,
          files: remote,
        );

        final resolved = await photos.resolve(
          PhotoOwner.expenseInvoice,
          expenseId,
        );
        expect(resolved, isNotNull);
        expect(decode(await resolved!.readAsBytes()).width, 800);
        expect(remote.downloads, ['photos/$remotePath']);

        final cached = await photos.resolve(
          PhotoOwner.expenseInvoice,
          expenseId,
        );
        expect(cached?.path, resolved.path);
        expect(remote.downloads, hasLength(1));
      },
    );

    test('الكتابة عبر SyncWriter (سجل عمليات وطابور مزامنة)', () async {
      await service.attach(PhotoOwner.student, 's1', testImage(300, 300));
      final outbox = await env.db.select(env.db.outbox).get();
      expect(outbox.any((o) => o.targetTable == 'students'), isTrue);
      final audit = await env.db.select(env.db.auditLog).get();
      expect(audit.any((a) => a.entity == 'students'), isTrue);
    });

    test('سجل غير موجود: StateError ولا يبقى ملف ولا طابور', () async {
      await expectLater(
        service.attach(PhotoOwner.student, 'missing', testImage(300, 300)),
        throwsStateError,
      );
      expect(dir.listSync(), isEmpty);
      expect(await env.db.select(env.db.uploadQueue).get(), isEmpty);
    });

    test('صورة تالفة: FormatException ولا تغيير', () async {
      await expectLater(
        service.attach(PhotoOwner.student, 's1', Uint8List.fromList([1, 2, 3])),
        throwsFormatException,
      );
      expect(await localPath('students', 's1'), isNull);
      expect(dir.listSync(), isEmpty);
    });

    test('الإزالة تمسح المسار والملف', () async {
      final path = await service.attach(
        PhotoOwner.student,
        's1',
        testImage(300, 300),
      );
      await service.remove(PhotoOwner.student, 's1');
      expect(await localPath('students', 's1'), isNull);
      expect(await File(path).exists(), isFalse);
    });

    test('UploadQueueWriter: نفس المفتاح لا يدخل مرتين', () async {
      final writer = UploadQueueWriter(env.db, env.writer);
      Future<bool> add() => writer.enqueue(
        kind: 'photo',
        bucket: 'photos',
        localPath: '/x.jpg',
        remotePath: 'a/x.jpg',
        dedupeKey: 'k',
      );
      expect(await add(), isTrue);
      expect(await add(), isFalse);
      expect(await env.db.select(env.db.uploadQueue).get(), hasLength(1));
    });
  });
}
