import 'dart:convert';

import 'package:school_core/school_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'assistant_models.dart';

/// عقد استدعاء النموذج؛ يمكن استبداله بعميل وهمي أو مزوّد آخر.
abstract interface class AssistantModelClient {
  Future<AssistantModelResponse> complete({
    required UserRole role,
    required List<AssistantMessage> messages,
    required List<AssistantToolDefinition> tools,
  });
}

typedef AssistantFunctionInvoker = Future<Object?> Function(
  String functionName,
  Map<String, Object?> body,
);

/// عميل Supabase Function. مفتاح النموذج يبقى في أسرار الخادم ولا يصل هنا.
class SupabaseAssistantModelClient implements AssistantModelClient {
  SupabaseAssistantModelClient(SupabaseClient client)
    : _invoke = _supabaseInvoker(client);

  /// ينشئ عميلاً من جلسة Supabase التي هيّأها [AppRuntime] قبل فتح الشاشة.
  factory SupabaseAssistantModelClient.fromInitializedInstance() =>
      SupabaseAssistantModelClient(Supabase.instance.client);

  /// نقطة حقن لاختبارات العقد دون تهيئة Supabase أو استخدام شبكة.
  SupabaseAssistantModelClient.withInvoker(this._invoke);

  final AssistantFunctionInvoker _invoke;

  @override
  Future<AssistantModelResponse> complete({
    required UserRole role,
    required List<AssistantMessage> messages,
    required List<AssistantToolDefinition> tools,
  }) async {
    final body = <String, Object?>{
      'role': role.code,
      'messages': [for (final message in messages) message.toJson()],
      'tools': [for (final tool in tools) tool.toJson()],
    };
    try {
      final raw = await _invoke('assistant', body);
      if (raw is! Map) throw const FormatException('استجابة المساعد غير صالحة');
      final content = raw['content'];
      if (content != null && content is! String) {
        throw const FormatException('نص استجابة المساعد غير صالح');
      }
      final calls = raw['toolCalls'];
      if (calls != null && calls is! List) {
        throw const FormatException('قائمة أدوات المساعد غير صالحة');
      }
      return AssistantModelResponse(
        content: content as String?,
        toolCalls: [
          for (final call in (calls as List? ?? const [])) _parseToolCall(call),
        ],
      );
    } on AssistantUnavailableException {
      rethrow;
    } on FormatException {
      rethrow;
    } on Object {
      throw const AssistantUnavailableException();
    }
  }

  AssistantToolCall _parseToolCall(Object? raw) {
    if (raw is! Map || raw['id'] is! String || raw['name'] is! String) {
      throw const FormatException('نداء أداة المساعد غير صالح');
    }
    final arguments = raw['arguments'];
    final Map<String, Object?> decoded;
    if (arguments is String) {
      final value = jsonDecode(arguments);
      if (value is! Map) {
        throw const FormatException('مدخلات أداة المساعد غير صالحة');
      }
      decoded = Map<String, Object?>.from(value);
    } else if (arguments is Map) {
      decoded = Map<String, Object?>.from(arguments);
    } else {
      throw const FormatException('مدخلات أداة المساعد غير صالحة');
    }
    return AssistantToolCall(
      id: raw['id']! as String,
      name: raw['name']! as String,
      arguments: decoded,
    );
  }
}

AssistantFunctionInvoker _supabaseInvoker(SupabaseClient client) =>
    (String functionName, Map<String, Object?> body) async =>
        (await client.functions.invoke(functionName, body: body)).data;
