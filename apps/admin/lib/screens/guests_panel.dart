import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

import 'student_picker.dart';

/// زر «ضيوف الحصة» تحت بطاقة ورقة الحضور: تلاميذ لمرة واحدة، أو تلاميذ منتسبون إلى فوج آخر، يحضرون
/// هذه الحصة وحدها ويدفعون ثمنها. يفتح قائمتهم بإضافتهم وتذاكرهم ودفعاتهم.
class GuestsButton extends ConsumerWidget {
  const GuestsButton({required this.roster, super.key});

  final SessionRoster roster;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionId = roster.session.id;
    final count =
        ref.watch(sessionGuestsProvider(sessionId)).value?.length ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ClaySpacing.screenPadding,
        0,
        ClaySpacing.screenPadding,
        ClaySpacing.sm,
      ),
      child: ClayButton(
        label: count == 0 ? 'ضيوف الحصة' : 'ضيوف الحصة ($count)',
        icon: ClayIcons.students,
        kind: ClayButtonKind.secondary,
        expand: true,
        onPressed: () => showClayBottomSheet<void>(
          context,
          title: 'ضيوف الحصة',
          builder: (_) => GuestsSheet(
            sessionId: sessionId,
            canAdd: !roster.closed && !roster.cancelled,
          ),
        ),
      ),
    );
  }
}

/// قائمة ضيوف حصة وإضافتهم.
class GuestsSheet extends ConsumerWidget {
  const GuestsSheet({required this.sessionId, required this.canAdd, super.key});

  final String sessionId;
  final bool canAdd;

  Future<void> _addOneTime(BuildContext context, WidgetRef ref) async {
    final created = await showDialog<SessionGuestItem>(
      context: context,
      builder: (_) => _GuestDialog(sessionId: sessionId, oneTime: true),
    );
    if (created == null || !context.mounted) return;
    await showTicket(context, created);
  }

  Future<void> _addStudent(BuildContext context, WidgetRef ref) async {
    final picked = await pickExistingStudents(
      context,
      title: 'تلميذ مسجَّل يحضر هذه الحصة',
      confirmLabel: 'اختيار',
    );
    final student = picked?.firstOrNull;
    if (student == null || !context.mounted) return;
    await showDialog<SessionGuestItem>(
      context: context,
      builder: (_) => _GuestDialog(
        sessionId: sessionId,
        oneTime: false,
        studentId: student.id,
        studentName: student.fullName,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final guests = ref.watch(sessionGuestsProvider(sessionId));
    final canPay = ref.can(PermissionModule.receiveMoney, PermissionAction.use);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'تلميذ لمرة واحدة: يدفع ثمن هذه الحصة فقط ويأخذ تذكرة QR تُستعمل مرة واحدة. تلميذ '
          'مسجَّل في فوج آخر: يدخل برمزه العادي وتظهر الحصة في ملفه.',
          style: text.bodySmall!.copyWith(color: p.textMuted),
        ),
        const SizedBox(height: ClaySpacing.md),
        if (canAdd)
          Wrap(
            spacing: ClaySpacing.sm,
            runSpacing: ClaySpacing.sm,
            children: [
              ClayButton(
                label: 'تلميذ لمرة واحدة',
                icon: ClayIcons.add,
                onPressed: () => _addOneTime(context, ref),
              ),
              ClayButton(
                label: 'تلميذ مسجَّل',
                icon: ClayIcons.students,
                kind: ClayButtonKind.secondary,
                onPressed: () => _addStudent(context, ref),
              ),
            ],
          )
        else
          Text(
            'انتهت الحصة أو أُلغيت: لا يُضاف إليها ضيوف.',
            style: text.bodySmall!.copyWith(color: p.textMuted),
          ),
        const SizedBox(height: ClaySpacing.md),
        guests.when(
          loading: () => const ClayLoadingView(),
          error: (_, _) => const Text('تعذّرت قراءة الضيوف'),
          data: (items) => items.isEmpty
              ? Text('لا ضيوف بعد', style: text.bodyMedium)
              : Column(
                  children: [
                    for (final guest in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: ClaySpacing.sm),
                        child: ClayListTile(
                          title: guest.studentName,
                          subtitle:
                              '${guest.singleUse ? 'لمرة واحدة' : 'من فوج آخر'}'
                              ' · ${Money.format(guest.price)}'
                              ' · ${guest.isPaid ? 'مدفوع' : 'باقي ${Money.format(guest.remaining)}'}'
                              '${guest.present ? ' · حضر' : ''}',
                          trailing: [
                            if (guest.ticketCode != null)
                              IconButton(
                                tooltip: 'تذكرة الدخول',
                                icon: const Icon(Icons.qr_code_2_rounded),
                                onPressed: () => showTicket(context, guest),
                              ),
                            if (canPay && !guest.isPaid)
                              IconButton(
                                tooltip: 'تسجيل دفعة',
                                icon: const Icon(ClayIcons.payments),
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  context.push(
                                    '/payments/new?student=${guest.studentId}',
                                  );
                                },
                              ),
                            if (canAdd && !guest.present && guest.paid == 0)
                              IconButton(
                                tooltip: 'حذف الضيف',
                                icon: const Icon(ClayIcons.delete),
                                onPressed: () => ref
                                    .read(guestServiceProvider)
                                    .remove(guest.id),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// تذكرة ضيف لمرة واحدة: رمز QR يُمسح عند الدخول فتُستعمل ولا تصلح بعدها.
Future<void> showTicket(BuildContext context, SessionGuestItem guest) {
  final code = guest.ticketCode;
  if (code == null) return Future.value();
  final text = Theme.of(context).textTheme;
  return showDialog<void>(
    context: context,
    builder: (context) => ClayDialog(
      title: 'تذكرة ${guest.studentName}',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClayQrCode(data: code, size: 200),
          const SizedBox(height: ClaySpacing.sm),
          Directionality(
            textDirection: TextDirection.ltr,
            child: SelectableText(code, style: text.bodySmall),
          ),
          const SizedBox(height: ClaySpacing.sm),
          Text(
            'تُمسح عند الدخول وتُستعمل مرة واحدة فقط، في يوم هذه الحصة. ثمن الحصة: '
            '${Money.format(guest.price)} · '
            '${guest.isPaid ? 'مدفوع' : 'باقي ${Money.format(guest.remaining)}'}',
            textAlign: TextAlign.center,
            style: text.bodyMedium,
          ),
        ],
      ),
      actions: [
        ClayButton(
          label: 'إغلاق',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    ),
  );
}

/// إضافة ضيف: اسمه ورقمه (للتلميذ لمرة واحدة)، وثمن الحصة ومبلغ الأستاذ وما دفعه الآن.
class _GuestDialog extends ConsumerStatefulWidget {
  const _GuestDialog({
    required this.sessionId,
    required this.oneTime,
    this.studentId,
    this.studentName,
  });

  final String sessionId;
  final bool oneTime;
  final String? studentId;
  final String? studentName;

  @override
  ConsumerState<_GuestDialog> createState() => _GuestDialogState();
}

class _GuestDialogState extends ConsumerState<_GuestDialog> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _price = TextEditingController();
  final _teacher = TextEditingController();
  final _paid = TextEditingController();
  Map<String, String> _errors = const {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _suggest();
  }

  Future<void> _suggest() async {
    final suggestion = await ref
        .read(guestServiceProvider)
        .suggest(widget.sessionId);
    if (!mounted) return;
    setState(() {
      _price.text = '${suggestion.price}';
      _teacher.text = '${suggestion.teacherAmount}';
      _paid.text = '${suggestion.price}';
    });
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _price, _teacher, _paid]) {
      c.dispose();
    }
    super.dispose();
  }

  int _number(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  Future<void> _submit() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _errors = const {};
    });
    final service = ref.read(guestServiceProvider);
    try {
      final guest = widget.oneTime
          ? await service.addOneTime(
              sessionId: widget.sessionId,
              name: _name.text,
              phone: _phone.text,
              price: _number(_price),
              teacherAmount: _number(_teacher),
              paidNow: _number(_paid),
            )
          : await service.addStudent(
              sessionId: widget.sessionId,
              studentId: widget.studentId!,
              price: _number(_price),
              teacherAmount: _number(_teacher),
              paidNow: _number(_paid),
            );
      if (mounted) Navigator.of(context).pop(guest);
    } on ValidationException catch (e) {
      if (mounted) setState(() => _errors = e.errors);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: ClaySpacing.md);
    Widget amount(TextEditingController c, String label, String field) =>
        ClayTextField(
          controller: c,
          label: label,
          keyboardType: TextInputType.number,
          textDirection: TextDirection.ltr,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          error: _errors[field],
        );
    return ClayDialog(
      title: widget.oneTime ? 'تلميذ لمرة واحدة' : 'تلميذ مسجَّل',
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.oneTime) ...[
              ClayTextField(
                controller: _name,
                label: 'الاسم',
                autofocus: true,
                error: _errors[GuestService.fieldName],
              ),
              gap,
              ClayTextField(
                controller: _phone,
                label: 'الهاتف (اختياري، يُسجَّل في دليل الهواتف)',
                keyboardType: TextInputType.phone,
                textDirection: TextDirection.ltr,
                error: _errors[GuestService.fieldPhone],
              ),
              gap,
            ] else ...[
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  widget.studentName ?? '',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (_errors[GuestService.fieldStudent] != null)
                Text(
                  _errors[GuestService.fieldStudent]!,
                  style: Theme.of(context).textTheme.bodySmall!
                      .copyWith(color: context.palette.status.danger),
                ),
              gap,
            ],
            amount(
              _price,
              'ثمن هذه الحصة (${Money.currency})',
              GuestService.fieldPrice,
            ),
            gap,
            amount(
              _teacher,
              'ما يأخذه الأستاذ عنه (${Money.currency})',
              GuestService.fieldTeacherAmount,
            ),
            gap,
            amount(
              _paid,
              'المدفوع الآن (${Money.currency})',
              GuestService.fieldPaid,
            ),
            if (_errors[GuestService.fieldSession] != null) ...[
              gap,
              Text(
                _errors[GuestService.fieldSession]!,
                style: Theme.of(context).textTheme.bodySmall!
                    .copyWith(color: context.palette.status.danger),
              ),
            ],
          ],
        ),
      ),
      actions: [
        ClayButton(label: 'إضافة', loading: _saving, onPressed: _submit),
        ClayButton(
          label: 'إلغاء',
          kind: ClayButtonKind.secondary,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
