import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:school_core/school_core.dart';

import '../clay/clay_button.dart';
import '../clay/clay_container.dart';
import '../clay/clay_display.dart';
import '../clay/clay_icons.dart';
import '../clay/clay_inputs.dart';
import '../theme/clay_theme.dart';
import '../theme/clay_tokens.dart';
import 'providers.dart';

/// هيكل شاشات الدخول: بطاقة في الوسط بعرض أقصى مريح للحاسوب.
class _AuthScaffold extends StatelessWidget {
  const _AuthScaffold({
    required this.app,
    required this.title,
    required this.children,
    this.subtitle,
  });

  final AppIdentity app;
  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(ClaySpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: ClayContainer(
                radius: ClayRadius.xl,
                padding: const EdgeInsets.all(ClaySpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      app.displayName,
                      textAlign: TextAlign.center,
                      style: text.bodyMedium!.copyWith(color: p.accent),
                    ),
                    const SizedBox(height: ClaySpacing.xs),
                    Semantics(
                      header: true,
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: text.headlineMedium,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: ClaySpacing.sm),
                      Text(
                        subtitle!,
                        textAlign: TextAlign.center,
                        style: text.bodyMedium!.copyWith(color: p.textMuted),
                      ),
                    ],
                    const SizedBox(height: ClaySpacing.xl),
                    ...children,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// رسالة خطأ عامة فوق الزر (خطأ الخادم أو الشبكة).
class _FormError extends StatelessWidget {
  const _FormError(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: ClaySpacing.md),
      child: Semantics(
        liveRegion: true,
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium!
              .copyWith(color: p.status.danger),
        ),
      ),
    );
  }
}

/// شاشة البداية: اسم التطبيق واسم المدرسة، ثم تنتقل بعد لحظة.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({
    required this.app,
    required this.onFinished,
    this.duration = const Duration(milliseconds: 900),
    super.key,
  });

  final AppIdentity app;
  final VoidCallback onFinished;
  final Duration duration;

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.duration, widget.onFinished);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final school = ref.watch(schoolNameProvider).value ?? '';
    return Scaffold(
      body: Center(
        child: Semantics(
          label: widget.app.displayName,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClayContainer(
                radius: ClayRadius.xl,
                padding: const EdgeInsets.all(ClaySpacing.xl),
                child: Icon(ClayIcons.students, size: 56, color: p.accent),
              ),
              const SizedBox(height: ClaySpacing.xl),
              Text(widget.app.displayName, style: text.displaySmall),
              if (school.isNotEmpty) ...[
                const SizedBox(height: ClaySpacing.sm),
                Text(
                  school,
                  style: text.titleMedium!.copyWith(color: p.textMuted),
                ),
              ],
              const SizedBox(height: ClaySpacing.xl),
              SizedBox.square(
                dimension: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: p.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// تسجيل الدخول بالبريد وكلمة السر. وفي الوضع المحلي على جهاز بلا حسابات
/// يتحول إلى إنشاء حساب صاحب المدرسة.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({required this.app, super.key});

  final AppIdentity app;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _busy = false;
  bool _showPassword = false;
  String? _formError;
  String? _nameError;
  String? _emailError;
  String? _passwordError;
  String? _confirmError;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool _validate({required bool setup}) {
    final nameEmpty = _name.text.trim().isEmpty;
    final emailProblem = LoginCredentials.emailProblem(_email.text);
    final passwordProblem = setup
        ? LoginCredentials.passwordProblem(_password.text)
        : (_password.text.isEmpty ? 'أدخل كلمة السر' : null);
    final confirmProblem = setup && _confirm.text != _password.text
        ? 'كلمتا السر غير متطابقتين'
        : null;
    setState(() {
      _nameError = setup && nameEmpty ? 'أدخل اسم صاحب المدرسة' : null;
      _emailError = emailProblem;
      _passwordError = passwordProblem;
      _confirmError = confirmProblem;
      _formError = null;
    });
    return !(setup && nameEmpty) &&
        emailProblem == null &&
        passwordProblem == null &&
        confirmProblem == null;
  }

  Future<void> _submit({required bool setup}) async {
    if (_busy || !_validate(setup: setup)) return;
    final runtime = ref.read(runtimeProvider);
    setState(() => _busy = true);
    try {
      if (setup) {
        await runtime.localGateway!.createFirstOwner(
          email: _email.text,
          displayName: _name.text,
          password: _password.text,
        );
      }
      await runtime.auth.signIn(email: _email.text, password: _password.text);
      // الانتقال تتولاه إعادة توجيه الموجِّه عند تغيّر الجلسة.
    } on AuthFailureException catch (e) {
      if (mounted) setState(() => _formError = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final runtime = ref.watch(runtimeProvider);
    final needsSetup = ref.watch(needsOwnerSetupProvider).value ?? false;
    final setup = needsSetup && runtime.isLocalMode;
    final p = context.palette;

    final visibility = IconButton(
      tooltip: _showPassword ? 'إخفاء كلمة السر' : 'إظهار كلمة السر',
      icon: Icon(
        _showPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
        color: p.textMuted,
      ),
      onPressed: () => setState(() => _showPassword = !_showPassword),
    );

    return _AuthScaffold(
      app: widget.app,
      title: setup ? 'إعداد أول مرة' : 'تسجيل الدخول',
      subtitle: setup
          ? 'أنشئ حساب صاحب المدرسة على هذا الجهاز'
          : 'أدخل البريد وكلمة السر اللذين وصلاك برسالة قصيرة',
      children: [
        if (setup) ...[
          ClayTextField(
            controller: _name,
            label: 'اسمك',
            error: _nameError,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: ClaySpacing.md),
        ],
        ClayTextField(
          controller: _email,
          label: 'البريد',
          error: _emailError,
          keyboardType: TextInputType.emailAddress,
          textDirection: TextDirection.ltr,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: ClaySpacing.md),
        ClayTextField(
          controller: _password,
          label: 'كلمة السر',
          error: _passwordError,
          obscureText: !_showPassword,
          textDirection: TextDirection.ltr,
          suffix: visibility,
          textInputAction: setup ? TextInputAction.next : TextInputAction.done,
          onSubmitted: setup ? null : (_) => _submit(setup: false),
        ),
        if (setup) ...[
          const SizedBox(height: ClaySpacing.md),
          ClayTextField(
            controller: _confirm,
            label: 'تأكيد كلمة السر',
            error: _confirmError,
            obscureText: !_showPassword,
            textDirection: TextDirection.ltr,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(setup: true),
          ),
        ],
        const SizedBox(height: ClaySpacing.xl),
        if (_formError != null) _FormError(_formError!),
        ClayButton(
          label: setup ? 'إنشاء الحساب' : 'دخول',
          expand: true,
          loading: _busy,
          onPressed: () => _submit(setup: setup),
        ),
        if (runtime.isLocalMode) ...[
          const SizedBox(height: ClaySpacing.lg),
          const Center(
            child: ClayBadge(label: 'وضع محلي: دون خادم', tone: ClayTone.info),
          ),
        ],
      ],
    );
  }
}

/// تغيير كلمة السر المولَّدة عند أول دخول (إجباري قبل استعمال التطبيق).
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({required this.app, super.key});

  final AppIdentity app;

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _showPassword = false;
  String? _formError;
  String? _passwordError;
  String? _confirmError;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final passwordProblem = LoginCredentials.passwordProblem(_password.text);
    final confirmProblem = _confirm.text != _password.text
        ? 'كلمتا السر غير متطابقتين'
        : null;
    setState(() {
      _passwordError = passwordProblem;
      _confirmError = confirmProblem;
      _formError = null;
    });
    if (passwordProblem != null || confirmProblem != null) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(runtimeProvider)
          .auth
          .changePassword(newPassword: _password.text);
    } on AuthFailureException catch (e) {
      if (mounted) setState(() => _formError = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return _AuthScaffold(
      app: widget.app,
      title: 'اختر كلمة سر جديدة',
      subtitle:
          'كلمة السر التي وصلتك مؤقتة. اختر كلمة سر خاصة بك '
          '(${LoginCredentials.minPasswordLength} رموز على الأقل).',
      children: [
        ClayTextField(
          controller: _password,
          label: 'كلمة السر الجديدة',
          error: _passwordError,
          obscureText: !_showPassword,
          textDirection: TextDirection.ltr,
          textInputAction: TextInputAction.next,
          suffix: IconButton(
            tooltip: _showPassword ? 'إخفاء كلمة السر' : 'إظهار كلمة السر',
            icon: Icon(
              _showPassword
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_rounded,
              color: p.textMuted,
            ),
            onPressed: () => setState(() => _showPassword = !_showPassword),
          ),
        ),
        const SizedBox(height: ClaySpacing.md),
        ClayTextField(
          controller: _confirm,
          label: 'تأكيد كلمة السر',
          error: _confirmError,
          obscureText: !_showPassword,
          textDirection: TextDirection.ltr,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: ClaySpacing.xl),
        if (_formError != null) _FormError(_formError!),
        ClayButton(
          label: 'حفظ ومتابعة',
          expand: true,
          loading: _busy,
          onPressed: _submit,
        ),
        const SizedBox(height: ClaySpacing.md),
        ClayButton(
          label: 'خروج',
          kind: ClayButtonKind.secondary,
          expand: true,
          onPressed: _busy
              ? null
              : () => ref.read(pushNotificationsProvider).signOut(),
        ),
      ],
    );
  }
}
