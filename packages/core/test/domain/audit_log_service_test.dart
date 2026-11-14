import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

import '../support/fixtures.dart';

void main() {
  late TestEnv env;
  late AuditLogService service;

  setUp(() {
    env = TestEnv();
    service = AuditLogService(env.db);
  });

  tearDown(() => env.close());

  Future<void> addLog({
    required String id,
    required String userId,
    required String userName,
    required String action,
    required String entity,
    required String entityId,
    required int createdAt,
  }) => env.db
      .into(env.db.auditLog)
      .insert(
        AuditLogCompanion.insert(
          id: id,
          userId: userId,
          userName: Value(userName),
          action: action,
          entity: entity,
          entityId: entityId,
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
      );

  test('يرتب الأحدث أولاً ويقسم السجل إلى صفحات محدودة', () async {
    await addLog(
      id: 'audit-old',
      userId: 'u1',
      userName: 'المدير',
      action: 'create',
      entity: 'students',
      entityId: 's1',
      createdAt: 100,
    );
    await addLog(
      id: 'audit-new',
      userId: 'u2',
      userName: 'عامل',
      action: 'update',
      entity: 'students',
      entityId: 's2',
      createdAt: 300,
    );
    await addLog(
      id: 'audit-middle',
      userId: 'u1',
      userName: 'المدير',
      action: 'delete',
      entity: 'groups',
      entityId: 'g1',
      createdAt: 200,
    );

    final newest = await service.load(pageSize: 2);
    final oldest = await service.load(page: 1, pageSize: 2);

    expect(newest.entries.map((entry) => entry.id), [
      'audit-new',
      'audit-middle',
    ]);
    expect(newest.totalCount, 3);
    expect(newest.pageCount, 2);
    expect(newest.hasPrevious, isFalse);
    expect(newest.hasNext, isTrue);
    expect(oldest.entries.map((entry) => entry.id), ['audit-old']);
    expect(oldest.hasPrevious, isTrue);
    expect(oldest.hasNext, isFalse);
  });

  test('يرشح في SQL بحسب نوع العملية ونص المنفذ والجدول والمعرّف', () async {
    await addLog(
      id: 'payment-log',
      userId: 'u1',
      userName: 'مدير المدرسة',
      action: 'receive_money',
      entity: 'payments',
      entityId: 'receipt-100',
      createdAt: 100,
    );
    await addLog(
      id: 'student-log',
      userId: 'u2',
      userName: 'عامل',
      action: 'delete',
      entity: 'students',
      entityId: 'student-200',
      createdAt: 200,
    );

    final byActor = await service.load(
      filters: const AuditLogFilters(action: 'receive_money', query: 'المدرسة'),
    );
    final byRecord = await service.load(
      filters: const AuditLogFilters(query: 'student-200'),
    );

    expect(byActor.entries.map((entry) => entry.id), ['payment-log']);
    expect(byRecord.entries.map((entry) => entry.id), ['student-log']);
  });

  test('البث يتحدث بعد إضافة عملية جديدة', () async {
    final events = StreamIterator(service.watch());
    expect(await events.moveNext(), isTrue);
    expect(events.current.totalCount, 0);

    await addLog(
      id: 'new-log',
      userId: 'u1',
      userName: 'المدير',
      action: 'create',
      entity: 'rooms',
      entityId: 'r1',
      createdAt: 100,
    );

    expect(await events.moveNext().timeout(const Duration(seconds: 2)), isTrue);
    expect(events.current.entries.single.id, 'new-log');
    await events.cancel();
  });

  test('يرفض رقم صفحة أو حجم صفحة غير صالح', () async {
    await expectLater(service.load(page: -1), throwsArgumentError);
    await expectLater(
      service.load(pageSize: AuditLogService.maxPageSize + 1),
      throwsArgumentError,
    );
  });
}
