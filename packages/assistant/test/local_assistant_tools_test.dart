import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_assistant/school_assistant.dart';
import 'package:school_core/school_core.dart';

void main() {
  late AppDatabase db;
  late SyncWriter writer;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    writer = SyncWriter(
      db,
      actor: () => const Actor(userId: 'worker-1', userName: 'عامل'),
      clock: () => 100,
      idGenerator: () => 'test-id',
    );
  });

  tearDown(() => db.close());

  test(
    'a parent search includes only students linked to that parent account',
    () async {
      await db
          .into(db.parents)
          .insert(
            ParentsCompanion.insert(
              id: 'parent-row-a',
              createdAt: 1,
              updatedAt: 1,
              phone: '0550000001',
              email: 'a@school.local',
              authUserId: const Value('parent-auth-a'),
            ),
          );
      await db
          .into(db.parents)
          .insert(
            ParentsCompanion.insert(
              id: 'parent-row-b',
              createdAt: 1,
              updatedAt: 1,
              phone: '0550000002',
              email: 'b@school.local',
              authUserId: const Value('parent-auth-b'),
            ),
          );
      await db
          .into(db.students)
          .insert(
            StudentsCompanion.insert(
              id: 'student-a',
              createdAt: 1,
              updatedAt: 1,
              firstName: 'Ali',
              lastName: 'A',
              parentPhone: '0550000001',
              qrCode: 'S-A',
              parentAccountId: const Value('parent-row-a'),
            ),
          );
      await db
          .into(db.students)
          .insert(
            StudentsCompanion.insert(
              id: 'student-b',
              createdAt: 1,
              updatedAt: 1,
              firstName: 'Ali',
              lastName: 'B',
              parentPhone: '0550000002',
              qrCode: 'S-B',
              parentAccountId: const Value('parent-row-b'),
            ),
          );
      final session = AuthSession(
        const AccountRecord(
          id: 'parent-auth-a',
          email: 'a@school.local',
          role: UserRole.parent,
        ),
      );
      final tool = createLocalAssistantTools().singleWhere(
        (item) => item.definition.name == 'search_students',
      );

      final result = await tool.execute(
        AssistantContext(
          db: db,
          writer: writer,
          session: session,
          now: DateTime(2026, 11, 14),
        ),
        {'query': 'Ali'},
      );

      final students = result.data! as List<Map<String, Object?>>;
      expect(students.map((student) => student['student_id']), ['student-a']);
      expect(students.first, isNot(contains('parentPhone')));
      expect(students.first, isNot(contains('phone')));
    },
  );

  test('worker tool availability requires every relevant view permission', () {
    final permissions = WorkerPermissions.none
        .withAction(
          PermissionModule.students,
          PermissionAction.view,
          allowed: true,
        )
        .withAction(
          PermissionModule.attendance,
          PermissionAction.view,
          allowed: true,
        );
    final session = AuthSession(
      AccountRecord(
        id: 'worker-1',
        email: 'worker@school.local',
        role: UserRole.worker,
        permissions: permissions,
      ),
    );
    final assistant = AssistantService(
      session: session,
      db: db,
      writer: writer,
      model: _UnusedModel(),
      tools: createLocalAssistantTools(),
    );

    expect(assistant.availableToolNames, contains('search_students'));
    expect(assistant.availableToolNames, contains('student_attendance'));
    expect(
      assistant.availableToolNames,
      isNot(contains('student_unpaid_dues')),
    );
    expect(assistant.availableToolNames, isNot(contains('my_schedule')));
    expect(
      assistant.availableToolNames,
      isNot(contains('propose_session_request')),
    );
  });

  test('tool definitions do not request phone or secret account fields', () {
    final serialized = createLocalAssistantTools()
        .map((tool) => tool.definition.toJson().toString())
        .join('\n');

    expect(serialized, isNot(contains('parentPhone')));
    expect(serialized, isNot(contains('authUserId')));
    expect(serialized, isNot(contains('password')));
  });
}

class _UnusedModel implements AssistantModelClient {
  @override
  Future<AssistantModelResponse> complete({
    required UserRole role,
    required List<AssistantMessage> messages,
    required List<AssistantToolDefinition> tools,
  }) => throw StateError('No model call expected');
}
