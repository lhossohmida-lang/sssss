import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

/// تسجيل الحضور السابق: حصص الدورة الحالية التي انعقدت قبل أن تبدأ المدرسة
/// باستعمال النظام، مع حضور تلاميذها. تقترح الشاشة حصصاً من جدول الفوج ابتداءً
/// من تاريخ أول حصة في الدورة، ويصحّح المدير الخانات ثم يحفظ كل شيء دفعة واحدة.
class PastSessionsScreen extends ConsumerStatefulWidget {
  const PastSessionsScreen({required this.groupId, super.key});

  final String groupId;

  @override
  ConsumerState<PastSessionsScreen> createState() => _PastSessionsScreenState();
}

class _PastSessionsScreenState extends ConsumerState<PastSessionsScreen> {
  static const double _nameWidth = 150;
  static const double _cellWidth = 72;
  static const double _rowHeight = 52;
  static const double _headerHeight = 64;

  late DateTime _today;
  late DateTime _from;
  bool _loading = true;
  bool _saving = false;
  String? _loadError;
  String? _formError;
  int _capacity = 0;
  List<PastRosterStudent> _roster = const [];
  List<PastSessionSuggestion> _suggested = const [];
  final List<PastSessionSuggestion> _custom = [];
  final Set<String> _chosen = {};

  /// مفتاح الحصة ← (معرّف التلميذ ← حالته؛ `null` = لا تسجيل).
  final Map<String, Map<String, AttendanceStatus?>> _marks = {};

  PastSessionsService get _service => ref.read(pastSessionsServiceProvider);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _today = DateTime(now.year, now.month, now.day);
    _from = _today.subtract(const Duration(days: 14));
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final capacity = await _service.capacity(widget.groupId);
      final roster = await _service.roster(widget.groupId);
      final suggested = await _suggest(_from);
      if (!mounted) return;
      setState(() {
        _capacity = capacity;
        _roster = roster;
        _suggested = suggested;
        _chosen
          ..clear()
          ..addAll(suggested.map((s) => s.key));
        _loading = false;
      });
    } on ValidationException catch (e) {
      if (mounted) {
        setState(() {
          _loadError = e.toString();
          _loading = false;
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _loadError = 'تعذّرت قراءة بيانات الفوج';
          _loading = false;
        });
      }
    }
  }

  Future<List<PastSessionSuggestion>> _suggest(DateTime from) => _service
      .suggest(widget.groupId, from: DateKey.of(from), now: DateTime.now());

  Future<void> _pickFrom() async {
    final picked = await showClayDatePicker(
      context,
      title: 'تاريخ أول حصة في الدورة الحالية',
      initial: _from,
    );
    if (picked == null || !mounted) return;
    if (!picked.isBefore(_today)) {
      setState(() => _formError = 'اختر تاريخاً قبل اليوم');
      return;
    }
    final suggested = await _suggest(picked);
    if (!mounted) return;
    setState(() {
      _formError = null;
      _from = picked;
      _suggested = suggested;
      _chosen
        ..clear()
        ..addAll(suggested.map((s) => s.key))
        ..addAll(_custom.map((s) => s.key));
    });
  }

  Future<void> _addCustom() async {
    final date = await showClayDatePicker(
      context,
      title: 'تاريخ الحصة',
      initial: _today.subtract(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    if (!date.isBefore(_today)) {
      setState(() => _formError = 'اختر تاريخاً قبل اليوم');
      return;
    }
    final start = await showClayTimePicker(context, title: 'وقت البداية');
    if (start == null || !mounted) return;
    final end = await showClayTimePicker(
      context,
      title: 'وقت النهاية',
      initial: start + 90,
    );
    if (end == null || !mounted) return;
    if (end <= start) {
      setState(() => _formError = 'وقت النهاية يجب أن يكون بعد البداية');
      return;
    }
    final session = PastSessionSuggestion(
      date: DateKey.of(date),
      startMinutes: start,
      endMinutes: end,
    );
    if (_sessions.any((s) => s.key == session.key)) {
      setState(() => _formError = 'هذه الحصة مضافة من قبل');
      return;
    }
    setState(() {
      _formError = null;
      _custom.add(session);
      _chosen.add(session.key);
    });
  }

  List<PastSessionSuggestion> get _sessions {
    final byKey = {
      for (final s in [..._suggested, ..._custom]) s.key: s,
    };
    return byKey.values.toList()..sort(_byTime);
  }

  List<PastSessionSuggestion> get _picked => [
    for (final s in _sessions)
      if (_chosen.contains(s.key)) s,
  ];

  static int _byTime(PastSessionSuggestion a, PastSessionSuggestion b) {
    final byDate = a.date.compareTo(b.date);
    return byDate != 0 ? byDate : a.startMinutes.compareTo(b.startMinutes);
  }

  Map<String, AttendanceStatus?> _marksOf(String key) => _marks.putIfAbsent(
    key,
    () => {for (final s in _roster) s.studentId: AttendanceStatus.present},
  );

  AttendanceStatus? _next(AttendanceStatus? current, {required bool excuse}) =>
      switch (current) {
        AttendanceStatus.present => AttendanceStatus.absent,
        AttendanceStatus.absent => excuse ? AttendanceStatus.excused : null,
        AttendanceStatus.excused => null,
        null => AttendanceStatus.present,
      };

  void _cycle(String key, String studentId, {required bool excuse}) {
    final marks = _marksOf(key);
    setState(() => marks[studentId] = _next(marks[studentId], excuse: excuse));
  }

  void _allPresent(String key) {
    final marks = _marksOf(key);
    setState(() {
      for (final s in _roster) {
        marks[s.studentId] = AttendanceStatus.present;
      }
    });
  }

  int _count(AttendanceStatus status) =>
      [for (final s in _picked) ..._marksOf(s.key).values]
          .where((m) => m == status)
          .length;

  Future<void> _save({required bool excuse}) async {
    final picked = _picked;
    final ok = await showClayConfirm(
      context,
      title: 'تسجيل الحضور السابق',
      message:
          'ستُسجَّل ${picked.length} حصة سابقة في الدورة الحالية بحضور تلاميذها، '
          'وتُحذف من نهاية الدورة ${picked.length} حصة قادمة ليبقى عدد حصصها '
          'كما هو. لا تُرسل رسائل لأولياء التلاميذ، ويمكن تعديل أي خانة لاحقاً '
          'من شاشة الحضور.',
      confirmLabel: 'تسجيل',
    );
    if (!ok || !mounted) return;
    setState(() {
      _saving = true;
      _formError = null;
    });
    try {
      final result = await _service.record(
        widget.groupId,
        [
          for (final s in picked)
            PastSessionInput(
              date: s.date,
              startMinutes: s.startMinutes,
              endMinutes: s.endMinutes,
              marks: {
                for (final e in _marksOf(s.key).entries)
                  if (e.value != null) e.key: e.value!,
              },
            ),
        ],
        now: DateTime.now(),
        canExcuse: excuse,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'سُجِّلت ${result.sessions} حصة سابقة و${result.marks} خانة حضور',
          ),
        ),
      );
      context.pop();
    } on ValidationException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _formError = e.toString();
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _saving = false;
          _formError = 'تعذّر الحفظ، حاول مرة أخرى';
        });
      }
    }
  }

  static String _times(PastSessionSuggestion s) =>
      '${DateKey.formatMinutes(s.startMinutes)}–'
      '${DateKey.formatMinutes(s.endMinutes)}';

  static String _dayName(String date) =>
      GroupService.weekdayName(DateKey.weekday(date));

  @override
  Widget build(BuildContext context) {
    final item = ref.watch(groupItemProvider(widget.groupId));
    final excuse =
        ref.can(PermissionModule.attendance, PermissionAction.add) ||
        ref.can(PermissionModule.attendance, PermissionAction.edit);
    return Scaffold(
      appBar: ClayAppBar(
        title: item == null
            ? 'الحضور السابق'
            : 'الحضور السابق · الفوج ${item.number}',
        showBack: true,
      ),
      body: _loading
          ? const ClayLoadingView()
          : _loadError != null
          ? ClayErrorView(message: _loadError!, onRetry: _retry)
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: ListView(
                  padding: const EdgeInsets.all(ClaySpacing.screenPadding),
                  children: _content(context, item, excuse),
                ),
              ),
            ),
    );
  }

  void _retry() {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    unawaited(_load());
  }

  List<Widget> _content(BuildContext context, GroupItem? item, bool excuse) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final picked = _picked;
    final overCapacity = picked.length > _capacity;
    final canSave =
        !_saving &&
        picked.isNotEmpty &&
        !overCapacity &&
        _roster.isNotEmpty &&
        _capacity > 0;
    return [
      ClayCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item != null) Text(item.subjectName, style: text.titleLarge),
            const SizedBox(height: ClaySpacing.xs),
            Text(
              'لتدوين حصص الدورة الحالية التي انعقدت قبل بدء استعمال النظام. '
              'يمكن تسجيل $_capacity حصة سابقة على الأكثر، وتبقى حصة واحدة '
              'على الأقل لتُغلق تلقائياً.',
              style: text.bodyMedium,
            ),
          ],
        ),
      ),
      const SizedBox(height: ClaySpacing.lg),
      if (_capacity <= 0)
        const ClayEmptyView(
          title: 'لا يمكن تسجيل حصص سابقة الآن',
          message:
              'الدورة الحالية على وشك أن تكتمل، فتبقى حصصها لتُسجَّل بالطريقة '
              'العادية من شاشة الحضور.',
          icon: ClayIcons.schedule,
        )
      else if (_roster.isEmpty)
        const ClayEmptyView(
          title: 'لا تلاميذ في هذا الفوج',
          message: 'أضف التلاميذ إلى الفوج أولاً ثم سجّل حضورهم السابق',
          icon: ClayIcons.students,
        )
      else ...[
        ClayCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('تاريخ أول حصة في الدورة الحالية', style: text.titleMedium),
              const SizedBox(height: ClaySpacing.sm),
              Row(
                children: [
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(DateKey.of(_from), style: text.titleMedium),
                  ),
                  const Spacer(),
                  ClayButton(
                    label: 'تغيير التاريخ',
                    kind: ClayButtonKind.secondary,
                    onPressed: _saving ? null : _pickFrom,
                  ),
                ],
              ),
              const SizedBox(height: ClaySpacing.xs),
              Text(
                'تقترح الشاشة حصص جدول الفوج من هذا التاريخ إلى أمس. ألغِ '
                'تحديد ما لم ينعقد فعلاً، وأضف ما انعقد في وقت آخر.',
                style: text.bodySmall!.copyWith(color: p.textMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: ClaySpacing.lg),
        _sessionsCard(context),
        const SizedBox(height: ClaySpacing.lg),
        if (overCapacity)
          Padding(
            padding: const EdgeInsets.only(bottom: ClaySpacing.md),
            child: Text(
              'المحدَّد ${picked.length} حصة والمسموح $_capacity: ألغِ '
              'تحديد ${picked.length - _capacity} حصة.',
              style: TextStyle(color: p.status.danger),
            ),
          ),
        if (picked.isNotEmpty) ...[
          _grid(context, picked, excuse),
          const SizedBox(height: ClaySpacing.md),
          _summary(context, excuse: excuse),
        ],
        if (_formError != null) ...[
          const SizedBox(height: ClaySpacing.md),
          Text(_formError!, style: TextStyle(color: p.status.danger)),
        ],
        const SizedBox(height: ClaySpacing.lg),
        ClayButton(
          label: 'حفظ الحضور السابق',
          icon: ClayIcons.check,
          expand: true,
          loading: _saving,
          onPressed: canSave ? () => _save(excuse: excuse) : null,
        ),
      ],
      const SizedBox(height: ClaySpacing.xl),
    ];
  }

  Widget _sessionsCard(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final sessions = _sessions;
    return ClayCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('الحصص التي انعقدت', style: text.titleMedium),
          const SizedBox(height: ClaySpacing.sm),
          if (sessions.isEmpty)
            Text(
              'لا حصص مقترحة بين هذا التاريخ وأمس: لا جدول أسبوعي للفوج أو '
              'سُجّلت حصصها. أضف حصة يدوياً أو غيّر التاريخ.',
              style: text.bodySmall!.copyWith(color: p.textMuted),
            ),
          for (final s in sessions)
            Row(
              children: [
                ClayCheckbox(
                  value: _chosen.contains(s.key),
                  semanticLabel: 'حصة ${s.date}',
                  onChanged: _saving
                      ? null
                      : (value) => setState(() {
                          if (value) {
                            _chosen.add(s.key);
                          } else {
                            _chosen.remove(s.key);
                          }
                        }),
                ),
                const SizedBox(width: ClaySpacing.sm),
                Text(_dayName(s.date), style: text.bodyMedium),
                const SizedBox(width: ClaySpacing.sm),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(s.date, style: text.bodyMedium),
                ),
                const Spacer(),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    _times(s),
                    style: text.bodySmall!.copyWith(color: p.textMuted),
                  ),
                ),
              ],
            ),
          const SizedBox(height: ClaySpacing.sm),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: ClayButton(
              label: 'إضافة حصة بتاريخ آخر',
              icon: ClayIcons.add,
              kind: ClayButtonKind.secondary,
              onPressed: _saving ? null : _addCustom,
            ),
          ),
        ],
      ),
    );
  }

  Widget _grid(
    BuildContext context,
    List<PastSessionSuggestion> sessions,
    bool excuse,
  ) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final width = _nameWidth + sessions.length * _cellWidth;
    return ClayContainer.flat(
      padding: EdgeInsets.zero,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: width,
          child: Column(
            children: [
              Container(
                height: _headerHeight,
                color: p.surfacePressed,
                child: Row(
                  children: [
                    const SizedBox(
                      width: _nameWidth,
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: ClaySpacing.md,
                        ),
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text('التلميذ'),
                        ),
                      ),
                    ),
                    for (final s in sessions)
                      SizedBox(
                        width: _cellWidth,
                        height: _headerHeight,
                        child: Semantics(
                          button: true,
                          label: 'تسجيل كل تلاميذ حصة ${s.date} حاضرين',
                          excludeSemantics: true,
                          child: InkWell(
                            onTap: _saving ? null : () => _allPresent(s.key),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Directionality(
                                  textDirection: TextDirection.ltr,
                                  child: Text(
                                    s.date.substring(5).replaceAll('-', '/'),
                                    style: text.labelMedium,
                                  ),
                                ),
                                Text(
                                  'الكل حاضر',
                                  style: text.labelSmall!.copyWith(
                                    color: p.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              for (final student in _roster)
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: p.outline.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: _nameWidth,
                        height: _rowHeight,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: ClaySpacing.md,
                          ),
                          child: Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(
                              student.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: text.bodyMedium,
                            ),
                          ),
                        ),
                      ),
                      for (final s in sessions)
                        _PastCell(
                          width: _cellWidth,
                          height: _rowHeight,
                          studentName: student.name,
                          date: s.date,
                          status: _marksOf(s.key)[student.studentId],
                          onTap: _saving
                              ? null
                              : () => _cycle(
                                  s.key,
                                  student.studentId,
                                  excuse: excuse,
                                ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summary(BuildContext context, {required bool excuse}) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'الخانات الخضراء تُحسب حضوراً وتدخل في حساب نصيب الأستاذ: راجعها قبل '
          'الحفظ. اضغط الخانة لتبديلها: حاضر ثم غائب'
          '${excuse ? ' ثم غائب برخصة' : ''} ثم لا تسجيل (لتلميذ لم يلتحق '
          'بالفوج بعد).',
          style: text.bodySmall!.copyWith(color: p.textMuted),
        ),
        const SizedBox(height: ClaySpacing.sm),
        Wrap(
          spacing: ClaySpacing.sm,
          runSpacing: ClaySpacing.xs,
          children: [
            ClayBadge(
              label: 'حاضر ${_count(AttendanceStatus.present)}',
              tone: ClayTone.success,
            ),
            ClayBadge(
              label: 'غائب ${_count(AttendanceStatus.absent)}',
              tone: ClayTone.danger,
            ),
            ClayBadge(
              label: 'غائب برخصة ${_count(AttendanceStatus.excused)}',
              tone: ClayTone.excused,
            ),
          ],
        ),
      ],
    );
  }
}

/// خلية حضور سابق: نقرة تبدّل الحالة. الحالة تُقرأ بقارئ الشاشة لا باللون فقط.
class _PastCell extends StatelessWidget {
  const _PastCell({
    required this.width,
    required this.height,
    required this.studentName,
    required this.date,
    required this.status,
    required this.onTap,
  });

  final double width;
  final double height;
  final String studentName;
  final String date;
  final AttendanceStatus? status;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (IconData?, Color, String) look = switch (status) {
      AttendanceStatus.present => (ClayIcons.check, p.status.success, 'حاضر'),
      AttendanceStatus.absent => (ClayIcons.close, p.status.danger, 'غائب'),
      AttendanceStatus.excused => (
        Icons.remove_circle_outline_rounded,
        p.status.excused,
        'غائب برخصة',
      ),
      null => (null, p.outline, 'لا تسجيل'),
    };
    return SizedBox(
      width: width,
      height: height,
      child: Semantics(
        button: true,
        label: '$studentName، $date: ${look.$3}',
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: look.$1 == null
                ? Text('·', style: TextStyle(color: look.$2, fontSize: 22))
                : Icon(look.$1, color: look.$2, size: 26),
          ),
        ),
      ),
    );
  }
}
