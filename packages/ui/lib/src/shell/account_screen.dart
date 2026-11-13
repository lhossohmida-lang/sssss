import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:school_core/school_core.dart';

import '../clay/clay_button.dart';
import '../clay/clay_container.dart';
import '../clay/clay_display.dart';
import '../clay/clay_icons.dart';
import '../clay/clay_inputs.dart';
import '../clay/clay_overlays.dart';
import '../theme/clay_theme.dart';
import '../theme/clay_tokens.dart';
import 'providers.dart';

/// سطر في بطاقة الحساب: عنوانه وقيمته.
typedef AccountDetail = ({String label, String value});

/// «حسابي»: بيانات صاحب الجلسة (الاسم والدور والبريد وما تضيفه الشاشة
/// المستضيفة)، وتغيير كلمة السر بعد التحقق من الحالية، والخروج.
///
/// مشتركة بين التطبيقات الثلاثة؛ كل تطبيق يمرّر [details] و[photo] من بياناته.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({this.details = const [], this.photo, super.key});

  /// بيانات إضافية تُعرض بعد البريد (هاتف، أبناء...).
  final List<AccountDetail> details;

  /// صورة صاحب الحساب إن وُجدت.
  final ImageProvider? photo;

  Future<void> _changePassword(BuildContext context, WidgetRef ref) async {
    final changed = await showClayDialog<bool>(
      context,
      title: 'تغيير كلمة السر',
      content: const _PasswordForm(),
    );
    if (changed == true && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('تم تغيير كلمة السر')));
    }
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final ok = await showClayConfirm(
      context,
      title: 'الخروج',
      message: 'سيُطلب منك البريد وكلمة السر عند الدخول من جديد.',
      confirmLabel: 'خروج',
    );
    if (ok) await ref.read(pushNotificationsProvider).signOut();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final session = ref.watch(sessionProvider.select((s) => s.value));
    final school = ref.watch(schoolNameProvider).value ?? '';
    if (session == null) return const SizedBox.shrink();
    final rows = <AccountDetail>[
      (label: 'البريد', value: session.email),
      ...details,
      if (school.isNotEmpty) (label: 'المدرسة', value: school),
    ];
    return ListView(
      padding: const EdgeInsets.all(ClaySpacing.screenPadding),
      children: [
        ClayCard(
          child: Column(
            children: [
              ClayAvatar(name: session.displayName, image: photo, size: 88),
              const SizedBox(height: ClaySpacing.md),
              Text(session.displayName, style: text.titleLarge),
              Text(
                session.role.label,
                style: text.bodyMedium!.copyWith(color: p.textMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: ClaySpacing.md),
        ClayCard(
          flat: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final row in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: ClaySpacing.xs),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.label,
                        style: text.bodySmall!.copyWith(color: p.textMuted),
                      ),
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(row.value, style: text.bodyLarge),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: ClaySpacing.xl),
        ClayButton(
          label: 'تغيير كلمة السر',
          icon: ClayIcons.edit,
          kind: ClayButtonKind.secondary,
          expand: true,
          onPressed: () => _changePassword(context, ref),
        ),
        const SizedBox(height: ClaySpacing.md),
        ClayButton(
          label: 'خروج',
          icon: ClayIcons.logout,
          kind: ClayButtonKind.danger,
          expand: true,
          onPressed: () => _signOut(context, ref),
        ),
      ],
    );
  }
}

/// نموذج تغيير كلمة السر: الحالية والجديدة وتأكيدها، وأخطاؤها على حقولها.
class _PasswordForm extends ConsumerStatefulWidget {
  const _PasswordForm();

  @override
  ConsumerState<_PasswordForm> createState() => _PasswordFormState();
}

class _PasswordFormState extends ConsumerState<_PasswordForm> {
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _show = false;
  String? _currentError;
  String? _newError;
  String? _confirmError;
  String? _formError;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final newProblem = LoginCredentials.passwordProblem(_new.text);
    final confirmProblem = _confirm.text != _new.text
        ? 'كلمتا السر غير متطابقتين'
        : null;
    setState(() {
      _currentError = _current.text.isEmpty ? 'أدخل كلمة السر الحالية' : null;
      _newError = newProblem;
      _confirmError = confirmProblem;
      _formError = null;
    });
    if (_currentError != null || newProblem != null || confirmProblem != null) {
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(runtimeProvider)
          .auth
          .updatePassword(
            currentPassword: _current.text,
            newPassword: _new.text,
          );
      if (mounted) Navigator.of(context).pop(true);
    } on AuthFailureException catch (e) {
      if (!mounted) return;
      setState(() {
        switch (e.failure) {
          case AuthFailure.invalidCredentials:
            _currentError = e.message;
          case AuthFailure.weakPassword:
            _newError = e.message;
          default:
            _formError = e.message;
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClayTextField(
          controller: _current,
          label: 'كلمة السر الحالية',
          error: _currentError,
          obscureText: !_show,
          textDirection: TextDirection.ltr,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: ClaySpacing.md),
        ClayTextField(
          controller: _new,
          label: 'كلمة السر الجديدة',
          error: _newError,
          obscureText: !_show,
          textDirection: TextDirection.ltr,
          textInputAction: TextInputAction.next,
          suffix: IconButton(
            tooltip: _show ? 'إخفاء كلمة السر' : 'إظهار كلمة السر',
            icon: Icon(
              _show ? Icons.visibility_off_rounded : Icons.visibility_rounded,
              color: p.textMuted,
            ),
            onPressed: () => setState(() => _show = !_show),
          ),
        ),
        const SizedBox(height: ClaySpacing.md),
        ClayTextField(
          controller: _confirm,
          label: 'تأكيد كلمة السر الجديدة',
          error: _confirmError,
          obscureText: !_show,
          textDirection: TextDirection.ltr,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
        ),
        if (_formError != null)
          Padding(
            padding: const EdgeInsets.only(top: ClaySpacing.sm),
            child: Text(
              _formError!,
              style: text.bodySmall!.copyWith(color: p.status.danger),
            ),
          ),
        const SizedBox(height: ClaySpacing.lg),
        ClayButton(
          label: 'حفظ',
          expand: true,
          loading: _busy,
          onPressed: _submit,
        ),
        const SizedBox(height: ClaySpacing.sm),
        ClayButton(
          label: 'إلغاء',
          kind: ClayButtonKind.secondary,
          expand: true,
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
        ),
      ],
    );
  }
}
