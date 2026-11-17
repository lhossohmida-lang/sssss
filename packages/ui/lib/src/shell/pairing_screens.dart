import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:school_core/school_core.dart';

import '../clay/clay_button.dart';
import '../clay/clay_icons.dart';
import '../clay/clay_inputs.dart';
import '../clay/clay_overlays.dart';
import '../clay/clay_qr.dart';
import '../theme/clay_theme.dart';
import '../theme/clay_tokens.dart';
import 'auth_scaffold.dart';
import 'providers.dart';
import 'qr_scanning.dart';
import 'school_bootstrap.dart';

/// شاشة ربط جهاز بمدرسة: يُلصق رمز الربط الذي سلّمته الإدارة أو يُمسح بالكاميرا.
///
/// تظهر قبل أي اتصال بخادم، فلا تعتمد على وقت تشغيل التطبيق.
class PairingScreen extends StatefulWidget {
  const PairingScreen({
    required this.app,
    required this.onPair,
    this.onLocalPreview,
    this.cameraFactory,
    super.key,
  });

  final AppIdentity app;

  /// يُستدعى بالربط الصحيح؛ ما يرميه يظهر خطأً على الشاشة.
  final Future<void> Function(SchoolPairing pairing) onPair;

  /// تجربة محلية بلا خادم (تطبيق الإدارة)؛ `null` يخفي الزر.
  final Future<void> Function()? onLocalPreview;

  /// كاميرا المسح؛ `null` يخفي زر المسح (Windows).
  final QrCodeSource Function()? cameraFactory;

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final _code = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final SchoolPairing pairing;
    try {
      pairing = SchoolPairing.parse(_code.text);
    } on PairingException catch (e) {
      setState(() => _error = e.message);
      return;
    }
    await _connect(pairing);
  }

  Future<void> _connect(SchoolPairing pairing) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onPair(pairing);
    } on Object {
      if (mounted) setState(() => _error = _connectFailure);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (!mounted) return;
    if (text.trim().isEmpty) {
      setState(() => _error = PairingFailure.empty.message);
      return;
    }
    _code.text = text.trim();
    await _submit();
  }

  Future<void> _scan() async {
    final factory = widget.cameraFactory;
    if (factory == null || _busy) return;
    final pairing = await Navigator.of(context).push<SchoolPairing>(
      MaterialPageRoute(
        builder: (_) => PairingScannerScreen(source: factory()),
      ),
    );
    if (pairing != null && mounted) await _connect(pairing);
  }

  Future<void> _localPreview() async {
    final action = widget.onLocalPreview;
    if (action == null || _busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on Object {
      if (mounted) setState(() => _error = _connectFailure);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static const _connectFailure =
      'تعذّر تشغيل التطبيق على هذه المدرسة، تحقق من الإنترنت ثم أعد المحاولة';

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AuthScaffold(
      app: widget.app,
      title: 'ربط التطبيق بمدرستك',
      subtitle:
          'الصق رمز الربط الذي سلّمته لك إدارة المدرسة، أو امسح رمز QR الخاص بها. '
          'تُربط هذه الخطوة مرة واحدة فقط.',
      children: [
        ClayTextField(
          controller: _code,
          label: 'رمز الربط',
          hint: 'SCH1.…',
          error: _error,
          textDirection: TextDirection.ltr,
          keyboardType: TextInputType.multiline,
          maxLines: 3,
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
        ),
        const SizedBox(height: ClaySpacing.lg),
        ClayButton(
          label: 'ربط',
          expand: true,
          loading: _busy,
          onPressed: _submit,
        ),
        const SizedBox(height: ClaySpacing.md),
        ClayButton(
          label: 'لصق الرمز من الحافظة',
          icon: ClayIcons.share,
          kind: ClayButtonKind.secondary,
          expand: true,
          onPressed: _busy ? null : _paste,
        ),
        if (widget.cameraFactory != null) ...[
          const SizedBox(height: ClaySpacing.md),
          ClayButton(
            label: 'مسح رمز QR',
            icon: ClayIcons.scan,
            kind: ClayButtonKind.secondary,
            expand: true,
            onPressed: _busy ? null : _scan,
          ),
        ],
        if (widget.onLocalPreview != null) ...[
          const SizedBox(height: ClaySpacing.xl),
          Divider(color: p.textMuted.withValues(alpha: 0.3)),
          const SizedBox(height: ClaySpacing.sm),
          Text(
            'للتجربة فقط: يعمل التطبيق على هذا الجهاز وحده دون خادم، ولا تظهر '
            'فيه بيانات أي مدرسة.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall!
                .copyWith(color: p.textMuted),
          ),
          const SizedBox(height: ClaySpacing.sm),
          ClayButton(
            label: 'تجربة محلية بلا خادم',
            kind: ClayButtonKind.secondary,
            expand: true,
            onPressed: _busy ? null : _localPreview,
          ),
        ],
      ],
    );
  }
}

/// مسح رمز ربط بالكاميرا: يُعيد أول رمز مدرسة صالح ويتجاهل غيره.
class PairingScannerScreen extends StatefulWidget {
  const PairingScannerScreen({required this.source, super.key});

  final QrCodeSource source;

  @override
  State<PairingScannerScreen> createState() => _PairingScannerScreenState();
}

class _PairingScannerScreenState extends State<PairingScannerScreen> {
  StreamSubscription<String>? _subscription;
  String? _hint;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _subscription = widget.source.codes.listen(_onCode);
    unawaited(widget.source.start().catchError((Object _) {}));
  }

  void _onCode(String raw) {
    if (_done) return;
    try {
      final pairing = SchoolPairing.parse(raw);
      _done = true;
      Navigator.of(context).pop(pairing);
    } on PairingException catch (e) {
      if (mounted) setState(() => _hint = e.message);
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    unawaited(widget.source.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('امسح رمز المدرسة')),
      body: Column(
        children: [
          Expanded(child: widget.source.buildPreview(context)),
          Padding(
            padding: const EdgeInsets.all(ClaySpacing.lg),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _hint ?? 'وجّه الكاميرا إلى رمز QR الذي تعرضه إدارة المدرسة',
                textAlign: TextAlign.center,
                style: text.bodyMedium!.copyWith(
                  color: _hint == null ? p.textMuted : p.status.danger,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// حوار رمز ربط المدرسة (QR والنص) لتُربط به أجهزة أخرى.
Future<void> showPairingCode(BuildContext context, SchoolPairing pairing) {
  return showClayDialog<void>(
    context,
    title: 'رمز ربط الأجهزة',
    content: _PairingCodeView(pairing: pairing),
  );
}

class _PairingCodeView extends StatelessWidget {
  const _PairingCodeView({required this.pairing});

  final SchoolPairing pairing;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'يمسحه الأساتذة والأولياء من تطبيقاتهم عند أول فتح، أو يُرسَل لهم '
          'نصّه. لا يكشف كلمات سر ولا بيانات، لكن لا تنشره خارج مدرستك.',
          textAlign: TextAlign.center,
          style: text.bodySmall!.copyWith(color: p.textMuted),
        ),
        const SizedBox(height: ClaySpacing.md),
        Center(
          child: ClayQrCode(
            data: pairing.code,
            size: 240,
            semanticLabel: 'رمز QR لربط الأجهزة بالمدرسة',
          ),
        ),
        const SizedBox(height: ClaySpacing.md),
        ClayButton(
          label: 'نسخ الرمز',
          icon: ClayIcons.share,
          kind: ClayButtonKind.secondary,
          expand: true,
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: pairing.code));
            if (context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('نُسخ رمز الربط')));
            }
          },
        ),
        const SizedBox(height: ClaySpacing.sm),
        ClayButton(
          label: 'إغلاق',
          kind: ClayButtonKind.secondary,
          expand: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// قسم «المدرسة» في «حسابي»: رمز ربط الأجهزة (الإدارة) وتغيير المدرسة.
///
/// لا يظهر خارج [SchoolBootstrap] (اختبارات الشاشات) ولا في بناء مضمَّن الإعداد.
class SchoolConnectionSection extends ConsumerWidget {
  const SchoolConnectionSection({super.key});

  Future<void> _changeSchool(
    BuildContext context,
    WidgetRef ref,
    SchoolConnection connection,
  ) async {
    final admin = ref.read(runtimeProvider).app == AppIdentity.admin;
    final leaving = admin
        ? 'سيخرج هذا الجهاز من الحساب، ثم تدخل برقم هاتفك فتُعرف مدرستك.'
        : 'سيخرج هذا الجهاز من الحساب، ثم تختار مدرستك من القائمة وتسجّل '
              'الدخول.';
    final ok = await showClayConfirm(
      context,
      title: connection.pairing == null ? 'ربط بمدرسة' : 'تغيير المدرسة',
      message: connection.usesDirectory
          ? '$leaving بيانات المدرسة الحالية تبقى على الجهاز ولا يراها غير '
                'حسابات مدرستها، وتعود كما كانت إن دخلت إليها من جديد.'
          : 'سيخرج هذا الجهاز من الحساب ويطلب رمز ربط مدرسة. بيانات المدرسة '
                'الحالية تبقى على الجهاز ولا يراها غير حسابات مدرستها، وتعود '
                'كما كانت إن ربطته بها من جديد.',
      confirmLabel: 'متابعة',
      danger: true,
    );
    if (!ok) return;
    // يُلغى تسجيل الجهاز لإشعارات المدرسة قبل مغادرتها.
    await ref.read(pushNotificationsProvider).signOut();
    await connection.leaveSchool();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = SchoolBootstrap.connectionOf(context);
    if (connection == null) return const SizedBox.shrink();
    final pairing = connection.pairing;
    final app = ref.watch(runtimeProvider.select((r) => r.app));
    final schoolName = ref.watch(schoolNameProvider).value ?? '';
    // مع دليل المدارس لا رمز ربط: يعرف الجهاز مدرسته من الهاتف أو من القائمة.
    final showCode =
        app == AppIdentity.admin &&
        pairing != null &&
        !connection.usesDirectory;
    if (!showCode && !connection.canChangeSchool) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showCode) ...[
          ClayButton(
            label: 'رمز ربط الأجهزة الأخرى',
            icon: ClayIcons.qr,
            kind: ClayButtonKind.secondary,
            expand: true,
            onPressed: () => showPairingCode(
              context,
              pairing.name.isEmpty && schoolName.isNotEmpty
                  ? SchoolPairing(
                      url: pairing.url,
                      key: pairing.key,
                      name: schoolName,
                    )
                  : pairing,
            ),
          ),
          const SizedBox(height: ClaySpacing.md),
        ],
        if (connection.canChangeSchool) ...[
          ClayButton(
            label: pairing == null ? 'ربط بمدرسة' : 'تغيير المدرسة',
            icon: ClayIcons.settings,
            kind: ClayButtonKind.secondary,
            expand: true,
            onPressed: () => _changeSchool(context, ref, connection),
          ),
          const SizedBox(height: ClaySpacing.md),
        ],
      ],
    );
  }
}
