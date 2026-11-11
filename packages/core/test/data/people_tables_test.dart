import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  StudentsCompanion student(String id, String qr, {String? levelId}) {
    return StudentsCompanion.insert(
      id: id,
      createdAt: 1,
      updatedAt: 1,
      firstName: 'أحمد',
      lastName: 'بن علي',
      parentPhone: '0550123456',
      qrCode: qr,
      levelId: Value(levelId),
    );
  }

  test('تُنشأ كل الجداول وتُقرأ فارغة', () async {
    expect(await db.select(db.settings).get(), isEmpty);
    expect(await db.select(db.levels).get(), isEmpty);
    expect(await db.select(db.transportLines).get(), isEmpty);
    expect(await db.select(db.parents).get(), isEmpty);
    expect(await db.select(db.students).get(), isEmpty);
    expect(await db.select(db.subjects).get(), isEmpty);
    expect(await db.select(db.rooms).get(), isEmpty);
    expect(await db.select(db.teachers).get(), isEmpty);
    expect(await db.select(db.teacherSubjects).get(), isEmpty);
    expect(await db.select(db.workers).get(), isEmpty);
  });

  test('إدراج تلميذ وقراءته بقيمه الافتراضية', () async {
    await db.into(db.students).insert(student('s1', 'S-AAAAAAAAAA'));
    final row = await db.select(db.students).getSingle();
    expect(row.firstName, 'أحمد');
    expect(row.usesTransport, isFalse);
    expect(row.transportPrice, 0);
    expect(row.deletedAt, isNull);
  });

  test('رمز QR فريد بين التلاميذ', () async {
    await db.into(db.students).insert(student('s1', 'S-AAAAAAAAAA'));
    expect(
      () => db.into(db.students).insert(student('s2', 'S-AAAAAAAAAA')),
      throwsA(isA<Exception>()),
    );
  });

  test('رقم هاتف الولي فريد بين حسابات الأولياء', () async {
    ParentsCompanion parent(String id) => ParentsCompanion.insert(
      id: id,
      createdAt: 1,
      updatedAt: 1,
      phone: '0550123456',
      email: '0550123456@school.local',
    );
    await db.into(db.parents).insert(parent('p1'));
    expect(
      () => db.into(db.parents).insert(parent('p2')),
      throwsA(isA<Exception>()),
    );
  });

  test('المفاتيح الخارجية مفعّلة: مستوى غير موجود يُرفض', () async {
    expect(
      () => db
          .into(db.students)
          .insert(student('s1', 'S-AAAAAAAAAA', levelId: 'missing')),
      throwsA(isA<Exception>()),
    );
  });

  test('قيم العامل الافتراضية: برنامج وصلاحيات فارغة', () async {
    await db
        .into(db.workers)
        .insert(
          WorkersCompanion.insert(
            id: 'w1',
            createdAt: 1,
            updatedAt: 1,
            name: 'سمير',
            phone: '0660000000',
            email: '0660000000@school.local',
            qrCode: 'W-AAAAAAAAAA',
          ),
        );
    final row = await db.select(db.workers).getSingle();
    expect(row.weeklySchedule, '{}');
    expect(row.permissions, '{}');
    expect(row.expectedStartMinutes, 480);
    expect(row.fullDayWage, 0);
    expect(row.halfDayWage, 0);
  });

  test('كل حقل يُبحث به له فهرس', () async {
    final rows = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'index'")
        .get();
    final names = rows.map((r) => r.read<String>('name')).toSet();
    expect(
      names,
      containsAll(<String>[
        'idx_students_name',
        'idx_students_first_name',
        'idx_students_qr',
        'idx_students_parent_phone',
        'idx_students_parent_account',
        'idx_students_level',
        'idx_students_transport_line',
        'idx_students_updated',
        'idx_teachers_name',
        'idx_teachers_qr',
        'idx_workers_qr',
        'idx_parents_phone',
        'idx_subjects_level',
        'idx_teacher_subjects_subject',
        'idx_levels_sort',
      ]),
    );
  });

  test('البحث بالرمز يستعمل الفهرس لا المسح الكامل', () async {
    final plan = await db
        .customSelect(
          "EXPLAIN QUERY PLAN SELECT * FROM students WHERE qr_code = 'S-X'",
        )
        .get();
    final detail = plan.map((r) => r.read<String>('detail')).join(' ');
    expect(detail, contains('idx_students_qr'));
  });
}
