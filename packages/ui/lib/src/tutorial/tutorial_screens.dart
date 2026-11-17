import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:school_core/school_core.dart';

import '../clay/clay_button.dart';
import '../clay/clay_container.dart';
import '../clay/clay_display.dart';
import '../clay/clay_icons.dart';
import '../clay/clay_navigation.dart';
import '../shell/list_page.dart';
import '../shell/providers.dart';
import '../theme/clay_theme.dart';
import '../theme/clay_tokens.dart';
import 'tutorial_lessons.dart';
import 'tutorial_progress.dart';

/// مسارات الدليل.
abstract final class HelpRoutes {
  /// قائمة الدروس.
  static const String list = '/help';

  /// نمط مسار الدرس.
  static const String lessonPattern = '/help/:id';

  static String lesson(String id) => '/help/$id';
}

/// التطبيق الذي تعمل عليه الواجهة، ومنه تُختار دروسه.
final Provider<AppIdentity> _appProvider = Provider<AppIdentity>(
  (ref) => ref.watch(runtimeProvider.select((r) => r.app)),
);

/// «دليل الاستخدام»: دروس قصيرة تعلّم استعمال التطبيق، وما أُنجز منها.
class HelpScreen extends ConsumerWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final app = ref.watch(_appProvider);
    final lessons = TutorialCatalog.forApp(app);
    final state =
        ref.watch(tutorialStateProvider).value ?? const TutorialState({});
    final done = state.doneCount(lessons);
    return Scaffold(
      appBar: const ClayAppBar(title: 'دليل الاستخدام', showBack: true),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(ClaySpacing.screenPadding),
            children: [
              ClayCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('تعلّم استعمال التطبيق', style: text.titleLarge),
                    const SizedBox(height: ClaySpacing.xs),
                    Text(
                      'دروس قصيرة، كل درس بضع خطوات بلغة بسيطة. ابدأ بالجولة '
                      'السريعة ثم افتح ما يهمّك.',
                      style: text.bodyMedium!.copyWith(color: p.textMuted),
                    ),
                    const SizedBox(height: ClaySpacing.md),
                    Text(
                      'أنهيت $done من ${lessons.length}',
                      style: text.titleSmall,
                    ),
                    const SizedBox(height: ClaySpacing.xs),
                    LinearProgressIndicator(
                      value: lessons.isEmpty ? 0 : done / lessons.length,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: ClaySpacing.lg),
              for (final lesson in lessons)
                ClayListTile(
                  title: lesson.title,
                  subtitle: lesson.summary,
                  leading: Icon(lesson.icon, color: p.accent),
                  trailing: [
                    if (state.isDone(lesson.id))
                      const ClayBadge(label: 'تم', tone: ClayTone.success),
                  ],
                  onTap: () => context.push(HelpRoutes.lesson(lesson.id)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// درس واحد بخطواته: خطوة في كل شاشة، و«تم» في آخرها تسجّله منتهياً.
class LessonScreen extends ConsumerStatefulWidget {
  const LessonScreen({required this.lessonId, super.key});

  final String lessonId;

  @override
  ConsumerState<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends ConsumerState<LessonScreen> {
  int _step = 0;
  bool _finishing = false;

  Future<void> _finish(TutorialLesson lesson) async {
    if (_finishing) return;
    setState(() => _finishing = true);
    await ref.read(tutorialProgressProvider)?.markDone(lesson.id);
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(HelpRoutes.list);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final app = ref.watch(_appProvider);
    final lesson = TutorialCatalog.find(app, widget.lessonId);
    if (lesson == null) {
      return const Scaffold(
        appBar: ClayAppBar(title: 'دليل الاستخدام', showBack: true),
        body: ClayEmptyView(
          title: 'هذا الدرس غير موجود',
          message: 'افتح دليل الاستخدام واختر درساً من القائمة',
        ),
      );
    }
    final steps = lesson.steps;
    final index = _step.clamp(0, steps.length - 1);
    final step = steps[index];
    final last = index == steps.length - 1;
    return Scaffold(
      appBar: ClayAppBar(title: lesson.title, showBack: true),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Padding(
            padding: const EdgeInsets.all(ClaySpacing.screenPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  label: 'الخطوة ${index + 1} من ${steps.length}',
                  child: LinearProgressIndicator(
                    value: (index + 1) / steps.length,
                  ),
                ),
                const SizedBox(height: ClaySpacing.sm),
                Text(
                  'الخطوة ${index + 1} من ${steps.length}',
                  style: text.bodySmall!.copyWith(color: p.textMuted),
                ),
                const SizedBox(height: ClaySpacing.md),
                Expanded(
                  child: SingleChildScrollView(
                    child: ClayCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(lesson.icon, color: p.accent),
                              const SizedBox(width: ClaySpacing.sm),
                              Expanded(
                                child: Semantics(
                                  header: true,
                                  child: Text(
                                    step.title,
                                    style: text.titleLarge,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: ClaySpacing.md),
                          Text(
                            step.body,
                            style: text.bodyLarge!.copyWith(height: 1.7),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: ClaySpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: ClayButton(
                        label: 'السابق',
                        kind: ClayButtonKind.secondary,
                        expand: true,
                        onPressed: index == 0
                            ? null
                            : () => setState(() => _step = index - 1),
                      ),
                    ),
                    const SizedBox(width: ClaySpacing.md),
                    Expanded(
                      child: ClayButton(
                        label: last ? 'تم' : 'التالي',
                        icon: last ? ClayIcons.check : null,
                        expand: true,
                        loading: _finishing,
                        onPressed: last
                            ? () => _finish(lesson)
                            : () => setState(() => _step = index + 1),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// بطاقة الجولة الأولى: تُعرض مرة واحدة لكل حساب على الجهاز، ثم تبقى المساعدة في زر «؟»
/// وفي «حسابي».
class TutorialWelcomeBanner extends ConsumerWidget {
  const TutorialWelcomeBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(tutorialWelcomeEnabledProvider)) {
      return const SizedBox.shrink();
    }
    final progress = ref.watch(tutorialProgressProvider);
    final state = ref.watch(tutorialStateProvider).value;
    // لا تُعرض قبل أن تُقرأ الحالة حتى لا تومض ثم تختفي.
    if (progress == null || state == null || state.prompted) {
      return const SizedBox.shrink();
    }
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ClaySpacing.screenPadding,
        ClaySpacing.sm,
        ClaySpacing.screenPadding,
        0,
      ),
      child: ClayCard(
        flat: true,
        padding: const EdgeInsets.all(ClaySpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(ClayIcons.help, color: p.accent),
                const SizedBox(width: ClaySpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('جديد في التطبيق؟', style: text.titleSmall),
                      Text(
                        'جولة قصيرة (دقيقتان) تعرّفك على أقسامه.',
                        style: text.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: ClaySpacing.sm),
            Row(
              children: [
                Expanded(
                  child: ClayButton(
                    label: 'ليس الآن',
                    kind: ClayButtonKind.secondary,
                    expand: true,
                    onPressed: progress.markPrompted,
                  ),
                ),
                const SizedBox(width: ClaySpacing.sm),
                Expanded(
                  child: ClayButton(
                    label: 'ابدأ الجولة',
                    expand: true,
                    onPressed: () async {
                      await progress.markPrompted();
                      if (context.mounted) {
                        await context.push(
                          HelpRoutes.lesson(TutorialCatalog.welcomeId),
                        );
                      }
                    },
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

/// زر «؟» في شريط التبويب: يفتح درس القسم الحالي، أو دليل الدروس إن لم يكن له درس.
class HelpButton extends ConsumerWidget {
  const HelpButton({required this.tabPath, super.key});

  /// مسار التبويب الحالي، مثل `/students`.
  final String tabPath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    return IconButton(
      tooltip: 'شرح هذه الشاشة',
      icon: Icon(ClayIcons.help, color: p.text),
      onPressed: () {
        final lesson = TutorialCatalog.forTab(ref.read(_appProvider), tabPath);
        context.push(
          lesson == null ? HelpRoutes.list : HelpRoutes.lesson(lesson.id),
        );
      },
    );
  }
}
