import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

/// قائمة المجموعات النشطة: رقمها ومادتها وأستاذها وقاعتها وجدولها وعدد
/// تلاميذها، مع الأرشفة.
class GroupsScreen extends ConsumerWidget {
  const GroupsScreen({super.key});

  Future<void> _archive(
    BuildContext context,
    WidgetRef ref,
    GroupItem item,
  ) async {
    final ok = await showClayConfirm(
      context,
      title: 'أرشفة المجموعة',
      message:
          'ستخرج المجموعة ${item.number} (${item.subjectName}) من القوائم '
          'النشطة وتبقى سجلاتها وحضورها ومدفوعاتها.',
      confirmLabel: 'أرشفة',
      danger: true,
    );
    if (ok) await ref.read(groupServiceProvider).archive(item.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canAdd = ref.can(PermissionModule.groups, PermissionAction.add);
    final canEdit = ref.can(PermissionModule.groups, PermissionAction.edit);
    final state = ref.watch(groupsProvider);
    return Column(
      children: [
        Expanded(
          child: state.when(
            loading: () => const ClaySkeletonList(),
            error: (_, _) => ClayErrorView(
              message: 'تعذّرت قراءة المجموعات',
              onRetry: () => ref.invalidate(groupsProvider),
            ),
            data: (items) {
              if (items.isEmpty) {
                return const ClayEmptyView(
                  title: 'لا توجد مجموعات بعد',
                  message: 'أنشئ مجموعة بجدولها الأسبوعي لتُولَّد حصصها',
                  icon: ClayIcons.groups,
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: ClaySpacing.screenPadding,
                  vertical: ClaySpacing.sm,
                ),
                itemCount: items.length,
                itemExtent: 112,
                itemBuilder: (context, i) {
                  final item = items[i];
                  return ClayListTile(
                    title: 'المجموعة ${item.number} · ${item.subjectName}',
                    subtitle:
                        '${item.teacherName} · ${item.roomName ?? 'بلا قاعة'} '
                        '· ${item.studentCount} تلميذ\n${item.scheduleText}',
                    subtitleLines: 2,
                    onTap: () => context.push('/groups/${item.id}'),
                    trailing: [
                      if (canEdit)
                        IconButton(
                          tooltip: 'تعديل المجموعة ${item.number}',
                          icon: const Icon(ClayIcons.edit),
                          onPressed: () =>
                              context.push('/groups/${item.id}/edit'),
                        ),
                      if (canEdit)
                        IconButton(
                          tooltip: 'أرشفة المجموعة ${item.number}',
                          icon: const Icon(ClayIcons.backup),
                          onPressed: () => _archive(context, ref, item),
                        ),
                    ],
                  );
                },
              );
            },
          ),
        ),
        if (canAdd)
          Padding(
            padding: const EdgeInsets.all(ClaySpacing.screenPadding),
            child: ClayButton(
              label: 'إنشاء مجموعة',
              icon: ClayIcons.add,
              expand: true,
              onPressed: () => context.push('/groups/new'),
            ),
          ),
      ],
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

  @override
  void initState() {
    super.initState();
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
    setState(() {
      _saving = true;
      _errors = const {};
    });
    final service = ref.read(groupServiceProvider);
    final today = DateKey.of(DateTime.now());
    try {
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
        await service.create(
          subjectId: subjectId,
          teacherId: teacherId,
          roomId: _roomId,
          sessionsPerCycle: int.tryParse(_cycle.text.trim()) ?? 0,
          ratePerStudent: _rateValue,
          slots: _inputs(),
          startDate: today,
        );
      }
      if (mounted) context.pop();
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
        ? const ClayEmptyView(title: 'هذه المجموعة غير موجودة')
        : Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.all(ClaySpacing.screenPadding),
                children: [
                  card('المجموعة', [
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
                    label: _editing ? 'حفظ التعديلات' : 'إنشاء المجموعة',
                    expand: true,
                    loading: _saving,
                    onPressed: _submit,
                  ),
                  const SizedBox(height: ClaySpacing.xl),
                ],
              ),
            ),
          );

    return Scaffold(
      appBar: ClayAppBar(
        title: _editing ? 'تعديل المجموعة' : 'إنشاء مجموعة',
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
                const ClayOption(value: null, label: 'قاعة المجموعة'),
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
