import 'dart:convert';

import 'package:school_core/school_core.dart';

import 'assistant_model_client.dart';
import 'assistant_models.dart';

/// سياق محلي ثابت للدور الحالي؛ لا يرسل قاعدة البيانات إلى النموذج.
class AssistantContext {
  const AssistantContext({
    required this.db,
    required this.writer,
    required this.session,
    required this.now,
  });

  final AppDatabase db;
  final SyncWriter writer;
  final AuthSession session;
  final DateTime now;
}

/// نتيجة أداة محلية: قراءة، أو إجراء ينتظر التأكيد.
class AssistantToolResult {
  const AssistantToolResult.data(this.data) : action = null;
  const AssistantToolResult.action(this.action) : data = null;

  final Object? data;
  final AssistantActionDraft? action;
}

/// مسودة تغيير؛ لا تستدعى [confirm] إلا بعد موافقة صريحة من المستخدم.
class AssistantActionDraft {
  const AssistantActionDraft({
    required this.title,
    required this.summary,
    required this.confirm,
  });

  final String title;
  final String summary;
  final Future<Object?> Function() confirm;
}

/// أداة تنفذ على القاعدة المحلية بعد التحقق من الدور والصلاحية.
abstract interface class AssistantTool {
  AssistantToolDefinition get definition;
  bool availableTo(AuthSession session);
  Future<AssistantToolResult> execute(
    AssistantContext context,
    Map<String, Object?> arguments,
  );
}

/// حوار محليّ أولاً، بأدوات allow-list، وإجراءات التغيير تتطلب تأكيداً.
class AssistantService {
  AssistantService({
    required AuthSession session,
    required this.db,
    required this.writer,
    required this.model,
    required Iterable<AssistantTool> tools,
    DateTime Function()? clock,
  }) : _session = session,
       _tools = {
         for (final tool in tools)
           if (tool.availableTo(session)) tool.definition.name: tool,
       },
       _clock = clock ?? DateTime.now;

  static const int maxInputLength = 2000;
  static const int maxToolRounds = 6;
  static const int maxHistoryMessages = 24;

  /// أقصى حجم لمحادثة واحدة تُرسل إلى الخادم (بالأحرف). الخادم يرفض ما يفوق 60 ألف حرف أو 96
  /// ألف بايت (العربية بايتان للحرف)، فتُختصر نتائج الأدوات القديمة قبل ذلك وتبقى أحدثها كاملة.
  static const int maxHistoryChars = 36000;

  static final String _omittedResult = jsonEncode({
    'omitted': 'حُذفت هذه النتيجة لتوفير المساحة؛ أعد الاستعلام إن احتجتها',
  });

  final AuthSession _session;
  final AppDatabase db;
  final SyncWriter writer;
  final AssistantModelClient model;
  final Map<String, AssistantTool> _tools;
  final DateTime Function() _clock;
  final List<AssistantMessage> _history = [];
  final Map<String, _PendingAssistantAction> _pendingActions = {};
  var _actionSequence = 0;

  Set<String> get availableToolNames => Set.unmodifiable(_tools.keys);

  Future<AssistantReply> ask(String prompt) async {
    if (_pendingActions.isNotEmpty) {
      throw StateError('أكمل تأكيد الإجراء أو ألغِه قبل سؤال جديد.');
    }
    final text = prompt.trim();
    if (text.isEmpty) {
      throw ArgumentError.value(prompt, 'prompt', 'أدخل سؤالاً');
    }
    if (text.length > maxInputLength) {
      throw ArgumentError.value(
        text.length,
        'prompt',
        'السؤال أطول من الحد المسموح',
      );
    }
    _history.add(AssistantMessage(role: 'user', content: text));
    _trimHistory();

    for (var round = 0; round < maxToolRounds; round++) {
      _fitHistory();
      final response = await model.complete(
        role: _session.role,
        messages: List.unmodifiable(_history),
        tools: [for (final tool in _tools.values) tool.definition],
      );
      if (response.toolCalls.isEmpty) {
        final answer = response.content?.trim() ?? '';
        _history.add(AssistantMessage(role: 'assistant', content: answer));
        _trimHistory();
        return AssistantReply(text: answer);
      }

      _history.add(
        AssistantMessage(
          role: 'assistant',
          content: response.content,
          toolCalls: response.toolCalls,
        ),
      );
      // The model function disables parallel tool use. Reject malformed or
      // unexpected batches locally as well so no side effect can be duplicated.
      if (response.toolCalls.length != 1) {
        for (final call in response.toolCalls) {
          _history.add(
            AssistantMessage(
              role: 'tool',
              toolCallId: call.id,
              isError: true,
              content: jsonEncode({'error': 'نفّذ أداة واحدة في كل مرة'}),
            ),
          );
        }
        continue;
      }
      for (final call in response.toolCalls) {
        final tool = _tools[call.name];
        if (tool == null || !tool.availableTo(_session)) {
          _history.add(
            AssistantMessage(
              role: 'tool',
              toolCallId: call.id,
              content: jsonEncode({'error': 'الأداة غير متاحة لهذا الحساب'}),
            ),
          );
          continue;
        }
        final AssistantToolResult result;
        try {
          result = await tool.execute(
            AssistantContext(
              db: db,
              writer: writer,
              session: _session,
              now: _clock(),
            ),
            call.arguments,
          );
        } on ArgumentError catch (e) {
          // رسالة التحقق عربية كتبناها نحن: تُعاد للنموذج ليصحّح مدخلاته بدل «تعذر» مبهمة.
          final detail = e.invalidValue == null
              ? '${e.message}'
              : '${e.message}: ${e.invalidValue}';
          _history.add(
            AssistantMessage(
              role: 'tool',
              toolCallId: call.id,
              isError: true,
              content: jsonEncode({'error': detail}),
            ),
          );
          continue;
        } on Object {
          _history.add(
            AssistantMessage(
              role: 'tool',
              toolCallId: call.id,
              isError: true,
              content: jsonEncode({'error': 'تعذر تنفيذ الأداة'}),
            ),
          );
          continue;
        }
        final action = result.action;
        if (action != null) {
          final id = 'assistant-action-${++_actionSequence}';
          _pendingActions[id] = _PendingAssistantAction(
            action: action,
            toolCallId: call.id,
          );
          return AssistantReply(
            text: action.summary,
            actions: [
              AssistantActionPreview(
                id: id,
                title: action.title,
                summary: action.summary,
              ),
            ],
          );
        }
        _history.add(
          AssistantMessage(
            role: 'tool',
            toolCallId: call.id,
            content: jsonEncode(result.data),
          ),
        );
      }
      _trimHistory();
    }
    throw StateError('تجاوز المساعد الحد الآمن لاستدعاءات الأدوات.');
  }

  /// ينفّذ الإجراء مرة واحدة بعد التأكيد، أو يستهلكه دون كتابة عند الإلغاء.
  Future<AssistantReply> confirmAction(
    String actionId, {
    required bool confirmed,
  }) async {
    final pending = _pendingActions.remove(actionId);
    if (pending == null) {
      throw StateError('الإجراء غير موجود أو عولج سابقاً.');
    }
    if (!confirmed) {
      _history.add(
        AssistantMessage(
          role: 'tool',
          toolCallId: pending.toolCallId,
          content: jsonEncode({'cancelled': true}),
        ),
      );
      _trimHistory();
      return const AssistantReply(text: 'أُلغي الإجراء دون تغيير.');
    }
    try {
      final result = await pending.action.confirm();
      _history.add(
        AssistantMessage(
          role: 'tool',
          toolCallId: pending.toolCallId,
          content: jsonEncode(result),
        ),
      );
      _trimHistory();
      return const AssistantReply(text: 'تم تنفيذ الإجراء بعد تأكيدك.');
    } on Object {
      _history.add(
        AssistantMessage(
          role: 'tool',
          toolCallId: pending.toolCallId,
          isError: true,
          content: jsonEncode({'error': 'تعذر تنفيذ الإجراء'}),
        ),
      );
      _trimHistory();
      return const AssistantReply(
        text: 'تعذر تنفيذ الإجراء؛ لم يكتمل التغيير.',
      );
    }
  }

  void clearHistory() {
    _history.clear();
    _pendingActions.clear();
  }

  int _historySize() {
    var total = 0;
    for (final message in _history) {
      total += message.content?.length ?? 0;
      for (final call in message.toolCalls) {
        total += call.name.length + jsonEncode(call.arguments).length;
      }
    }
    return total;
  }

  /// يُبقي المحادثة ضمن [maxHistoryChars]: تُستبدل أقدم نتائج الأدوات بإشارة قصيرة (فيبقى
  /// ترتيب النداء والنتيجة سليماً)، وأحدث نتيجة كاملة لأنها ما يقرؤه النموذج الآن؛ فإن لم يكفِ
  /// سقطت أقدم الأدوار كاملة.
  void _fitHistory() {
    var total = _historySize();
    if (total <= maxHistoryChars) return;
    final newestTool = _history.lastIndexWhere((m) => m.role == 'tool');
    for (var i = 0; i < _history.length && total > maxHistoryChars; i++) {
      final message = _history[i];
      final content = message.content;
      if (message.role != 'tool' ||
          i == newestTool ||
          content == null ||
          content.length <= _omittedResult.length) {
        continue;
      }
      total -= content.length - _omittedResult.length;
      _history[i] = AssistantMessage(
        role: 'tool',
        toolCallId: message.toolCallId,
        isError: message.isError,
        content: _omittedResult,
      );
    }
    while (_historySize() > maxHistoryChars) {
      final nextUser = _history.indexWhere((m) => m.role == 'user', 1);
      if (nextUser == -1) return;
      _history.removeRange(0, nextUser);
    }
  }

  void _trimHistory() {
    while (_history.length > maxHistoryMessages) {
      var nextUser = 1;
      while (nextUser < _history.length && _history[nextUser].role != 'user') {
        nextUser++;
      }
      if (nextUser == _history.length) {
        _history.clear();
        return;
      }
      _history.removeRange(0, nextUser);
    }
  }
}

class _PendingAssistantAction {
  const _PendingAssistantAction({
    required this.action,
    required this.toolCallId,
  });

  final AssistantActionDraft action;
  final String toolCallId;
}
