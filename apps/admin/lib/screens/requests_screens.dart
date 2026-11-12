import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

/// لون حالة الطلب.
ClayTone requestTone(SessionRequestStatus s) => switch (s) {
  SessionRequestStatus.pending => ClayTone.warning,
  SessionRequestStatus.approved => ClayTone.success,
  SessionRequestStatus.rejected => ClayTone.danger,
};

/// «السبت 2026-11-14 10:00–11:30».
String requestSlotText(String date, int start, int end) =>
    '${GroupService.weekdayName(DateKey.weekday(date))} $date '
    '${DateKey.formatMinutes(start)}–${DateKey.formatMinutes(end)}';

/// طلبات الأساتذة: المعلّقة أولاً (وهي الافتراضية)، وحصر بالحالة، ومنها إلى
/// تفاصيل الطلب للبتّ فيه.
class RequestsScreen extends ConsumerStatefulWidget {
  const RequestsScreen({super.key});

  @override
  ConsumerState<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends ConsumerState<RequestsScreen> {
  SessionRequestStatus? _status = SessionRequestStatus.pending;

  @override
  Widget build(BuildContext context) {
    final requests = ref.watch(allRequestsProvider(_status));
    final pending = ref.watch(pendingRequestsCountProvider).value ?? 0;
    return Scaffold(
      appBar: const ClayAppBar(title: 'طلبات الأساتذة', showBack: true),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ClaySpacing.screenPadding,
            ),
            child: Wrap(
              spacing: ClaySpacing.sm,
              children: [
                ClayChip(
                  label: pending > 0
                      ? 'قيد الانتظار ($pending)'
                      : 'قيد الانتظار',
                  selected: _status == SessionRequestStatus.pending,
                  onTap: () =>
                      setState(() => _status = SessionRequestStatus.pending),
                ),
                ClayChip(
                  label: 'المقبولة',
                  selected: _status == SessionRequestStatus.approved,
                  onTap: () =>
                      setState(() => _status = SessionRequestStatus.approved),
                ),
                ClayChip(
                  label: 'المرفوضة',
                  selected: _status == SessionRequestStatus.rejected,
                  onTap: () =>
                      setState(() => _status = SessionRequestStatus.rejected),
                ),
                ClayChip(
                  label: 'الكل',
                  selected: _status == null,
                  onTap: () => setState(() => _status = null),
                ),
              ],
            ),
          ),
          Expanded(
            child: requests.when(
              loading: () => const ClaySkeletonList(),
              error: (_, _) => ClayErrorView(
                message: 'تعذّرت قراءة الطلبات',
                onRetry: () => ref.invalidate(allRequestsProvider),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return ClayEmptyView(
                    title: _status == SessionRequestStatus.pending
                        ? 'لا طلبات معلّقة'
                        : 'لا طلبات',
                    message: 'تصل هنا طلبات الأساتذة لتغيير حصصهم',
                    icon: ClayIcons.schedule,
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(ClaySpacing.screenPadding),
                  itemCount: items.length,
                  itemExtent: 112,
                  itemBuilder: (context, i) {
                    final item = items[i];
                    final r = item.request;
                    return ClayListTile(
                      title: '${item.teacherName} · ${item.type.label}',
                      subtitle:
                          '${item.groupLabel}\n'
                          '${r.newDate == null ? (r.reason.isEmpty ? '—' : r.reason) : requestSlotText(r.newDate!, r.newStartMinutes ?? 0, r.newEndMinutes ?? 0)}',
                      subtitleLines: 2,
                      onTap: () => context.push('/requests/${item.id}'),
                      trailing: [
                        ClayBadge(
                          label: item.status.label,
                          tone: requestTone(item.status),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// تفاصيل طلب: بياناته وسببه، وللمعلّق منه موافقة (مع إمكان تعديل التاريخ
/// والوقت والقاعة بفحص تعارض لحظي) أو رفض بملاحظة. الموافقة تُحدّث الجدول
/// وتُنبّه الأولياء والأستاذ؛ ولا يتغير شيء دونها.
class RequestDetailsScreen extends ConsumerStatefulWidget {
  const RequestDetailsScreen({required this.requestId, super.key});

  final String requestId;

  @override
  ConsumerState<RequestDetailsScreen> createState() =>
      _RequestDetailsScreenState();
}

class _RequestDetailsScreenState extends ConsumerState<RequestDetailsScreen> {
  final _note = TextEditingController();
  String? _date;
  int _start = 0;
  int _end = 0;
  String? _roomId;
  bool _initialised = false;
  RequestPreview? _preview;
  String? _error;
  bool _saving = false;
  Timer? _debounce;
  int _token = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _note.dispose();
    super.dispose();
  }

  void _init(RequestItem item) {
    if (_initialised) return;
    _initialised = true;
    final r = item.request;
    _date = r.newDate;
    _start = r.newStartMinutes ?? 0;
    _end = r.newEndMinutes ?? 0;
    _roomId = r.newRoomId;
    if (item.status == SessionRequestStatus.pending) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _check(item));
    }
  }

  void _changed(RequestItem item, VoidCallback change) {
    setState(change);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => _check(item));
  }

  Future<void> _check(RequestItem item) async {
    final r = item.request;
    final token = ++_token;
    final type = item.type;
    final result = await ref
        .read(requestServiceProvider)
        .preview(
          teacherId: r.teacherId,
          groupId: r.groupId,
          type: type,
          sessionId: r.sessionId,
          newDate: type.needsNewSlot ? _date : null,
          newStartMinutes: type.needsNewSlot ? _start : null,
          newEndMinutes: type.needsNewSlot ? _end : null,
          newRoomId: type.needsNewSlot ? _roomId : null,
        );
    if (!mounted || token != _token) return;
    setState(() => _preview = result);
  }

  Future<void> _pickDate(RequestItem item) async {
    final picked = await showClayDatePicker(
      context,
      title: 'التاريخ',
      initial: _date == null ? null : DateKey.parse(_date!),
    );
    if (picked != null) _changed(item, () => _date = DateKey.of(picked));
  }

  Future<void> _pickTime(RequestItem item, {required bool start}) async {
    final picked = await showClayTimePicker(
      context,
      title: start ? 'بداية الحصة' : 'نهاية الحصة',
      initial: start ? _start : _end,
    );
    if (picked == null) return;
    _changed(item, () {
      if (start) {
        final length = _end - _start;
        _start = picked;
        _end = (picked + (length > 0 ? length : 90)).clamp(0, 24 * 60);
      } else {
        _end = picked;
      }
    });
  }

  Future<void> _approve(RequestItem item) async {
    final reviewer = ref.read(sessionProvider).value?.accountId;
    if (reviewer == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final type = item.type;
    try {
      final result = await ref
          .read(requestServiceProvider)
          .approve(
            item.id,
            reviewerId: reviewer,
            date: type.needsNewSlot ? _date : null,
            startMinutes: type.needsNewSlot ? _start : null,
            endMinutes: type.needsNewSlot ? _end : null,
            roomId: type.needsNewSlot ? _roomId : null,
            note: _note.text,
          );
      ref.invalidate(requestItemProvider(item.id));
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            result.smsQueued == 0
                ? 'قُبل الطلب وحُدّث الجدول'
                : 'قُبل الطلب وحُدّث الجدول، وأُرسلت ${result.smsQueued} '
                      'رسالة للأولياء',
          ),
        ),
      );
    } on ScheduleConflictException catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } on InvalidRequestException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reject(RequestItem item) async {
    final note = _note.text.trim();
    if (note.isEmpty) {
      setState(() => _error = 'اكتب سبب الرفض ليصل الأستاذ');
      return;
    }
    final ok = await showClayConfirm(
      context,
      title: 'رفض الطلب',
      message: 'سيُبلَّغ ${item.teacherName} برفض طلبه ولا يتغير الجدول.',
      confirmLabel: 'رفض',
      danger: true,
    );
    final reviewer = ref.read(sessionProvider).value?.accountId;
    if (!ok || reviewer == null || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(requestServiceProvider)
          .reject(item.id, reviewerId: reviewer, note: note);
      ref.invalidate(requestItemProvider(item.id));
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
    final state = ref.watch(requestItemProvider(widget.requestId));
    final rooms = ref.watch(roomsProvider).value ?? const <RoomRow>[];
    final canDecide = ref.can(PermissionModule.requests, PermissionAction.edit);
    return Scaffold(
      appBar: const ClayAppBar(title: 'تفاصيل الطلب', showBack: true),
      body: state.when(
        loading: () => const ClayLoadingView(),
        error: (_, _) => ClayErrorView(
          message: 'تعذّرت قراءة الطلب',
          onRetry: () => ref.invalidate(requestItemProvider),
        ),
        data: (item) {
          if (item == null) {
            return const ClayEmptyView(title: 'هذا الطلب غير موجود');
          }
          _init(item);
          final r = item.request;
          final pending = item.status == SessionRequestStatus.pending;
          final preview = _preview;
          Widget row(String label, String value) => Padding(
            padding: const EdgeInsets.symmetric(vertical: ClaySpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 110,
                  child: Text(
                    label,
                    style: text.bodyMedium!.copyWith(color: p.textMuted),
                  ),
                ),
                Expanded(child: Text(value, style: text.bodyLarge)),
              ],
            ),
          );
          return ListView(
            padding: const EdgeInsets.all(ClaySpacing.screenPadding),
            children: [
              ClayCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${item.type.label} · ${item.teacherName}',
                            style: text.titleMedium,
                          ),
                        ),
                        ClayBadge(
                          label: item.status.label,
                          tone: requestTone(item.status),
                        ),
                      ],
                    ),
                    const SizedBox(height: ClaySpacing.sm),
                    row('المجموعة', item.groupLabel),
                    if (item.sessionDate != null)
                      row(
                        'الحصة الحالية',
                        '${item.sessionDate} '
                            '${DateKey.formatMinutes(item.sessionStart ?? 0)}',
                      ),
                    if (r.newDate != null)
                      row(
                        'المطلوب',
                        requestSlotText(
                          r.newDate!,
                          r.newStartMinutes ?? 0,
                          r.newEndMinutes ?? 0,
                        ),
                      ),
                    if (r.reason.isNotEmpty) row('السبب', r.reason),
                    if (r.adminNote.isNotEmpty)
                      row('ملاحظة الإدارة', r.adminNote),
                  ],
                ),
              ),
              if (pending && canDecide) ...[
                const SizedBox(height: ClaySpacing.lg),
                if (item.type.needsNewSlot) ...[
                  Text('الموعد عند الموافقة', style: text.titleSmall),
                  const SizedBox(height: ClaySpacing.xs),
                  ClayButton(
                    label: _date == null ? 'اختر التاريخ' : 'التاريخ: $_date',
                    icon: ClayIcons.schedule,
                    kind: ClayButtonKind.secondary,
                    expand: true,
                    onPressed: () => _pickDate(item),
                  ),
                  const SizedBox(height: ClaySpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: ClayButton(
                          label: 'من ${DateKey.formatMinutes(_start)}',
                          kind: ClayButtonKind.secondary,
                          onPressed: () => _pickTime(item, start: true),
                        ),
                      ),
                      const SizedBox(width: ClaySpacing.sm),
                      Expanded(
                        child: ClayButton(
                          label: 'إلى ${DateKey.formatMinutes(_end)}',
                          kind: ClayButtonKind.secondary,
                          onPressed: () => _pickTime(item, start: false),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: ClaySpacing.md),
                  ClayDropdown<String?>(
                    label: 'القاعة',
                    value: _roomId,
                    options: [
                      const ClayOption(
                        value: null,
                        label: 'تلقائي (تُقترح قاعة متاحة)',
                      ),
                      for (final room in rooms)
                        ClayOption(value: room.id, label: room.name),
                    ],
                    onChanged: (v) => _changed(item, () => _roomId = v),
                  ),
                  const SizedBox(height: ClaySpacing.md),
                ],
                ClayTextField(
                  controller: _note,
                  label: 'ملاحظة للأستاذ (إلزامية عند الرفض)',
                  maxLines: 2,
                ),
                const SizedBox(height: ClaySpacing.md),
                if (preview != null) ...[
                  for (final c in preview.conflicts)
                    Text(
                      c.message,
                      style: text.bodyMedium!.copyWith(color: p.status.danger),
                    ),
                  if (preview.error != null)
                    Text(
                      preview.error!,
                      style: text.bodyMedium!.copyWith(color: p.status.danger),
                    ),
                  if (preview.ok && item.type.needsNewSlot && _roomId == null)
                    Text(
                      preview.suggestedRoom == null
                          ? 'لا قاعة متاحة في هذا الوقت'
                          : 'القاعة المقترحة: ${preview.suggestedRoom!.name}',
                      style: text.bodyMedium!.copyWith(color: p.status.success),
                    ),
                ],
                if (_error != null)
                  Text(
                    _error!,
                    style: text.bodyMedium!.copyWith(color: p.status.danger),
                  ),
                const SizedBox(height: ClaySpacing.lg),
                ClayButton(
                  label: 'موافقة',
                  icon: ClayIcons.check,
                  expand: true,
                  loading: _saving,
                  onPressed: preview != null && preview.ok
                      ? () => _approve(item)
                      : null,
                ),
                const SizedBox(height: ClaySpacing.sm),
                ClayButton(
                  label: 'رفض',
                  icon: ClayIcons.close,
                  kind: ClayButtonKind.danger,
                  expand: true,
                  onPressed: _saving ? null : () => _reject(item),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
