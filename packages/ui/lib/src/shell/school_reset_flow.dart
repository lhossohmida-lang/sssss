import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:school_core/school_core.dart';

import '../clay/clay_button.dart';
import '../clay/clay_inputs.dart';
import '../clay/clay_overlays.dart';
import '../theme/clay_theme.dart';
import '../theme/clay_tokens.dart';
import 'providers.dart';

/// العبارة التي يكتبها صاحب المدرسة بنفسه لتأكيد مسح مدرسته كلها.
const String schoolResetPhrase = 'حذف كل البيانات';

const String _warning =
    'ستُحذف مدرستك كلها نهائياً وتعود جديدة، من الخادم ومن كل الأجهزة:\n'
    '• التلاميذ والأولياء، والأساتذة والعمال وحسابات دخولهم.\n'
    '• الأفواج والجداول والحصص، والحضور، والمدفوعات والوصولات والمصاريف.\n'
    '• الرسائل والإشعارات، والصور والملفات، والإعدادات.\n\n'
    'يبقى حسابك (صاحب المدرسة) وحده. لا يمكن التراجع عن هذا، فخذ نسخة احتياطية أولاً '
    'إن أردت الاحتفاظ بشيء.\n\n'
    'أغلق تطبيقات الأساتذة والعمال قبل المتابعة؛ تمسح بياناتها عند أول اتصال لها. '
    'وهذا غير «مسح بيانات هذا الجهاز» الذي لا يمسّ الخادم.';

/// تدفق «إعادة تعيين بيانات المصنع» لصاحب المدرسة: تحذير مفصّل، ثم كلمة السر والعبارة، ثم المسح
/// على الخادم والجهاز وعرض النتيجة. لا يُنفَّذ إلا بتأكيدين صريحين وكلمة السر.
Future<void> runSchoolReset(BuildContext context, WidgetRef ref) async {
  final proceed = await showClayConfirm(
    context,
    title: 'إعادة تعيين بيانات المصنع',
    message: _warning,
    confirmLabel: 'متابعة',
    danger: true,
  );
  if (!proceed || !context.mounted) return;
  final result = await showClayDialog<SchoolResetResult>(
    context,
    title: 'تأكيد حذف كل البيانات',
    content: const _ResetForm(),
    barrierDismissible: false,
  );
  if (result == null || !context.mounted) return;
  await showClayDialog<void>(
    context,
    title: result.complete
        ? 'تمت إعادة تعيين المدرسة'
        : 'تمت الإعادة وبقيت بقايا',
    message: result.complete
        ? 'مُسحت بيانات المدرسة كلها وحُذف ${result.removedAccounts} من حسابات طاقمها '
              'وأوليائها، فأصبحت جديدة وبقي حسابك. تُبذَر المستويات الدراسية من جديد، '
              'وتمسح بقية الأجهزة بياناتها عند أول اتصال لها.'
        : 'مُسحت بيانات المدرسة كلها، لكن تعذّر حذف بعض ما يتبعها: '
              '${_leftovers(result)}. أعد «إعادة تعيين بيانات المصنع» لإكمال حذفها.',
    actions: [
      Builder(
        builder: (context) => ClayButton(
          label: 'تم',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
    ],
  );
}

String _leftovers(SchoolResetResult result) => [
  if (result.authFailures > 0) '${result.authFailures} من حسابات الدخول',
  if (result.directoryFailures > 0)
    '${result.directoryFailures} من أرقام دليل المدارس',
  if (result.storageFailures > 0) '${result.storageFailures} من الملفات',
].join('، ');

/// نموذج التأكيد: كلمة سر المالك والعبارة، ثم المسح بإظهار تقدمه وأخطائه.
class _ResetForm extends ConsumerStatefulWidget {
  const _ResetForm();

  @override
  ConsumerState<_ResetForm> createState() => _ResetFormState();
}

class _ResetFormState extends ConsumerState<_ResetForm> {
  final _password = TextEditingController();
  final _phrase = TextEditingController();
  bool _show = false;
  bool _busy = false;
  String? _passwordError;
  String? _formError;

  @override
  void dispose() {
    _password.dispose();
    _phrase.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_busy &&
      _password.text.isNotEmpty &&
      _phrase.text.trim() == schoolResetPhrase;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _busy = true;
      _passwordError = null;
      _formError = null;
    });
    try {
      final result = await ref
          .read(runtimeProvider)
          .resetSchool(password: _password.text);
      if (mounted) Navigator.of(context).pop(result);
    } on SchoolResetException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.failure == SchoolResetFailure.wrongPassword) {
          _passwordError = e.message;
        } else {
          _formError = e.message;
        }
      });
    } on Object {
      if (mounted) setState(() => _formError = 'تعذّرت الإعادة، حاول مرة أخرى');
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
        Text(
          'لا رجعة بعد هذه الخطوة. اكتب كلمة سرّك والعبارة المطلوبة لتأكيد حذف المدرسة كلها.',
          style: text.bodyMedium!.copyWith(color: p.status.danger),
        ),
        const SizedBox(height: ClaySpacing.md),
        ClayTextField(
          controller: _password,
          label: 'كلمة سر صاحب المدرسة',
          error: _passwordError,
          enabled: !_busy,
          obscureText: !_show,
          textDirection: TextDirection.ltr,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {}),
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
          controller: _phrase,
          label: 'اكتب «$schoolResetPhrase» للتأكيد',
          enabled: !_busy,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() {}),
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
        if (_busy)
          Padding(
            padding: const EdgeInsets.only(top: ClaySpacing.md),
            child: Row(
              children: [
                const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: ClaySpacing.md),
                Expanded(
                  child: Text(
                    'جارٍ مسح المدرسة... لا تُغلق التطبيق.',
                    style: text.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: ClaySpacing.lg),
        ClayButton(
          label: 'حذف كل البيانات',
          kind: ClayButtonKind.danger,
          expand: true,
          loading: _busy,
          onPressed: _canSubmit ? _submit : null,
        ),
        const SizedBox(height: ClaySpacing.sm),
        ClayButton(
          label: 'إلغاء',
          kind: ClayButtonKind.secondary,
          expand: true,
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
