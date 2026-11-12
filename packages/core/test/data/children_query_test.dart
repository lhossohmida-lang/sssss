import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

import '../support/fixtures.dart';

void main() {
  late TestEnv env;

  setUp(() async {
    env = TestEnv();
    for (final id in ['p1', 'p2']) {
      await env.db
          .into(env.db.parents)
          .insert(
            ParentsCompanion.insert(
              id: id,
              createdAt: 1,
              updatedAt: 1,
              phone: '055000000${id.substring(1)}',
              email: '$id@school.local',
            ),
          );
    }
  });
  tearDown(() => env.close());

  Future<void> child(String id, String first, String? parentId) => env.db
      .into(env.db.students)
      .insert(
        StudentsCompanion.insert(
          id: id,
          createdAt: 1,
          updatedAt: 1,
          firstName: first,
          lastName: 'بن علي',
          parentPhone: '0550000001',
          qrCode: 'S-$id',
          parentAccountId: Value(parentId),
        ),
      );

  test('أبناء الوليّ فقط مرتبين بالاسم، دون المحذوفين', () async {
    await child('s1', 'نور', 'p1');
    await child('s2', 'سمير', 'p1');
    await child('s3', 'ليلى', 'p2');
    await child('s4', 'يوسف', null);
    await child('s5', 'أمين', 'p1');
    await env.writer.softDelete(env.db.students, key: {'id': 's5'});
    final list = await env.db.watchChildren('p1').first;
    expect(list.map((s) => s.firstName), ['سمير', 'نور']);
    expect(await env.db.watchChildren('p2').first, hasLength(1));
    expect(await env.db.watchChildren('nobody').first, isEmpty);
  });

  test('يتحدث عند إضافة ابن', () async {
    await child('s1', 'نور', 'p1');
    final seen = <int>[];
    final sub = env.db.watchChildren('p1').listen((l) => seen.add(l.length));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await child('s2', 'سمير', 'p1');
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await sub.cancel();
    expect(seen.first, 1);
    expect(seen.last, 2);
  });
}
