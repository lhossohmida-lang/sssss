import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

/// لون حالة الطلب.
ClayTone statusTone(SessionRequestStatus s) => switch (s) {
  SessionRequestStatus.pending => ClayTone.warning,
  SessionRequestStatus.approved => ClayTone.success,
  SessionRequestStatus.rejected => ClayTone.danger,
};

/// «السبت 2026-11-14 10:00–11:30».
String slotText(String date, int start, int end) =>
    '${GroupService.weekdayName(DateKey.weekday(date))} $date '
    '${DateKey.formatMinutes(start)}–${DateKey.formatMinutes(end)}';

/// طلباتي: كل طلبات الأستاذ بحالتها (قيد الانتظار، مقبول، مرفوض)، ومنها إلى
/// طلب جديد. النقر على طلب يعرض تفاصيله وملاحظة الإدارة.
class TeacherRequestsScreen extends ConsumerWidget {
  const TeacherRequestsScreen({super.key});

  void _details(BuildContext context, RequestItem item) {
    final r = item.request;
    showClayBottomSheet<void>(
      context,
      title: item.type.label,
      builder: (context) {
        final text = Theme.of(context).textTheme;
        Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: ClaySpacing.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 100,
                child: Text(
                  label,
                  style: text.bodyMedium!.copyWith(
                    color: context.palette.textMuted,
                  ),
                ),
              ),
              Expanded(child: Text(value, style: text.bodyLarge)),
            ],
          ),
        );

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            row('الحالة', item.status.label),
            row('المجموعة', item.groupLabel),
            if (item.sessionDate != null)
              row(
                'الحصة',
                '${item.sessionDate} '
                    '${DateKey.formatMinutes(item.sessionStart ?? 0)}',
              ),
            if (r.newDate != null)
              row(
                'الموعد الجديد',
                slotText(
                  r.newDate!,
                  r.newStartMinutes ?? 0,
                  r.newEndMinutes ?? 0,
                ),
              ),
            if (r.reason.isNotEmpty) row('السبب', r.reason),
            if (r.adminNote.isNotEmpty) row('ملاحظة الإدارة', r.adminNote),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(myRequestsProvider);
    return Column(
      children: [
        Expanded(
          child: requests.when(
            loading: () => const ClaySkeletonList(),
            error: (_, _) => ClayErrorView(
              message: 'تعذّرت قراءة طلباتك',
              onRetry: () => ref.invalidate(myRequestsProvider),
            ),
            data: (items) {
              if (items.isEmpty) {
                return const ClayEmptyView(
                  title: 'لا طلبات بعد',
                  message:
                      'اطلب تغيير موعد حصة أو إضافتها أو تسبيقها أو '
                      'إلغاءها؛ تقررها الإدارة',
                  icon: ClayIcons.schedule,
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: ClaySpacing.screenPadding,
                  vertical: ClaySpacing.sm,
                ),
                itemCount: items.length,
                itemExtent: 104,
                itemBuilder: (context, i) {
                  final item = items[i];
                  final r = item.request;
                  return ClayListTile(
                    title: '${item.type.label} · ${item.groupLabel}',
                    subtitle: r.newDate == null
                        ? (r.reason.isEmpty ? '—' : r.reason)
                        : slotText(
                            r.newDate!,
                            r.newStartMinutes ?? 0,
                            r.newEndMinutes ?? 0,
                          ),
                    onTap: () => _details(context, item),
                    trailing: [
                      ClayBadge(
                        label: item.status.label,
                        tone: statusTone(item.status),
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
            label: 'طلب جديد',
            icon: ClayIcons.add,
            expand: true,
            onPressed: () => context.push('/requests/new'),
          ),
        ),
      ],
    );
  }
}

/// طلب جديد: النوع (تغيير موعد / إضافة حصة / تسبيق / إلغاء) والمجموعة
/// والحصة والموعد الجديد والقاعة والسبب، مع فحص التعارض لحظياً واقتراح قاعة.
class NewRequestScreen extends ConsumerStatefulWidget {
  const NewRequestScreen({super.key});

  @override
  ConsumerState<NewRequestScreen> createState() => _NewRequestScreenState();
}

class _NewRequestScreenState extends ConsumerState<NewRequestScreen> {
  final _reason = TextEditingController();
  SessionRequestType _type = SessionRequestType.reschedule;
  String? _groupId;
  String? _sessionId;
  String? _date;
  int _start = 900;
  int _end = 990;
  String? _roomId;
  RequestPreview? _preview;
  String? _error;
  bool _saving = false;
  Timer? _debounce;
  int _token = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _reason.dispose();
    super.dispose();
  }

  void _changed(VoidCallback change) {
    setState(change);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _check);
  }

  Future<void> _check() async {
    final me = ref.read(myTeacherIdProvider);
    final groupId = _groupId;
    if (me == null || groupId == null) return;
    final token = ++_token;
    final result = await ref
        .read(requestServiceProvider)
        .preview(
          teacherId: me,
          groupId: groupId,
          type: _type,
          sessionId: _sessionId,
          newDate: _type.needsNewSlot ? _date : null,
          newStartMinutes: _type.needsNewSlot ? _start : null,
          newEndMinutes: _type.needsNewSlot ? _end : null,
          newRoomId: _type.needsNewSlot ? _roomId : null,
        );
    // نتيجة فحص أقدم من آخر تعديل تُهمل.
    if (!mounted || token != _token) return;
    setState(() => _preview = result);
  }

  Future<void> _pickDate() async {
    final picked = await showClayDatePicker(
      context,
      title: 'التاريخ الجديد',
      initial: _date == null ? null : DateKey.parse(_date!),
    );
    if (picked != null) _changed(() => _date = DateKey.of(picked));
  }

  Future<void> _pickTime({required bool start}) async {
    final picked = await showClayTimePicker(
      context,
      title: start ? 'بداية الحصة' : 'نهاية الحصة',
      initial: start ? _start : _end,
    );
    if (picked == null) return;
    _changed(() {
      if (start) {
        final length = _end - _start;
        _start = picked;
        _end = (picked + (length > 0 ? length : 90)).clamp(0, 24 * 60);
      } else {
        _end = picked;
      }
    });
  }

  void _selectSession(SessionRow? session) => _changed(() {
    _sessionId = session?.id;
    if (session != null && _type.needsNewSlot) {
      _date ??= session.date;
      _start = session.startMinutes;
      _end = session.endMinutes;
    }
  });

  Future<void> _submit() async {
    final me = ref.read(myTeacherIdProvider);
    final groupId = _groupId;
    if (me == null || groupId == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(requestServiceProvider)
          .submit(
            teacherId: me,
            groupId: groupId,
            type: _type,
            sessionId: _sessionId,
            newDate: _type.needsNewSlot ? _date : null,
            newStartMinutes: _type.needsNewSlot ? _start : null,
            newEndMinutes: _type.needsNewSlot ? _end : null,
            newRoomId: _type.needsNewSlot ? _roomId : null,
            reason: _reason.text,
          );
      if (mounted) context.pop();
    } on ScheduleConflictException catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } on InvalidRequestException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final groups = ref.watch(myGroupsProvider).value ?? const <GroupItem>[];
    final rooms = ref.watch(roomsProvider).value ?? const <RoomRow>[];
    final groupId = _groupId ?? (groups.isEmpty ? null : groups.first.id);
    if (_groupId == null && groupId != null) {
      // أول مجموعة افتراضياً.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _groupId == null) _changed(() => _groupId = groupId);
      });
    }
    final sessions = groupId == null
        ? const <SessionRow>[]
        : ref.watch(openSessionsProvider(groupId)).value ??
              const <SessionRow>[];
    final preview = _preview;
    const gap = SizedBox(height: ClaySpacing.md);

    return Scaffold(
      appBar: const ClayAppBar(title: 'طلب جديد', showBack: true),
      body: groups.isEmpty
          ? const ClayEmptyView(
              title: 'لا مجموعات لك',
              message: 'لا طلب دون مجموعة',
              icon: ClayIcons.groups,
            )
          : ListView(
              padding: const EdgeInsets.all(ClaySpacing.screenPadding),
              children: [
                Text('نوع الطلب', style: text.titleSmall),
                const SizedBox(height: ClaySpacing.xs),
                Wrap(
                  spacing: ClaySpacing.sm,
                  children: [
                    for (final type in SessionRequestType.values)
                      ClayChip(
                        label: type.label,
                        selected: _type == type,
                        onTap: () => _changed(() {
                          _type = type;
                          _sessionId = null;
                          _preview = null;
                        }),
                      ),
                  ],
                ),
                gap,
                ClayDropdown<String>(
                  label: 'المجموعة',
                  value: groupId,
                  options: [
                    for (final g in groups)
                      ClayOption(
                        value: g.id,
                        label: 'المجموعة ${g.number} · ${g.subjectName}',
                      ),
                  ],
                  onChanged: (v) => _changed(() {
                    _groupId = v;
                    _sessionId = null;
                    _preview = null;
                  }),
                ),
                if (_type.targetsExistingSession) ...[
                  gap,
                  ClayDropdown<String>(
                    label: 'الحصة',
                    hint: sessions.isEmpty ? 'لا حصص قادمة' : 'اختر الحصة',
                    value: _sessionId,
                    options: [
                      for (final s in sessions)
                        ClayOption(
                          value: s.id,
                          label: slotText(s.date, s.startMinutes, s.endMinutes),
                        ),
                    ],
                    onChanged: (v) => _selectSession(
                      sessions.where((s) => s.id == v).firstOrNull,
                    ),
                  ),
                ],
                if (_type.needsNewSlot) ...[
                  gap,
                  Text('الموعد الجديد', style: text.titleSmall),
                  const SizedBox(height: ClaySpacing.xs),
                  ClayButton(
                    label: _date == null ? 'اختر التاريخ' : 'التاريخ: $_date',
                    icon: ClayIcons.schedule,
                    kind: ClayButtonKind.secondary,
                    expand: true,
                    onPressed: _pickDate,
                  ),
                  const SizedBox(height: ClaySpacing.sm),
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
                  gap,
                  ClayDropdown<String?>(
                    label: 'القاعة',
                    value: _roomId,
                    options: [
                      const ClayOption(
                        value: null,
                        label: 'تلقائي (تُقترح قاعة متاحة)',
                      ),
                      for (final r in rooms)
                        ClayOption(value: r.id, label: r.name),
                    ],
                    onChanged: (v) => _changed(() => _roomId = v),
                  ),
                ],
                gap,
                ClayTextField(
                  controller: _reason,
                  label: 'سبب الطلب',
                  maxLines: 3,
                ),
                gap,
                if (preview != null) ...[
                  for (final c in preview.conflicts)
                    Padding(
                      padding: const EdgeInsets.only(bottom: ClaySpacing.xs),
                      child: Text(
                        c.message,
                        style: text.bodyMedium!.copyWith(
                          color: p.status.danger,
                        ),
                      ),
                    ),
                  if (preview.error != null)
                    Text(
                      preview.error!,
                      style: text.bodyMedium!.copyWith(color: p.status.danger),
                    ),
                  if (preview.ok && _type.needsNewSlot && _roomId == null)
                    Text(
                      preview.suggestedRoom == null
                          ? 'لا قاعة متاحة في هذا الوقت؛ تقررها الإدارة'
                          : 'القاعة المقترحة: ${preview.suggestedRoom!.name}',
                      style: text.bodyMedium!.copyWith(color: p.status.success),
                    ),
                  if (preview.ok && !_type.needsNewSlot)
                    Text(
                      'الإلغاء يُخرج الحصة من حساب الدورة وتُبرمج حصة بديلة '
                      'عند موافقة الإدارة',
                      style: text.bodySmall!.copyWith(color: p.textMuted),
                    ),
                ],
                if (_error != null)
                  Text(
                    _error!,
                    style: text.bodyMedium!.copyWith(color: p.status.danger),
                  ),
                const SizedBox(height: ClaySpacing.lg),
                ClayButton(
                  label: 'إرسال الطلب',
                  icon: ClayIcons.check,
                  expand: true,
                  loading: _saving,
                  onPressed: preview != null && preview.ok ? _submit : null,
                ),
              ],
            ),
    );
  }
}
