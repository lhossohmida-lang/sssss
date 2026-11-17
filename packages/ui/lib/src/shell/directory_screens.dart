import 'dart:async';

import 'package:flutter/material.dart';
import 'package:school_core/school_core.dart';

import '../clay/clay_button.dart';
import '../clay/clay_inputs.dart';
import '../clay/clay_overlays.dart';
import '../theme/clay_theme.dart';
import '../theme/clay_tokens.dart';
import 'auth_scaffold.dart';

const String _connectFailure =
    'تعذّر تشغيل التطبيق على هذه المدرسة، تحقق من الإنترنت ثم أعد المحاولة';

/// تسجيل دخول تطبيق الإدارة قبل أن يعرف الجهاز مدرسته: رقم الهاتف وكلمة السر
/// فقط. يسأل الدليل أي مدرسة لطاقمها هذا الرقم، فيربط الجهاز بها ويدخل دون أن
/// يلصق أحد رمز ربط.
class DirectorySignInScreen extends StatefulWidget {
  const DirectorySignInScreen({
    required this.app,
    required this.directory,
    required this.onSignIn,
    this.onLocalPreview,
    super.key,
  });

  final AppIdentity app;
  final SchoolDirectory directory;

  /// يُستدعى بعد معرفة المدرسة: يربط الجهاز بها ثم يدخل بالبيانات. ما يرميه
  /// يظهر خطأً على الشاشة.
  final Future<void> Function(
    DirectorySchool school,
    String login,
    String password,
  )
  onSignIn;

  /// تجربة محلية بلا خادم؛ `null` يخفي الزر.
  final Future<void> Function()? onLocalPreview;

  @override
  State<DirectorySignInScreen> createState() => _DirectorySignInScreenState();
}

class _DirectorySignInScreenState extends State<DirectorySignInScreen> {
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _showPassword = false;
  String? _phoneError;
  String? _passwordError;
  String? _formError;

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  String? _phoneProblem() {
    final text = _phone.text.trim();
    if (text.contains('@')) return 'أدخل رقم هاتفك لا بريداً إلكترونياً';
    return LoginCredentials.identifierProblem(text);
  }

  Future<DirectorySchool?> _choose(List<DirectorySchool> schools) =>
      showClayDialog<DirectorySchool>(
        context,
        title: 'اختر المدرسة',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('هذا الرقم مسجّل في أكثر من مدرسة. أي مدرسة تريد؟'),
            const SizedBox(height: ClaySpacing.md),
            for (final school in schools) ...[
              ClayButton(
                label: school.name,
                kind: ClayButtonKind.secondary,
                expand: true,
                onPressed: () => Navigator.of(context).pop(school),
              ),
              const SizedBox(height: ClaySpacing.sm),
            ],
          ],
        ),
      );

  Future<void> _submit() async {
    if (_busy) return;
    final phoneProblem = _phoneProblem();
    final passwordProblem = _password.text.isEmpty ? 'أدخل كلمة السر' : null;
    setState(() {
      _phoneError = phoneProblem;
      _passwordError = passwordProblem;
      _formError = null;
    });
    if (phoneProblem != null || passwordProblem != null) return;

    setState(() => _busy = true);
    try {
      final schools = await widget.directory.resolveByPhone(_phone.text);
      if (!mounted) return;
      if (schools.isEmpty) {
        setState(
          () => _formError =
              'هذا الرقم غير مسجّل في أي مدرسة. تأكد من الرقم، أو اطلب من '
              'مدرستك إضافة حسابك.',
        );
        return;
      }
      final school = schools.length == 1
          ? schools.single
          : await _choose(schools);
      if (school == null || !mounted) return;
      await widget.onSignIn(school, _phone.text, _password.text);
    } on DirectoryException catch (e) {
      if (mounted) setState(() => _formError = e.message);
    } on Object {
      if (mounted) setState(() => _formError = _connectFailure);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _localPreview() async {
    final action = widget.onLocalPreview;
    if (action == null || _busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on Object {
      if (mounted) setState(() => _formError = _connectFailure);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AuthScaffold(
      app: widget.app,
      title: 'تسجيل الدخول',
      subtitle: 'أدخل رقم هاتفك وكلمة السر. يعرف التطبيق مدرستك من رقمك.',
      children: [
        ClayTextField(
          controller: _phone,
          label: 'رقم الهاتف',
          hint: '0550123456',
          error: _phoneError,
          keyboardType: TextInputType.phone,
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
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
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
        const SizedBox(height: ClaySpacing.xl),
        if (_formError != null) FormErrorText(_formError!),
        ClayButton(
          label: 'دخول',
          expand: true,
          loading: _busy,
          onPressed: _submit,
        ),
        if (widget.onLocalPreview != null) ...[
          const SizedBox(height: ClaySpacing.lg),
          Center(
            child: TextButton(
              onPressed: _busy ? null : _localPreview,
              child: const Text('تجربة محلية بلا خادم'),
            ),
          ),
        ],
      ],
    );
  }
}

/// تطبيقا الأستاذ والتلميذ: قائمة المدارس المُعلنة في الدليل، يضغط المستخدم
/// مدرسته ثم يسجّل الدخول برقم هاتفه وكلمة سره. ينجح الدخول إن كان حسابه
/// في تلك المدرسة، وإلا يرفضه خادمها.
class SchoolPickerScreen extends StatefulWidget {
  const SchoolPickerScreen({
    required this.app,
    required this.directory,
    required this.onPick,
    super.key,
  });

  final AppIdentity app;
  final SchoolDirectory directory;

  /// يُستدعى بالمدرسة المختارة: يربط الجهاز بها ويشغّل التطبيق. ما يرميه
  /// يظهر خطأً على الشاشة.
  final Future<void> Function(DirectorySchool school) onPick;

  @override
  State<SchoolPickerScreen> createState() => _SchoolPickerScreenState();
}

class _SchoolPickerScreenState extends State<SchoolPickerScreen> {
  late Future<List<DirectorySchool>> _schools = widget.directory.listSchools();
  final _search = TextEditingController();
  String _query = '';
  bool _busy = false;
  String? _error;

  /// تظهر خانة البحث حين تكثر المدارس.
  static const int _searchFrom = 6;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _retry() {
    setState(() {
      _error = null;
      _schools = widget.directory.listSchools();
    });
  }

  Future<void> _pick(DirectorySchool school) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onPick(school);
    } on Object {
      if (mounted) setState(() => _error = _connectFailure);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return AuthScaffold(
      app: widget.app,
      title: 'اختر مدرستك',
      subtitle:
          'اضغط المدرسة التي تنتسب إليها، ثم سجّل الدخول برقم هاتفك '
          'وكلمة السر.',
      children: [
        FutureBuilder<List<DirectorySchool>>(
          future: _schools,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: ClaySpacing.xl),
                child: Center(
                  child: Semantics(
                    label: 'جارٍ تحميل المدارس',
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: p.accent,
                    ),
                  ),
                ),
              );
            }
            final error = snapshot.error;
            if (error != null) {
              final message = error is DirectoryException
                  ? error.message
                  : DirectoryFailure.unavailable.message;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FormErrorText(message),
                  ClayButton(
                    label: 'إعادة المحاولة',
                    expand: true,
                    onPressed: _retry,
                  ),
                ],
              );
            }
            final all = snapshot.data ?? const <DirectorySchool>[];
            if (all.isEmpty) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'لا توجد مدارس في القائمة بعد. اطلب من مدرستك تفعيل التطبيق.',
                    textAlign: TextAlign.center,
                    style: text.bodyMedium!.copyWith(color: p.textMuted),
                  ),
                  const SizedBox(height: ClaySpacing.md),
                  ClayButton(
                    label: 'تحديث',
                    kind: ClayButtonKind.secondary,
                    expand: true,
                    onPressed: _retry,
                  ),
                ],
              );
            }
            final query = _query.trim();
            final shown = query.isEmpty
                ? all
                : [
                    for (final school in all)
                      if (school.name.toLowerCase().contains(
                        query.toLowerCase(),
                      ))
                        school,
                  ];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (all.length >= _searchFrom) ...[
                  ClayTextField(
                    controller: _search,
                    label: 'ابحث عن مدرستك',
                    onChanged: (value) => setState(() => _query = value),
                  ),
                  const SizedBox(height: ClaySpacing.md),
                ],
                if (_error != null) FormErrorText(_error!),
                if (shown.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: ClaySpacing.md,
                    ),
                    child: Text(
                      'لا مدرسة بهذا الاسم',
                      textAlign: TextAlign.center,
                      style: text.bodyMedium!.copyWith(color: p.textMuted),
                    ),
                  ),
                for (final school in shown) ...[
                  ClayButton(
                    label: school.name,
                    kind: ClayButtonKind.secondary,
                    expand: true,
                    onPressed: _busy ? null : () => _pick(school),
                  ),
                  const SizedBox(height: ClaySpacing.sm),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}
