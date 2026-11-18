import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

/// يحذف الفوج بعد تأكيد المستخدم، ويعيد `true` إن حُذف. ما لا يصح فقده (مدفوعات أو
/// خلاص أو حضور مسجَّل...) تمنعه الخدمة فيُعرض سبب المنع ويُقترح الأرشفة.
Future<bool> _deleteGroup(
  BuildContext context,
  WidgetRef ref, {
  required String id,
  required int number,
}) async {
  final ok = await showClayConfirm(
    context,
    title: 'حذف الفوج',
    message:
        'سيُحذف الفوج $number بجدوله وحصصه المبرمجة وانتساب تلاميذه إليه، '
        'ويبقى التلاميذ أنفسهم. لا يُحذف فوج له مدفوعات أو حضور مسجَّل: '
        'أرشفه بدل ذلك.',
    confirmLabel: 'حذف',
    danger: true,
  );
  if (!ok || !context.mounted) return false;
  try {
    return await ref.read(groupServiceProvider).delete(id);
  } on ValidationException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          duration: const Duration(seconds: 8),
        ),
      );
    }
    return false;
  }
}

/// الأفواج النشطة مقسَّمة بالمادة أولاً ثم السنة (المستوى)، فيُختار اسم المادة، ثم السنة، فتظهر
/// أفواجها مرقَّمة من 1 (فوج 1، فوج 2...) برقمها في تلك المادة وسنتها، مع الأرشفة والحذف.
class GroupsScreen extends ConsumerStatefulWidget {
  const GroupsScreen({super.key});

  @override
  ConsumerState<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends ConsumerState<GroupsScreen> {
  /// معرّف المادة المختارة (اسمها المقصوص بأحرف صغيرة)، و`null` في قائمة المواد.
  String? _subject;

  /// السنة المختارة: معرّف المستوى، أو [_noLevel] للمادة العامة، و`null` في قائمة السنوات.
  String? _level;

  static const String _noLevel = '';

  static String _subjectKey(GroupItem item) =>
      item.baseSubjectName.trim().toLowerCase();

  /// الصعود درجة: من أفواج السنة إلى سنوات المادة، ومنها إلى المواد.
  void _up() => setState(() {
    if (_level != null) {
      _level = null;
    } else {
      _subject = null;
    }
  });

  Future<void> _archive(GroupItem item) async {
    final ok = await showClayConfirm(
      context,
      title: 'أرشفة الفوج',
      message:
          'سيخرج الفوج ${item.number} (${item.subjectName}) من القوائم '
          'النشطة وتبقى سجلاته وحضوره ومدفوعاته.',
      confirmLabel: 'أرشفة',
      danger: true,
    );
    if (ok) await ref.read(groupServiceProvider).archive(item.id);
  }

  static String _countText(int groups, int students) =>
      '$groups فوج · $students تلميذ';

  @override
  Widget build(BuildContext context) {
    final canAdd = ref.can(PermissionModule.groups, PermissionAction.add);
    final state = ref.watch(groupsProvider);
    final levelOrder = {
      for (final level in ref.watch(levelsProvider).value ?? const <LevelRow>[])
        level.id: level.sortOrder,
    };
    return PopScope(
      canPop: _subject == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _up();
      },
      child: state.when(
        loading: () => const ClaySkeletonList(),
        error: (_, _) => ClayErrorView(
          message: 'تعذّرت قراءة الأفواج',
          onRetry: () => ref.invalidate(groupsProvider),
        ),
        data: (items) {
          // مادة أو سنة لم يبقَ فيها فوج (أُرشف أو حُذف آخر أفواجها): نعود إلى ما فوقها.
          final inSubject = [
            for (final item in items)
              if (_subject == null || _subjectKey(item) == _subject) item,
          ];
          final inLevel = [
            for (final item in inSubject)
              if (_level == null || (item.levelId ?? _noLevel) == _level) item,
          ];
          if ((_subject != null && inSubject.isEmpty) ||
              (_level != null && inLevel.isEmpty)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() {
                if (inSubject.isEmpty) _subject = null;
                _level = null;
              });
            });
          }
          final body = items.isEmpty
              ? const ClayEmptyView(
                  title: 'لا توجد أفواج بعد',
                  message: 'أنشئ فوجاً بجدوله الأسبوعي لتُولَّد حصصه',
                  icon: ClayIcons.groups,
                )
              : _subject == null
              ? _subjectsView(items)
              : _level == null
              ? _levelsView(inSubject, levelOrder)
              : _groupsView(inLevel);
          // المادة التي يُنشأ فيها الفوج الجديد: مادة السنة المفتوحة إن فُتحت.
          final newSubject = _level != null && inLevel.isNotEmpty
              ? inLevel.first.group.subjectId
              : null;
          return Column(
            children: [
              if (_subject != null && inSubject.isNotEmpty)
                _breadcrumb(inSubject.first, inLevel),
              Expanded(child: body),
              if (canAdd)
                Padding(
                  padding: const EdgeInsets.all(ClaySpacing.screenPadding),
                  child: ClayButton(
                    label: 'إنشاء فوج',
                    icon: ClayIcons.add,
                    expand: true,
                    onPressed: () => context.push(
                      newSubject == null
                          ? '/groups/new'
                          : '/groups/new?subject=$newSubject',
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// «الأفواج › المادة › السنة»: كل جزء يعيد إلى مستواه.
  Widget _breadcrumb(GroupItem subject, List<GroupItem> inLevel) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    Widget crumb(String label, VoidCallback? onTap) => TextButton(
      onPressed: onTap,
      child: Text(
        label,
        style: text.titleSmall!.copyWith(
          color: onTap == null ? p.text : p.accent,
        ),
      ),
    );
    final chevron = Icon(Icons.chevron_left_rounded, color: p.textMuted);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ClaySpacing.screenPadding,
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          crumb(
            'الأفواج',
            () => setState(() {
              _subject = null;
              _level = null;
            }),
          ),
          chevron,
          crumb(
            subject.baseSubjectName,
            _level == null ? null : () => setState(() => _level = null),
          ),
          if (_level != null && inLevel.isNotEmpty) ...[
            chevron,
            crumb(inLevel.first.levelName ?? 'كل المستويات', null),
          ],
        ],
      ),
    );
  }

  /// المواد: كل اسم مادة مرة واحدة مهما تعددت سنواته.
  Widget _subjectsView(List<GroupItem> items) {
    final bySubject = <String, List<GroupItem>>{};
    for (final item in items) {
      bySubject.putIfAbsent(_subjectKey(item), () => []).add(item);
    }
    final keys = bySubject.keys.toList()
      ..sort(
        (a, b) => bySubject[a]!.first.baseSubjectName.compareTo(
          bySubject[b]!.first.baseSubjectName,
        ),
      );
    return ListView.builder(
      padding: const EdgeInsets.symmetric(
        horizontal: ClaySpacing.screenPadding,
        vertical: ClaySpacing.sm,
      ),
      itemCount: keys.length,
      itemBuilder: (context, i) {
        final group = bySubject[keys[i]]!;
        final years = {for (final item in group) item.levelId ?? _noLevel};
        final students = group.fold(0, (sum, item) => sum + item.studentCount);
        return ClayListTile(
          title: group.first.baseSubjectName,
          subtitle: [
            if (years.length > 1 || !years.contains(_noLevel))
              '${years.length} سنة',
            _countText(group.length, students),
          ].join(' · '),
          trailing: const [Icon(Icons.chevron_left_rounded)],
          onTap: () => setState(() {
            _subject = keys[i];
            _level = null;
          }),
        );
      },
    );
  }

  /// سنوات المادة المختارة بترتيب المستويات، والمادة العامة (بلا سنة) آخراً.
  Widget _levelsView(List<GroupItem> items, Map<String, int> levelOrder) {
    final byLevel = <String, List<GroupItem>>{};
    for (final item in items) {
      byLevel.putIfAbsent(item.levelId ?? _noLevel, () => []).add(item);
    }
    final keys = byLevel.keys.toList()
      ..sort((a, b) {
        int rank(String key) => levelOrder[key] ?? (1 << 30);
        final byOrder = rank(a).compareTo(rank(b));
        return byOrder != 0 ? byOrder : a.compareTo(b);
      });
    return ListView.builder(
      padding: const EdgeInsets.symmetric(
        horizontal: ClaySpacing.screenPadding,
        vertical: ClaySpacing.sm,
      ),
      itemCount: keys.length,
      itemBuilder: (context, i) {
        final group = byLevel[keys[i]]!;
        final students = group.fold(0, (sum, item) => sum + item.studentCount);
        return ClayListTile(
          title: group.first.levelName ?? 'كل المستويات',
          subtitle: _countText(group.length, students),
          trailing: const [Icon(Icons.chevron_left_rounded)],
          onTap: () => setState(() => _level = keys[i]),
        );
      },
    );
  }

  /// أفواج المادة والسنة بأرقامها: فوج 1، فوج 2...
  Widget _groupsView(List<GroupItem> items) {
    final canEdit = ref.can(PermissionModule.groups, PermissionAction.edit);
    final canDelete = ref.can(PermissionModule.groups, PermissionAction.delete);
    final sorted = [...items]..sort((a, b) => a.number.compareTo(b.number));
    return ListView.builder(
      padding: const EdgeInsets.symmetric(
        horizontal: ClaySpacing.screenPadding,
        vertical: ClaySpacing.sm,
      ),
      itemCount: sorted.length,
      itemExtent: 112,
      itemBuilder: (context, i) {
        final item = sorted[i];
        return ClayListTile(
          title: 'فوج ${item.number}',
          subtitle:
              '${item.teacherName} · ${item.roomName ?? 'بلا قاعة'} '
              '· ${item.studentCount} تلميذ\n${item.scheduleText}',
          subtitleLines: 2,
          onTap: () => context.push('/groups/${item.id}'),
          trailing: [
            if (canEdit)
              IconButton(
                tooltip: 'تعديل الفوج ${item.number}',
                icon: const Icon(ClayIcons.edit),
                onPressed: () => context.push('/groups/${item.id}/edit'),
              ),
            if (canEdit)
              IconButton(
                tooltip: 'أرشفة الفوج ${item.number}',
                icon: const Icon(ClayIcons.backup),
                onPressed: () => _archive(item),
              ),
            if (canDelete)
              IconButton(
                tooltip: 'حذف الفوج ${item.number}',
                icon: const Icon(ClayIcons.delete),
                onPressed: () => _deleteGroup(
                  context,
                  ref,
                  id: item.id,
                  number: item.number,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// مسودة خانة أسبوعية في النموذج.
class _SlotDraft {
  _SlotDraft({this.weekday = 6, this.start = 600, this.end = 690, this.roomId});

  int weekday;
  int start;
  int end;
  String? roomId;
}

/// إنشاء مجموعة أو تعديلها: مادة، أستاذ، قاعة، حصص الدورة، مبلغ الأستاذ،
/// وجدول أسبوعي يُفحص تعارضه مع المجموعات الأخرى لحظياً مع اقتراح قاعة.
class GroupFormScreen extends ConsumerStatefulWidget {
  const GroupFormScreen({
    this.groupId,
    this.initialSubjectId,
    this.initialTeacherId,
    super.key,
  });

  /// معرّف المجموعة عند التعديل؛ `null` للإنشاء.
  final String? groupId;

  /// مادة وأستاذ مقترحان عند الإنشاء من قائمة انتظار.
  final String? initialSubjectId;
  final String? initialTeacherId;

  @override
  ConsumerState<GroupFormScreen> createState() => _GroupFormScreenState();
}

class _GroupFormScreenState extends ConsumerState<GroupFormScreen> {
  final _cycle = TextEditingController(text: '8');
  final _rate = TextEditingController();
  final List<_SlotDraft> _slots = [_SlotDraft()];

  /// حقل خطأ تاريخ أول حصة في [_errors].
  static const String _fieldFirstDate = 'first_date';

  /// أبعد ما يُقبل لتاريخ أول حصة: ما مضى أكثر من هذا لا تكفي حصص الدورة لتغطيته.
  static const int _maxDaysBack = 120;
  static const int _maxDaysAhead = 365;

  late DateTime _firstDate;
  String? _subjectId;
  String? _teacherId;
  String? _roomId;
  GroupRow? _existing;
  bool _loaded = false;
  bool _saving = false;
  Map<String, String> _errors = const {};
  Timer? _debounce;
  int _checkToken = 0;

  bool get _editing => widget.groupId != null;

  static DateTime _dayOf(DateTime time) =>
      DateTime(time.year, time.month, time.day);

  @override
  void initState() {
    super.initState();
    _firstDate = _dayOf(DateTime.now());
    if (_editing) {
      unawaited(_loadExisting());
    } else {
      _loaded = true;
      if (widget.initialSubjectId != null) unawaited(_prefill());
    }
  }

  /// يملأ المادة والأستاذ المقترحين (إن كان الأستاذ يدرّس المادة) ونصيبه
  /// الافتراضي من ملفه.
  Future<void> _prefill() async {
    final subjectId = widget.initialSubjectId!;
    final teachers = await ref.read(subjectTeachersProvider(subjectId).future);
    if (!mounted) return;
    final teacher = teachers
        .where((t) => t.id == widget.initialTeacherId)
        .firstOrNull;
    setState(() {
      _subjectId = subjectId;
      if (teacher != null) {
        _teacherId = teacher.id;
        if (teacher.ratePerStudent > 0) {
          _rate.text = '${teacher.ratePerStudent}';
        }
      }
    });
    _scheduleCheck();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _cycle.dispose();
    _rate.dispose();
    super.dispose();
  }

  Future<void> _loadExisting() async {
    final runtime = ref.read(runtimeProvider);
    final group = await (runtime.db.select(
      runtime.db.groups,
    )..where((g) => g.id.equals(widget.groupId!))).getSingleOrNull();
    final slots = await ref.read(groupServiceProvider).slotsOf(widget.groupId!);
    if (!mounted) return;
    setState(() {
      _existing = group;
      _loaded = true;
      if (group != null) {
        _subjectId = group.subjectId;
        _teacherId = group.teacherId;
        _roomId = group.roomId;
        _cycle.text = '${group.sessionsPerCycle}';
        _rate.text = group.ratePerStudent == null
            ? ''
            : '${group.ratePerStudent}';
      }
      _slots
        ..clear()
        ..addAll([
          for (final s in slots)
            _SlotDraft(
              weekday: s.weekday,
              start: s.startMinutes,
              end: s.endMinutes,
              roomId: s.roomId,
            ),
        ]);
    });
    _scheduleCheck();
  }

  List<GroupSlotInput> _inputs() => [
    for (final s in _slots)
      GroupSlotInput(
        weekday: s.weekday,
        startMinutes: s.start,
        endMinutes: s.end,
        roomId: s.roomId,
      ),
  ];

  int? get _rateValue =>
      _rate.text.trim().isEmpty ? null : int.tryParse(_rate.text.trim());

  /// يفحص الجدول بعد مهلة قصيرة من آخر تعديل، فتظهر التعارضات لحظياً.
  void _scheduleCheck() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _check);
  }

  Future<void> _check() async {
    final subjectId = _subjectId;
    final teacherId = _teacherId;
    if (subjectId == null || teacherId == null) return;
    final token = ++_checkToken;
    final errors = await ref
        .read(groupServiceProvider)
        .validate(
          subjectId: subjectId,
          teacherId: teacherId,
          roomId: _roomId,
          sessionsPerCycle: int.tryParse(_cycle.text.trim()) ?? 0,
          ratePerStudent: _rateValue,
          slots: _inputs(),
          excludeGroupId: widget.groupId,
        );
    // نتيجة فحص أقدم من آخر تعديل تُهمَل.
    if (!mounted || token != _checkToken) return;
    setState(() => _errors = errors);
  }

  void _changed(VoidCallback change) {
    setState(change);
    _scheduleCheck();
  }

  Future<void> _pickTime(_SlotDraft slot, {required bool start}) async {
    final picked = await showClayTimePicker(
      context,
      title: start ? 'بداية الحصة' : 'نهاية الحصة',
      initial: start ? slot.start : slot.end,
    );
    if (picked == null) return;
    _changed(() {
      if (start) {
        // تبقى مدة الحصة عند تحريك البداية.
        final length = slot.end - slot.start;
        slot.start = picked;
        slot.end = (picked + (length > 0 ? length : 90)).clamp(0, 24 * 60);
      } else {
        slot.end = picked;
      }
    });
  }

  /// يقترح قاعة متاحة للخانة: أصغر قاعة متاحة.
  Future<void> _suggestRoom(_SlotDraft slot) async {
    final free = await ref
        .read(scheduleServiceProvider)
        .freeRoomsForSlot(
          weekday: slot.weekday,
          startMinutes: slot.start,
          endMinutes: slot.end,
          excludeGroupId: widget.groupId,
        );
    if (!mounted) return;
    if (free.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد قاعة متاحة في هذا الوقت')),
      );
      return;
    }
    _changed(() => slot.roomId = free.first.id);
  }

  Future<void> _delete() async {
    final existing = _existing;
    if (existing == null) return;
    final deleted = await _deleteGroup(
      context,
      ref,
      id: existing.id,
      number: existing.number,
    );
    if (deleted && mounted) context.go('/groups');
  }

  Future<void> _pickFirstDate() async {
    final picked = await showClayDatePicker(
      context,
      title: 'تاريخ أول حصة',
      initial: _firstDate,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _firstDate = _dayOf(picked);
      _errors = {..._errors}..remove(_fieldFirstDate);
    });
  }

  /// خطأ تاريخ أول حصة، أو `null` إن صلح.
  String? _firstDateError(DateTime today) {
    final days = _firstDate.difference(today).inDays;
    if (days < -_maxDaysBack) {
      return 'تاريخ بعيد في الماضي: اختر تاريخاً خلال آخر $_maxDaysBack يوماً';
    }
    if (days > _maxDaysAhead) {
      return 'تاريخ بعيد: اختر تاريخاً خلال سنة من اليوم';
    }
    return null;
  }

  Future<void> _submit() async {
    if (_saving) return;
    final subjectId = _subjectId;
    final teacherId = _teacherId;
    if (subjectId == null || teacherId == null) {
      setState(() {
        _errors = {
          if (subjectId == null) GroupService.fieldSubject: 'اختر المادة',
          if (teacherId == null) GroupService.fieldTeacher: 'اختر الأستاذ',
        };
      });
      return;
    }
    final now = _dayOf(DateTime.now());
    final dateError = _editing ? null : _firstDateError(now);
    if (dateError != null) {
      setState(() => _errors = {_fieldFirstDate: dateError});
      return;
    }
    setState(() {
      _saving = true;
      _errors = const {};
    });
    final service = ref.read(groupServiceProvider);
    final today = DateKey.of(now);
    // حصص ماضية لا تُنشأ مفتوحة (يغلقها النظام غائبين): الفوج يُبرمج من اليوم، وتاريخ
    // أول حصة ينتقل إلى «الحضور السابق» الذي يبني منه الحصص المقررة ويسجّل الماضي.
    final firstIsPast = _firstDate.isBefore(now);
    try {
      GroupRow? created;
      if (_editing) {
        await service.update(
          widget.groupId!,
          teacherId: teacherId,
          roomId: _roomId,
          ratePerStudent: _rateValue,
          slots: _inputs(),
          today: today,
        );
      } else {
        created = await service.create(
          subjectId: subjectId,
          teacherId: teacherId,
          roomId: _roomId,
          sessionsPerCycle: int.tryParse(_cycle.text.trim()) ?? 0,
          ratePerStudent: _rateValue,
          slots: _inputs(),
          startDate: firstIsPast ? today : DateKey.of(_firstDate),
        );
      }
      if (!mounted) return;
      if (created == null) {
        context.pop();
      } else {
        // بعد إنشاء الفوج تُفتح صفحة إعداده: تلاميذه وحضورهم السابق وتسديدهم.
        final from = firstIsPast ? '?from=${DateKey.of(_firstDate)}' : '';
        context.pushReplacement('/groups/${created.id}/setup$from');
      }
    } on ValidationException catch (e) {
      if (mounted) setState(() => _errors = e.errors);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// تاريخ أول حصة: منه تُولَّد حصص الدورة بعددها وتواريخها من الجدول الأسبوعي.
  Widget _firstDateField(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final today = _dayOf(DateTime.now());
    final past = _firstDate.isBefore(today);
    final error = _errors[_fieldFirstDate];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('تاريخ أول حصة', style: text.labelLarge),
        const SizedBox(height: ClaySpacing.xs),
        Row(
          children: [
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(DateKey.of(_firstDate), style: text.titleMedium),
                ),
              ),
            ),
            ClayButton(
              label: 'تغيير التاريخ',
              kind: ClayButtonKind.secondary,
              onPressed: _saving ? null : _pickFirstDate,
            ),
          ],
        ),
        const SizedBox(height: ClaySpacing.xs),
        Text(
          past
              ? 'التاريخ قبل اليوم: يُنشأ الفوج وتُبرمج حصصه القادمة من اليوم، ثم '
                    'تُبنى «الحصص المقررة» من هذا التاريخ وتُسجَّل حصصه الماضية '
                    'بحضورها من «تسجيل الحضور السابق» بعد إضافة التلاميذ.'
              : 'تُولَّد حصص الدورة بعددها من هذا التاريخ بحسب الجدول الأسبوعي.',
          style: text.bodySmall!.copyWith(color: p.textMuted),
        ),
        if (error != null)
          Semantics(
            liveRegion: true,
            child: Text(
              error,
              style: text.bodySmall!.copyWith(color: p.status.danger),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final subjects = ref.watch(subjectsProvider).value ?? const <SubjectItem>[];
    final rooms = ref.watch(roomsProvider).value ?? const <RoomRow>[];
    final teachers = _subjectId == null
        ? const <TeacherRow>[]
        : ref.watch(subjectTeachersProvider(_subjectId!)).value ??
              const <TeacherRow>[];
    const gap = SizedBox(height: ClaySpacing.md);

    Widget card(String title, List<Widget> children) => Padding(
      padding: const EdgeInsets.only(bottom: ClaySpacing.lg),
      child: ClayCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(title, style: text.titleMedium),
            ),
            const SizedBox(height: ClaySpacing.md),
            ...children,
          ],
        ),
      ),
    );

    final body = !_loaded
        ? const ClayLoadingView()
        : _editing && _existing == null
        ? const ClayEmptyView(title: 'هذا الفوج غير موجود')
        : Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.all(ClaySpacing.screenPadding),
                children: [
                  card('الفوج', [
                    ClayDropdown<String>(
                      label: 'المادة',
                      hint: 'اختر المادة',
                      value: _subjectId,
                      error: _errors[GroupService.fieldSubject],
                      options: [
                        for (final s in subjects)
                          ClayOption(
                            value: s.id,
                            label: s.levelName == null
                                ? s.name
                                : '${s.name} (${s.levelName})',
                          ),
                      ],
                      // المادة لا تتغير بعد الإنشاء: عليها مستحقات التلاميذ.
                      onChanged: _editing
                          ? null
                          : (value) => _changed(() {
                              _subjectId = value;
                              _teacherId = null;
                            }),
                    ),
                    gap,
                    ClayDropdown<String>(
                      label: 'الأستاذ',
                      hint: _subjectId == null
                          ? 'اختر المادة أولاً'
                          : teachers.isEmpty
                          ? 'لا أستاذ يدرّس هذه المادة'
                          : 'اختر الأستاذ',
                      value: _teacherId,
                      error: _errors[GroupService.fieldTeacher],
                      options: [
                        for (final t in teachers)
                          ClayOption(value: t.id, label: t.name),
                      ],
                      onChanged: (value) => _changed(() {
                        _teacherId = value;
                        // مبلغ الأستاذ الافتراضي من ملفه إن لم يُحدَّد.
                        final teacher = teachers
                            .where((t) => t.id == value)
                            .firstOrNull;
                        if (!_editing &&
                            _rate.text.isEmpty &&
                            teacher != null &&
                            teacher.ratePerStudent > 0) {
                          _rate.text = '${teacher.ratePerStudent}';
                        }
                      }),
                    ),
                    gap,
                    ClayDropdown<String?>(
                      label: 'القاعة الافتراضية',
                      value: _roomId,
                      options: [
                        const ClayOption(value: null, label: 'بلا قاعة'),
                        for (final r in rooms)
                          ClayOption(
                            value: r.id,
                            label: '${r.name} (${r.capacity})',
                          ),
                      ],
                      onChanged: (value) => _changed(() => _roomId = value),
                    ),
                    gap,
                    ClayTextField(
                      controller: _cycle,
                      label: 'عدد حصص الدورة (الشهر)',
                      enabled: !_editing,
                      keyboardType: TextInputType.number,
                      textDirection: TextDirection.ltr,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      helper: _editing
                          ? 'لا يتغير بعد الإنشاء لأنه أساس المستحقات'
                          : null,
                      error: _errors[GroupService.fieldCycleSize],
                      onChanged: (_) => _scheduleCheck(),
                    ),
                    if (!_editing) ...[gap, _firstDateField(context)],
                    gap,
                    ClayTextField(
                      controller: _rate,
                      label: 'نصيب الأستاذ لكل تلميذ (${Money.currency})',
                      keyboardType: TextInputType.number,
                      textDirection: TextDirection.ltr,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      helper: 'فارغ يعني قيمة الأستاذ الافتراضية',
                      error: _errors[GroupService.fieldRate],
                      onChanged: (_) => _scheduleCheck(),
                    ),
                  ]),
                  card('الجدول الأسبوعي', [
                    for (var i = 0; i < _slots.length; i++)
                      _SlotCard(
                        index: i,
                        slot: _slots[i],
                        rooms: rooms,
                        error: _errors[GroupService.slotField(i)],
                        onPickStart: () => _pickTime(_slots[i], start: true),
                        onPickEnd: () => _pickTime(_slots[i], start: false),
                        onWeekday: (day) =>
                            _changed(() => _slots[i].weekday = day),
                        onRoom: (room) =>
                            _changed(() => _slots[i].roomId = room),
                        onSuggest: () => _suggestRoom(_slots[i]),
                        onRemove: _slots.length > 1
                            ? () => _changed(() => _slots.removeAt(i))
                            : null,
                      ),
                    if (_errors[GroupService.fieldSlots] != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: ClaySpacing.sm),
                        child: Text(
                          _errors[GroupService.fieldSlots]!,
                          style: text.bodySmall!.copyWith(
                            color: p.status.danger,
                          ),
                        ),
                      ),
                    ClayButton(
                      label: 'إضافة خانة',
                      icon: ClayIcons.add,
                      kind: ClayButtonKind.secondary,
                      onPressed: () => _changed(() => _slots.add(_SlotDraft())),
                    ),
                  ]),
                  ClayButton(
                    label: _editing ? 'حفظ التعديلات' : 'إنشاء الفوج',
                    expand: true,
                    loading: _saving,
                    onPressed: _submit,
                  ),
                  if (_editing &&
                      ref.can(
                        PermissionModule.groups,
                        PermissionAction.delete,
                      )) ...[
                    gap,
                    ClayButton(
                      label: 'حذف الفوج',
                      icon: ClayIcons.delete,
                      kind: ClayButtonKind.danger,
                      expand: true,
                      onPressed: _saving ? null : _delete,
                    ),
                  ],
                  const SizedBox(height: ClaySpacing.xl),
                ],
              ),
            ),
          );

    return Scaffold(
      appBar: ClayAppBar(
        title: _editing ? 'تعديل الفوج' : 'إنشاء فوج',
        showBack: true,
      ),
      body: body,
    );
  }
}

/// بطاقة خانة أسبوعية: اليوم، الوقتان، القاعة، واقتراح قاعة، وخطؤها إن وُجد.
class _SlotCard extends StatelessWidget {
  const _SlotCard({
    required this.index,
    required this.slot,
    required this.rooms,
    required this.error,
    required this.onPickStart,
    required this.onPickEnd,
    required this.onWeekday,
    required this.onRoom,
    required this.onSuggest,
    required this.onRemove,
  });

  final int index;
  final _SlotDraft slot;
  final List<RoomRow> rooms;
  final String? error;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;
  final ValueChanged<int> onWeekday;
  final ValueChanged<String?> onRoom;
  final VoidCallback onSuggest;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: ClaySpacing.md),
      child: ClayContainer.flat(
        padding: const EdgeInsets.all(ClaySpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('الخانة ${index + 1}', style: text.titleSmall),
                ),
                if (onRemove != null)
                  IconButton(
                    tooltip: 'حذف الخانة ${index + 1}',
                    icon: const Icon(ClayIcons.close),
                    onPressed: onRemove,
                  ),
              ],
            ),
            ClayDropdown<int>(
              label: 'اليوم',
              searchable: false,
              value: slot.weekday,
              options: [
                for (final day in GroupService.displayWeekdays)
                  ClayOption(value: day, label: GroupService.weekdayName(day)),
              ],
              onChanged: (day) => onWeekday(day ?? slot.weekday),
            ),
            const SizedBox(height: ClaySpacing.md),
            Row(
              children: [
                Expanded(
                  child: ClayButton(
                    label: 'من ${DateKey.formatMinutes(slot.start)}',
                    icon: ClayIcons.schedule,
                    kind: ClayButtonKind.secondary,
                    onPressed: onPickStart,
                  ),
                ),
                const SizedBox(width: ClaySpacing.md),
                Expanded(
                  child: ClayButton(
                    label: 'إلى ${DateKey.formatMinutes(slot.end)}',
                    icon: ClayIcons.schedule,
                    kind: ClayButtonKind.secondary,
                    onPressed: onPickEnd,
                  ),
                ),
              ],
            ),
            const SizedBox(height: ClaySpacing.md),
            ClayDropdown<String?>(
              label: 'قاعة هذه الخانة',
              value: slot.roomId,
              options: [
                const ClayOption(value: null, label: 'قاعة الفوج'),
                for (final r in rooms)
                  ClayOption(value: r.id, label: '${r.name} (${r.capacity})'),
              ],
              onChanged: onRoom,
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: onSuggest,
                child: Text('اقتراح قاعة متاحة ${index + 1}'),
              ),
            ),
            if (error != null)
              Semantics(
                liveRegion: true,
                child: Text(
                  error!,
                  style: text.bodySmall!.copyWith(color: p.status.danger),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
