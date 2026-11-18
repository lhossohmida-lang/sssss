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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ClayButton(
                        label: 'إنشاء فوج',
                        icon: ClayIcons.add,
                        expand: true,
                        onPressed: () => context.push(
                          newSubject == null
                              ? '/groups/new'
                              : '/groups/new?subject=$newSubject',
                        ),
                      ),
                      const SizedBox(height: ClaySpacing.sm),
                      ClayButton(
                        label: 'حصة مراجعة (حصة واحدة)',
                        icon: ClayIcons.schedule,
                        kind: ClayButtonKind.secondary,
                        expand: true,
                        onPressed: () => context.push('/groups/review'),
                      ),
                    ],
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
        // فوج منتظِر: له عدد مطلوب ولا جدول بعد (يُحدَّد جدوله عند تحديد أول حصة).
        final target = item.group.waitingTarget;
        final waiting = target != null && item.slots.isEmpty;
        return ClayListTile(
          title: item.group.isReview
              ? 'فوج ${item.number} · حصة مراجعة'
              : 'فوج ${item.number}',
          subtitle:
              '${item.teacherName} · ${item.roomName ?? 'بلا قاعة'} '
              '· ${item.studentCount} تلميذ\n'
              '${waiting
                  ? 'منتظِر ${item.studentCount} من $target — بلا موعد لأول حصة بعد'
                  : item.group.isReview
                  ? 'حصة واحدة · ${Money.format(item.group.monthlyPrice)}'
                  : item.scheduleText}',
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
  final _price = TextEditingController();
  final _rate = TextEditingController();
  final _target = TextEditingController();
  final List<_SlotDraft> _slots = [_SlotDraft()];

  /// فوج منتظِر: ينسب إليه المدير تلاميذه دون موعد لأول حصة، وينتظر بلوغ العدد المطلوب ([_target]).
  bool _waiting = false;

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

  /// سعر المادة الافتراضي مقترحاً لسعر الفوج (يُكتب غيره إن شاء)، أو فارغ إن لم يُحدَّد لها سعر.
  String _subjectPriceText(List<SubjectItem> subjects, String? subjectId) {
    final price = subjects
        .where((s) => s.id == subjectId)
        .firstOrNull
        ?.monthlyPrice;
    return price == null || price <= 0 ? '' : '$price';
  }

  /// يملأ المادة والأستاذ المقترحين (إن كان الأستاذ يدرّس المادة) ونصيبه
  /// الافتراضي من ملفه، وسعر الفوج من سعر المادة.
  Future<void> _prefill() async {
    final subjectId = widget.initialSubjectId!;
    final teachers = await ref.read(subjectTeachersProvider(subjectId).future);
    final subjects = await ref.read(subjectsProvider.future);
    if (!mounted) return;
    final teacher = teachers
        .where((t) => t.id == widget.initialTeacherId)
        .firstOrNull;
    setState(() {
      _subjectId = subjectId;
      _price.text = _subjectPriceText(subjects, subjectId);
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
    _price.dispose();
    _rate.dispose();
    _target.dispose();
    super.dispose();
  }

  Future<void> _loadExisting() async {
    final runtime = ref.read(runtimeProvider);
    final group = await (runtime.db.select(
      runtime.db.groups,
    )..where((g) => g.id.equals(widget.groupId!))).getSingleOrNull();
    final slots = await ref.read(groupServiceProvider).slotsOf(widget.groupId!);
    final price = group == null ? 0 : await GroupPrice.of(runtime.db, group);
    if (!mounted) return;
    setState(() {
      _existing = group;
      _loaded = true;
      if (group != null) {
        _subjectId = group.subjectId;
        _teacherId = group.teacherId;
        _roomId = group.roomId;
        _cycle.text = '${group.sessionsPerCycle}';
        _price.text = price > 0 ? '$price' : '';
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

  int? get _priceValue =>
      _price.text.trim().isEmpty ? null : int.tryParse(_price.text.trim());

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
          monthlyPrice: _priceValue,
          slots: _noSchedule ? const [] : _inputs(),
          excludeGroupId: widget.groupId,
          requireSlots: !_noSchedule,
        );
    // نتيجة فحص أقدم من آخر تعديل تُهمَل.
    if (!mounted || token != _checkToken) return;
    setState(() => _errors = errors);
  }

  void _changed(VoidCallback change) {
    setState(change);
    _scheduleCheck();
  }

  /// بلا جدول أسبوعي الآن: فوج منتظِر قيد الإنشاء، أو فوج منتظِر قائم لم يبدأ (جدوله عند تحديد أول حصة).
  bool get _noSchedule =>
      _waiting ||
      (_editing && _existing?.waitingTarget != null && _slots.isEmpty);

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
    // سعر الفوج ومبلغ أستاذه يُكتبان عند الإنشاء ولا يُتركان فارغين.
    if (!_editing) {
      final missing = {
        if (_priceValue == null)
          GroupService.fieldPrice: 'أدخل سعر الشهر للتلميذ',
        if (_rateValue == null)
          GroupService.fieldRate: 'أدخل ما يأخذه الأستاذ عن كل تلميذ',
      };
      if (missing.isNotEmpty) {
        setState(() => _errors = missing);
        return;
      }
    }
    final now = _dayOf(DateTime.now());
    final targetValue = int.tryParse(_target.text.trim());
    if (_waiting && !_editing) {
      final targetError = GroupService.waitingTargetError(targetValue);
      if (targetError != null) {
        setState(
          () => _errors = {GroupService.fieldWaitingTarget: targetError},
        );
        return;
      }
    }
    final dateError = _editing || _waiting ? null : _firstDateError(now);
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
          monthlyPrice: _priceValue,
          ratePerStudent: _rateValue,
          slots: _noSchedule ? const [] : _inputs(),
          today: today,
          requireSlots: !_noSchedule,
        );
      } else if (_waiting) {
        created = await service.createWaiting(
          subjectId: subjectId,
          teacherId: teacherId,
          roomId: _roomId,
          sessionsPerCycle: int.tryParse(_cycle.text.trim()) ?? 0,
          monthlyPrice: _priceValue,
          ratePerStudent: _rateValue,
          waitingTarget: targetValue!,
        );
      } else {
        created = await service.create(
          subjectId: subjectId,
          teacherId: teacherId,
          roomId: _roomId,
          sessionsPerCycle: int.tryParse(_cycle.text.trim()) ?? 0,
          monthlyPrice: _priceValue,
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
        final from = firstIsPast && !_waiting
            ? '?from=${DateKey.of(_firstDate)}'
            : '';
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
    // السعر ومبلغ الأستاذ لا يتغيّران بعد ربط تلميذ بالفوج.
    final valuesLocked =
        _editing &&
        (ref.watch(groupItemProvider(widget.groupId!))?.studentCount ?? 0) > 0;

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
                              // سعر المادة مقترح لسعر الفوج (سنة المادة تحدد سعرها).
                              _price.text = _subjectPriceText(subjects, value);
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
                    if (!_editing) ...[
                      gap,
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'فوج منتظِر (بلا موعد لأول حصة بعد)',
                              style: text.bodyLarge,
                            ),
                          ),
                          ClayToggle(
                            value: _waiting,
                            semanticLabel: 'فوج منتظِر',
                            onChanged: (value) => _changed(() {
                              _waiting = value;
                            }),
                          ),
                        ],
                      ),
                      if (_waiting) ...[
                        gap,
                        ClayTextField(
                          controller: _target,
                          label: 'عدد التلاميذ المطلوب لبدء الفوج',
                          keyboardType: TextInputType.number,
                          textDirection: TextDirection.ltr,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          helper:
                              'ينسب المدير تلاميذه إليه، وعند بلوغ هذا العدد يصله إشعار في '
                              'التطبيق ورسالة SMS ليحدد تاريخ أول حصة. يُحدَّد هنا فقط.',
                          error: _errors[GroupService.fieldWaitingTarget],
                        ),
                      ] else ...[
                        gap,
                        _firstDateField(context),
                      ],
                    ],
                    gap,
                    ClayTextField(
                      controller: _price,
                      label: 'سعر الشهر للتلميذ (${Money.currency})',
                      enabled: !valuesLocked,
                      keyboardType: TextInputType.number,
                      textDirection: TextDirection.ltr,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      helper: valuesLocked
                          ? 'لا يتغيّر بعد ربط التلاميذ بالفوج'
                          : 'يدفعه كل تلميذ عن الدورة في هذا الفوج؛ يُعيَّن عند '
                                'إنشائه فقط، ويظهر كما كُتب عند ربط التلاميذ به',
                      error: _errors[GroupService.fieldPrice],
                      onChanged: (_) => _scheduleCheck(),
                    ),
                    gap,
                    ClayTextField(
                      controller: _rate,
                      label: 'نصيب الأستاذ لكل تلميذ (${Money.currency})',
                      enabled: !valuesLocked,
                      keyboardType: TextInputType.number,
                      textDirection: TextDirection.ltr,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      helper: valuesLocked
                          ? 'لا يتغيّر بعد ربط التلاميذ بالفوج'
                          : 'يأخذه الأستاذ عن كل تلميذ في هذا الفوج؛ يُعيَّن عند '
                                'إنشائه فقط',
                      error: _errors[GroupService.fieldRate],
                      onChanged: (_) => _scheduleCheck(),
                    ),
                  ]),
                  if (_noSchedule)
                    card('الجدول الأسبوعي', [
                      Text(
                        'لا جدول لفوج منتظِر قبل تحديد تاريخ أول حصة: عند اكتمال العدد '
                        'تحدد التاريخ وأيام الحصص من صفحة الفوج.',
                        style: text.bodyMedium!.copyWith(color: p.textMuted),
                      ),
                      if (_editing) ...[
                        gap,
                        ClayButton(
                          label: 'تحديد تاريخ أول حصة',
                          icon: ClayIcons.schedule,
                          kind: ClayButtonKind.secondary,
                          onPressed: () =>
                              context.push('/groups/${widget.groupId}/start'),
                        ),
                      ],
                    ])
                  else
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
                          padding: const EdgeInsets.only(
                            bottom: ClaySpacing.sm,
                          ),
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
                        onPressed: () =>
                            _changed(() => _slots.add(_SlotDraft())),
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

/// تحديد تاريخ أول حصة لفوج منتظِر: يُختار التاريخ وأيام الحصص، فيحفظ الجدول ويولّد حصص الدورة الأولى
/// ويخبر أولياء التلاميذ بالموعد.
class WaitingGroupStartScreen extends ConsumerStatefulWidget {
  const WaitingGroupStartScreen({required this.groupId, super.key});

  final String groupId;

  @override
  ConsumerState<WaitingGroupStartScreen> createState() =>
      _WaitingGroupStartScreenState();
}

class _WaitingGroupStartScreenState
    extends ConsumerState<WaitingGroupStartScreen> {
  final List<_SlotDraft> _slots = [_SlotDraft()];
  late DateTime _startDate = _dayOf(DateTime.now());
  Map<String, String> _errors = const {};
  bool _saving = false;
  Timer? _debounce;
  int _checkToken = 0;

  static DateTime _dayOf(DateTime time) =>
      DateTime(time.year, time.month, time.day);

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
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

  void _changed(VoidCallback change) {
    setState(change);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _check);
  }

  /// يفحص تعارض الجدول مع أفواج الأستاذ والقاعة لحظياً.
  Future<void> _check() async {
    final group = ref
        .read(waitingGroupsProvider)
        .value
        ?.where((w) => w.id == widget.groupId)
        .firstOrNull
        ?.group;
    if (group == null) return;
    final token = ++_checkToken;
    final errors = await ref
        .read(groupServiceProvider)
        .validate(
          subjectId: group.subjectId,
          teacherId: group.teacherId,
          roomId: group.roomId,
          sessionsPerCycle: group.sessionsPerCycle,
          ratePerStudent: null,
          monthlyPrice: null,
          slots: _inputs(),
          excludeGroupId: widget.groupId,
        );
    if (!mounted || token != _checkToken) return;
    setState(() => _errors = errors);
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
        final length = slot.end - slot.start;
        slot.start = picked;
        slot.end = (picked + (length > 0 ? length : 90)).clamp(0, 24 * 60);
      } else {
        slot.end = picked;
      }
    });
  }

  Future<void> _pickDate() async {
    final picked = await showClayDatePicker(
      context,
      title: 'تاريخ أول حصة',
      initial: _startDate,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _startDate = _dayOf(picked);
      _errors = {..._errors}..remove(GroupService.fieldFirstDate);
    });
  }

  Future<void> _submit() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _errors = const {};
    });
    try {
      await ref
          .read(groupServiceProvider)
          .startWaiting(
            widget.groupId,
            slots: _inputs(),
            startDate: DateKey.of(_startDate),
            today: DateKey.of(DateTime.now()),
          );
      if (mounted) context.pushReplacement('/groups/${widget.groupId}');
    } on ValidationException catch (e) {
      if (mounted) setState(() => _errors = e.errors);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final rooms = ref.watch(roomsProvider).value ?? const <RoomRow>[];
    final waiting = ref
        .watch(waitingGroupsProvider)
        .value
        ?.where((w) => w.id == widget.groupId)
        .firstOrNull;
    final loading = ref.watch(waitingGroupsProvider).isLoading;
    return Scaffold(
      appBar: const ClayAppBar(title: 'تحديد تاريخ أول حصة', showBack: true),
      body: waiting == null
          ? (loading
                ? const ClayLoadingView()
                : const ClayEmptyView(
                    title: 'هذا الفوج ليس منتظِراً',
                    message: 'بدأ فوجه أو حُذف',
                  ))
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.all(ClaySpacing.screenPadding),
                  children: [
                    ClayCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${waiting.subjectName} · الفوج ${waiting.number}',
                            style: text.titleMedium,
                          ),
                          const SizedBox(height: ClaySpacing.xs),
                          Text(
                            '${waiting.teacherName} · ${waiting.studentCount} '
                            'من ${waiting.target} تلميذاً'
                            '${waiting.isReady ? ' — اكتمل العدد' : ''}',
                            style: text.bodyMedium,
                          ),
                          const SizedBox(height: ClaySpacing.md),
                          Text('تاريخ أول حصة', style: text.labelLarge),
                          const SizedBox(height: ClaySpacing.xs),
                          Row(
                            children: [
                              Expanded(
                                child: Align(
                                  alignment: AlignmentDirectional.centerStart,
                                  child: Directionality(
                                    textDirection: TextDirection.ltr,
                                    child: Text(
                                      DateKey.of(_startDate),
                                      style: text.titleMedium,
                                    ),
                                  ),
                                ),
                              ),
                              ClayButton(
                                label: 'تغيير التاريخ',
                                kind: ClayButtonKind.secondary,
                                onPressed: _saving ? null : _pickDate,
                              ),
                            ],
                          ),
                          if (_errors[GroupService.fieldFirstDate] != null)
                            Text(
                              _errors[GroupService.fieldFirstDate]!,
                              style: text.bodySmall!.copyWith(
                                color: p.status.danger,
                              ),
                            ),
                          const SizedBox(height: ClaySpacing.xs),
                          Text(
                            'تُولَّد حصص الدورة من هذا التاريخ بحسب أيام الحصص أدناه، ويصل '
                            'أولياء التلاميذ رسالة بالموعد.',
                            style: text.bodySmall!.copyWith(color: p.textMuted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: ClaySpacing.lg),
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
                        onSuggest: () async {
                          final free = await ref
                              .read(scheduleServiceProvider)
                              .freeRoomsForSlot(
                                weekday: _slots[i].weekday,
                                startMinutes: _slots[i].start,
                                endMinutes: _slots[i].end,
                                excludeGroupId: widget.groupId,
                              );
                          if (free.isNotEmpty && mounted) {
                            _changed(() => _slots[i].roomId = free.first.id);
                          }
                        },
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
                    if (_errors[GroupService.fieldGroup] != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: ClaySpacing.sm),
                        child: Text(
                          _errors[GroupService.fieldGroup]!,
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
                    const SizedBox(height: ClaySpacing.lg),
                    ClayButton(
                      label: 'بدء الفوج',
                      expand: true,
                      loading: _saving,
                      onPressed: _submit,
                    ),
                    const SizedBox(height: ClaySpacing.xl),
                  ],
                ),
              ),
            ),
    );
  }
}

/// حصة مراجعة: فوج من حصة واحدة في يوم محدد، بثمن للحصة ونصيب للأستاذ عن كل حاضر. يحضرها تلاميذ لمرة
/// واحدة (يدفعون ثمنها ويأخذون تذكرة QR لمرة واحدة) أو تلاميذ فوج آخر؛ يُضافون من ورقة حضور الحصة.
class ReviewSessionFormScreen extends ConsumerStatefulWidget {
  const ReviewSessionFormScreen({super.key});

  @override
  ConsumerState<ReviewSessionFormScreen> createState() =>
      _ReviewSessionFormScreenState();
}

class _ReviewSessionFormScreenState
    extends ConsumerState<ReviewSessionFormScreen> {
  final _fee = TextEditingController();
  final _rate = TextEditingController();
  String? _subjectId;
  String? _teacherId;
  String? _roomId;
  late DateTime _date = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );
  int _start = 600;
  int _end = 780;
  Map<String, String> _errors = const {};
  bool _saving = false;

  @override
  void dispose() {
    _fee.dispose();
    _rate.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showClayDatePicker(
      context,
      title: 'تاريخ الحصة',
      initial: _date,
    );
    if (picked == null || !mounted) return;
    setState(() => _date = DateTime(picked.year, picked.month, picked.day));
  }

  Future<void> _pickTime({required bool start}) async {
    final picked = await showClayTimePicker(
      context,
      title: start ? 'بداية الحصة' : 'نهاية الحصة',
      initial: start ? _start : _end,
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        final length = _end - _start;
        _start = picked;
        _end = (picked + (length > 0 ? length : 120)).clamp(0, 24 * 60);
      } else {
        _end = picked;
      }
    });
  }

  Future<void> _submit() async {
    if (_saving) return;
    final subjectId = _subjectId;
    final teacherId = _teacherId;
    final fee = int.tryParse(_fee.text.trim());
    final rate = int.tryParse(_rate.text.trim());
    final missing = {
      if (subjectId == null) GroupService.fieldSubject: 'اختر المادة',
      if (teacherId == null) GroupService.fieldTeacher: 'اختر الأستاذ',
      if (fee == null) GroupService.fieldPrice: 'أدخل ثمن الحصة',
      if (rate == null)
        GroupService.fieldRate: 'أدخل ما يأخذه الأستاذ عن كل حاضر',
    };
    if (missing.isNotEmpty) {
      setState(() => _errors = missing);
      return;
    }
    setState(() {
      _saving = true;
      _errors = const {};
    });
    try {
      final group = await ref
          .read(groupServiceProvider)
          .createReview(
            subjectId: subjectId!,
            teacherId: teacherId!,
            roomId: _roomId,
            date: DateKey.of(_date),
            startMinutes: _start,
            endMinutes: _end,
            fee: fee!,
            teacherAmount: rate!,
            today: DateKey.of(DateTime.now()),
          );
      if (!mounted) return;
      // تُفتح ورقة حضور الحصة لإضافة الضيوف.
      final sessionId = await ref
          .read(groupServiceProvider)
          .firstSessionId(group.id);
      if (!mounted) return;
      context.pushReplacement(
        sessionId == null ? '/groups/${group.id}' : '/attendance/$sessionId',
      );
    } on ValidationException catch (e) {
      if (mounted) setState(() => _errors = e.errors);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
    return Scaffold(
      appBar: const ClayAppBar(title: 'حصة مراجعة', showBack: true),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(ClaySpacing.screenPadding),
            children: [
              Text(
                'فوج من حصة واحدة. يحضرها تلاميذ لمرة واحدة (يدفعون ثمنها فقط ويأخذون تذكرة '
                'QR تُستعمل مرة واحدة)، ويمكن لتلميذ مسجَّل في فوج آخر أن يحضرها فتظهر في ملفه.',
                style: text.bodyMedium!.copyWith(color: p.textMuted),
              ),
              gap,
              ClayCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
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
                      onChanged: (value) => setState(() {
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
                      onChanged: (value) => setState(() {
                        _teacherId = value;
                        final teacher = teachers
                            .where((t) => t.id == value)
                            .firstOrNull;
                        if (_rate.text.isEmpty &&
                            teacher != null &&
                            teacher.ratePerStudent > 0) {
                          _rate.text = '${teacher.ratePerStudent}';
                        }
                      }),
                    ),
                    gap,
                    ClayDropdown<String?>(
                      label: 'القاعة',
                      value: _roomId,
                      options: [
                        const ClayOption(value: null, label: 'بلا قاعة'),
                        for (final r in rooms)
                          ClayOption(
                            value: r.id,
                            label: '${r.name} (${r.capacity})',
                          ),
                      ],
                      onChanged: (value) => setState(() => _roomId = value),
                    ),
                    gap,
                    Text('تاريخ الحصة', style: text.labelLarge),
                    Row(
                      children: [
                        Expanded(
                          child: Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Directionality(
                              textDirection: TextDirection.ltr,
                              child: Text(
                                DateKey.of(_date),
                                style: text.titleMedium,
                              ),
                            ),
                          ),
                        ),
                        ClayButton(
                          label: 'تغيير التاريخ',
                          kind: ClayButtonKind.secondary,
                          onPressed: _saving ? null : _pickDate,
                        ),
                      ],
                    ),
                    if (_errors[GroupService.fieldDate] != null)
                      Text(
                        _errors[GroupService.fieldDate]!,
                        style: text.bodySmall!.copyWith(color: p.status.danger),
                      ),
                    gap,
                    Row(
                      children: [
                        Expanded(
                          child: ClayButton(
                            label: 'من ${DateKey.formatMinutes(_start)}',
                            kind: ClayButtonKind.secondary,
                            onPressed: () => _pickTime(start: true),
                          ),
                        ),
                        const SizedBox(width: ClaySpacing.sm),
                        Expanded(
                          child: ClayButton(
                            label: 'إلى ${DateKey.formatMinutes(_end)}',
                            kind: ClayButtonKind.secondary,
                            onPressed: () => _pickTime(start: false),
                          ),
                        ),
                      ],
                    ),
                    if (_errors[GroupService.slotField(0)] != null)
                      Text(
                        _errors[GroupService.slotField(0)]!,
                        style: text.bodySmall!.copyWith(color: p.status.danger),
                      ),
                    gap,
                    ClayTextField(
                      controller: _fee,
                      label: 'ثمن الحصة (${Money.currency})',
                      keyboardType: TextInputType.number,
                      textDirection: TextDirection.ltr,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      helper: 'يدفعه كل من يحضرها؛ ويمكن تغييره لضيف بعينه',
                      error: _errors[GroupService.fieldPrice],
                    ),
                    gap,
                    ClayTextField(
                      controller: _rate,
                      label: 'نصيب الأستاذ عن كل حاضر (${Money.currency})',
                      keyboardType: TextInputType.number,
                      textDirection: TextDirection.ltr,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      error: _errors[GroupService.fieldRate],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: ClaySpacing.lg),
              ClayButton(
                label: 'إنشاء حصة المراجعة',
                expand: true,
                loading: _saving,
                onPressed: _submit,
              ),
              const SizedBox(height: ClaySpacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}
