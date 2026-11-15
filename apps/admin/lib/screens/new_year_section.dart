import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

/// قسم «السنة الدراسية» في الإعدادات: وقت آخر «سنة جديدة» وزرها.
///
/// الزر يؤرشف كل المجموعات النشطة، ويُبقي التلاميذ وحضورهم ومدفوعاتهم
/// وخلاص الأساتذة؛ ويشترط كتابة عبارة التأكيد لأنه لا يُتراجع عنه من
/// التطبيق.
class NewYearSection extends ConsumerWidget {
  const NewYearSection({required this.canEdit, super.key});

  final bool canEdit;

  Future<void> _start(BuildContext context, WidgetRef ref) async {
    final result = await showClayDialog<NewYearResult>(
      context,
      title: 'سنة جديدة',
      content: const _NewYearForm(),
    );
    if (result == null || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'أُرشفت ${result.archivedGroups} مجموعة، وبقي '
          '${result.retainedStudents} تلميذاً بسجلاتهم',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final last = ref.watch(lastNewYearAtProvider).value;
    return ClayCard(
      flat: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('السنة الدراسية', style: text.titleSmall),
          const SizedBox(height: ClaySpacing.xs),
          Text(
            last == null
                ? 'لم تُبدأ سنة جديدة بعد من هذا النظام.'
                : 'آخر سنة جديدة بدأت في ${_dateText(last)}.',
            style: text.bodyMedium!.copyWith(color: p.textMuted),
          ),
          const SizedBox(height: ClaySpacing.xs),
          Text(
            'تؤرشف كل المجموعات النشطة وتبقى سجلاتها، ويبقى التلاميذ '
            'وحضورهم ومدفوعاتهم وخلاص الأساتذة. تبدأ السنة الجديدة بمجموعات '
            'جديدة.',
            style: text.bodySmall!.copyWith(color: p.textMuted),
          ),
          const SizedBox(height: ClaySpacing.md),
          ClayButton(
            label: 'سنة جديدة',
            icon: ClayIcons.groups,
            kind: ClayButtonKind.danger,
            expand: true,
            onPressed: canEdit ? () => _start(context, ref) : null,
          ),
        ],
      ),
    );
  }

  static String _dateText(int millis) {
    final t = DateTime.fromMillisecondsSinceEpoch(
      millis,
      isUtc: true,
    ).toLocal();
    final d = DateKey.of(t).split('-');
    return '${d[2]}/${d[1]}/${d[0]}';
  }
}

/// نموذج التأكيد: ما سيُؤرشف، وحقل العبارة، ثم «بدء سنة جديدة» (لا يُفعَّل
/// إلا بالعبارة الصحيحة).
class _NewYearForm extends ConsumerStatefulWidget {
  const _NewYearForm();

  @override
  ConsumerState<_NewYearForm> createState() => _NewYearFormState();
}

class _NewYearFormState extends ConsumerState<_NewYearForm> {
  final _phrase = TextEditingController();
  NewYearPreview? _preview;
  bool _failed = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _phrase.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final preview = await ref.read(newYearServiceProvider).preview();
      if (mounted) setState(() => _preview = preview);
    } on Object {
      if (mounted) setState(() => _failed = true);
    }
  }

  bool get _confirmed => _phrase.text.trim() == NewYearService.confirmPhrase;

  Future<void> _submit() async {
    if (_busy || !_confirmed) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(newYearServiceProvider)
          .start(confirmation: _phrase.text);
      if (mounted) Navigator.of(context).pop(result);
    } on ValidationException catch (e) {
      if (mounted) setState(() => _error = e.errors.values.first);
    } on Object {
      if (mounted) {
        setState(() => _error = 'تعذّر بدء السنة الجديدة، أعد المحاولة');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final preview = _preview;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_failed)
          Text(
            'تعذّرت قراءة المجموعات الحالية',
            style: text.bodyMedium!.copyWith(color: p.status.danger),
          )
        else if (preview == null)
          const SizedBox(height: 48, child: ClayLoadingView())
        else ...[
          Text(
            'ستُؤرشف ${preview.activeGroups} مجموعة نشطة، وتخرج من القوائم '
            'والجداول ${preview.upcomingSessions} حصة قادمة غير منعقدة.',
            style: text.bodyMedium,
          ),
          const SizedBox(height: ClaySpacing.sm),
          Text(
            'يبقى ${preview.enrolledStudents} تلميذاً بسجلاتهم وحضورهم '
            'ومدفوعاتهم وخلاص أساتذتهم. لا يُتراجع عن هذا من التطبيق.',
            style: text.bodyMedium!.copyWith(color: p.textMuted),
          ),
        ],
        const SizedBox(height: ClaySpacing.md),
        ClayTextField(
          controller: _phrase,
          label: 'اكتب «${NewYearService.confirmPhrase}» للتأكيد',
          error: _error,
          onChanged: (_) => setState(() => _error = null),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: ClaySpacing.lg),
        ClayButton(
          label: 'بدء سنة جديدة',
          kind: ClayButtonKind.danger,
          expand: true,
          loading: _busy,
          onPressed: _confirmed && preview != null ? _submit : null,
        ),
        const SizedBox(height: ClaySpacing.sm),
        ClayButton(
          label: 'إلغاء',
          kind: ClayButtonKind.secondary,
          expand: true,
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
