import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

import '../support/fixtures.dart';

void main() {
  late TestEnv env;
  late TransportService transport;

  setUp(() {
    env = TestEnv();
    transport = TransportService(env.db, env.writer);
  });

  tearDown(() => env.close());

  Future<void> addTransportStudent(
    String id, {
    String? lineId,
    bool usesTransport = true,
  }) async {
    await env.student(id: id);
    await env.writer.patch(
      env.db.students,
      key: {'id': id},
      values: {
        'uses_transport': usesTransport,
        'transport_price': 1800,
        'transport_line_id': lineId,
      },
    );
  }

  group('إدارة الخطوط', () {
    test('المعرّف ثابت والاسم فريد دون حساسية لحالة الأحرف', () async {
      final id = await transport.addLine(
        name: '  خط بئر مراد  ',
        driverName: ' سليم ',
        driverPhone: '+213 550 123 456',
        busNumber: ' 12-345 ',
      );

      expect(id, StableId.transportLine('خط بئر مراد'));
      final line = (await transport.lines()).single;
      expect(line.name, 'خط بئر مراد');
      expect(line.driverName, 'سليم');
      expect(line.driverPhone, '0550123456');
      expect(line.busNumber, '12-345');
      await expectLater(
        transport.addLine(name: 'خط بئر مراد'),
        throwsA(isA<StateError>()),
      );
      final routeId = await transport.addLine(name: 'Route A');
      expect(routeId, StableId.transportLine('route a'));
      await expectLater(
        transport.addLine(name: 'route a'),
        throwsA(isA<StateError>()),
      );
    });

    test('الاسم والهاتف ورقم الحافلة تتحقق قبل الحفظ', () async {
      await expectLater(transport.addLine(name: '  '), throwsFormatException);
      await expectLater(
        transport.addLine(name: 'خط المدينة', driverPhone: '0123'),
        throwsFormatException,
      );
      await expectLater(
        transport.addLine(name: 'خط المدينة', busNumber: 'ب' * 41),
        throwsFormatException,
      );
      expect(await transport.lines(), isEmpty);
    });

    test('تعديل بيانات الخط يحفظ معلومات السائق والحافلة', () async {
      final id = await transport.addLine(name: 'الجامعة');
      await transport.updateLine(
        id: id,
        name: 'وسط المدينة',
        driverName: 'مروان',
        driverPhone: '0661234567',
        busNumber: '02-778',
      );

      final line = (await transport.lines()).single;
      expect(line.id, id);
      expect(line.name, 'وسط المدينة');
      expect(line.driverName, 'مروان');
      expect(line.driverPhone, '0661234567');
      expect(line.busNumber, '02-778');
      await expectLater(
        transport.updateLine(id: 'missing', name: 'خط غير موجود'),
        throwsA(isA<StateError>()),
      );
    });

    test('حذف الخط ممنوع ما دام تلميذ نشط مربوطاً به', () async {
      final id = await transport.addLine(name: 'المدرسة');
      await addTransportStudent('s1', lineId: id);

      await expectLater(transport.deleteLine(id), throwsA(isA<StateError>()));
      expect((await transport.lines()).single.id, id);

      await transport.unassignStudent(lineId: id, studentId: 's1');
      await transport.deleteLine(id);
      expect(await transport.lines(), isEmpty);
      final row = await (env.db.select(
        env.db.transportLines,
      )..where((line) => line.id.equals(id))).getSingle();
      expect(row.deletedAt, isNotNull);

      expect(await transport.addLine(name: 'المدرسة'), id);
      expect((await transport.lines()).single.id, id);
      expect((await transport.lines()).single.line.deletedAt, isNull);
    });
  });

  group('ربط التلاميذ', () {
    test('يعرض عدد المستعملين للنقل فقط ويحدّث قائمة الخط', () async {
      final id = await transport.addLine(name: 'خط الحي');
      await addTransportStudent('s1', lineId: id);
      await addTransportStudent('s2', lineId: id, usesTransport: false);
      await addTransportStudent('s3', lineId: id);
      await (env.db.update(env.db.students)..where((s) => s.id.equals('s3')))
          .write(const StudentsCompanion(deletedAt: Value(10)));

      final line = (await transport.lines()).single;
      expect(line.studentCount, 1);
      expect((await transport.students(id)).map((student) => student.id), [
        's1',
      ]);
    });

    test('الإسناد والنقل والإزالة تحفظ رابط التلميذ', () async {
      final first = await transport.addLine(name: 'وسط المدينة');
      final second = await transport.addLine(name: 'الجامعة');
      await addTransportStudent('s1');

      expect(
        await transport.assignStudent(lineId: first, studentId: 's1'),
        isTrue,
      );
      expect((await transport.students(first)).single.id, 's1');
      expect((await transport.otherStudents(second)).single.lineId, first);

      await transport.assignStudent(lineId: second, studentId: 's1');
      expect(await transport.students(first), isEmpty);
      expect((await transport.students(second)).single.id, 's1');
      expect(
        await transport.unassignStudent(lineId: first, studentId: 's1'),
        isFalse,
        reason: 'لا يمسح الرابط إذا لم يعد التلميذ في ذلك الخط',
      );
      expect(
        await transport.unassignStudent(lineId: second, studentId: 's1'),
        isTrue,
      );
      expect(await transport.students(second), isEmpty);
      expect((await transport.otherStudents(second)).single.lineId, isNull);
    });

    test('لا يُسند تلميذ لا يستعمل النقل أو خط غير موجود', () async {
      final line = await transport.addLine(name: 'المحطة');
      await addTransportStudent('s1', usesTransport: false);
      await addTransportStudent('s2');

      await expectLater(
        transport.assignStudent(lineId: line, studentId: 's1'),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        transport.assignStudent(lineId: line, studentId: 'missing'),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        transport.assignStudent(lineId: 'missing', studentId: 's2'),
        throwsA(isA<StateError>()),
      );
    });

    test('البحث بالاسم وهاتف الوليّ يعيد المطابقات فقط', () async {
      final line = await transport.addLine(name: 'النخيل');
      await addTransportStudent('s1');
      await addTransportStudent('s2');
      await (env.db.update(env.db.students)..where((s) => s.id.equals('s1')))
          .write(const StudentsCompanion(firstName: Value('أمين')));
      await (env.db.update(env.db.students)..where((s) => s.id.equals('s2')))
          .write(const StudentsCompanion(parentPhone: Value('0661111111')));

      expect(
        (await transport.otherStudents(
          line,
          query: 'أمين',
        )).map((student) => student.id),
        ['s1'],
      );
      expect(
        (await transport.otherStudents(
          line,
          query: '066111',
        )).map((student) => student.id),
        ['s2'],
      );
    });

    test('كل الكتابات تمر عبر الكاتب وتسجل الأثر وطابور المزامنة', () async {
      final id = await transport.addLine(name: 'خط المطار');
      await addTransportStudent('s1');
      await transport.assignStudent(lineId: id, studentId: 's1');
      await transport.updateLine(id: id, name: 'خط المطار الجديد');
      await transport.unassignStudent(lineId: id, studentId: 's1');
      await transport.deleteLine(id);

      final log = await env.db.select(env.db.auditLog).get();
      expect(
        log.where((entry) => entry.entity == 'transport_lines'),
        hasLength(3),
      );
      expect(log.where((entry) => entry.entity == 'students'), hasLength(3));
      final outbox = await env.db.select(env.db.outbox).get();
      expect(
        outbox.where((entry) => entry.targetTable == 'transport_lines'),
        hasLength(1),
      );
      expect(
        outbox.where((entry) => entry.targetTable == 'students'),
        hasLength(1),
      );
    });
  });
}
