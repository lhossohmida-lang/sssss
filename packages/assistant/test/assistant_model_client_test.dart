import 'package:flutter_test/flutter_test.dart';
import 'package:school_assistant/school_assistant.dart';
import 'package:school_core/school_core.dart';

void main() {
  test(
    'sends only the conversation contract to the Supabase function',
    () async {
      String? functionName;
      Map<String, Object?>? sentBody;
      final client = SupabaseAssistantModelClient.withInvoker((
        name,
        body,
      ) async {
        functionName = name;
        sentBody = body;
        return {
          'content': 'وجدت النتيجة.',
          'toolCalls': [
            {
              'id': 'call-1',
              'name': 'search_students',
              'arguments': '{"query":"أمين"}',
            },
          ],
        };
      });

      final result = await client.complete(
        role: UserRole.parent,
        messages: const [
          AssistantMessage(role: 'user', content: 'ابحث عن أمين'),
        ],
        tools: const [
          AssistantToolDefinition(
            name: 'search_students',
            description: 'بحث ضمن نطاق الحساب',
            parameters: {'type': 'object'},
          ),
        ],
      );

      expect(functionName, 'assistant');
      expect(sentBody, containsPair('role', 'parent'));
      expect(sentBody, isNot(contains('apiKey')));
      expect(result.content, 'وجدت النتيجة.');
      expect(result.toolCalls.single.arguments, {'query': 'أمين'});
    },
  );

  test('maps network failures to an unavailable state', () async {
    final client = SupabaseAssistantModelClient.withInvoker((_, _) async {
      throw StateError('offline');
    });

    await expectLater(
      client.complete(
        role: UserRole.owner,
        messages: const [AssistantMessage(role: 'user', content: 'مرحبا')],
        tools: const [],
      ),
      throwsA(isA<AssistantUnavailableException>()),
    );
  });

  test('rejects malformed tool arguments', () async {
    final client = SupabaseAssistantModelClient.withInvoker((_, _) async {
      return {
        'toolCalls': [
          {'id': 'call-1', 'name': 'search_students', 'arguments': '[]'},
        ],
      };
    });

    await expectLater(
      client.complete(
        role: UserRole.parent,
        messages: const [AssistantMessage(role: 'user', content: 'ابحث')],
        tools: const [],
      ),
      throwsFormatException,
    );
  });
}
