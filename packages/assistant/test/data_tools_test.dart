import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_assistant/school_assistant.dart';
import 'package:school_core/school_core.dart';

AuthSession owner() => AuthSession(
  const AccountRecord(
    id: 'owner-1',
    email: 'owner@school.local',
    role: UserRole.owner,
  ),
);

AuthSession worker(Map<PermissionModule, List<PermissionAction>> grants) {
  var permissions = WorkerPermissions.none;
  for (final entry in grants.entries) {
    for (final action in entry.value) {
      permissions = permissions.withAction(entry.key, action, allowed: true);
    }
  }
  return AuthSession(
    AccountRecord(
      id: 'worker-1',
      email: 'worker@school.local',
      role: UserRole.worker,
      permissions: permissions,
    ),
  );
}

AuthSession role(UserRole value) => AuthSession(
  AccountRecord(
    id: '${value.name}-1',
    email: '${value.name}@school.local',
    role: value,
  ),
);

void main() {
  late AppDatabase db;
  late SyncWriter writer;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    var next = 0;
    writer = SyncWriter(
      db,
      actor: () => const Actor(userId: 'owner-1', userName: 'المدير'),
      clock: () => 100,
      idGenerator: () => 'gen-${next++}',
    );
  });

  tearDown(() => db.close());

  AssistantTool tool(String name) =>
      createLocalAssistantTools().singleWhere((t) => t.definition.name == name);

  Future<Map<String, Object?>> run(
    String name,
    AuthSession session,
    Map<String, Object?> arguments,
  ) async {
    final result = await tool(name).execute(
      AssistantContext(
        db: db,
        writer: writer,
        session: session,
        now: DateTime(2026, 11, 14, 10),
      ),
      arguments,
    );
    return Map<String, Object?>.from(result.data! as Map);
  }

  Future<void> student(String id, String first, {bool deleted = false}) => db
      .into(db.students)
      .insert(
        StudentsCompanion.insert(
          id: id,
          createdAt: 1,
          updatedAt: 1,
          firstName: first,
          lastName: 'بن علي',
          parentPhone: '0550123456',
          qrCode: 'QR-SECRET-$id',
          deletedAt: Value(deleted ? 5 : null),
        ),
      );

  group('التوفر بحسب الدور', () {
    Set<String> names(AuthSession session) => AssistantService(
      session: session,
      db: db,
      writer: writer,
      model: _NoModel(),
      tools: createLocalAssistantTools(),
    ).availableToolNames;

    test('صاحب المدرسة: كل أدوات المعرفة', () {
      expect(
        names(owner()),
        containsAll([
          'school_overview',
          'describe_schema',
          'query_database',
          'app_guide',
          'propose_school_name_change',
        ]),
      );
    });

    test('الأستاذ والوليّ: الدليل فقط من أدوات المعرفة', () {
      for (final user in [role(UserRole.teacher), role(UserRole.parent)]) {
        final available = names(user);
        expect(available, contains('app_guide'));
        for (final blocked in [
          'school_overview',
          'describe_schema',
          'query_database',
          'propose_school_name_change',
        ]) {
          expect(available, isNot(contains(blocked)), reason: blocked);
        }
      }
    });

    test('عامل بصلاحية عرض: يقرأ، ولا يغيّر الاسم إلا بصلاحية الإعدادات', () {
      final viewer = worker({
        PermissionModule.students: [PermissionAction.view],
      });
      expect(
        names(viewer),
        containsAll(['school_overview', 'describe_schema', 'query_database']),
      );
      expect(names(viewer), isNot(contains('propose_school_name_change')));

      final admin = worker({
        PermissionModule.students: [PermissionAction.view],
        PermissionModule.settings: [PermissionAction.edit],
      });
      expect(names(admin), contains('propose_school_name_change'));
    });

    test('عامل بلا أي صلاحية: لا قراءة', () {
      final nobody = worker({});
      expect(names(nobody), isNot(contains('query_database')));
      expect(names(nobody), isNot(contains('school_overview')));
    });
  });

  group('school_overview', () {
    test('يعدّ التلاميذ الأحياء فقط ويجيب سؤال المجموع', () async {
      await student('s1', 'أحمد');
      await student('s2', 'سعاد');
      await student('s3', 'محذوف', deleted: true);

      final result = await run('school_overview', owner(), {});

      expect(result['students'], 2);
      expect(result['today'], '2026-11-14');
      expect(result['unsynced_changes'], 0);
      expect(result['teachers'], 0);
      expect(result['received_today_dzd'], 0);
    });

    test('العامل يرى أقسام صلاحياته فقط', () async {
      await student('s1', 'أحمد');
      final result = await run(
        'school_overview',
        worker({
          PermissionModule.students: [PermissionAction.view],
        }),
        {},
      );
      expect(result['students'], 1);
      expect(result, isNot(contains('received_today_dzd')));
      expect(result, isNot(contains('teachers')));
      expect(result, isNot(contains('teacher_payouts_unpaid_dzd')));
    });
  });

  group('describe_schema', () {
    test('يعدّد الجداول المتاحة بوصفها وعدد صفوفها، ويحجب الحساس', () async {
      await student('s1', 'أحمد');
      final result = await run('describe_schema', owner(), {});
      final tables = (result['tables']! as List).cast<Map<String, Object?>>();
      final byName = {for (final t in tables) t['name']! as String: t};

      expect(byName['students']!['rows'], 1);
      expect(byName['students']!['description'], contains('التلاميذ'));
      expect(byName, contains('payments'));
      expect(byName, contains('staff_debts'), reason: 'للمالك');
      for (final hidden in [
        'user_accounts',
        'local_credentials',
        'outbox',
        'sync_state',
        'device_info',
        'chat_messages',
        'notifications',
      ]) {
        expect(byName, isNot(contains(hidden)), reason: hidden);
      }
      expect('${result['conventions']}', contains('deleted_at'));
      expect('${result['codes']}', contains('present = حاضر'));
    });

    test('أعمدة جدول: دون رمز QR ومعرّفات المصادقة، وبشرح الرموز', () async {
      final result = await run('describe_schema', owner(), {
        'table': 'students',
      });
      final columns = (result['columns']! as List).cast<Map<String, Object?>>();
      final names = columns.map((c) => c['name']).toList();
      expect(names, containsAll(['id', 'first_name', 'parent_phone']));
      expect(names, isNot(contains('qr_code')));
      expect(names, isNot(contains('photo_url')));
      expect(names, isNot(contains('photo_local_path')));
      expect(names, contains('parent_account_id'), reason: 'رابط بالوليّ ظاهر');
    });

    test('العامل لا يرى جدول المدفوعات دون صلاحيته، ولا يطلب أعمدته', () async {
      final viewer = worker({
        PermissionModule.students: [PermissionAction.view],
      });
      final list = await run('describe_schema', viewer, {});
      final names = [
        for (final t in (list['tables']! as List).cast<Map<String, Object?>>())
          t['name'],
      ];
      expect(names, contains('students'));
      expect(names, isNot(contains('payments')));
      expect(names, isNot(contains('staff_debts')));

      final direct = await run('describe_schema', viewer, {
        'table': 'payments',
      });
      expect('${direct['error']}', contains('غير متاح'));
    });
  });

  group('query_database', () {
    test('عدّ وتجميع للقراءة', () async {
      await student('s1', 'أحمد');
      await student('s2', 'أحمد');
      await student('s3', 'سعاد');
      final result = await run('query_database', owner(), {
        'sql':
            'SELECT first_name, COUNT(*) AS n FROM students '
            'WHERE deleted_at IS NULL GROUP BY first_name ORDER BY n DESC',
      });

      expect(result['columns'], ['first_name', 'n']);
      expect(result['row_count'], 2);
      expect(result['truncated'], false);
      final rows = (result['rows']! as List).cast<Map<String, Object?>>();
      expect(rows.first, {'first_name': 'أحمد', 'n': 2});
    });

    test('يرفض الكتابة والحساس برسالة عربية ولا يغيّر شيئاً', () async {
      await student('s1', 'أحمد');
      for (final sql in [
        'DELETE FROM students',
        'SELECT * FROM user_accounts',
        'SELECT qr_code FROM students',
        'SELECT 1; SELECT 2',
      ]) {
        final result = await run('query_database', owner(), {'sql': sql});
        expect(result['error'], isNotNull, reason: sql);
        expect(result, isNot(contains('rows')), reason: sql);
      }
      expect(await db.select(db.students).get(), hasLength(1));
    });

    test('العامل بلا صلاحية المدفوعات لا يقرؤها', () async {
      final result = await run(
        'query_database',
        worker({
          PermissionModule.students: [PermissionAction.view],
        }),
        {'sql': 'SELECT SUM(amount) FROM payments'},
      );
      expect('${result['error']}', contains('payments'));
    });

    test('خطأ SQL يُعاد للنموذج ليصحّح استعلامه', () async {
      final result = await run('query_database', owner(), {
        'sql': 'SELECT no_such_column FROM students',
      });
      expect('${result['error']}', contains('خطأ في الاستعلام'));
    });

    test('سقف الصفوف والاقتطاع وطول القيم', () async {
      for (var i = 0; i < 130; i++) {
        await db
            .into(db.students)
            .insert(
              StudentsCompanion.insert(
                id: 's$i',
                createdAt: 1,
                updatedAt: 1,
                firstName: 'x' * 500,
                lastName: 'ل',
                parentPhone: '0550000000',
                qrCode: 'Q$i',
              ),
            );
      }
      final result = await run('query_database', owner(), {
        'sql': 'SELECT id, first_name FROM students',
      });
      expect(result['truncated'], isTrue);
      expect(result['note'], isNotNull);
      final rows = (result['rows']! as List).cast<Map<String, Object?>>();
      expect(rows.length, lessThanOrEqualTo(ReadOnlySql.maxRows));
      expect((rows.first['first_name']! as String).length, 301);
      expect(jsonEncode(result).length, lessThan(60000));
    });
  });

  group('app_guide', () {
    test('قائمة المواضيع بحسب الدور', () async {
      final staff = await run('app_guide', owner(), {});
      final staffIds = [
        for (final t in (staff['topics']! as List).cast<Map<String, Object?>>())
          t['id'],
      ];
      expect(
        staffIds,
        containsAll(['overview', 'payments', 'payouts', 'codes']),
      );

      final parent = await run('app_guide', role(UserRole.parent), {});
      final parentIds = [
        for (final t
            in (parent['topics']! as List).cast<Map<String, Object?>>())
          t['id'],
      ];
      expect(parentIds, contains('overview'));
      expect(parentIds, contains('attendance'));
      expect(parentIds, isNot(contains('payouts')));
      expect(parentIds, isNot(contains('codes')));
    });

    test('قراءة موضوع، والمجهول يعيد قائمة المواضيع', () async {
      final topic = await run('app_guide', owner(), {'topic': 'payments'});
      expect(topic['title'], 'المدفوعات والمستحقات');
      expect('${topic['text']}', contains('وصل مرقّم'));

      final codes = await run('app_guide', owner(), {'topic': 'codes'});
      expect('${codes['text']}', contains('absent = غائب'));

      final unknown = await run('app_guide', owner(), {'topic': 'zzz'});
      expect('${unknown['error']}', contains('overview'));

      final forbidden = await run('app_guide', role(UserRole.parent), {
        'topic': 'payouts',
      });
      expect(forbidden['error'], isNotNull);
    });
  });

  group('propose_school_name_change', () {
    test('يجهّز مسودة ولا يكتب قبل التأكيد، ثم يغيّر الاسم بعده', () async {
      await SettingsService(
        db,
        writer,
      ).save(const SchoolSettings(schoolName: 'مدرسة النجاح'));
      final before = await tool('propose_school_name_change').execute(
        AssistantContext(
          db: db,
          writer: writer,
          session: owner(),
          now: DateTime(2026, 11, 14),
        ),
        {'new_name': 'مدرسة الأمل'},
      );

      final draft = before.action!;
      expect(draft.title, 'تغيير اسم المدرسة');
      expect(draft.summary, contains('مدرسة النجاح'));
      expect(draft.summary, contains('مدرسة الأمل'));
      expect(
        (await SettingsService(db, writer).load()).schoolName,
        'مدرسة النجاح',
        reason: 'لا كتابة قبل التأكيد',
      );

      await draft.confirm();
      expect(
        (await SettingsService(db, writer).load()).schoolName,
        'مدرسة الأمل',
      );
    });

    test('الاسم نفسه: لا تغيير، وطول غير صالح مرفوض', () async {
      await SettingsService(
        db,
        writer,
      ).save(const SchoolSettings(schoolName: 'مدرسة النجاح'));
      final same = await tool('propose_school_name_change').execute(
        AssistantContext(
          db: db,
          writer: writer,
          session: owner(),
          now: DateTime(2026, 11, 14),
        ),
        {'new_name': 'مدرسة النجاح'},
      );
      expect(same.action, isNull);
      expect((same.data! as Map)['unchanged'], isTrue);

      for (final bad in ['ا', 'ا' * 81]) {
        await expectLater(
          tool('propose_school_name_change').execute(
            AssistantContext(
              db: db,
              writer: writer,
              session: owner(),
              now: DateTime(2026, 11, 14),
            ),
            {'new_name': bad},
          ),
          throwsArgumentError,
        );
      }
    });
  });

  group('الخدمة', () {
    test('خطأ التحقق يصل النموذج بنصه ليصحّح (لا «تعذر» مبهمة)', () async {
      final model = _ScriptedModel([
        const AssistantModelResponse(
          toolCalls: [
            AssistantToolCall(
              id: 'c1',
              name: 'search_students',
              arguments: {'query': 'ا'},
            ),
          ],
        ),
        const AssistantModelResponse(content: 'حاولت'),
      ]);
      final assistant = AssistantService(
        session: owner(),
        db: db,
        writer: writer,
        model: model,
        tools: createLocalAssistantTools(),
      );

      await assistant.ask('كم عدد التلاميذ؟');

      final toolMessage = model.lastMessages.lastWhere((m) => m.role == 'tool');
      expect(toolMessage.content, contains('school_overview'));
      expect(toolMessage.content, isNot(contains('تعذر تنفيذ الأداة')));
    });

    test('سؤال العدد عبر الأدوات: نظرة عامة ثم جواب', () async {
      await student('s1', 'أحمد');
      await student('s2', 'سعاد');
      final model = _ScriptedModel([
        const AssistantModelResponse(
          toolCalls: [
            AssistantToolCall(id: 'c1', name: 'school_overview', arguments: {}),
          ],
        ),
        const AssistantModelResponse(content: 'لديك تلميذان.'),
      ]);
      final assistant = AssistantService(
        session: owner(),
        db: db,
        writer: writer,
        model: model,
        tools: createLocalAssistantTools(),
      );

      final reply = await assistant.ask('ما مجموع التلاميذ؟');

      expect(reply.text, 'لديك تلميذان.');
      final result = jsonDecode(
        model.lastMessages.lastWhere((m) => m.role == 'tool').content!,
      );
      expect((result as Map)['students'], 2);
    });
  });
}

class _NoModel implements AssistantModelClient {
  @override
  Future<AssistantModelResponse> complete({
    required UserRole role,
    required List<AssistantMessage> messages,
    required List<AssistantToolDefinition> tools,
  }) => throw StateError('No model call expected');
}

class _ScriptedModel implements AssistantModelClient {
  _ScriptedModel(this.replies);

  final List<AssistantModelResponse> replies;
  List<AssistantMessage> lastMessages = const [];

  @override
  Future<AssistantModelResponse> complete({
    required UserRole role,
    required List<AssistantMessage> messages,
    required List<AssistantToolDefinition> tools,
  }) async {
    lastMessages = List.of(messages);
    return replies.removeAt(0);
  }
}
