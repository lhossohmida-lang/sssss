import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

/// حالة الحصة بالنسبة لوقت الآن.
enum SessionPhase {
  upcoming('لم تبدأ', ClayTone.neutral),
  ongoing('جارية الآن', ClayTone.success),
  finished('انتهت', ClayTone.info),
  closed('مغلقة', ClayTone.neutral),
  cancelled('ملغاة', ClayTone.danger);

  const SessionPhase(this.label, this.tone);

  final String label;
  final ClayTone tone;

  /// حالة [s] عند [now].
  static SessionPhase of(DaySession s, DateTime now) {
    if (s.cancelled) return cancelled;
    if (s.closed) return closed;
    final minutes = DateKey.minutesOf(now);
    if (minutes < s.session.startMinutes) return upcoming;
    if (minutes < s.session.endMinutes) return ongoing;
    return finished;
  }
}

/// الرئيسية: ترحيب وحصص اليوم بحالتها (الجارية أو التالية أولاً) وعدّادات
/// حضورها، ومنها إلى ورقة الحضور.
class TeacherHomeScreen extends ConsumerWidget {
  const TeacherHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final session = ref.watch(sessionProvider.select((s) => s.value));
    final school = ref.watch(schoolNameProvider).value ?? '';
    final now = DateTime.now();
    final today = DateKey.of(now);
    final sessions = ref.watch(myDaySessionsProvider(today));

    return ListView(
      padding: const EdgeInsets.all(ClaySpacing.screenPadding),
      children: [
        Text('أهلاً ${session?.displayName ?? ''}', style: text.headlineSmall),
        Text(
          [
            if (school.isNotEmpty) school,
            '${GroupService.weekdayName(now.weekday)} $today',
          ].join(' · '),
          style: text.bodyMedium!.copyWith(color: p.textMuted),
        ),
        const SizedBox(height: ClaySpacing.md),
        Wrap(
          spacing: ClaySpacing.sm,
          children: [
            ClayButton(
              label: 'رمزي',
              icon: ClayIcons.scan,
              kind: ClayButtonKind.secondary,
              onPressed: () => context.push('/my-qr'),
            ),
            ClayButton(
              label: 'حضوري',
              icon: ClayIcons.attendance,
              kind: ClayButtonKind.secondary,
              onPressed: () => context.push('/my-attendance'),
            ),
          ],
        ),
        const SizedBox(height: ClaySpacing.lg),
        Text('حصص اليوم', style: text.titleMedium),
        const SizedBox(height: ClaySpacing.sm),
        sessions.when(
          loading: () => const SizedBox(
            height: 320,
            child: ClaySkeletonList(count: 3, itemExtent: 96),
          ),
          error: (_, _) => ClayErrorView(
            message: 'تعذّرت قراءة حصص اليوم',
            onRetry: () => ref.invalidate(myDaySessionsProvider),
          ),
          data: (items) {
            if (items.isEmpty) {
              return const ClayEmptyView(
                title: 'لا حصص لك اليوم',
                message: 'تظهر هنا حصصك المبرمجة في هذا اليوم',
                icon: ClayIcons.schedule,
              );
            }
            return Column(
              children: [
                for (final item in items)
                  SizedBox(
                    height: 104,
                    child: _SessionTile(item: item, now: now),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.item, required this.now});

  final DaySession item;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final s = item.session;
    final phase = SessionPhase.of(item, now);
    final times =
        '${DateKey.formatMinutes(s.startMinutes)}–'
        '${DateKey.formatMinutes(s.endMinutes)}';
    return ClayListTile(
      title: 'المجموعة ${item.groupNumber} · ${item.subjectName}',
      subtitle:
          '$times · ${item.roomName ?? 'بلا قاعة'}\n'
          'حاضر ${item.present} · غائب ${item.absent} · '
          'بلا تسجيل ${item.unmarked < 0 ? 0 : item.unmarked}',
      subtitleLines: 2,
      onTap: item.cancelled
          ? () => context.push('/groups/${s.groupId}')
          : () => context.push('/attendance/${s.id}'),
      trailing: [ClayBadge(label: phase.label, tone: phase.tone)],
    );
  }
}

/// مجموعاتي: مجموعات الأستاذ النشطة بجدولها وعدد تلاميذها.
class TeacherGroupsScreen extends ConsumerWidget {
  const TeacherGroupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(myGroupsProvider);
    return groups.when(
      loading: () => const ClaySkeletonList(),
      error: (_, _) => ClayErrorView(
        message: 'تعذّرت قراءة مجموعاتك',
        onRetry: () => ref.invalidate(groupsProvider),
      ),
      data: (items) {
        if (items.isEmpty) {
          return const ClayEmptyView(
            title: 'لا مجموعات لك بعد',
            message: 'تُنشئ الإدارة مجموعاتك وتظهر هنا',
            icon: ClayIcons.groups,
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(ClaySpacing.screenPadding),
          itemCount: items.length,
          itemExtent: 112,
          itemBuilder: (context, i) {
            final g = items[i];
            return ClayListTile(
              title: 'المجموعة ${g.number} · ${g.subjectName}',
              subtitle:
                  '${g.roomName ?? 'بلا قاعة'} · ${g.studentCount} تلميذ\n'
                  '${g.scheduleText}',
              subtitleLines: 2,
              onTap: () => context.push('/groups/${g.id}'),
              trailing: const [Icon(Icons.chevron_left_rounded)],
            );
          },
        );
      },
    );
  }
}

/// تفاصيل مجموعة الأستاذ: معلوماتها وشبكة حضور دورتها.
class TeacherGroupDetailsScreen extends ConsumerWidget {
  const TeacherGroupDetailsScreen({required this.groupId, super.key});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final item = ref.watch(groupItemProvider(groupId));
    return Scaffold(
      appBar: ClayAppBar(
        title: item == null ? 'المجموعة' : 'المجموعة ${item.number}',
        showBack: true,
      ),
      body: GroupGridView(
        groupId: groupId,
        header: [
          if (item != null)
            Padding(
              padding: const EdgeInsets.only(bottom: ClaySpacing.lg),
              child: ClayCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.subjectName, style: text.titleLarge),
                    const SizedBox(height: ClaySpacing.xs),
                    Text(
                      '${item.roomName ?? 'بلا قاعة'} · '
                      '${item.studentCount} تلميذ',
                      style: text.bodyMedium,
                    ),
                    Text(
                      item.scheduleText,
                      style: text.bodySmall!.copyWith(color: p.textMuted),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// ورقة حضور حصة للأستاذ: لحصص مجموعاته فقط، يسجّل حاضراً أو غائباً (لا
/// «برخصة»؛ هي للإدارة)، وتُغلق الحصة وتُغيَّب البقية تلقائياً عند نهايتها.
class TeacherSessionRoster extends ConsumerWidget {
  const TeacherSessionRoster({required this.sessionId, super.key});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roster = ref.watch(sessionRosterProvider(sessionId));
    final groups = ref.watch(myGroupsProvider).value;
    final mine =
        roster.value != null &&
        groups != null &&
        groups.any((g) => g.id == roster.value!.session.groupId);
    if (roster.hasValue && groups != null && !mine) {
      return const Scaffold(
        appBar: ClayAppBar(title: 'ورقة الحضور', showBack: true),
        body: ClayEmptyView(
          title: 'هذه الحصة ليست من حصصك',
          icon: ClayIcons.attendance,
        ),
      );
    }
    return SessionRosterScreen(
      sessionId: sessionId,
      canWrite: true,
      canExcuse: false,
    );
  }
}

/// رمزي: رمز QR الشخصي للأستاذ يعرضه للماسح عند الدخول والخروج.
class MyQrScreen extends ConsumerWidget {
  const MyQrScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final teacher = ref.watch(myTeacherProvider);
    return Scaffold(
      appBar: const ClayAppBar(title: 'رمزي', showBack: true),
      body: teacher.when(
        loading: () => const ClayLoadingView(),
        error: (_, _) => ClayErrorView(
          message: 'تعذّرت قراءة بياناتك',
          onRetry: () => ref.invalidate(myTeacherProvider),
        ),
        data: (t) {
          if (t == null) {
            return const ClayEmptyView(title: 'لا بيانات لحسابك');
          }
          return ListView(
            padding: const EdgeInsets.all(ClaySpacing.screenPadding),
            children: [
              ClayCard(
                child: Column(
                  children: [
                    Text(t.name, style: text.titleLarge),
                    const SizedBox(height: ClaySpacing.md),
                    ClayQrCode(
                      data: t.qrCode,
                      size: 240,
                      semanticLabel: 'رمز QR للأستاذ ${t.name}',
                    ),
                    const SizedBox(height: ClaySpacing.sm),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: SelectableText(t.qrCode, style: text.bodySmall),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: ClaySpacing.md),
              Text(
                'اعرض هذا الرمز على الماسح عند دخولك قاعة الحصة، وعند خروجك '
                'منها: المسح الأول دخول والثاني خروج.',
                style: text.bodyMedium!.copyWith(color: p.textMuted),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// حضوري: كشف حصصي الشهري، ما حضرتُه وما غبتُ عنه وتأخري.
class MyAttendanceScreen extends ConsumerWidget {
  const MyAttendanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(myTeacherIdProvider);
    if (me == null) {
      return const Scaffold(
        appBar: ClayAppBar(title: 'حضوري', showBack: true),
        body: ClayLoadingView(),
      );
    }
    return TeacherMonthScreen(teacherId: me);
  }
}
