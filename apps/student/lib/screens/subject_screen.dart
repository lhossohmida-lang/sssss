import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

/// مادة الابن: بطاقتها (المادة والأستاذ والمجموعة)، ثم نتائجه في اختباراتها
/// ومتوسطه، ثم ملفاتها (دروس وتمارين) يفتحها بالضغط.
class SubjectScreen extends ConsumerWidget {
  const SubjectScreen({required this.groupId, super.key});

  final String groupId;

  static const double _gradeHeight = 96;
  static const double _fileHeight = 96;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final child = ref.watch(selectedChildProvider);
    final profile = child == null
        ? null
        : ref.watch(studentProfileProvider(child.id)).value;
    EnrolmentInfo? info;
    for (final e in profile?.enrolments ?? const <EnrolmentInfo>[]) {
      if (e.groupId == groupId) info = e;
    }
    if (child == null || (profile != null && info == null)) {
      return const Scaffold(
        appBar: ClayAppBar(title: 'المادة', showBack: true),
        body: ClayEmptyView(
          title: 'هذه المادة ليست من مواد ابنك',
          icon: ClayIcons.subjects,
        ),
      );
    }
    final grades = ref.watch(
      childGradesProvider((studentId: child.id, groupId: groupId)),
    );
    final files = ref.watch(groupFilesProvider(groupId));
    return Scaffold(
      appBar: ClayAppBar(title: info?.subjectName ?? 'المادة', showBack: true),
      body: CustomScrollView(
        slivers: [
          if (info != null)
            SliverPadding(
              padding: const EdgeInsets.all(ClaySpacing.screenPadding),
              sliver: SliverToBoxAdapter(
                child: ClayCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(info.subjectName, style: text.titleLarge),
                      Text(
                        'المجموعة ${info.groupNumber} · '
                        'الأستاذ ${info.teacherName}',
                        style: text.bodyMedium!.copyWith(color: p.textMuted),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ..._gradesSection(context, grades, ref),
          ..._filesSection(context, files, ref),
          const SliverToBoxAdapter(child: SizedBox(height: ClaySpacing.xl)),
        ],
      ),
    );
  }

  List<Widget> _gradesSection(
    BuildContext context,
    AsyncValue<List<ChildGrade>> grades,
    WidgetRef ref,
  ) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    return grades.when(
      loading: () => const [
        SliverToBoxAdapter(
          child: SizedBox(height: 80, child: ClayLoadingView()),
        ),
      ],
      error: (_, _) => [
        SliverToBoxAdapter(
          child: SizedBox(
            height: 160,
            child: ClayErrorView(
              message: 'تعذّرت قراءة النتائج',
              onRetry: () => ref.invalidate(childGradesProvider),
            ),
          ),
        ),
      ],
      data: (list) {
        final average = GradeService.averageOutOf20(list);
        return [
          SliverPadding(
            padding: const EdgeInsets.symmetric(
              horizontal: ClaySpacing.screenPadding,
            ),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Expanded(child: Text('النتائج', style: text.titleSmall)),
                  if (average != null)
                    ClayBadge(
                      label:
                          'المتوسط ${GradeService.format(double.parse(average.toStringAsFixed(2)))}/20',
                      tone: ClayTone.info,
                    ),
                ],
              ),
            ),
          ),
          if (list.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(ClaySpacing.screenPadding),
                child: Text('لم تُدخل نتائج لهذه المادة بعد'),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: ClaySpacing.screenPadding,
              ),
              sliver: SliverFixedExtentList(
                itemExtent: _gradeHeight,
                delegate: SliverChildBuilderDelegate((context, i) {
                  final g = list[i];
                  return ClayListTile(
                    title: g.title,
                    subtitle: g.note.isEmpty ? g.date : '${g.date} · ${g.note}',
                    subtitleLines: 2,
                    trailing: [
                      Text(
                        '${GradeService.format(g.score)}/'
                        '${GradeService.format(g.maxScore)}',
                        style: text.titleSmall!.copyWith(color: p.accent),
                      ),
                    ],
                  );
                }, childCount: list.length),
              ),
            ),
        ];
      },
    );
  }

  List<Widget> _filesSection(
    BuildContext context,
    AsyncValue<List<GroupFileItem>> files,
    WidgetRef ref,
  ) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    return files.when(
      loading: () => const [],
      error: (_, _) => const [],
      data: (list) => [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            ClaySpacing.screenPadding,
            ClaySpacing.lg,
            ClaySpacing.screenPadding,
            0,
          ),
          sliver: SliverToBoxAdapter(
            child: Text('الملفات', style: text.titleSmall),
          ),
        ),
        if (list.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(ClaySpacing.screenPadding),
              child: Text('لم يرفع الأستاذ ملفات بعد'),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(
              horizontal: ClaySpacing.screenPadding,
            ),
            sliver: SliverFixedExtentList(
              itemExtent: _fileHeight,
              delegate: SliverChildBuilderDelegate((context, i) {
                final f = list[i];
                return ClayListTile(
                  title: f.title,
                  subtitle: '${f.fileName} · ${fileSizeText(f.sizeBytes)}',
                  subtitleLines: 2,
                  leading: Icon(
                    f.isPdf ? ClayIcons.files : ClayIcons.receipt,
                    color: p.accent,
                  ),
                  onTap: () => openGroupFile(context, ref, f),
                );
              }, childCount: list.length),
            ),
          ),
      ],
    );
  }
}
