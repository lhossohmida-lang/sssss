import 'dart:convert';

/// رسالة في محادثة المساعد أو نتيجة أداة محلية.
class AssistantMessage {
  const AssistantMessage({
    required this.role,
    required this.content,
    this.toolCallId,
    this.isError = false,
    this.toolCalls = const [],
  });

  final String role;
  final String? content;
  final String? toolCallId;
  final bool isError;
  final List<AssistantToolCall> toolCalls;

  Map<String, Object?> toJson() => {
    'role': role,
    if (content != null) 'content': content,
    if (toolCallId != null) 'tool_call_id': toolCallId,
    if (isError) 'is_error': true,
    if (toolCalls.isNotEmpty)
      'tool_calls': [for (final call in toolCalls) call.toJson()],
  };
}

/// نداء أداة يطلبه النموذج؛ لا يُنفّذ إلا بعد مطابقة الاسم والصلاحية محلياً.
class AssistantToolCall {
  const AssistantToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  final String id;
  final String name;
  final Map<String, Object?> arguments;

  Map<String, Object?> toJson() => {
    'id': id,
    'type': 'function',
    'function': {'name': name, 'arguments': jsonEncode(arguments)},
  };
}

/// تعريف أداة بصيغة OpenAI-compatible يمرّرها الخادم إلى مزوّد النموذج.
class AssistantToolDefinition {
  const AssistantToolDefinition({
    required this.name,
    required this.description,
    required this.parameters,
  });

  final String name;
  final String description;
  final Map<String, Object?> parameters;

  Map<String, Object?> toJson() => {
    'type': 'function',
    'function': {
      'name': name,
      'description': description,
      'parameters': parameters,
    },
  };
}

/// استجابة موحّدة من عميل النموذج القابل للاستبدال.
class AssistantModelResponse {
  const AssistantModelResponse({this.content, this.toolCalls = const []});

  final String? content;
  final List<AssistantToolCall> toolCalls;
}

/// إجراء مقترح ينتظر تأكيد المستخدم؛ لا يحمل أي كتابة جرت مسبقاً.
class AssistantActionPreview {
  const AssistantActionPreview({
    required this.id,
    required this.title,
    required this.summary,
  });

  final String id;
  final String title;
  final String summary;
}

/// نتيجة دور واحد للمساعد.
class AssistantReply {
  const AssistantReply({this.text = '', this.actions = const []});

  final String text;
  final List<AssistantActionPreview> actions;
}

/// تعذّر الاتصال بدالة المساعد أو لم تُجهّز إعداداتها.
class AssistantUnavailableException implements Exception {
  const AssistantUnavailableException([
    this.message = 'المساعد غير متاح دون اتصال بالإنترنت.',
  ]);

  final String message;

  @override
  String toString() => message;
}
