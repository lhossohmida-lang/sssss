import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_assistant/school_assistant.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';
import 'package:school_ui/testing.dart';

void main() {
  late AppDatabase db;
  late SyncWriter writer;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    writer = SyncWriter(
      db,
      actor: () => const Actor(userId: 'teacher', userName: 'أستاذ'),
    );
  });

  tearDown(() => db.close());

  appTest('Windows assistant accepts text and reports offline availability', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await tester.pumpWidget(
        _host(service: null, child: const AssistantScreen()),
      );

      expect(
        find.textContaining('المساعد يحتاج إلى الإنترنت.'),
        findsOneWidget,
      );
      expect(find.byTooltip('تحدث'), findsNothing);
      await tester.enterText(find.byType(TextField), 'متى موعد الحصة؟');
      await tester.pump();
      await tester.tap(find.byTooltip('إرسال'));
      await tester.pumpAndSettle();

      expect(find.text('متى موعد الحصة؟'), findsOneWidget);
      expect(find.textContaining('المساعد غير متاح دون اتصال'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  appTest('action preview waits for the user confirmation', (tester) async {
    final model = _QueuedModel([
      const AssistantModelResponse(
        toolCalls: [
          AssistantToolCall(id: 'tool-1', name: 'test_change', arguments: {}),
        ],
      ),
    ]);
    final tool = _ActionTool();
    final service = _serviceFor(db, writer, model, [tool]);
    await tester.pumpWidget(
      _host(service: service, child: const AssistantScreen()),
    );

    await tester.enterText(find.byType(TextField), 'غيّر الموعد');
    await tester.pump();
    await tester.tap(find.byTooltip('إرسال'));
    await tester.pumpAndSettle();

    expect(find.text('تأكيد الإجراء'), findsOneWidget);
    expect(tool.writes, 0);
    await tester.tap(find.widgetWithText(ClayButton, 'تأكيد الإجراء'));
    await tester.pumpAndSettle();

    expect(tool.writes, 1);
    expect(find.text('تم التأكيد'), findsOneWidget);
    expect(find.text('تم تنفيذ الإجراء بعد تأكيدك.'), findsOneWidget);
  });

  appTest('Android voice fills the draft and sends only after tapping send', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final voice = _FakeVoice();
    addTearDown(voice.dispose);
    final model = _QueuedModel([
      const AssistantModelResponse(content: 'موعدك غداً على الساعة 15:00.'),
    ]);
    try {
      await tester.pumpWidget(
        _host(
          service: _serviceFor(db, writer, model, const []),
          voice: voice,
          child: const AssistantScreen(),
        ),
      );

      await tester.tap(find.byTooltip('تحدث'));
      await tester.pump();
      voice.recognize('متى موعد الحصة؟');
      await tester.pump();

      expect(model.calls, 0);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'متى موعد الحصة؟');
      expect(find.textContaining('جارٍ الاستماع'), findsOneWidget);

      await tester.tap(find.byTooltip('إيقاف الاستماع'));
      await tester.pump();
      await tester.tap(find.byTooltip('إرسال'));
      await tester.pumpAndSettle();

      expect(model.calls, 1);
      expect(find.text('موعدك غداً على الساعة 15:00.'), findsOneWidget);
      await tester.tap(find.byTooltip('اقرأ الإجابة بصوت').last);
      await tester.pumpAndSettle();
      expect(voice.spoken, ['موعدك غداً على الساعة 15:00.']);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

AssistantService _serviceFor(
  AppDatabase db,
  SyncWriter writer,
  AssistantModelClient model,
  Iterable<AssistantTool> tools,
) => AssistantService(
  session: AuthSession(
    const AccountRecord(
      id: 'teacher-auth',
      email: 'teacher@school.local',
      role: UserRole.teacher,
      entityId: 'teacher-row',
    ),
  ),
  db: db,
  writer: writer,
  model: model,
  tools: tools,
);

Widget _host({
  required AssistantService? service,
  AssistantVoiceEngine? voice,
  required Widget child,
}) => ClayApp(
  app: AppIdentity.teacher,
  home: ProviderScope(
    overrides: [
      assistantServiceProvider.overrideWith((ref) => service),
      if (voice != null) assistantVoiceProvider.overrideWithValue(voice),
    ],
    child: child,
  ),
);

class _QueuedModel implements AssistantModelClient {
  _QueuedModel(this.responses);

  final List<AssistantModelResponse> responses;
  int calls = 0;

  @override
  Future<AssistantModelResponse> complete({
    required UserRole role,
    required List<AssistantMessage> messages,
    required List<AssistantToolDefinition> tools,
  }) async {
    calls++;
    return responses.removeAt(0);
  }
}

class _ActionTool implements AssistantTool {
  int writes = 0;

  @override
  AssistantToolDefinition get definition => const AssistantToolDefinition(
    name: 'test_change',
    description: 'تغيير اختباري ينتظر التأكيد.',
    parameters: {
      'type': 'object',
      'properties': {},
      'additionalProperties': false,
    },
  );

  @override
  bool availableTo(AuthSession session) => true;

  @override
  Future<AssistantToolResult> execute(
    AssistantContext context,
    Map<String, Object?> arguments,
  ) async => AssistantToolResult.action(
    AssistantActionDraft(
      title: 'تغيير موعد الحصة',
      summary: 'سيتم إرسال طلب تغيير الموعد.',
      confirm: () async {
        writes++;
        return {'sent': true};
      },
    ),
  );
}

class _FakeVoice extends AssistantVoiceEngine {
  bool _listening = false;
  ValueChanged<String>? _onResult;
  final spoken = <String>[];

  @override
  bool get isListening => _listening;

  @override
  String? get error => null;

  @override
  Future<void> listen({required ValueChanged<String> onResult}) async {
    _onResult = onResult;
    _listening = true;
    notifyListeners();
  }

  void recognize(String text) => _onResult?.call(text);

  @override
  Future<void> stopListening() async {
    _listening = false;
    notifyListeners();
  }

  @override
  Future<void> speak(String text) async => spoken.add(text);

  @override
  Future<void> stopSpeaking() async {}
}
