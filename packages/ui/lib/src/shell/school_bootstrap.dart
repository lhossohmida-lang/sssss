import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
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
import 'device_reset.dart';
import 'directory_screens.dart';
import 'pairing_screens.dart';
import 'providers.dart';
import 'pwa_install.dart';
import 'qr_scanning.dart';
import 'school_app.dart';

/// يشغّل وقت تشغيل التطبيق لإعدادات مدرسة ([config] فارغ = معاينة محلية).
typedef RuntimeStarter = Future<AppRuntime> Function(
  AppIdentity app,
  AppConfig? config,
);

/// يوقف وقت تشغيل بعد أن فُكّت واجهته.
typedef RuntimeStopper = Future<void> Function(AppRuntime runtime);

/// يمسح ما حفظه التطبيق على الجهاز عند «مسح بيانات هذا الجهاز»، بعد إيقاف وقت التشغيل.
typedef DeviceDataWipe = Future<void> Function(AppIdentity app);

/// ما يتيحه الجذر لشاشات التطبيق المُشغَّل: أي مدرسة ربط بها الجهاز، والخروج منها.
abstract interface class SchoolConnection {
  /// ربط الجهاز بمدرسة، أو `null` في المعاينة المحلية وفي بناء مضمَّن الإعداد.
  SchoolPairing? get pairing;

  /// هل يُسمح بتغيير المدرسة من التطبيق؟ لا في بناء مضمَّن الإعداد.
  bool get canChangeSchool;

  /// هل يعرف الجهاز مدرسته من دليل المدارس (دون رمز ربط)؟ فلا يُعرض رمز الربط.
  bool get usesDirectory;

  /// يغلق التطبيق على المدرسة الحالية ويعرض شاشة الدخول أو اختيار المدرسة من جديد.
  ///
  /// قاعدة المدرسة المحلية تبقى على الجهاز وتعود عند الربط بها ثانية.
  Future<void> leaveSchool();

  /// «إعادة تعيين بيانات المصنع» للجهاز: يخرج من الحساب ويغلق التطبيق ويمسح كل ما حفظه
  /// عليه (قواعد كل المدارس وصورها وملفاتها وربط المدرسة وجلسة الدخول) ثم يبدأ كأول تشغيل.
  ///
  /// لا يمسّ شيئاً على خادم المدرسة، فتعود بياناته بعد الدخول من جديد؛ أما ما لم يُرسل إليه
  /// من هذا الجهاز بعد فيضيع.
  Future<void> factoryReset();
}

/// جذر التطبيقات الثلاثة: يحدد مدرسة الجهاز ثم يشغّل التطبيق عليها.
///
/// - إعدادات مضمَّنة وقت البناء (`--dart-define`): تُستعمل دون سؤال.
/// - وإلا مدرسة محفوظة على الجهاز (من الدليل أو من رمز ربط).
/// - وإلا، إن كان دليل المدارس مضمَّناً: تطبيق الإدارة يطلب رقم الهاتف وكلمة
///   السر ويعرف المدرسة من رقمه، وتطبيقا الأستاذ والتلميذ يعرضان قائمة المدارس.
/// - وإلا شاشة الربط برمز المدرسة (بناء التطوير)، ومعها «تجربة محلية» في
///   تطبيق الإدارة وحده.
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
    this.directory,
    this.startRuntime = _defaultStart,
    this.stopRuntime = _defaultStop,
    this.wipeData = defaultWipe,
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

  /// دليل المدارس؛ الافتراضي ما مُرِّر وقت البناء (`DIRECTORY_URL` و`DIRECTORY_KEY`)،
  /// ودونه تبقى شاشة الربط برمز المدرسة.
  final SchoolDirectory? directory;

  final RuntimeStarter startRuntime;
  final RuntimeStopper stopRuntime;

  /// مسح بيانات الجهاز عند إعادة التعيين؛ الافتراضي [defaultWipe]. ويمرّر تطبيق الإدارة دالة
  /// تزيد عليه مسح رموز Drive المحفوظة في التخزين الآمن.
  final DeviceDataWipe wipeData;

  /// اتصال الجهاز بمدرسته لمن هم تحت الجذر، أو `null` خارجه.
  static SchoolConnection? connectionOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_SchoolConnectionScope>()
      ?.connection;

  static Future<AppRuntime> _defaultStart(AppIdentity app, AppConfig? config) =>
      AppRuntime.start(app: app, config: config);

  static Future<void> _defaultStop(AppRuntime runtime) => runtime.dispose();

  /// يمسح ملفات التطبيق على الجهاز (قواعد المدارس والصور والربط) وجلسات الدخول المحفوظة.
  /// يعيد ما تعذّر مسحه إلى [StateError] فيظهر للمستخدم بدل أن يبقى بيان قديم مخفياً.
  static Future<void> defaultWipe(AppIdentity app) async {
    final report = await DeviceDataWiper(app).wipe();
    await DeviceDataWiper.clearAuthSessions();
    if (!report.complete) {
      throw StateError('تعذّر مسح: ${report.failures.join('، ')}');
    }
  }

  @override
  State<SchoolBootstrap> createState() => _SchoolBootstrapState();
}

enum _Phase { loading, pairing, directorySignIn, schoolPicker, running, failed }

class _SchoolBootstrapState extends State<SchoolBootstrap>
    implements SchoolConnection {
  _Phase _phase = _Phase.loading;
  PairingStore? _store;
  AppRuntime? _runtime;
  SchoolPairing? _pairing;
  bool _baked = false;
  SchoolDirectory? _directory;

  /// بيانات دخول كتبها المستخدم قبل أن تُعرف مدرسته، تُجرَّب مرة واحدة حين يبدأ
  /// التطبيق على مدرسته (ولا تُحفظ).
  ({String login, String password})? _pendingLogin;

  /// سبب فشل الدخول التلقائي، يعرضه شاشة الدخول.
  String? _loginError;

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
  bool get usesDirectory => _directory != null && !_baked;

  @override
  void initState() {
    super.initState();
    _directory = widget.directory ?? _environmentDirectory();
    unawaited(_boot());
  }

  /// الدليل المضمَّن وقت البناء، أو `null` في بناء التطوير.
  static SchoolDirectory? _environmentDirectory() {
    final config = DirectoryConfig.fromEnvironment();
    return config.isConfigured ? HttpSchoolDirectory(config) : null;
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
      _showEntry(epoch);
    } on Object {
      _fail(epoch);
    }
  }

  /// أول شاشة بلا مدرسة: دخول الإدارة بالهاتف، أو قائمة المدارس للأستاذ والتلميذ،
  /// أو الربط برمز المدرسة حين لا دليل.
  void _showEntry(int epoch) {
    if (!mounted || epoch != _epoch) return;
    setState(
      () => _phase = switch (_directory) {
        null => _Phase.pairing,
        _ when widget.app == AppIdentity.admin => _Phase.directorySignIn,
        _ => _Phase.schoolPicker,
      },
    );
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
    } on Object catch (error, stack) {
      // في سجل التطبيق (وحدة تحكم المتصفح في نسخة الويب) لتشخيص سبب التعذّر.
      debugPrint('school-start-failed: $error \n$stack');
      _fail(epoch);
      return;
    }
    if (!mounted || epoch != _epoch) {
      await widget.stopRuntime(runtime);
      return;
    }
    // الدخول التلقائي ببيانات كتبها المستخدم قبل أن تُعرف مدرسته (تطبيق الإدارة).
    final pending = _pendingLogin;
    _pendingLogin = null;
    _loginError = null;
    if (pending != null) {
      try {
        await runtime.auth.signIn(
          email: pending.login,
          password: pending.password,
        );
      } on AuthFailureException catch (e) {
        _loginError = e.message;
      } on Object {
        _loginError = 'تعذّر تسجيل الدخول، تحقق من الإنترنت ثم أعد المحاولة';
      }
      if (!mounted || epoch != _epoch) {
        await widget.stopRuntime(runtime);
        return;
      }
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

  /// تطبيق الإدارة: عرف الدليل المدرسة من الهاتف، فيُربط الجهاز بها ويدخل
  /// المستخدم بما كتبه دون أن يكتبه مرة ثانية.
  Future<void> _directorySignIn(
    DirectorySchool school,
    String login,
    String password,
  ) async {
    final epoch = ++_epoch;
    final pairing = school.toPairing();
    await _store!.save(pairing);
    _pairing = pairing;
    _pendingLogin = (login: login, password: password);
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
    _pendingLogin = null;
    _loginError = null;
    _showEntry(epoch);
  }

  @override
  Future<void> factoryReset() async {
    final epoch = ++_epoch;
    final old = _runtime;
    setState(() {
      _runtime = null;
      _pairing = null;
      _phase = _Phase.loading;
    });
    // الإطار التالي يفكّ شجرة التطبيق قبل إغلاق قاعدته، فلا تقرأ شاشة منها.
    await WidgetsBinding.instance.endOfFrame;
    if (old != null) {
      // الخروج من الحساب إن أمكن (دون إنترنت تُمحى الجلسة المحلية فقط)، ثم إغلاق القاعدة.
      try {
        await old.auth.signOut().timeout(const Duration(seconds: 5));
      } on Object {
        // لا يمنع المسح.
      }
      await widget.stopRuntime(old);
    }
    Object? failure;
    try {
      await widget.wipeData(widget.app);
    } on Object catch (e) {
      failure = e;
    }
    // ملف الربط يُمسح دائماً (ولو تعذّر مسح غيره) فلا يعود الجهاز إلى مدرسة قديمة.
    await _store?.clear();
    _hasLastConfig = false;
    _pendingLogin = null;
    _loginError = null;
    if (failure != null) {
      _fail(epoch);
      return;
    }
    // الإقلاع من جديد: بناء مضمَّن الإعداد يبدأ على مدرسته، وغيره يعرض أول شاشة.
    if (mounted && epoch == _epoch) unawaited(_boot());
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
            initialLoginErrorProvider.overrideWithValue(_loginError),
            if (widget.cameraFactory != null)
              qrCameraFactoryProvider.overrideWithValue(widget.cameraFactory),
            ...widget.overrides,
          ],
          child: app,
        ),
      );
    }
    // قبل الاتصال بالمدرسة (الربط ودليل المدارس واختيار المدرسة): بطاقة التثبيت على الشاشة الرئيسية في نسخة الويب.
    return ClayApp(
      app: widget.app,
      footer: kIsWeb ? const PwaInstallOverlay() : null,
      home: switch (_phase) {
        _Phase.pairing => PairingScreen(
          app: widget.app,
          onPair: _pair,
          onLocalPreview: widget.app == AppIdentity.admin
              ? _chooseLocalPreview
              : null,
          cameraFactory: widget.cameraFactory,
        ),
        _Phase.directorySignIn => DirectorySignInScreen(
          app: widget.app,
          directory: _directory!,
          onSignIn: _directorySignIn,
          onLocalPreview: _chooseLocalPreview,
        ),
        _Phase.schoolPicker => SchoolPickerScreen(
          app: widget.app,
          directory: _directory!,
          onPick: (school) => _pair(school.toPairing()),
        ),
        _Phase.failed => _StartFailureScreen(
          app: widget.app,
          onRetry: _retry,
          onChangeSchool: _baked ? null : leaveSchool,
          onReset: factoryReset,
          usesDirectory: usesDirectory,
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
    required this.onReset,
    required this.usesDirectory,
  });

  final AppIdentity app;
  final Future<void> Function() onRetry;
  final Future<void> Function()? onChangeSchool;
  final Future<void> Function() onReset;
  final bool usesDirectory;

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      app: app,
      title: 'تعذّر تشغيل التطبيق',
      subtitle: usesDirectory
          ? 'تحقق من اتصال الإنترنت ثم أعد المحاولة. إن تكرر الخطأ فجرّب '
                'تغيير المدرسة.'
          : 'تحقق من اتصال الإنترنت ثم أعد المحاولة. إن تكرر الخطأ فقد يكون '
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
        // قاعدة محلية تالفة أو قديمة هي من أكثر أسباب العطل، ومسحها يعيد التطبيق كأول تشغيل.
        const SizedBox(height: ClaySpacing.md),
        TextButton(
          onPressed: () async {
            if (await confirmDeviceReset(context)) await onReset();
          },
          child: const Text('مسح بيانات هذا الجهاز'),
        ),
      ],
    );
  }
}
