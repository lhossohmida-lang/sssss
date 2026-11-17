import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:school_core/school_core.dart';

import '../shell/providers.dart';
import 'tutorial_lessons.dart';

/// ما أنهاه صاحب الحساب من دروس الدليل، وهل عُرضت عليه الجولة الأولى.
class TutorialState {
  const TutorialState(this._tokens);

  final Set<String> _tokens;

  /// هل أنهى الدرس [lessonId]؟
  bool isDone(String lessonId) => _tokens.contains(lessonId);

  /// هل عُرضت الجولة الأولى من قبل (قُبلت أو أُجِّلت)؟
  bool get prompted => _tokens.contains(TutorialProgress.promptedMarker);

  /// عدد ما أنهاه من [lessons].
  int doneCount(Iterable<TutorialLesson> lessons) =>
      lessons.where((lesson) => isDone(lesson.id)).length;
}

/// تقدّم صاحب الحساب في الدليل، محفوظ على هذا الجهاز لكل حساب.
///
/// يُخزَّن في `device_info` المحلي (لا يُزامَن ولا شيء حساس فيه): فمن دخل بحساب آخر على
/// الجهاز نفسه رأى جولته هو، ومن غيّر هاتفه لا يضيع تقدّمه لأن المفتاح معرّف الحساب لا الهاتف.
class TutorialProgress {
  TutorialProgress(this._preferences, this._accountId);

  final DevicePreferences _preferences;
  final String _accountId;

  /// علامة تعني أن الجولة الأولى عُرضت على صاحب الحساب.
  static const String promptedMarker = '_prompted';

  String get _key => 'tutorial_$_accountId';

  static TutorialState _parse(String? raw) => TutorialState({
    if (raw != null)
      for (final part in raw.split(','))
        if (part.trim().isNotEmpty) part.trim(),
  });

  Future<TutorialState> load() async => _parse(await _preferences.read(_key));

  /// الحالة وتتحدث مع كل تغيير.
  Stream<TutorialState> watch() => _preferences.watch(_key).map(_parse);

  /// يسجّل أن الدرس [lessonId] اكتمل.
  Future<void> markDone(String lessonId) => _add(lessonId);

  /// يسجّل أن الجولة الأولى عُرضت، فلا تُعرض مرة أخرى تلقائياً.
  Future<void> markPrompted() => _add(promptedMarker);

  Future<void> _add(String token) async {
    final saved = await _preferences.read(_key);
    final tokens = {
      if (saved != null)
        for (final part in saved.split(','))
          if (part.trim().isNotEmpty) part.trim(),
    };
    if (!tokens.add(token)) return;
    await _preferences.write(_key, (tokens.toList()..sort()).join(','));
  }
}

/// هل تُعرض الجولة الأولى تلقائياً بعد الدخول؟ تعطّلها الاختبارات الافتراضية حتى لا
/// تعترض شاشاتها.
final Provider<bool> tutorialWelcomeEnabledProvider = Provider<bool>(
  (ref) => true,
);

/// تقدّم الحساب الحالي، أو `null` قبل الدخول.
final Provider<TutorialProgress?> tutorialProgressProvider =
    Provider<TutorialProgress?>((ref) {
      final account = ref.watch(
        sessionProvider.select((s) => s.value?.accountId),
      );
      if (account == null) return null;
      return TutorialProgress(
        DevicePreferences(ref.watch(runtimeProvider).db),
        account,
      );
    });

/// حالة الدليل للحساب الحالي (فارغة قبل الدخول).
final tutorialStateProvider = StreamProvider.autoDispose<TutorialState>((ref) {
  final progress = ref.watch(tutorialProgressProvider);
  if (progress == null) return Stream.value(const TutorialState({}));
  return progress.watch();
});
