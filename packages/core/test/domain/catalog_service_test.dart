import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

import '../support/fixtures.dart';

void main() {
  late TestEnv env;
  setUp(() => env = TestEnv());
  tearDown(() => env.close());

  group('SubjectService', () {
    late SubjectService service;
    late LevelRow level;

    setUp(() async {
      service = SubjectService(env.db, env.writer);
      level = await LevelService(
        env.db,
        env.writer,
      ).add(name: '3 متوسط', stage: EducationStage.middle);
    });

    Future<List<SubjectItem>> all() => service.watchAll().first;

    test('الإضافة والقراءة مع اسم المستوى', () async {
      final general = await service.add(name: 'رياضيات', monthlyPrice: 2000);
      await service.add(name: 'فيزياء', levelId: level.id, monthlyPrice: 2500);
      final items = await all();
      expect(items.map((i) => i.name), ['رياضيات', 'فيزياء']);
      expect(items.first.levelName, isNull);
      expect(items.last.levelName, '3 متوسط');
      expect(items.last.monthlyPrice, 2500);
      expect(items.first.id, general.id);
    });

    test('الكتابة عبر SyncWriter', () async {
      await service.add(name: 'رياضيات', monthlyPrice: 2000);
      final outbox = await env.db.select(env.db.outbox).get();
      expect(outbox.where((o) => o.targetTable == 'subjects'), hasLength(1));
      final audit = await env.db.select(env.db.auditLog).get();
      expect(audit.where((a) => a.entity == 'subjects'), hasLength(1));
    });

    test('بيانات غير صالحة: أخطاء حسب الحقل', () async {
      await expectLater(
        service.add(name: '  ', monthlyPrice: -10),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.errors.keys,
            'keys',
            containsAll([SubjectService.fieldName, SubjectService.fieldPrice]),
          ),
        ),
      );
      await expectLater(
        service.add(name: 'رياضيات', monthlyPrice: 2005),
        throwsA(isA<ValidationException>()),
      );
      expect(await all(), isEmpty);
    });

    test('نفس الاسم: مرفوض في نفس المستوى، ومسموح في مستوى آخر', () async {
      await service.add(name: 'رياضيات', levelId: level.id, monthlyPrice: 2000);
      await expectLater(
        service.add(name: ' رياضيات ', levelId: level.id, monthlyPrice: 3000),
        throwsA(isA<ValidationException>()),
      );
      await service.add(name: 'رياضيات', monthlyPrice: 3000);
      expect(await all(), hasLength(2));
    });

    test('التعديل يغيّر الحقول ويقبل اسمه الحالي', () async {
      final row = await service.add(name: 'رياضيات', monthlyPrice: 2000);
      expect(
        await service.update(
          row.id,
          name: 'رياضيات',
          levelId: level.id,
          monthlyPrice: 2200,
        ),
        isTrue,
      );
      final item = (await all()).single;
      expect(item.monthlyPrice, 2200);
      expect(item.levelName, '3 متوسط');
      expect(
        await service.update('missing', name: 'س', monthlyPrice: 0),
        isFalse,
      );
    });

    test('التعديل إلى اسم مادة أخرى مرفوض', () async {
      await service.add(name: 'رياضيات', monthlyPrice: 2000);
      final other = await service.add(name: 'فيزياء', monthlyPrice: 2000);
      await expectLater(
        service.update(other.id, name: 'رياضيات', monthlyPrice: 2000),
        throwsA(isA<ValidationException>()),
      );
    });

    test('الحذف ناعم: يختفي من القائمة ويبقى في الجدول', () async {
      final row = await service.add(name: 'رياضيات', monthlyPrice: 2000);
      expect(await service.remove(row.id), isTrue);
      expect(await service.remove(row.id), isFalse);
      expect(await all(), isEmpty);
      final stored = await env.db.select(env.db.subjects).getSingle();
      expect(stored.deletedAt, isNotNull);
      // ويمكن إعادة استعمال اسمها.
      await service.add(name: 'رياضيات', monthlyPrice: 2000);
      expect(await all(), hasLength(1));
    });

    test('مادة مستواها محذوف تظهر باسم المستوى الباقي في الجدول', () async {
      await service.add(name: 'فيزياء', levelId: level.id, monthlyPrice: 2000);
      await LevelService(env.db, env.writer).remove(level.id);
      final item = (await all()).single;
      expect(item.levelName, '3 متوسط');
    });
  });

  group('RoomService', () {
    late RoomService service;
    setUp(() => service = RoomService(env.db, env.writer));

    Future<List<RoomRow>> all() => service.watchAll().first;

    test('الإضافة والترتيب بالاسم', () async {
      await service.add(name: 'ب', capacity: 20);
      await service.add(name: 'أ', capacity: 12);
      final rooms = await all();
      expect(rooms.map((r) => r.name), ['أ', 'ب']);
      expect(rooms.first.capacity, 12);
    });

    test('الاسم والسعة مطلوبان وضمن الحدود', () async {
      await expectLater(
        service.add(name: ' ', capacity: 0),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.errors.keys,
            'keys',
            containsAll([RoomService.fieldName, RoomService.fieldCapacity]),
          ),
        ),
      );
      await expectLater(
        service.add(name: 'قاعة', capacity: 501),
        throwsA(isA<ValidationException>()),
      );
      expect(await all(), isEmpty);
    });

    test('اسم مكرر مرفوض ويُقبل بعد حذف صاحبه', () async {
      final room = await service.add(name: 'القاعة 1', capacity: 20);
      await expectLater(
        service.add(name: 'القاعة 1', capacity: 10),
        throwsA(isA<ValidationException>()),
      );
      await service.remove(room.id);
      await service.add(name: 'القاعة 1', capacity: 10);
      expect(await all(), hasLength(1));
    });

    test('التعديل والحذف', () async {
      final room = await service.add(name: 'القاعة 1', capacity: 20);
      expect(
        await service.update(room.id, name: 'القاعة الكبرى', capacity: 30),
        isTrue,
      );
      expect((await all()).single.name, 'القاعة الكبرى');
      expect((await all()).single.capacity, 30);
      expect(await service.update('missing', name: 'س', capacity: 5), isFalse);
      await expectLater(
        service.update(room.id, name: '', capacity: 5),
        throwsA(isA<ValidationException>()),
      );
      expect(await service.remove(room.id), isTrue);
      expect(await all(), isEmpty);
    });

    test('الكتابة عبر SyncWriter', () async {
      await service.add(name: 'القاعة 1', capacity: 20);
      final outbox = await env.db.select(env.db.outbox).get();
      expect(outbox.where((o) => o.targetTable == 'rooms'), hasLength(1));
    });
  });
}
