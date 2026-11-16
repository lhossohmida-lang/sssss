import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:school_core/school_core.dart';

import '../clay/clay_button.dart';
import '../clay/clay_icons.dart';
import '../theme/clay_theme.dart';
import '../theme/clay_tokens.dart';
import 'app_page.dart';
import 'app_tab.dart';
import 'auth_scaffold.dart';
import 'pairing_screens.dart';
import 'providers.dart';
import 'qr_scanning.dart';
import 'school_app.dart';

/// يشغّل وقت تشغيل التطبيق لإعدادات مدرسة ([config] فارغ = معاينة محلية).
typedef RuntimeStarter = Future<AppRuntime> Function(
  AppIdentity app,
  AppConfig? config,
);

/// يوقف وقت تشغيل بعد أن فُكّت واجهته.
typedef RuntimeStopper = Future<void> Function(AppRuntime runtime);

/// ما يتيحه الجذر لشاشات التطبيق المُشغَّل: أي مدرسة ربط بها الجهاز، والخروج منها.
abstract interface class SchoolConnection {
  /// ربط الجهاز بمدرسة، أو `null` في المعاينة المحلية وفي بناء مضمَّن الإعداد.
  SchoolPairing? get pairing;

  /// هل يُسمح بتغيير المدرسة من التطبيق؟ لا في بناء مضمَّن الإعداد.
  bool get canChangeSchool;

  /// يغلق التطبيق على المدرسة الحالية ويعرض شاشة الربط من جديد.
  ///
  /// قاعدة المدرسة المحلية تبقى على الجهاز وتعود عند الربط بها ثانية.
  Future<void> leaveSchool();
}

/// جذر التطبيقات الثلاثة: يحدد مدرسة الجهاز ثم يشغّل التطبيق عليها.
///
/// - إعدادات مضمَّنة وقت البناء (`--dart-define`): تُستعمل دون سؤال.
/// - وإلا ربط محفوظ على الجهاز بعد أن لصق المستخدم رمز مدرسته أو مسحه.
/// - وإلا شاشة الربط (ومعها «تجربة محلية» في تطبيق الإدارة وحده).
///
/// تغيير المدرسة يفكّ واجهة التطبيق ثم يغلق وقت تشغيله ثم يبدأ وقتاً جديداً
/// بقاعدة المدرسة الجديدة، فلا تختلط بيانات مدرستين.
class SchoolBootstrap extends StatefulWidget {
  const SchoolBootstrap({
    required this.app,
    required this.tabs,
    this.pages = const [],
    this.cameraFactory,
    this.wrapApp,
    this.overrides = const [],
    this.bakedConfig,
    this.store,
    this.startRuntime = _defaultStart,
    this.stopRuntime = _defaultStop,
    super.key,
  });

  final AppIdentity app;
  final List<AppTab> tabs;
  final List<AppPage> pages;

  /// كاميرا مسح QR (Android)؛ `null` حيث لا كاميرا.
  final QrCodeSource Function()? cameraFactory;

  /// يلفّ التطبيق المُشغَّل (مثل نسخ Drive الاحتياطي في الإدارة).
  final Widget Function(Widget app)? wrapApp;

  /// تجاوزات Riverpod إضافية لكل وقت تشغيل (تُستعمل في الاختبارات).
  final List<Override> overrides;

  /// الإعدادات المضمَّنة؛ الافتراضي ما مُرِّر وقت البناء.
  final AppConfig? bakedConfig;

  /// مخزن الربط؛ الافتراضي ملف في مجلد التطبيق.
  final PairingStore? store;

  final RuntimeStarter startRuntime;
  final RuntimeStopper stopRuntime;

  /// اتصال الجهاز بمدرسته لمن هم تحت الجذر، أو `null` خارجه.
  static SchoolConnection? connectionOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_SchoolConnectionScope>()
      ?.connection;

  static Future<AppRuntime> _defaultStart(AppIdentity app, AppConfig? config) =>
      AppRuntime.start(app: app, config: config);

  static Future<void> _defaultStop(AppRuntime runtime) => runtime.dispose();

  @override
  State<SchoolBootstrap> createState() => _SchoolBootstrapState();
}

enum _Phase { loading, pairing, running, failed }

class _SchoolBootstrapState extends State<SchoolBootstrap>
    implements SchoolConnection {
  _Phase _phase = _Phase.loading;
  PairingStore? _store;
  AppRuntime? _runtime;
  SchoolPairing? _pairing;
  bool _baked = false;

  /// آخر إعدادات حاولنا تشغيلها (للمحاولة من جديد بعد فشل).
  AppConfig? _lastConfig;
  bool _hasLastConfig = false;

  /// يُلغي نتائج عمليات متأخرة بعد تغيّر وجهة الجهاز.
  int _epoch = 0;

  @override
  SchoolPairing? get pairing => _pairing;

  @override
  bool get canChangeSchool => !_baked;

  @override
  void initState() {
    super.initState();
    unawaited(_boot());
  }

  @override
  void dispose() {
    _epoch++;
    final runtime = _runtime;
    _runtime = null;
    if (runtime != null) unawaited(widget.stopRuntime(runtime));
    super.dispose();
  }

  Future<void> _boot() async {
    final epoch = ++_epoch;
    try {
      final store = _store ??=
          widget.store ?? await AppRuntime.pairingStore(widget.app);
      final baked = widget.bakedConfig ?? AppConfig.fromEnvironment();
      if (baked.isConfigured) {
        _baked = true;
        await _start(baked, epoch);
        return;
      }
      _baked = false;
      final saved = await store.load();
      if (saved != null) {
        _pairing = saved;
        await _start(saved.toConfig(), epoch);
        return;
      }
      if (widget.app == AppIdentity.admin && await store.isLocalPreview()) {
        await _start(null, epoch);
        return;
      }
      _showPairing(epoch);
    } on Object {
      _fail(epoch);
    }
  }

  void _showPairing(int epoch) {
    if (!mounted || epoch != _epoch) return;
    setState(() => _phase = _Phase.pairing);
  }

  void _fail(int epoch) {
    if (!mounted || epoch != _epoch) return;
    setState(() => _phase = _Phase.failed);
  }

  Future<void> _start(AppConfig? config, int epoch) async {
    _lastConfig = config;
    _hasLastConfig = true;
    if (mounted && epoch == _epoch) setState(() => _phase = _Phase.loading);
    final AppRuntime runtime;
    try {
      runtime = await widget.startRuntime(widget.app, config);
    } on Object {
      _fail(epoch);
      return;
    }
    if (!mounted || epoch != _epoch) {
      await widget.stopRuntime(runtime);
      return;
    }
    setState(() {
      _runtime = runtime;
      _phase = _Phase.running;
    });
  }

  Future<void> _pair(SchoolPairing pairing) async {
    final epoch = ++_epoch;
    await _store!.save(pairing);
    _pairing = pairing;
    await _start(pairing.toConfig(), epoch);
  }

  Future<void> _chooseLocalPreview() async {
    final epoch = ++_epoch;
    await _store!.chooseLocalPreview();
    _pairing = null;
    await _start(null, epoch);
  }

  Future<void> _retry() async {
    if (!_hasLastConfig) {
      unawaited(_boot());
      return;
    }
    await _start(_lastConfig, ++_epoch);
  }

  @override
  Future<void> leaveSchool() async {
    final epoch = ++_epoch;
    final old = _runtime;
    setState(() {
      _runtime = null;
      _pairing = null;
      _phase = _Phase.loading;
    });
    // الإطار التالي يفكّ شجرة التطبيق قبل إغلاق قاعدته، فلا تقرأ شاشة منها.
    await WidgetsBinding.instance.endOfFrame;
    if (old != null) await widget.stopRuntime(old);
    await _store?.clear();
    _hasLastConfig = false;
    _showPairing(epoch);
  }

  @override
  Widget build(BuildContext context) {
    final runtime = _runtime;
    if (_phase == _Phase.running && runtime != null) {
      Widget app = SchoolApp(tabs: widget.tabs, pages: widget.pages);
      final wrap = widget.wrapApp;
      if (wrap != null) app = wrap(app);
      return _SchoolConnectionScope(
        connection: this,
        pairing: _pairing,
        child: ProviderScope(
          key: ObjectKey(runtime),
          overrides: [
            runtimeProvider.overrideWithValue(runtime),
            if (widget.cameraFactory != null)
              qrCameraFactoryProvider.overrideWithValue(widget.cameraFactory),
            ...widget.overrides,
          ],
          child: app,
        ),
      );
    }
    return ClayApp(
      app: widget.app,
      home: switch (_phase) {
        _Phase.pairing => PairingScreen(
          app: widget.app,
          onPair: _pair,
          onLocalPreview: widget.app == AppIdentity.admin
              ? _chooseLocalPreview
              : null,
          cameraFactory: widget.cameraFactory,
        ),
        _Phase.failed => _StartFailureScreen(
          app: widget.app,
          onRetry: _retry,
          onChangeSchool: _baked ? null : leaveSchool,
        ),
        _ => _BootSplash(app: widget.app),
      },
    );
  }
}

class _SchoolConnectionScope extends InheritedWidget {
  const _SchoolConnectionScope({
    required this.connection,
    required this.pairing,
    required super.child,
  });

  final SchoolConnection connection;
  final SchoolPairing? pairing;

  @override
  bool updateShouldNotify(_SchoolConnectionScope oldWidget) =>
      oldWidget.pairing != pairing ||
      !identical(oldWidget.connection, connection);
}

/// شاشة انتظار أثناء تحديد المدرسة وتشغيل التطبيق.
class _BootSplash extends StatelessWidget {
  const _BootSplash({required this.app});

  final AppIdentity app;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      body: Center(
        child: Semantics(
          label: 'جارٍ تشغيل ${app.displayName}',
          child: SizedBox.square(
            dimension: 32,
            child: CircularProgressIndicator(strokeWidth: 3, color: p.accent),
          ),
        ),
      ),
    );
  }
}

/// تعذّر تشغيل التطبيق على المدرسة المحددة.
class _StartFailureScreen extends StatelessWidget {
  const _StartFailureScreen({
    required this.app,
    required this.onRetry,
    required this.onChangeSchool,
  });

  final AppIdentity app;
  final Future<void> Function() onRetry;
  final Future<void> Function()? onChangeSchool;

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      app: app,
      title: 'تعذّر تشغيل التطبيق',
      subtitle:
          'تحقق من اتصال الإنترنت ثم أعد المحاولة. إن تكرر الخطأ فقد يكون '
          'رمز الربط قديماً أو تالفاً.',
      children: [
        ClayButton(
          label: 'إعادة المحاولة',
          icon: ClayIcons.check,
          expand: true,
          onPressed: onRetry,
        ),
        if (onChangeSchool != null) ...[
          const SizedBox(height: ClaySpacing.md),
          ClayButton(
            label: 'تغيير المدرسة',
            kind: ClayButtonKind.secondary,
            expand: true,
            onPressed: onChangeSchool,
          ),
        ],
      ],
    );
  }
}
