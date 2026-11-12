import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:school_core/school_core.dart';
import 'package:school_core/testing.dart';

import '../support/fixtures.dart';
import '../support/remote_files.dart';

/// بيانات خط Cairo من حزمة الواجهة (المسار نسبي لمجلد حزمة core).
Uint8List cairo() => File('../ui/assets/fonts/Cairo.ttf').readAsBytesSync();

void main() {
  group('StudentCard', () {
    StudentCardData data({
      Uint8List? photo,
      Uint8List? logo,
      String name = 'أحمد بن علي',
      String? level = '3 متوسط',
      String school = 'مدرسة النجاح',
    }) => StudentCardData(
      schoolName: school,
      studentName: name,
      qrCode: 'S-ABCDEFGHJK',
      levelName: level,
      parentPhone: '0550123456',
      photo: photo,
      logo: logo,
    );

    test('ملف PDF صالح من صفحة واحدة بحجم 85.6×54 مم', () async {
      final bytes = await StudentCard.build(data(), fontData: cairo());
      final text = latin1.decode(bytes, allowInvalid: true);
      expect(text.startsWith('%PDF-'), isTrue);
      expect(text.trimRight().endsWith('%%EOF'), isTrue);
      expect(RegExp(r'/Type\s*/Page\b').allMatches(text), hasLength(1));
      // حجم الصفحة بالنقاط (1 مم = 72/25.4).
      final box = RegExp(r'/MediaBox\s*\[\s*0\s+0\s+([\d.]+)\s+([\d.]+)\s*\]')
          .firstMatch(text)!;
      expect(double.parse(box.group(1)!), closeTo(85.6 * 72 / 25.4, 0.1));
      expect(double.parse(box.group(2)!), closeTo(54 * 72 / 25.4, 0.1));
    });

    test('بالصورة والشعار، وبلا مستوى ولا هاتف', () async {
      final photo = samplePngBytes(width: 220, height: 280);
      final logo = samplePngBytes(width: 90, height: 90);
      final withImages = await StudentCard.build(
        data(photo: photo, logo: logo),
        fontData: cairo(),
      );
      final plain = await StudentCard.build(
        const StudentCardData(
          schoolName: 'م',
          studentName: 'س',
          qrCode: 'S-ABCDEFGHJK',
        ),
        fontData: cairo(),
      );
      expect(withImages.length, greaterThan(plain.length));
      expect(
        latin1.decode(plain, allowInvalid: true).startsWith('%PDF-'),
        isTrue,
      );
    });

    test('الاسم الطويل جداً لا يرمي', () async {
      final bytes = await StudentCard.build(
        data(name: 'محمد عبد الرحمن بن أحمد بن علي بن إبراهيم الحسني السوفي'),
        fontData: cairo(),
      );
      expect(bytes, isNotEmpty);
    });

    test('الخط يُضمَّن في الملف', () async {
      final bytes = await StudentCard.build(data(), fontData: cairo());
      expect(latin1.decode(bytes, allowInvalid: true), contains('/FontFile2'));
    });
  });

  group('LogoService', () {
    late TestEnv env;
    late Directory dir;
    late RecordingFileStore files;
    late LogoService service;

    setUp(() async {
      env = TestEnv();
      dir = await Directory.systemTemp.createTemp('school_logo_');
      files = RecordingFileStore();
      service = LogoService(env.db, env.writer, directory: dir, files: files);
    });

    tearDown(() async {
      await env.close();
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    Future<String?> setting(String key) async {
      final rows = await env.db.select(env.db.settings).get();
      for (final r in rows) {
        if (r.key == key) return r.value;
      }
      return null;
    }

    test('يضغط الشعار إلى 400 ويحفظه ويضع الرفع في الطابور', () async {
      final path = await service.set(samplePngBytes(width: 1000, height: 800));
      expect(path.startsWith(dir.path), isTrue);
      final image = img.decodeImage(File(path).readAsBytesSync())!;
      expect(image.width, 400);
      expect(image.height, 320);
      expect(await setting(SettingKeys.schoolLogoLocal), path);

      final queue = await env.db.select(env.db.uploadQueue).getSingle();
      expect(queue.bucket, 'photos');
      expect(queue.remotePath, startsWith('school/logo-'));
      expect(queue.targetTable, 'settings');
      expect(queue.targetRowId, SettingKeys.schoolLogo);
      expect(queue.targetColumn, 'value');
    });

    test('تغييره يحذف القديم', () async {
      final first = await service.set(samplePngBytes(width: 300, height: 300));
      env.time += 5;
      final second = await service.set(samplePngBytes(width: 300, height: 300));
      expect(second, isNot(first));
      expect(File(first).existsSync(), isFalse);
      expect(File(second).existsSync(), isTrue);
    });

    test('بعد اكتمال الرفع يُكتب رابط الشعار في الإعدادات', () async {
      await service.set(samplePngBytes(width: 300, height: 300));
      final worker = UploadWorker(env.db, env.writer, files);
      expect(await worker.processPending(), 1);
      expect(
        await setting(SettingKeys.schoolLogo),
        startsWith('photos/school/logo-'),
      );
    });

    test('resolve: المحلي أولاً، وبلا شعار null', () async {
      expect(await service.resolve(), isNull);
      final path = await service.set(samplePngBytes(width: 300, height: 300));
      expect((await service.resolve())?.path, path);
      expect(files.downloads, isEmpty);
    });

    test('resolve على جهاز آخر: يجلب من الخادم ويحفظ للمرات القادمة', () async {
      // جهاز آخر: الرابط البعيد موجود (وصل بالمزامنة) ولا ملف محلي.
      await env.writer.save(
        env.db.settings,
        SettingsCompanion.insert(
          key: SettingKeys.schoolLogo,
          value: 'photos/school/logo-7.jpg',
          updatedAt: 1,
        ),
        key: {'key': SettingKeys.schoolLogo},
      );
      files.stored['photos/school/logo-7.jpg'] = Uint8List.fromList([1, 2, 3]);
      final file = await service.resolve();
      expect(file, isNotNull);
      expect(file!.readAsBytesSync(), [1, 2, 3]);
      expect(files.downloads, ['photos/school/logo-7.jpg']);
      // المرة الثانية من الملف المحلي دون جلب.
      await service.resolve();
      expect(files.downloads, hasLength(1));
    });

    test('تعذّر الجلب أو بلا مخزن: null', () async {
      await env.writer.save(
        env.db.settings,
        SettingsCompanion.insert(
          key: SettingKeys.schoolLogo,
          value: 'photos/school/missing.jpg',
          updatedAt: 1,
        ),
        key: {'key': SettingKeys.schoolLogo},
      );
      expect(await service.resolve(), isNull);
      final offline = LogoService(env.db, env.writer, directory: dir);
      expect(await offline.resolve(), isNull);
    });

    test('الإزالة تمسح الملف والإعدادين', () async {
      final path = await service.set(samplePngBytes(width: 300, height: 300));
      await service.clear();
      expect(File(path).existsSync(), isFalse);
      expect(await setting(SettingKeys.schoolLogoLocal), '');
      expect(await service.resolve(), isNull);
    });

    test('صورة تالفة: FormatException', () async {
      await expectLater(
        service.set(Uint8List.fromList([1, 2, 3])),
        throwsFormatException,
      );
      expect(dir.listSync(), isEmpty);
    });
  });
}
