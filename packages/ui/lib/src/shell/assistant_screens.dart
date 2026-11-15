import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:school_assistant/school_assistant.dart';

import '../clay/clay_button.dart';
import '../clay/clay_container.dart';
import '../clay/clay_icons.dart';
import '../clay/clay_navigation.dart';
import '../theme/clay_theme.dart';
import '../theme/clay_tokens.dart';
import 'assistant_voice.dart';
import 'providers.dart';

/// محادثة المدرسة المشتركة بين تطبيق الإدارة والأستاذ ووليّ التلميذ.
class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key});

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  final _composer = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <_AssistantChatEntry>[
    const _AssistantChatEntry.answer(
      AssistantReply(
        text: 'مرحباً، أنا مساعد المدرسة. اكتب سؤالك وسأجيب من البيانات التي يسمح بها حسابك.',
      ),
    ),
  ];
  final _resolvedActions = <String, bool>{};
  String _voicePrefix = '';
  String? _speakingText;
  AssistantVoiceEngine? _activeVoice;
  bool _busy = false;
  bool _resolvingAction = false;

  bool get _voiceSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void dispose() {
    _composer.dispose();
    _scroll.dispose();
    final voice = _activeVoice;
    if (voice != null) unawaited(voice.stopListening());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final voice = _voiceSupported ? ref.watch(assistantVoiceProvider) : null;
    if (voice == null) return _buildPage(context, null);
    return ListenableBuilder(
      listenable: voice,
      builder: (context, _) => _buildPage(context, voice),
    );
  }

  Widget _buildPage(BuildContext context, AssistantVoiceEngine? voice) {
    return Scaffold(
      appBar: const ClayAppBar(title: 'مساعد المدرسة', showBack: true),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ClaySpacing.screenPadding,
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: ClaySpacing.sm),
                  child: Text(
                    voice == null
                        ? 'المساعد يحتاج إلى الإنترنت. ستظهر الإجابة هنا بعد إرسال سؤالك.'
                        : 'عند استخدام الميكروفون قد تستعمل خدمة Android الشبكة للتعرّف على الكلام. راجع النص؛ لن يُرسل للمساعد إلا بعد ضغط «إرسال».',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.only(bottom: ClaySpacing.sm),
                    itemCount: _messages.length + (_busy ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (_busy && index == _messages.length) {
                        return const _AssistantTypingIndicator();
                      }
                      return _AssistantMessageTile(
                        entry: _messages[index],
                        voice: voice,
                        resolving: _resolvingAction,
                        resolvedActions: _resolvedActions,
                        onResolveAction: _resolveAction,
                        onSpeak: voice == null ? null : _speak,
                      );
                    },
                  ),
                ),
                if (voice?.isListening ?? false)
                  Padding(
                    padding: const EdgeInsets.only(bottom: ClaySpacing.xs),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.mic, color: context.palette.status.danger),
                        const SizedBox(width: ClaySpacing.xs),
                        Flexible(
                          child: Text(
                            'جارٍ الاستماع… اضغط الميكروفون للإيقاف',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                _composerBar(context, voice),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _composerBar(BuildContext context, AssistantVoiceEngine? voice) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: ClaySpacing.md,
        top: ClaySpacing.xs,
      ),
      child: ClayContainer(
        depth: ClayDepth.pressed,
        padding: const EdgeInsets.symmetric(horizontal: ClaySpacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _composer,
                minLines: 1,
                maxLines: 4,
                maxLength: AssistantService.maxInputLength,
                enabled: !_busy && !_resolvingAction,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => unawaited(_send()),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'اكتب سؤالك…',
                  border: InputBorder.none,
                  counterText: '',
                  contentPadding: EdgeInsets.all(ClaySpacing.sm),
                ),
              ),
            ),
            if (voice != null)
              IconButton(
                tooltip: voice.isListening ? 'إيقاف الاستماع' : 'تحدث',
                onPressed: _busy || _resolvingAction
                    ? null
                    : () => unawaited(_toggleListening(voice)),
                icon: Icon(
                  voice.isListening
                      ? Icons.stop_circle_rounded
                      : Icons.mic_rounded,
                ),
              ),
            IconButton(
              tooltip: 'إرسال',
              onPressed:
                  _busy || _resolvingAction || _composer.text.trim().isEmpty
                  ? null
                  : () => unawaited(_send()),
              icon: const Icon(Icons.send_rounded),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleListening(AssistantVoiceEngine voice) async {
    _activeVoice = voice;
    if (voice.isListening) {
      await voice.stopListening();
      return;
    }
    _voicePrefix = _composer.text.trim();
    try {
      await voice.stopSpeaking();
      await voice.listen(
        onResult: (recognized) {
          if (!mounted) return;
          final words = recognized.trim();
          final text = words.isEmpty
              ? _voicePrefix
              : _voicePrefix.isEmpty
              ? words
              : '$_voicePrefix $words';
          _composer.value = TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length),
          );
          setState(() {});
        },
      );
    } on Object {
      if (mounted) {
        _showNotice('تحقق من إذن الميكروفون وتوفر خدمة الصوت في الهاتف.');
      }
    }
  }

  Future<void> _send() async {
    if (_busy || _resolvingAction) return;
    final prompt = _composer.text.trim();
    if (prompt.isEmpty) return;
    if (prompt.length > AssistantService.maxInputLength) {
      _showNotice('السؤال أطول من الحد المسموح.');
      return;
    }
    final voice = _voiceSupported ? ref.read(assistantVoiceProvider) : null;
    if (voice?.isListening ?? false) await voice!.stopListening();
    setState(() {
      _composer.clear();
      _messages.add(_AssistantChatEntry.user(prompt));
      _busy = true;
    });
    _scrollToEnd();

    AssistantReply reply;
    final service = ref.read(assistantServiceProvider);
    if (service == null) {
      reply = const AssistantReply(
        text: 'المساعد غير متاح دون اتصال بالإنترنت أو قبل إعداد الخادم.',
      );
    } else {
      try {
        reply = await service.ask(prompt);
      } on AssistantUnavailableException catch (error) {
        reply = AssistantReply(text: error.message);
      } on Object {
        reply = const AssistantReply(
          text: 'تعذّر الاتصال بالمساعد. تحقق من الإنترنت ثم أعد المحاولة.',
        );
      }
    }
    if (!mounted) return;
    setState(() {
      _messages.add(_AssistantChatEntry.answer(reply));
      for (final action in reply.actions) {
        _resolvedActions.remove(action.id);
      }
      _busy = false;
    });
    _scrollToEnd();
  }

  Future<void> _resolveAction(
    AssistantActionPreview action,
    bool confirmed,
  ) async {
    final service = ref.read(assistantServiceProvider);
    if (service == null || _resolvingAction) return;
    setState(() => _resolvingAction = true);
    AssistantReply reply;
    try {
      reply = await service.confirmAction(action.id, confirmed: confirmed);
    } on Object {
      reply = const AssistantReply(
        text: 'تعذّر معالجة التأكيد؛ أعد فتح المحادثة.',
      );
    }
    if (!mounted) return;
    setState(() {
      _resolvedActions[action.id] = confirmed;
      _messages.add(_AssistantChatEntry.answer(reply));
      _resolvingAction = false;
    });
    _scrollToEnd();
  }

  Future<void> _speak(AssistantVoiceEngine voice, String text) async {
    if (_speakingText == text) {
      await voice.stopSpeaking();
      if (mounted) setState(() => _speakingText = null);
      return;
    }
    await voice.stopSpeaking();
    setState(() => _speakingText = text);
    try {
      await voice.speak(text);
    } on Object {
      if (mounted) _showNotice('تعذّرت قراءة الإجابة صوتياً.');
    } finally {
      if (mounted && _speakingText == text) {
        setState(() => _speakingText = null);
      }
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  void _showNotice(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _AssistantChatEntry {
  const _AssistantChatEntry.user(this.text) : reply = null, isUser = true;

  const _AssistantChatEntry.answer(this.reply) : text = '', isUser = false;

  final bool isUser;
  final String text;
  final AssistantReply? reply;
}

class _AssistantMessageTile extends StatelessWidget {
  const _AssistantMessageTile({
    required this.entry,
    required this.voice,
    required this.resolving,
    required this.resolvedActions,
    required this.onResolveAction,
    required this.onSpeak,
  });

  final _AssistantChatEntry entry;
  final AssistantVoiceEngine? voice;
  final bool resolving;
  final Map<String, bool> resolvedActions;
  final Future<void> Function(AssistantActionPreview, bool) onResolveAction;
  final Future<void> Function(AssistantVoiceEngine, String)? onSpeak;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final reply = entry.reply;
    final content = entry.isUser ? entry.text : reply?.text ?? '';
    return Align(
      alignment: entry.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.86,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: ClaySpacing.xs),
          child: ClayContainer.flat(
            color: entry.isUser ? p.surfacePressed : p.surface,
            padding: const EdgeInsets.all(ClaySpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!entry.isUser)
                  Row(
                    children: [
                      Icon(ClayIcons.assistant, size: 18, color: p.accent),
                      const SizedBox(width: ClaySpacing.xs),
                      Text('مساعد المدرسة', style: text.labelMedium),
                      const Spacer(),
                      if (voice != null &&
                          onSpeak != null &&
                          content.isNotEmpty)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: 'اقرأ الإجابة بصوت',
                          onPressed: () => unawaited(onSpeak!(voice!, content)),
                          icon: const Icon(Icons.volume_up_rounded),
                        ),
                    ],
                  ),
                if (content.isNotEmpty)
                  SelectableText(
                    content,
                    style: text.bodyMedium,
                    textAlign: TextAlign.start,
                  ),
                if (reply != null)
                  for (final action in reply.actions)
                    _AssistantActionCard(
                      action: action,
                      resolved: resolvedActions[action.id],
                      resolving: resolving,
                      onResolve: onResolveAction,
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AssistantActionCard extends StatelessWidget {
  const _AssistantActionCard({
    required this.action,
    required this.resolved,
    required this.resolving,
    required this.onResolve,
  });

  final AssistantActionPreview action;
  final bool? resolved;
  final bool resolving;
  final Future<void> Function(AssistantActionPreview, bool) onResolve;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final done = resolved != null;
    return Padding(
      padding: const EdgeInsets.only(top: ClaySpacing.sm),
      child: ClayContainer(
        depth: ClayDepth.pressed,
        padding: const EdgeInsets.all(ClaySpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(action.title, style: text.titleSmall),
            const SizedBox(height: ClaySpacing.xs),
            SelectableText(action.summary, style: text.bodySmall),
            const SizedBox(height: ClaySpacing.sm),
            if (done)
              Text(
                resolved! ? 'تم التأكيد' : 'أُلغي دون تغيير',
                style: text.labelMedium,
              )
            else
              Row(
                children: [
                  Expanded(
                    child: ClayButton(
                      label: 'تأكيد الإجراء',
                      icon: ClayIcons.check,
                      loading: resolving,
                      onPressed: resolving
                          ? null
                          : () => unawaited(onResolve(action, true)),
                    ),
                  ),
                  const SizedBox(width: ClaySpacing.sm),
                  Expanded(
                    child: ClayButton(
                      label: 'إلغاء',
                      icon: ClayIcons.close,
                      kind: ClayButtonKind.secondary,
                      onPressed: resolving
                          ? null
                          : () => unawaited(onResolve(action, false)),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _AssistantTypingIndicator extends StatelessWidget {
  const _AssistantTypingIndicator();

  @override
  Widget build(BuildContext context) => const Align(
    alignment: Alignment.centerLeft,
    child: Padding(
      padding: EdgeInsets.all(ClaySpacing.md),
      child: SizedBox.square(
        dimension: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  );
}
