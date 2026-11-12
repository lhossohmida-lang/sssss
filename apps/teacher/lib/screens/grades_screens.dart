import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

/// نتائج المجموعة: اختباراتها بمتوسطاتها، ومنها إدخال اختبار جديد أو تعديل
/// اختبار سابق.
class GradesScreen extends ConsumerWidget {
  const GradesScreen({required this.groupId, super.key});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final item = ref.watch(groupItemProvider(groupId));
    final assessments = ref.watch(assessmentsProvider(groupId));
    return Scaffold(
      appBar: ClayAppBar(
        title: item == null ? 'النتائج' : 'نتائج المجموعة ${item.number}',
        showBack: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: assessments.when(
              loading: () => const ClaySkeletonList(),
              error: (_, _) => ClayErrorView(
                message: 'تعذّرت قراءة النتائج',
                onRetry: () => ref.invalidate(assessmentsProvider),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return const ClayEmptyView(
                    title: 'لا نتائج بعد',
                    message: 'أدخل نتائج اختبار لتلاميذ مجموعتك دفعة واحدة',
                    icon: ClayIcons.attendance,
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(ClaySpacing.screenPadding),
                  itemCount: items.length,
                  itemExtent: 96,
                  itemBuilder: (context, i) {
                    final a = items[i];
                    return ClayListTile(
                      title: a.title,
                      subtitle: '${a.date} · ${a.count} نتيجة',
                      onTap: () => context.push(
                        Uri(
                          path: '/groups/$groupId/grades/edit',
                          queryParameters: {
                            'title': a.title,
                            'date': a.date,
                            'max': GradeService.format(a.maxScore),
                          },
                        ).toString(),
                      ),
                      trailing: [
                        Text(
                          'المتوسط ${GradeService.format(double.parse(a.average.toStringAsFixed(2)))}'
                          '/${GradeService.format(a.maxScore)}',
                          style: text.labelLarge!.copyWith(color: p.accent),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(ClaySpacing.screenPadding),
            child: ClayButton(
              label: 'اختبار جديد',
              icon: ClayIcons.add,
              expand: true,
              onPressed: () => context.push('/groups/$groupId/grades/edit'),
            ),
          ),
        ],
      ),
    );
  }
}

/// إدخال اختبار أو تعديله: العنوان والتاريخ والسلّم، ثم علامة وملاحظة لكل
/// تلميذ؛ ومن تُترك علامته فارغة لا نتيجة له.
class AssessmentFormScreen extends ConsumerStatefulWidget {
  const AssessmentFormScreen({
    required this.groupId,
    this.title,
    this.date,
    this.maxScore,
    super.key,
  });

  final String groupId;

  /// سلّم الاختبار القائم (نص رقم)؛ 20 افتراضاً.
  final String? maxScore;

  /// عنوان وتاريخ اختبار قائم للتعديل؛ `null` لاختبار جديد.
  final String? title;
  final String? date;

  @override
  ConsumerState<AssessmentFormScreen> createState() =>
      _AssessmentFormScreenState();
}

class _AssessmentFormScreenState extends ConsumerState<AssessmentFormScreen> {
  late final _title = TextEditingController(text: widget.title ?? '');
  late final _max = TextEditingController(text: widget.maxScore ?? '20');
  late String _date = widget.date ?? GradeService.today();
  final Map<String, TextEditingController> _scores = {};
  final Map<String, TextEditingController> _notes = {};
  bool _filled = false;
  bool _saving = false;
  Map<String, String> _errors = const {};

  bool get _editing => widget.title != null;

  @override
  void dispose() {
    _title.dispose();
    _max.dispose();
    for (final c in [..._scores.values, ..._notes.values]) {
      c.dispose();
    }
    super.dispose();
  }

  static double? _parse(String raw) =>
      double.tryParse(raw.trim().replaceAll(',', '.'));

  void _fill(List<GradeEntry> entries) {
    if (_filled) return;
    _filled = true;
    for (final e in entries) {
      _scores[e.studentId] = TextEditingController(
        text: e.score == null ? '' : GradeService.format(e.score!),
      );
      _notes[e.studentId] = TextEditingController(text: e.note);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showClayDatePicker(
      context,
      title: 'تاريخ الاختبار',
      initial: DateKey.parse(_date),
    );
    if (picked != null) setState(() => _date = DateKey.of(picked));
  }

  Future<void> _save() async {
    final me = ref.read(myTeacherIdProvider);
    if (me == null || _saving) return;
    final max = _parse(_max.text);
    // علامة غير رقمية تُعرض خطأً على حقلها.
    final bad = <String, String>{};
    final results = <String, GradeInput>{};
    for (final entry in _scores.entries) {
      final raw = entry.value.text.trim();
      final score = raw.isEmpty ? null : _parse(raw);
      if (raw.isNotEmpty && score == null) {
        bad[GradeService.fieldScore(entry.key)] = 'أدخل رقماً';
      }
      results[entry.key] = (score: score, note: _notes[entry.key]!.text);
    }
    if (max == null) bad[GradeService.fieldMax] = 'أدخل السلّم رقماً';
    if (bad.isNotEmpty) {
      setState(() => _errors = bad);
      return;
    }
    setState(() {
      _saving = true;
      _errors = const {};
    });
    try {
      await ref
          .read(gradeServiceProvider)
          .saveAssessment(
            groupId: widget.groupId,
            title: _title.text,
            date: _date,
            results: results,
            maxScore: max!,
            teacherId: me,
            originalTitle: widget.title,
            originalDate: widget.date,
          );
      if (mounted) context.pop();
    } on ValidationException catch (e) {
      if (mounted) setState(() => _errors = e.errors);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final me = ref.read(myTeacherIdProvider);
    final ok = await showClayConfirm(
      context,
      title: 'حذف الاختبار',
      message: 'ستُحذف كل نتائج «${widget.title}» لهذه المجموعة.',
      confirmLabel: 'حذف',
      danger: true,
    );
    if (!ok || me == null || !mounted) return;
    await ref
        .read(gradeServiceProvider)
        .deleteAssessment(
          widget.groupId,
          title: widget.title!,
          date: widget.date!,
          teacherId: me,
        );
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final entries = ref.watch(
      gradeEntriesProvider((
        groupId: widget.groupId,
        title: widget.title ?? '',
        date: widget.date ?? '',
      )),
    );
    return Scaffold(
      appBar: ClayAppBar(
        title: _editing ? 'تعديل الاختبار' : 'اختبار جديد',
        showBack: true,
        actions: [
          if (_editing)
            IconButton(
              tooltip: 'حذف الاختبار',
              icon: const Icon(ClayIcons.delete),
              onPressed: _delete,
            ),
        ],
      ),
      body: entries.when(
        loading: () => const ClayLoadingView(),
        error: (_, _) => ClayErrorView(
          message: 'تعذّرت قراءة التلاميذ',
          onRetry: () => ref.invalidate(gradeEntriesProvider),
        ),
        data: (list) {
          _fill(list);
          return ListView(
            padding: const EdgeInsets.all(ClaySpacing.screenPadding),
            children: [
              ClayTextField(
                controller: _title,
                label: 'عنوان الاختبار',
                error: _errors[GradeService.fieldTitle],
              ),
              const SizedBox(height: ClaySpacing.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ClayButton(
                      label: 'التاريخ: $_date',
                      icon: ClayIcons.schedule,
                      kind: ClayButtonKind.secondary,
                      onPressed: _pickDate,
                    ),
                  ),
                  const SizedBox(width: ClaySpacing.sm),
                  SizedBox(
                    width: 120,
                    child: ClayTextField(
                      controller: _max,
                      label: 'السلّم',
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textDirection: TextDirection.ltr,
                      error: _errors[GradeService.fieldMax],
                    ),
                  ),
                ],
              ),
              if (_errors[GradeService.fieldDate] != null)
                Text(
                  _errors[GradeService.fieldDate]!,
                  style: text.bodySmall!.copyWith(color: p.status.danger),
                ),
              if (_errors[GradeService.fieldGroup] != null)
                Text(
                  _errors[GradeService.fieldGroup]!,
                  style: text.bodySmall!.copyWith(color: p.status.danger),
                ),
              const SizedBox(height: ClaySpacing.lg),
              Text('علامات التلاميذ', style: text.titleSmall),
              const SizedBox(height: ClaySpacing.sm),
              if (list.isEmpty)
                const ClayEmptyView(
                  title: 'لا تلاميذ في هذه المجموعة',
                  icon: ClayIcons.students,
                ),
              for (final e in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: ClaySpacing.md),
                  child: ClayCard(
                    flat: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.name, style: text.titleSmall),
                        const SizedBox(height: ClaySpacing.xs),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 110,
                              child: ClayTextField(
                                controller: _scores[e.studentId],
                                hint: 'العلامة',
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                textDirection: TextDirection.ltr,
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp('[0-9.,]'),
                                  ),
                                ],
                                error:
                                    _errors[GradeService.fieldScore(
                                      e.studentId,
                                    )],
                              ),
                            ),
                            const SizedBox(width: ClaySpacing.sm),
                            Expanded(
                              child: ClayTextField(
                                controller: _notes[e.studentId],
                                hint: 'ملاحظة (اختيارية)',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: ClaySpacing.md),
              ClayButton(
                label: 'حفظ النتائج',
                icon: ClayIcons.check,
                expand: true,
                loading: _saving,
                onPressed: _save,
              ),
            ],
          );
        },
      ),
    );
  }
}
