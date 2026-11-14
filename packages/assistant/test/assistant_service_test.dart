import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_assistant/school_assistant.dart';
import 'package:school_core/school_core.dart';

void main() {
  late AppDatabase db;
  late SyncWriter writer;
  late AuthSession session;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    writer = SyncWriter(
      db,
      actor: () => const Actor(userId: 'parent-1', userName: 'ولي'),
      clock: () => 100,
      idGenerator: () => 'test-id',
    );
    session = AuthSession(
      const AccountRecord(
        id: 'parent-1',
        email: 'parent@school.local',
        role: UserRole.parent,
      ),
    );
  });

  tearDown(() => db.close());

  AssistantService createAssistant(
    _QueueModel model,
    Iterable<AssistantTool> tools,
  ) => AssistantService(
    session: session,
    db: db,
    writer: writer,
    model: model,
    tools: tools,
    clock: () => DateTime(2026, 11, 14),
  );

  test(
    'does not perform a write before confirmation and cancellation is final',
    () async {
      final model = _QueueModel([
        const AssistantModelResponse(
          toolCalls: [
            AssistantToolCall(
              id: 'call-1',
              name: 'request_change',
              arguments: {},
            ),
          ],
        ),
        const AssistantModelResponse(content: 'تم الإلغاء دون تغيير.'),
      ]);
      final tool = _ActionTool();
      final assistant = createAssistant(model, [tool]);

      final reply = await assistant.ask('أرسل طلباً');
      expect(reply.actions, hasLength(1));
      expect(tool.writes, 0);
      await expectLater(assistant.ask('سؤال آخر'), throwsStateError);

      final cancelled = await assistant.confirmAction(
        reply.actions.single.id,
        confirmed: false,
      );
      expect(cancelled.text, contains('أُلغي'));
      expect(tool.writes, 0);
      await expectLater(
        assistant.confirmAction(reply.actions.single.id, confirmed: true),
        throwsStateError,
      );
      await assistant.ask('تابع');
      expect(
        model.lastMessages
            .lastWhere((message) => message.role == 'tool')
            .toolCallId,
        'call-1',
      );
    },
  );

  test('executes a pending action once after confirmation', () async {
    final model = _QueueModel([
      const AssistantModelResponse(
        toolCalls: [
          AssistantToolCall(
            id: 'call-2',
            name: 'request_change',
            arguments: {},
          ),
        ],
      ),
      const AssistantModelResponse(content: 'اكتمل الطلب.'),
    ]);
    final tool = _ActionTool();
    final assistant = createAssistant(model, [tool]);

    final pending = await assistant.ask('اقترح تغييراً');
    expect(tool.writes, 0);
    await assistant.confirmAction(pending.actions.single.id, confirmed: true);
    expect(tool.writes, 1);
    await expectLater(
      assistant.confirmAction(pending.actions.single.id, confirmed: true),
      throwsStateError,
    );

    final reply = await assistant.ask('تابع');
    expect(reply.text, 'اكتمل الطلب.');
    expect(
      model.lastMessages
          .lastWhere((message) => message.role == 'tool')
          .toolCallId,
      'call-2',
    );
  });

  test('rejects multiple tool calls without executing any', () async {
    final model = _QueueModel([
      const AssistantModelResponse(
        toolCalls: [
          AssistantToolCall(
            id: 'call-a',
            name: 'request_change',
            arguments: {},
          ),
          AssistantToolCall(
            id: 'call-b',
            name: 'request_change',
            arguments: {},
          ),
        ],
      ),
      const AssistantModelResponse(content: 'أعد المحاولة بأداة واحدة.'),
    ]);
    final tool = _ActionTool();
    final reply = await createAssistant(model, [tool]).ask('غيّر الموعد');

    expect(reply.text, 'أعد المحاولة بأداة واحدة.');
    expect(tool.executions, 0);
    expect(
      model.lastMessages.where((message) => message.role == 'tool'),
      hasLength(2),
    );
  });

  test('limits prompt size before contacting the model', () async {
    final model = _QueueModel([]);
    final assistant = createAssistant(model, const []);

    await expectLater(
      assistant.ask('س' * (AssistantService.maxInputLength + 1)),
      throwsArgumentError,
    );
    expect(model.requests, 0);
  });
}

class _QueueModel implements AssistantModelClient {
  _QueueModel(this.responses);

  final List<AssistantModelResponse> responses;
  int requests = 0;
  List<AssistantMessage> lastMessages = const [];

  @override
  Future<AssistantModelResponse> complete({
    required UserRole role,
    required List<AssistantMessage> messages,
    required List<AssistantToolDefinition> tools,
  }) async {
    requests++;
    lastMessages = List.of(messages);
    return responses.removeAt(0);
  }
}

class _ActionTool implements AssistantTool {
  int executions = 0;
  int writes = 0;

  @override
  AssistantToolDefinition get definition => const AssistantToolDefinition(
    name: 'request_change',
    description: 'اقتراح تغيير ينتظر التأكيد',
    parameters: {
      'type': 'object',
      'properties': {},
      'additionalProperties': false,
    },
  );

  @override
  bool availableTo(AuthSession session) => session.role == UserRole.parent;

  @override
  Future<AssistantToolResult> execute(
    AssistantContext context,
    Map<String, Object?> arguments,
  ) async {
    executions++;
    return AssistantToolResult.action(
      AssistantActionDraft(
        title: 'تأكيد',
        summary: 'طلب تغيير',
        confirm: () async {
          writes++;
          return {'accepted': true};
        },
      ),
    );
  }
}
