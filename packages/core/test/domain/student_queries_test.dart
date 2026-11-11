import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

import '../support/fixtures.dart';

void main() {
  late TestEnv env;
  late StudentQueries queries;

  setUp(() {
    env = TestEnv();
    queries = StudentQueries(env.db);
  });
  tearDown(() => env.close());

  Future<void> add(
    String id,
    String first,
    String last, {
    String phone = '0550000000',
    String? levelId,
    bool deleted = false,
  }) => env.db
      .into(env.db.students)
      .insert(
        StudentsCompanion.insert(
          id: id,
          createdAt: 1,
          updatedAt: 1,
          firstName: first,
          lastName: last,
          parentPhone: phone,
          qrCode: 'S-$id',
          levelId: Value(levelId),
          deletedAt: Value(deleted ? 5 : null),
        ),
      );

  Future<StudentPage> page({String query = '', int limit = 50}) =>
      queries.watchPage(query: query, limit: limit).first;

  Future<List<String>> names({String query = '', int limit = 50}) async =>
      (await page(
        query: query,
        limit: limit,
      )).items.map((i) => i.fullName).toList();

  group('القائمة', () {
    test('مرتبة باللقب ثم الاسم، دون المحذوفين', () async {
      await add('1', 'ياسين', 'بن علي');
      await add('2', 'أحمد', 'بن علي');
      await add('3', 'سارة', 'حداد');
      await add('4', 'محمد', 'أمين', deleted: true);
      expect(await names(), ['أحمد بن علي', 'ياسين بن علي', 'سارة حداد']);
      expect((await page()).total, 3);
    });

    test('اسم المستوى', () async {
      await env.db
          .into(env.db.levels)
          .insert(
            LevelsCompanion.insert(
              id: 'lv',
              createdAt: 1,
              updatedAt: 1,
              name: '3 متوسط',
              stage: 'middle',
              sortOrder: 203,
            ),
          );
      await add('1', 'أحمد', 'علي', levelId: 'lv');
      await add('2', 'سارة', 'حداد');
      final items = (await page()).items;
      expect(items.firstWhere((i) => i.id == '1').levelName, '3 متوسط');
      expect(items.firstWhere((i) => i.id == '2').levelName, isNull);
    });

    test('قاعدة فارغة', () async {
      final p = await page();
      expect(p.items, isEmpty);
      expect(p.total, 0);
      expect(p.hasMore, isFalse);
    });

    test('تحميل مقسّم: الصفحة بحد، والعدد الكلي كاملاً', () async {
      for (var i = 0; i < 120; i++) {
        await add('s$i', 'اسم$i', 'لقب${i.toString().padLeft(3, '0')}');
      }
      final first = await page(limit: 50);
      expect(first.items, hasLength(50));
      expect(first.total, 120);
      expect(first.hasMore, isTrue);
      final all = await page(limit: 500);
      expect(all.items, hasLength(120));
      expect(all.hasMore, isFalse);
      // الترتيب ثابت بين الصفحات.
      expect(first.items.map((i) => i.id), all.items.take(50).map((i) => i.id));
    });

    test('تتحدث القائمة مع كل إضافة', () async {
      final seen = <int>[];
      final sub = queries.watchPage().listen((p) => seen.add(p.total));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await add('1', 'أحمد', 'علي');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await sub.cancel();
      expect(seen.first, 0);
      expect(seen.last, 1);
    });
  });

  group('البحث', () {
    setUp(() async {
      await add('1', 'أحمد', 'بن علي', phone: '0550123456');
      await add('2', 'محمد أمين', 'حداد', phone: '0661234567');
      await add('3', 'سارة', 'بن عيسى', phone: '0550999888');
      await add('4', 'إيمان', 'علي', phone: '0770000001');
    });

    test('ببداية الاسم أو اللقب', () async {
      expect(await names(query: 'أحم'), ['أحمد بن علي']);
      expect(await names(query: 'بن'), ['أحمد بن علي', 'سارة بن عيسى']);
      expect(await names(query: 'حداد'), ['محمد أمين حداد']);
      expect(await names(query: 'علي'), ['إيمان علي']);
    });

    test('بكلمتين بأي ترتيب', () async {
      expect(await names(query: 'أحمد بن'), ['أحمد بن علي']);
      expect(await names(query: 'بن أحمد'), ['أحمد بن علي']);
      expect(await names(query: 'سارة بن ع'), ['سارة بن عيسى']);
      expect(await names(query: 'سارة حداد'), isEmpty);
    });

    test('صيغ الألف في أول الاسم: «احمد» تجد «أحمد»', () async {
      expect(await names(query: 'احمد'), ['أحمد بن علي']);
      expect(await names(query: 'ايمان'), ['إيمان علي']);
      expect(await names(query: 'أحمد'), ['أحمد بن علي']);
      expect(await names(query: 'إحمد'), ['أحمد بن علي']);
    });

    test('variants: الألف فقط في أول الكلمة', () {
      expect(StudentQueries.variants('احمد'), ['احمد', 'أحمد', 'إحمد', 'آحمد']);
      expect(StudentQueries.variants('محمد'), ['محمد']);
      expect(StudentQueries.variants(''), ['']);
    });

    test('بالهاتف: بداية الرقم بصيغ مختلفة', () async {
      expect(await names(query: '0550'), ['أحمد بن علي', 'سارة بن عيسى']);
      expect(await names(query: '055012'), ['أحمد بن علي']);
      expect(await names(query: '+213 661 23'), ['محمد أمين حداد']);
      expect(await names(query: '0999'), isEmpty);
    });

    test('المسافات الزائدة وحالة بلا نتائج', () async {
      expect(await names(query: '  أحمد   بن  '), ['أحمد بن علي']);
      final none = await page(query: 'لا أحد');
      expect(none.items, isEmpty);
      expect(none.total, 0);
    });

    test('العدد الكلي يخص نتائج البحث', () async {
      final p = await page(query: 'بن', limit: 1);
      expect(p.items, hasLength(1));
      expect(p.total, 2);
      expect(p.hasMore, isTrue);
    });

    test('المحذوفون لا يظهرون في البحث', () async {
      await add('5', 'أحمد', 'مخفي', deleted: true);
      expect(await names(query: 'أحمد'), ['أحمد بن علي']);
    });
  });

  group('الأداء مع 5000 تلميذ', () {
    setUp(() async {
      await env.db.batch((batch) {
        batch.insertAll(env.db.students, [
          for (var i = 0; i < 5000; i++)
            StudentsCompanion.insert(
              id: 'p$i',
              createdAt: 1,
              updatedAt: 1,
              firstName: 'اسم${i % 97}',
              lastName: 'لقب${(i * 7) % 1000}',
              parentPhone: '05${(50000000 + i).toString().padLeft(8, '0')}',
              qrCode: 'S-P$i',
            ),
        ]);
      });
    });

    Future<String> plan(String sql, List<Object> args) async {
      final rows = await env.db
          .customSelect(
            'EXPLAIN QUERY PLAN $sql',
            variables: [for (final a in args) Variable<Object>(a)],
          )
          .get();
      return rows.map((r) => r.read<String>('detail')).join(' ');
    }

    test('الاستعلامات تستعمل الفهارس لا مسح الجدول', () async {
      expect(
        await plan(
          'SELECT * FROM students s WHERE s.deleted_at IS NULL AND '
          '(s.last_name >= ? AND s.last_name < ?) '
          'ORDER BY s.last_name, s.first_name, s.id LIMIT 50',
          ['لقب1', 'لقب1￿'],
        ),
        contains('idx_students_name'),
      );
      expect(
        await plan(
          'SELECT * FROM students s WHERE s.deleted_at IS NULL AND '
          '(s.first_name >= ? AND s.first_name < ?)',
          ['اسم1', 'اسم1￿'],
        ),
        contains('idx_students_first_name'),
      );
      expect(
        await plan(
          'SELECT * FROM students s WHERE s.deleted_at IS NULL AND '
          '(s.parent_phone >= ? AND s.parent_phone < ?)',
          ['0550', '0550￿'],
        ),
        contains('idx_students_parent_phone'),
      );
      expect(
        await plan(
          'SELECT * FROM students s WHERE s.deleted_at IS NULL '
          'ORDER BY s.last_name, s.first_name, s.id LIMIT 50',
          const [],
        ),
        contains('idx_students_name'),
      );
    });

    test('الصفحة الأولى والبحث أقل من 150 ميلي ثانية', () async {
      Future<int> time(String query) async {
        final watch = Stopwatch()..start();
        await page(query: query);
        return watch.elapsedMilliseconds;
      }

      await time(''); // تسخين
      expect(await time(''), lessThan(150));
      expect(await time('لقب12'), lessThan(150));
      expect(await time('اسم5 لقب7'), lessThan(150));
      expect(await time('0550'), lessThan(150));
      final p = await page();
      expect(p.total, 5000);
      expect(p.items, hasLength(50));
    });
  });
}
