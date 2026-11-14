import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:school_core/school_core.dart';

import '../clay/clay_button.dart';
import '../clay/clay_container.dart';
import '../clay/clay_display.dart';
import '../clay/clay_icons.dart';
import '../clay/clay_navigation.dart';
import '../clay/clay_overlays.dart';
import '../clay/clay_selection.dart';
import '../theme/clay_theme.dart';
import '../theme/clay_tokens.dart';
import 'attendance_excel.dart';
import 'providers.dart';

/// ورقة حضور حصة: حالة كل تلميذ بنقرة، وتسجيل الكل حاضراً دفعة واحدة.
class SessionRosterScreen extends ConsumerStatefulWidget {
  const SessionRosterScreen({
    required this.sessionId,
    required this.canWrite,
    required this.canExcuse,
    super.key,
  });

  final String sessionId;

  /// هل يسجّل المستخدم الحضور (وإلا عرض فقط)؟
  final bool canWrite;

  /// هل يمنح «غائب برخصة»؟ للإدارة فقط (قرار 44).
  final bool canExcuse;

  @override
  ConsumerState<SessionRosterScreen> createState() =>
      _SessionRosterScreenState();
}

class _SessionRosterScreenState extends ConsumerState<SessionRosterScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _busy = true);
    try {
      await action();
    } on ValidationException catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export(SessionRoster roster) async {
    if (_busy) return;
    final controller = TextEditingController(
      text: AttendanceExcelExporter.defaultFileName(
        AttendanceExcelData.fromRoster(roster),
      ),
    );
    try {
      final requestedName = await showClayDialog<String>(
        context,
        title: 'تصدير ورقة الحضور',
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 100,
          textDirection: TextDirection.rtl,
          decoration: const InputDecoration(labelText: 'اسم الملف'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          ClayButton(
            label: 'إلغاء',
            kind: ClayButtonKind.secondary,
            onPressed: () => Navigator.of(context).pop(),
          ),
          ClayButton(
            label: 'متابعة',
            icon: Icons.file_download_outlined,
            onPressed: () => Navigator.of(context).pop(controller.text),
          ),
        ],
      );
      if (requestedName == null || !mounted) return;

      final fileName = AttendanceExcelExporter.normalizeFileName(requestedName);
      setState(() => _busy = true);
      final bytes = await AttendanceExcelExporter.generate(
        AttendanceExcelData.fromRoster(roster),
      );
      if (!mounted) return;
      final savedPath = await FilePicker.saveFile(
        dialogTitle: 'حفظ كشف الحضور',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        bytes: bytes,
      );
      if (savedPath == null || !mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('حُفظ ملف Excel: $fileName')));
    } on FormatException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message.toString())));
      }
    } on Exception {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّر إنشاء ملف Excel أو حفظه')),
        );
      }
    } finally {
      controller.dispose();
      if (mounted && _busy) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final roster = ref.watch(sessionRosterProvider(widget.sessionId));
    final currentRoster = roster.value;
    final canWrite = widget.canWrite;
    final service = ref.watch(attendanceServiceProvider);

    return Scaffold(
      appBar: ClayAppBar(
        title: 'ورقة الحضور',
        showBack: true,
        actions: [
          IconButton(
            tooltip: 'تصدير Excel',
            onPressed: _busy || currentRoster == null
                ? null
                : () => _export(currentRoster),
            icon: _busy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.file_download_outlined),
          ),
        ],
      ),
      body: roster.when(
        loading: () => const ClayLoadingView(),
        error: (_, _) => ClayErrorView(
          message: 'تعذّرت قراءة ورقة الحضور',
          onRetry: () => ref.invalidate(sessionRosterProvider),
        ),
        data: (r) {
          if (r == null) {
            return const ClayEmptyView(title: 'هذه الحصة غير موجودة');
          }
          final s = r.session;
          final editable = canWrite && !r.cancelled;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(ClaySpacing.screenPadding),
                child: ClayCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'المجموعة ${r.groupNumber} · ${r.subjectName}',
                              style: text.titleMedium,
                            ),
                          ),
                          if (r.cancelled)
                            const ClayBadge(
                              label: 'ملغاة',
                              tone: ClayTone.danger,
                            )
                          else if (r.closed)
                            const ClayBadge(
                              label: 'مغلقة',
                              tone: ClayTone.neutral,
                            ),
                        ],
                      ),
                      const SizedBox(height: ClaySpacing.xs),
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(
                          '${s.date}  ${DateKey.formatMinutes(s.startMinutes)}'
                          '–${DateKey.formatMinutes(s.endMinutes)}',
                          style: text.bodySmall!.copyWith(color: p.textMuted),
                        ),
                      ),
                      Text(r.teacherName, style: text.bodyMedium),
                      const SizedBox(height: ClaySpacing.sm),
                      Text(
                        'حاضر ${r.count(AttendanceStatus.present)} · '
                        'غائب ${r.count(AttendanceStatus.absent)} · '
                        'برخصة ${r.count(AttendanceStatus.excused)} · '
                        'بلا تسجيل ${r.unmarked}',
                        style: text.bodySmall,
                      ),
                      if (editable && !r.closed && r.unmarked > 0) ...[
                        const SizedBox(height: ClaySpacing.md),
                        ClayButton(
                          label: 'تسجيل الكل حاضراً',
                          icon: ClayIcons.check,
                          loading: _busy,
                          onPressed: () =>
                              _run(() async => service.markAllPresent(s.id)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Expanded(
                child: r.students.isEmpty
                    ? const ClayEmptyView(
                        title: 'لا تلاميذ في هذه الحصة',
                        message: 'يُنسب التلاميذ إلى المجموعة من ملفهم',
                        icon: ClayIcons.students,
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: ClaySpacing.screenPadding,
                        ),
                        itemCount: r.students.length,
                        itemExtent: 112,
                        itemBuilder: (context, i) => _StudentRow(
                          student: r.students[i],
                          editable: editable,
                          canExcuse: widget.canExcuse,
                          closed: r.closed,
                          busy: _busy,
                          onMark: (status) => _run(
                            () => service.mark(
                              sessionId: s.id,
                              studentId: r.students[i].studentId,
                              status: status,
                              canExcuse: widget.canExcuse,
                            ),
                          ),
                          onClear: () => _run(
                            () => service.clear(
                              sessionId: s.id,
                              studentId: r.students[i].studentId,
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StudentRow extends StatelessWidget {
  const _StudentRow({
    required this.student,
    required this.editable,
    required this.canExcuse,
    required this.closed,
    required this.busy,
    required this.onMark,
    required this.onClear,
  });

  final RosterStudent student;
  final bool editable;
  final bool canExcuse;
  final bool closed;
  final bool busy;
  final ValueChanged<AttendanceStatus> onMark;
  final VoidCallback onClear;

  static const _tones = {
    AttendanceStatus.present: ClayTone.success,
    AttendanceStatus.absent: ClayTone.danger,
    AttendanceStatus.excused: ClayTone.excused,
  };

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final current = student.status;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ClaySpacing.xs),
      child: ClayCard(
        flat: true,
        padding: const EdgeInsets.symmetric(
          horizontal: ClaySpacing.md,
          vertical: ClaySpacing.xs,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    student.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleSmall,
                  ),
                ),
                if (current != null &&
                    (!editable ||
                        (!canExcuse && current == AttendanceStatus.excused)))
                  ClayBadge(label: current.label, tone: _tones[current]!),
                if (current != null &&
                    student.method == AttendanceMethod.qr &&
                    editable)
                  const ClayBadge(label: 'مسح الرمز', tone: ClayTone.info),
              ],
            ),
            // من منحته الإدارة رخصة لا يغيّرها من لا يملكها.
            if (editable && (canExcuse || current != AttendanceStatus.excused))
              Wrap(
                spacing: ClaySpacing.sm,
                children: [
                  for (final status in AttendanceStatus.values)
                    if (canExcuse || status != AttendanceStatus.excused)
                      ClayChip(
                        label: status.label,
                        selected: current == status,
                        onTap: busy
                            ? null
                            : () {
                                if (current != status) {
                                  onMark(status);
                                } else if (!closed) {
                                  onClear();
                                }
                              },
                      ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
