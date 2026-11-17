import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

/// الحصص المقررة للدورة الحالية وتسجيل الماضي منها: تُنشأ حصص الدورة دائماً بعددها
/// وبتواريخها من جدول الفوج ابتداءً من تاريخ أول حصة. ما مضى منها يُسجَّل حضوره
/// (ويُلغى تحديد ما لم ينعقد فعلاً)، وما بقي يُبرمج قادماً. وتغيير تاريخ أول حصة يعيد
/// بناء الحصص المقررة كلها منه (ومن بعد اليوم تُبرمج الدورة كلها من ذلك التاريخ).
class PastSessionsScreen extends ConsumerStatefulWidget {
  const PastSessionsScreen({required this.groupId, this.firstDate, super.key});

  final String groupId;

  /// تاريخ أول حصة (`YYYY-MM-DD`) كما أُدخل عند إنشاء الفوج؛ بدونه يُقرأ من حصص الدورة.
  final String? firstDate;

  @override
  ConsumerState<PastSessionsScreen> createState() => _PastSessionsScreenState();
}

enum _RowKind { held, upcoming, past }

class _PlanRow {
  const _PlanRow(this.session, this.kind);

  final PlannedSession session;
  final _RowKind kind;
}

class _PastSessionsScreenState extends ConsumerState<PastSessionsScreen> {
  static const double _nameWidth = 150;
  static const double _cellWidth = 72;
  static const double _rowHeight = 52;
  static const double _headerHeight = 64;

  late DateTime _today;
  DateTime? _from;
  String _initialFrom = '';
  bool _loading = true;
  bool _saving = false;
  String? _loadError;
  String? _formError;
  CyclePlan? _plan;
  List<PastRosterStudent> _roster = const [];
  final List<PlannedSession> _custom = [];
  final Set<String> _chosen = {};

  /// مفتاح الحصة ← (معرّف التلميذ ← حالته؛ `null` = لا تسجيل).
  final Map<String, Map<String, AttendanceStatus?>> _marks = {};

  PastSessionsService get _service => ref.read(pastSessionsServiceProvider);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _today = DateTime(now.year, now.month, now.day);
    unawaited(_load());
  }

  static String? _validDate(String? value) {
    if (value == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      return null;
    }
    return DateKey.of(DateKey.parse(value)) == value ? value : null;
  }

  Future<void> _load() async {
    try {
      final roster = await _service.roster(widget.groupId);
      final first =
          _validDate(widget.firstDate) ??
          await _service.firstDate(widget.groupId, now: DateTime.now());
      final plan = await _service.plan(
        widget.groupId,
        from: first,
        now: DateTime.now(),
      );
      if (!mounted) return;
      setState(() {
        _roster = roster;
        _initialFrom = first;
        _from = DateKey.parse(first);
        _plan = plan;
        _chosen
          ..clear()
          ..addAll(plan.past.map((s) => s.key));
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

  Future<void> _pickFrom() async {
    final picked = await showClayDatePicker(
      context,
      title: 'تاريخ أول حصة في الدورة الحالية',
      initial: _from,
    );
    if (picked == null || !mounted) return;
    await _replan(picked);
  }

  /// يبني الحصص المقررة من جديد من تاريخ أول حصة [first].
  Future<void> _replan(DateTime first) async {
    try {
      final plan = await _service.plan(
        widget.groupId,
        from: DateKey.of(first),
        now: DateTime.now(),
      );
      if (!mounted) return;
      setState(() {
        _formError = null;
        _from = first;
        _plan = plan;
        // حصة أضافها المدير قبل أول حصة الجديدة لا مكان لها بعد الآن.
        _custom.removeWhere((s) => s.date.compareTo(plan.from) < 0);
        _chosen
          ..clear()
          ..addAll(plan.past.map((s) => s.key))
          ..addAll(_custom.map((s) => s.key));
      });
    } on ValidationException catch (e) {
      if (mounted) setState(() => _formError = e.toString());
    }
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
    if (DateKey.of(date).compareTo(DateKey.of(_from!)) < 0) {
      setState(
        () => _formError =
            'اختر تاريخاً من أول حصة في الدورة فصاعداً، أو غيّر تاريخ أول حصة',
      );
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
    final session = PlannedSession(
      date: DateKey.of(date),
      startMinutes: start,
      endMinutes: end,
    );
    if (_allKeys.contains(session.key)) {
      setState(() => _formError = 'هذه الحصة مضافة من قبل');
      return;
    }
    setState(() {
      _formError = null;
      _custom.add(session);
      _chosen.add(session.key);
    });
  }

  /// مفاتيح كل الحصص المعروضة الآن.
  Set<String> get _allKeys => {
    for (final row in _rows) row.session.key,
    for (final s in _custom) s.key,
  };

  /// الحصص الماضية المعروضة بخانات تحديد: المقترحة ثم المضافة يدوياً.
  List<PlannedSession> get _pastRows {
    final byKey = {
      for (final s in [..._plan!.past, ..._custom]) s.key: s,
    };
    return byKey.values.toList()..sort(_byTime);
  }

  List<PlannedSession> get _picked => [
    for (final s in _pastRows)
      if (_chosen.contains(s.key)) s,
  ];

  /// كل صفوف «الحصص المقررة»: الثابتة والماضية والقادمة، بالترتيب الزمني. القادمة بقدر ما
  /// يبقى للدورة بعد الثابتة والماضية المحدَّدة، فيبقى المجموع بعدد حصص الدورة دائماً.
  List<_PlanRow> get _rows {
    final plan = _plan!;
    final room = plan.cycleSize - plan.fixed.length - _picked.length;
    return [
      for (final s in plan.fixed)
        _PlanRow(s, s.held ? _RowKind.held : _RowKind.upcoming),
      for (final s in _pastRows) _PlanRow(s, _RowKind.past),
      for (final s in plan.upcoming.take(room < 0 ? 0 : room))
        _PlanRow(s, _RowKind.upcoming),
    ]..sort((a, b) => _byTime(a.session, b.session));
  }

  static int _byTime(PlannedSession a, PlannedSession b) {
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
    final plan = _plan!;
    final first = DateKey.of(_from!);
    final replanOnly = picked.isEmpty;
    final ok = await showClayConfirm(
      context,
      title: replanOnly ? 'برمجة حصص الدورة' : 'تسجيل الحضور السابق',
      message: replanOnly
          ? 'ستُعاد برمجة حصص الدورة الحالية (${plan.cycleSize} حصة) من جدول '
                'الفوج ابتداءً من $first، وتُحذف الحصص المبرمجة غير المنعقدة '
                'لتحلّ محلها الجديدة.'
          : 'ستُسجَّل ${picked.length} حصة سابقة في الدورة الحالية بحضور '
                'تلاميذها، وتُبرمج الحصص القادمة من جدول الفوج لتبقى الدورة '
                '${plan.cycleSize} حصة. لا تُرسل رسائل لأولياء التلاميذ، '
                'ويمكن تعديل أي خانة لاحقاً من شاشة الحضور.',
      confirmLabel: replanOnly ? 'برمجة' : 'تسجيل',
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
        firstDate: first,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            replanOnly
                ? 'أُعيدت برمجة حصص الدورة من $first'
                : 'سُجِّلت ${result.sessions} حصة سابقة و${result.marks} خانة حضور',
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

  static String _times(PlannedSession s) =>
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
    final plan = _plan!;
    final picked = _picked;
    final overCapacity = picked.length > plan.capacity;
    final first = DateKey.of(_from!);
    final needsStudents = picked.isNotEmpty && _roster.isEmpty;
    final dirty = picked.isNotEmpty || first != _initialFrom;
    final canSave =
        !_saving &&
        dirty &&
        !overCapacity &&
        !needsStudents &&
        plan.capacity > 0;
    return [
      ClayCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item != null) Text(item.subjectName, style: text.titleLarge),
            const SizedBox(height: ClaySpacing.xs),
            Text(
              'لتدوين حصص الدورة الحالية التي انعقدت قبل بدء استعمال النظام. '
              'يمكن تسجيل ${plan.capacity} حصة سابقة على الأكثر، وتبقى حصة واحدة '
              'على الأقل لتُغلق تلقائياً.',
              style: text.bodyMedium,
            ),
          ],
        ),
      ),
      const SizedBox(height: ClaySpacing.lg),
      if (plan.capacity <= 0)
        const ClayEmptyView(
          title: 'لا يمكن تسجيل حصص سابقة الآن',
          message:
              'الدورة الحالية على وشك أن تكتمل، فتبقى حصصها لتُسجَّل بالطريقة '
              'العادية من شاشة الحضور.',
          icon: ClayIcons.schedule,
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
                  Expanded(
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(first, style: text.titleMedium),
                      ),
                    ),
                  ),
                  ClayButton(
                    label: 'تغيير التاريخ',
                    kind: ClayButtonKind.secondary,
                    onPressed: _saving ? null : _pickFrom,
                  ),
                ],
              ),
              const SizedBox(height: ClaySpacing.xs),
              Text(
                'تُنشأ حصص الدورة (${plan.cycleSize}) دائماً من هذا التاريخ '
                'بحسب جدول الفوج. ألغِ تحديد ما مضى ولم ينعقد فعلاً، وأضف ما '
                'انعقد في وقت آخر. وإن كان التاريخ بعد اليوم بُرمجت الدورة '
                'كلها منه.',
                style: text.bodySmall!.copyWith(color: p.textMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: ClaySpacing.lg),
        _sessionsCard(context, plan),
        const SizedBox(height: ClaySpacing.lg),
        if (overCapacity)
          Padding(
            padding: const EdgeInsets.only(bottom: ClaySpacing.md),
            child: Text(
              'المحدَّد ${picked.length} حصة والمسموح ${plan.capacity}: ألغِ '
              'تحديد ${picked.length - plan.capacity} حصة.',
              style: TextStyle(color: p.status.danger),
            ),
          ),
        if (needsStudents)
          Padding(
            padding: const EdgeInsets.only(bottom: ClaySpacing.md),
            child: Text(
              'أضف التلاميذ إلى الفوج أولاً ثم سجّل حضورهم السابق.',
              style: TextStyle(color: p.status.danger),
            ),
          ),
        if (picked.isNotEmpty && _roster.isNotEmpty) ...[
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
          label: picked.isEmpty ? 'حفظ الحصص المقررة' : 'حفظ الحضور السابق',
          icon: ClayIcons.check,
          expand: true,
          loading: _saving,
          onPressed: canSave ? () => _save(excuse: excuse) : null,
        ),
      ],
      const SizedBox(height: ClaySpacing.xl),
    ];
  }

  Widget _sessionsCard(BuildContext context, CyclePlan plan) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final rows = _rows;
    final held = plan.fixed.where((s) => s.held).length + _picked.length;
    final coming = plan.cycleSize - held;
    return ClayCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('الحصص المقررة', style: text.titleMedium),
          const SizedBox(height: ClaySpacing.xs),
          Text(
            'حصص الدورة ${plan.cycleSize}: $held منعقدة و${coming < 0 ? 0 : coming} '
            'قادمة.',
            style: text.bodySmall!.copyWith(color: p.textMuted),
          ),
          const SizedBox(height: ClaySpacing.sm),
          if (rows.isEmpty)
            Text(
              'لا حصص: لا جدول أسبوعي للفوج. أضف خانة أسبوعية من تعديل الفوج.',
              style: text.bodySmall!.copyWith(color: p.textMuted),
            ),
          for (final row in rows) _sessionRow(context, row),
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

  Widget _sessionRow(BuildContext context, _PlanRow row) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final s = row.session;
    final Widget leading = switch (row.kind) {
      _RowKind.past => ClayCheckbox(
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
      _RowKind.held => SizedBox.square(
        dimension: ClayCheckbox.size,
        child: Icon(ClayIcons.check, color: p.status.success),
      ),
      _RowKind.upcoming => SizedBox.square(
        dimension: ClayCheckbox.size,
        child: Icon(ClayIcons.schedule, color: p.textMuted),
      ),
    };
    final badge = switch (row.kind) {
      _RowKind.past => null,
      _RowKind.held => const ClayBadge(
        label: 'سُجِّلت',
        tone: ClayTone.success,
      ),
      _RowKind.upcoming => const ClayBadge(label: 'قادمة'),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ClaySpacing.xs),
      child: Row(
        children: [
          leading,
          const SizedBox(width: ClaySpacing.sm),
          Expanded(
            child: Wrap(
              spacing: ClaySpacing.sm,
              runSpacing: ClaySpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(_dayName(s.date), style: text.bodyMedium),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(s.date, style: text.bodyMedium),
                ),
                ?badge,
              ],
            ),
          ),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              _times(s),
              style: text.bodySmall!.copyWith(color: p.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _grid(
    BuildContext context,
    List<PlannedSession> sessions,
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
