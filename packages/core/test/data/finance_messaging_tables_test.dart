import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db
        .into(db.students)
        .insert(
          StudentsCompanion.insert(
            id: 's1',
            createdAt: 1,
            updatedAt: 1,
            firstName: 'أحمد',
            lastName: 'بن علي',
            parentPhone: '0550123456',
            qrCode: 'S-AAAAAAAAAA',
          ),
        );
  });

  tearDown(() => db.close());

  test('القاعدة تحتوي كل جداول نموذج البيانات', () async {
    final rows = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name NOT LIKE 'sqlite_%'",
        )
        .get();
    final names = rows.map((r) => r.read<String>('name')).toSet();
    expect(
      names,
      containsAll(<String>[
        'students',
        'parents',
        'teachers',
        'workers',
        'subjects',
        'rooms',
        'groups',
        'group_students',
        'waiting_lists',
        'waiting_entries',
        'sessions',
        'attendance',
        'teacher_attendance',
        'worker_attendance',
        'session_requests',
        'payments',
        'student_credits',
        'registration_fees',
        'teacher_payouts',
        'expense_categories',
        'expenses',
        'sms_queue',
        'chat_rooms',
        'chat_members',
        'chat_messages',
        'transport_lines',
        'grades',
        'group_files',
        'audit_log',
        'outbox',
        'sync_state',
        'upload_queue',
        'notifications',
        'user_accounts',
        'settings',
      ]),
    );
  });

  test('رقم الوصل فريد', () async {
    PaymentsCompanion pay(String id) => PaymentsCompanion.insert(
      id: id,
      createdAt: 1,
      updatedAt: 1,
      studentId: 's1',
      type: 'registration',
      amount: 500,
      receivedBy: 'u1',
      receiptNumber: 'A-000001',
    );
    await db.into(db.payments).insert(pay('p1'));
    expect(
      () => db.into(db.payments).insert(pay('p2')),
      throwsA(isA<Exception>()),
    );
  });

  test('حقوق التسجيل مرة واحدة لكل تلميذ في الفترة', () async {
    RegistrationFeesCompanion fee(String id, String period) =>
        RegistrationFeesCompanion.insert(
          id: id,
          createdAt: 1,
          updatedAt: 1,
          studentId: 's1',
          periodKey: period,
          amount: 500,
        );
    await db.into(db.registrationFees).insert(fee('f1', '2026-2027'));
    await db.into(db.registrationFees).insert(fee('f2', '2027-2028'));
    expect(
      () => db.into(db.registrationFees).insert(fee('f3', '2026-2027')),
      throwsA(isA<Exception>()),
    );
    final first = await (db.select(
      db.registrationFees,
    )..where((f) => f.id.equals('f1'))).getSingle();
    expect(first.paid, isFalse);
  });

  test('الرسالة الجديدة في الطابور حالتها في الانتظار', () async {
    await db
        .into(db.smsQueue)
        .insert(
          SmsQueueCompanion.insert(
            id: 'm1',
            createdAt: 1,
            updatedAt: 1,
            phone: '+213550123456',
            message: 'مرحبا',
          ),
        );
    final m = await db.select(db.smsQueue).getSingle();
    expect(m.status, 'pending');
    expect(m.attempts, 0);
    expect(m.sentAt, isNull);
  });

  test('طابور العمليات يرقّم العمليات بالترتيب', () async {
    Future<int> add(String id) => db
        .into(db.outbox)
        .insert(
          OutboxCompanion.insert(
            targetTable: 'students',
            rowId: id,
            payload: '{}',
            createdAt: 1,
          ),
        );
    final first = await add('a');
    final second = await add('b');
    expect(second, greaterThan(first));
  });

  test('نفس الملف لا يدخل طابور الرفع مرتين', () async {
    UploadQueueCompanion up(String id) => UploadQueueCompanion.insert(
      id: id,
      kind: 'attendance_excel',
      localPath: '/tmp/a.xlsx',
      remotePath: 'المدرسة/رياضيات/مجموعة 1/a.xlsx',
      dedupeKey: 'session:se1',
      createdAt: 1,
    );
    await db.into(db.uploadQueue).insert(up('u1'));
    expect(
      () => db.into(db.uploadQueue).insert(up('u2')),
      throwsA(isA<Exception>()),
    );
  });

  test('استعلامات المحادثة والطوابير تستعمل الفهارس', () async {
    Future<String> plan(String sql) async {
      final rows = await db.customSelect('EXPLAIN QUERY PLAN $sql').get();
      return rows.map((r) => r.read<String>('detail')).join(' ');
    }

    expect(
      await plan(
        "SELECT * FROM chat_messages WHERE room_id = 'r' "
        'ORDER BY created_at DESC LIMIT 50',
      ),
      contains('idx_chat_messages_room'),
    );
    expect(
      await plan(
        "SELECT * FROM sms_queue WHERE status = 'pending' ORDER BY created_at",
      ),
      contains('idx_sms_queue_status'),
    );
    // الطابور يُقرأ بترتيب مفتاحه الأساسي مباشرة، دون فرز مؤقت.
    expect(
      await plan(
        'SELECT * FROM outbox WHERE next_attempt_at <= 5 ORDER BY seq LIMIT 50',
      ),
      isNot(contains('TEMP B-TREE')),
    );
    expect(
      await plan(
        "SELECT SUM(amount) FROM payments WHERE group_id = 'g' "
        'AND cycle_number = 1',
      ),
      contains('idx_payments_group_cycle'),
    );
  });
}
