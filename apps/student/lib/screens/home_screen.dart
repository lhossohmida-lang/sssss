import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

/// رئيسية الوليّ: مبدّل الأبناء، وملخص الابن المختار (اسمه ومستواه وما
/// بقي عليه)، وبطاقة لكل مادة ينتسب إليها بأستاذها وحضوره فيها.
class ParentHomeScreen extends ConsumerWidget {
  const ParentHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final children = ref.watch(childrenProvider);
    final child = ref.watch(selectedChildProvider);
    return children.when(
      loading: () => const ClaySkeletonList(),
      error: (_, _) => ClayErrorView(
        message: 'تعذّرت قراءة بيانات أبنائك',
        onRetry: () => ref.invalidate(childrenProvider),
      ),
      data: (_) {
        if (child == null) {
          return const ClayEmptyView(
            title: 'لا أبناء مرتبطون بحسابك',
            message: 'تواصل مع المدرسة لربط أبنائك بحسابك',
            icon: ClayIcons.students,
          );
        }
        return Column(
          children: [
            const ChildSwitcher(),
            Expanded(child: _ChildHome(studentId: child.id)),
          ],
        );
      },
    );
  }
}

class _ChildHome extends ConsumerWidget {
  const _ChildHome({required this.studentId});

  final String studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(studentProfileProvider(studentId));
    return profile.when(
      loading: () => const ClaySkeletonList(),
      error: (_, _) => ClayErrorView(
        message: 'تعذّرت قراءة بيانات ابنك',
        onRetry: () => ref.invalidate(studentProfileProvider),
      ),
      data: (data) {
        if (data == null) {
          return const ClayEmptyView(title: 'هذا التلميذ غير موجود');
        }
        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(ClaySpacing.screenPadding),
              sliver: SliverToBoxAdapter(child: _Summary(profile: data)),
            ),
            if (data.enrolments.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: ClayEmptyView(
                  title: 'لا مواد بعد',
                  message: 'لم ينتسب بعد إلى أي مجموعة',
                  icon: ClayIcons.subjects,
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(
                  horizontal: ClaySpacing.screenPadding,
                ),
                sliver: SliverFixedExtentList(
                  itemExtent: _SubjectCard.height,
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => _SubjectCard(info: data.enrolments[i]),
                    childCount: data.enrolments.length,
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: ClaySpacing.xl)),
          ],
        );
      },
    );
  }
}

/// بطاقة الابن: اسمه وصورته ومستواه ومجموع ما بقي عليه.
class _Summary extends StatelessWidget {
  const _Summary({required this.profile});

  final StudentProfile profile;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final remaining = profile.totalRemaining;
    return ClayCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClayAvatar(
                name: profile.fullName,
                image: localPhoto(profile.student.photoLocalPath),
                size: 56,
              ),
              const SizedBox(width: ClaySpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(profile.fullName, style: text.titleLarge),
                    if (profile.levelName != null)
                      Text(
                        profile.levelName!,
                        style: text.bodyMedium!.copyWith(color: p.textMuted),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: ClaySpacing.md),
          if (remaining > 0) ...[
            Text('المتبقي عليه', style: text.bodyMedium),
            Text(
              Money.format(remaining),
              style: text.headlineSmall!.copyWith(color: p.status.warning),
            ),
          ] else
            Row(
              children: [
                Icon(ClayIcons.check, color: p.status.success, size: 20),
                const SizedBox(width: ClaySpacing.xs),
                Text(
                  'لا مبالغ متبقية عليه',
                  style: text.bodyMedium!.copyWith(color: p.status.success),
                ),
              ],
            ),
          const SizedBox(height: ClaySpacing.md),
          ClayButton(
            label: 'رمز الدخول QR',
            icon: ClayIcons.scan,
            kind: ClayButtonKind.secondary,
            expand: true,
            onPressed: () => context.push('/qr'),
          ),
          if (profile.waiting.isNotEmpty) ...[
            const SizedBox(height: ClaySpacing.sm),
            Wrap(
              spacing: ClaySpacing.sm,
              runSpacing: ClaySpacing.xs,
              children: [
                for (final w in profile.waiting)
                  ClayBadge(
                    label: 'ينتظر: ${w.subjectName}',
                    tone: ClayTone.info,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// بطاقة مادة: المادة وأستاذها ومجموعتها، وحضوره فيها وما بقي من دفعها.
class _SubjectCard extends StatelessWidget {
  const _SubjectCard({required this.info});

  /// ارتفاع البطاقة الثابت (قائمة بارتفاع ثابت للأداء).
  static const double height = 148;

  final EnrolmentInfo info;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: ClaySpacing.sm),
      child: ClayCard(
        flat: true,
        padding: const EdgeInsets.all(ClaySpacing.md),
        onTap: () => context.push('/subjects/${info.groupId}'),
        semanticLabel:
            '${info.subjectName}، المجموعة ${info.groupNumber}، '
            'الأستاذ ${info.teacherName}',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              info.subjectName,
              style: text.titleMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              'المجموعة ${info.groupNumber} · الأستاذ ${info.teacherName}',
              style: text.bodySmall!.copyWith(color: p.textMuted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const Spacer(),
            Wrap(
              spacing: ClaySpacing.sm,
              runSpacing: ClaySpacing.xs,
              children: [
                ClayBadge(label: 'حضر ${info.present}', tone: ClayTone.success),
                ClayBadge(label: 'غاب ${info.absent}', tone: ClayTone.danger),
                if (info.excused > 0)
                  ClayBadge(
                    label: 'برخصة ${info.excused}',
                    tone: ClayTone.excused,
                  ),
                if (info.remaining > 0)
                  ClayBadge(
                    label: 'متبقٍ ${Money.format(info.remaining)}',
                    tone: ClayTone.warning,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
