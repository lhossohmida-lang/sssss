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
/// ويمكن تغيير تاريخ أي حصة قادمة (لم تمضِ ولم تنعقد) إلى يوم آخر بوقتها نفسه؛ ويُحفظ
/// النقل مع الحفظ ولا تعيده إعادة البرمجة اللاحقة إلى موعده الأول.
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
  const _PlanRow(this.session, this.kind, {this.movedFrom});

  final PlannedSession session;
  final _RowKind kind;

  /// تاريخها المبرمج الأول إن نُقلت في هذه الشاشة ولم يُحفظ النقل بعد.
  final String? movedFrom;

  /// مفتاح موعدها المبرمج الذي تُنقل منه (الأصلي إن كانت منقولة هنا).
  String get originalKey =>
      movedFrom == null ? session.key : '$movedFrom|${session.startMinutes}';
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
  final Set<String> _chosen = {};

  /// حصص قادمة غُيّر تاريخها ولم يُحفظ بعد: مفتاحها الأصلي (`تاريخ|بداية`) ← التاريخ الجديد،
  /// بترتيب إجرائها (نقل إلى موعد أخلاه نقل سابق يأتي بعده).
  final Map<String, String> _moves = {};

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
      final dropped = _moves.isNotEmpty;
      setState(() {
        _formError = null;
        _from = first;
        _plan = plan;
        // الحصص أُعيد بناؤها من التاريخ الجديد، فلا مكان لتغييرات تواريخ الحصص السابقة.
        _moves.clear();
        _chosen
          ..clear()
          ..addAll(plan.past.map((s) => s.key));
      });
      if (dropped) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'أُعيد بناء الحصص من التاريخ الجديد فأُلغيت تغييرات تواريخ الحصص '
              'غير المحفوظة',
            ),
          ),
        );
      }
    } on ValidationException catch (e) {
      if (mounted) setState(() => _formError = e.toString());
    }
  }

  /// الحصص القادمة التي يجوز تغيير تاريخها (لم تمضِ ولم تنعقد).
  List<_PlanRow> get _movable => [
    for (final row in _rows)
      if (row.kind == _RowKind.upcoming) row,
  ];

  /// يغيّر تاريخ حصة قادمة إلى يوم آخر بوقتها نفسه. [chosen] الحصة المقصودة إن عُرفت (من
  /// أيقونة صفّها)، وإلا يُسأل عنها. لا يُنقل ما مضى ولا ما انعقد، ولا إلى يوم قبل اليوم.
  Future<void> _changeDate([_PlanRow? chosen]) async {
    final movable = _movable;
    if (movable.isEmpty) {
      setState(() => _formError = 'لا حصة قادمة لتغيير تاريخها');
      return;
    }
    final row =
        chosen ??
        (movable.length == 1 ? movable.single : await _chooseSession(movable));
    if (row == null || !mounted) return;
    final session = row.session;
    final picked = await showClayDatePicker(
      context,
      title: 'التاريخ الجديد للحصة',
      initial: DateKey.parse(session.date),
    );
    if (picked == null || !mounted) return;
    final date = DateKey.of(picked);
    if (date == session.date) return;
    if (picked.isBefore(_today)) {
      setState(
        () => _formError =
            'اختر اليوم أو تاريخاً بعده: الحصة القادمة لا تُنقل إلى ما مضى',
      );
      return;
    }
    final now = DateTime.now();
    if (date == DateKey.of(_today) &&
        session.endMinutes <= DateKey.minutesOf(now)) {
      setState(
        () => _formError = 'انتهى وقت هذه الحصة اليوم؛ اختر يوماً بعد اليوم',
      );
      return;
    }
    final target = '$date|${session.startMinutes}';
    if (_rows.any((r) => r.session.key == target)) {
      setState(
        () => _formError =
            'للفوج حصة يوم $date على ${DateKey.formatMinutes(session.startMinutes)} '
            'من قبل؛ اختر تاريخاً آخر',
      );
      return;
    }
    setState(() {
      _formError = null;
      if (date == row.movedFrom) {
        _moves.remove(row.originalKey);
      } else {
        _moves[row.originalKey] = date;
      }
    });
  }

  /// يتراجع عن نقل لم يُحفظ بعد، فتعود الحصة إلى موعدها المبرمج.
  void _undoMove(_PlanRow row) {
    final original = row.originalKey;
    // نقل آخر إلى موعدها الأول يمنع عودتها إليه قبل أن يُلغى هو.
    final blocker = _moves.entries
        .where(
          (e) =>
              e.key != original &&
              '${e.value}|${row.session.startMinutes}' == original,
        )
        .firstOrNull;
    if (blocker != null) {
      setState(
        () => _formError =
            'حصة أخرى نُقلت إلى موعدها الأول (${blocker.value}): تراجع عن نقلها أولاً',
      );
      return;
    }
    setState(() {
      _formError = null;
      _moves.remove(original);
    });
  }

  /// يسأل عن الحصة القادمة التي يُغيَّر تاريخها حين يتعدد القادم منها.
  Future<_PlanRow?> _chooseSession(List<_PlanRow> rows) {
    return showClayBottomSheet<_PlanRow>(
      context,
      title: 'اختر الحصة التي يتغير تاريخها',
      builder: (sheet) => ListView(
        shrinkWrap: true,
        children: [
          for (final row in rows)
            ClayListTile(
              title: '${_dayName(row.session.date)} ${row.session.date}',
              subtitle: row.movedFrom == null
                  ? _times(row.session)
                  : '${_times(row.session)} · كانت ${row.movedFrom}',
              leading: const Icon(ClayIcons.schedule),
              onTap: () => Navigator.of(sheet).pop(row),
            ),
        ],
      ),
    );
  }

  /// الحصص الماضية المعروضة بخانات تحديد. لا ماضية حين لا سعة لتسجيلها.
  List<PlannedSession> get _pastRows =>
      _plan!.capacity <= 0 ? const [] : _plan!.past;

  List<PlannedSession> get _picked => [
    for (final s in _pastRows)
      if (_chosen.contains(s.key)) s,
  ];

  /// كل صفوف «الحصص المقررة»: الثابتة والماضية والقادمة، بالترتيب الزمني. القادمة بقدر ما
  /// يبقى للدورة بعد الثابتة والماضية المحدَّدة، فيبقى المجموع بعدد حصص الدورة دائماً.
  /// والحصة القادمة التي غُيّر تاريخها تظهر في تاريخها الجديد.
  List<_PlanRow> get _rows {
    final plan = _plan!;
    final room = plan.cycleSize - plan.fixed.length - _picked.length;
    final rows = [
      for (final s in plan.fixed)
        _PlanRow(s, s.held ? _RowKind.held : _RowKind.upcoming),
      for (final s in _pastRows) _PlanRow(s, _RowKind.past),
      for (final s in plan.upcoming.take(room < 0 ? 0 : room))
        _PlanRow(s, _RowKind.upcoming),
    ];
    return [for (final row in rows) _moved(row)]
      ..sort((a, b) => _byTime(a.session, b.session));
  }

  _PlanRow _moved(_PlanRow row) {
    final to = row.kind == _RowKind.upcoming ? _moves[row.session.key] : null;
    if (to == null) return row;
    return _PlanRow(
      PlannedSession(
        date: to,
        startMinutes: row.session.startMinutes,
        endMinutes: row.session.endMinutes,
      ),
      _RowKind.upcoming,
      movedFrom: row.session.date,
    );
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
    final movesNote = _moves.isEmpty
        ? ''
        : ' وتُنقل ${_moves.length} '
              '${_moves.length == 1 ? 'حصة قادمة' : 'حصص قادمة'} إلى '
              'التواريخ التي اخترتها (تُلغى في موعدها وتحلّ محلها حصة تعويضية).';
    final ok = await showClayConfirm(
      context,
      title: replanOnly ? 'برمجة حصص الدورة' : 'تسجيل الحضور السابق',
      message: replanOnly
          ? 'ستُعاد برمجة حصص الدورة الحالية (${plan.cycleSize} حصة) من جدول '
                'الفوج ابتداءً من $first، وتُحذف الحصص المبرمجة غير المنعقدة '
                'لتحلّ محلها الجديدة.$movesNote'
          : 'ستُسجَّل ${picked.length} حصة سابقة في الدورة الحالية بحضور '
                'تلاميذها، وتُبرمج الحصص القادمة من جدول الفوج لتبقى الدورة '
                '${plan.cycleSize} حصة.$movesNote لا تُرسل رسائل لأولياء '
                'التلاميذ، ويمكن تعديل أي خانة لاحقاً من شاشة الحضور.',
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
        moves: [
          for (final e in _moves.entries)
            SessionMove(
              fromDate: e.key.split('|').first,
              startMinutes: int.parse(e.key.split('|').last),
              toDate: e.value,
            ),
        ],
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            replanOnly
                ? (_moves.isEmpty
                      ? 'أُعيدت برمجة حصص الدورة من $first'
                      : 'حُفظت الحصص المقررة وغُيّر تاريخ ${_moves.length} منها')
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
    final dirty =
        picked.isNotEmpty || first != _initialFrom || _moves.isNotEmpty;
    // حين لا سعة لتسجيل ماضٍ يبقى حفظ تغيير التواريخ وحده ممكناً.
    final canSave =
        !_saving &&
        dirty &&
        !overCapacity &&
        !needsStudents &&
        (plan.capacity > 0 || _moves.isNotEmpty);
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
      if (plan.capacity <= 0) ...[
        const ClayEmptyView(
          title: 'لا يمكن تسجيل حصص سابقة الآن',
          message:
              'الدورة الحالية على وشك أن تكتمل، فتبقى حصصها لتُسجَّل بالطريقة '
              'العادية من شاشة الحضور. ويمكنك تغيير تاريخ أي حصة قادمة منها.',
          icon: ClayIcons.schedule,
        ),
        _sessionsCard(context, plan),
        if (_formError != null) ...[
          const SizedBox(height: ClaySpacing.md),
          Text(_formError!, style: TextStyle(color: p.status.danger)),
        ],
        if (_moves.isNotEmpty) ...[
          const SizedBox(height: ClaySpacing.lg),
          ClayButton(
            label: 'حفظ الحصص المقررة',
            icon: ClayIcons.check,
            expand: true,
            loading: _saving,
            onPressed: canSave ? () => _save(excuse: excuse) : null,
          ),
        ],
      ] else ...[
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
                'بحسب جدول الفوج. ألغِ تحديد ما مضى ولم ينعقد فعلاً. وإن كان '
                'التاريخ بعد اليوم بُرمجت الدورة كلها منه، ويمكنك تغيير تاريخ '
                'أي حصة قادمة منها.',
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
              label: 'تغيير تاريخ حصة',
              icon: ClayIcons.schedule,
              kind: ClayButtonKind.secondary,
              onPressed: _saving || _movable.isEmpty ? null : _changeDate,
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
      // أيقونة التقويم تغيّر تاريخ هذه الحصة القادمة.
      _RowKind.upcoming => SizedBox.square(
        dimension: ClayCheckbox.size,
        child: IconButton(
          tooltip: 'تغيير تاريخ حصة ${s.date}',
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          icon: Icon(
            ClayIcons.schedule,
            color: row.movedFrom == null ? p.textMuted : p.accent,
          ),
          onPressed: _saving ? null : () => _changeDate(row),
        ),
      ),
    };
    final badge = switch (row.kind) {
      _RowKind.past => null,
      _RowKind.held => const ClayBadge(
        label: 'سُجِّلت',
        tone: ClayTone.success,
      ),
      _RowKind.upcoming when row.movedFrom != null => const ClayBadge(
        label: 'منقولة',
        tone: ClayTone.warning,
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
                if (row.movedFrom != null)
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(
                      'كانت ${row.movedFrom}',
                      style: text.bodySmall!.copyWith(color: p.textMuted),
                    ),
                  ),
              ],
            ),
          ),
          if (row.movedFrom != null)
            IconButton(
              tooltip: 'التراجع عن نقل حصة ${s.date}',
              icon: const Icon(Icons.undo_rounded),
              onPressed: _saving ? null : () => _undoMove(row),
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
