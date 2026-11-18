import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/testing.dart';
import 'package:school_ui/school_ui.dart';
import 'package:school_ui/testing.dart';

const _urlA = 'https://aaaaaaaaaaaaaaaaaaaa.supabase.co';
const _urlB = 'https://bbbbbbbbbbbbbbbbbbbb.supabase.co';
const _key = 'sb_publishable_abcdefghijklmnopqrstuvwxyz012345';
const _a = SchoolPairing(url: _urlA, key: _key, name: 'مدرسة أ');
const _b = SchoolPairing(url: _urlB, key: _key, name: 'مدرسة ب');

class MemoryPairingStore implements PairingStore {
  SchoolPairing? pairing;
  bool localPreview = false;
  final List<String> calls = [];

  @override
  Future<SchoolPairing?> load() async => pairing;

  @override
  Future<bool> isLocalPreview() async => localPreview;

  @override
  Future<void> save(SchoolPairing value) async {
    calls.add('save');
    pairing = value;
    localPreview = false;
  }

  @override
  Future<void> chooseLocalPreview() async {
    calls.add('local');
    pairing = null;
    localPreview = true;
  }

  @override
  Future<void> clear() async {
    calls.add('clear');
    pairing = null;
    localPreview = false;
  }
}

final _tabs = [
  AppTab(
    path: '/home',
    destination: const ClayDestination(label: 'الرئيسية', icon: ClayIcons.home),
    builder: (_) => const Text('صفحة الرئيسية'),
  ),
];

/// جذر اختباري: وقت تشغيل جاهز يُعاد عند كل طلب، ويُسجَّل ما طُلب تشغيله وإيقافه.
class _Harness {
  _Harness(
    this.tester, {
    required this.app,
    MemoryPairingStore? store,
    this.baked = const AppConfig(),
    this.wrap,
    this.failures = 0,
    this.wipeFails = false,
    this._reuse,
  }) : store = store ?? MemoryPairingStore();

  final WidgetTester tester;
  final AppIdentity app;
  final MemoryPairingStore store;
  final AppConfig baked;
  final Widget Function(Widget app)? wrap;
  int failures;

  /// هل يفشل مسح بيانات الجهاز؟
  final bool wipeFails;
  final AppRuntime? _reuse;

  final List<AppConfig?> started = [];
  final List<AppRuntime> stopped = [];
  final List<AppIdentity> wiped = [];
  SchoolConnection? connection;
  late final AppRuntime runtime;

  Future<void> mount() async {
    final reuse = _reuse;
    if (reuse != null) {
      runtime = reuse;
    } else {
      runtime = (await tester.runAsync(() => startTestRuntime(app: app)))!;
      addTearDown(() async {
        await tester.runAsync(() async {
          await runtime.auth.dispose();
          await runtime.db.close();
        });
      });
    }
    await tester.pumpWidget(
      SchoolBootstrap(
        app: app,
        tabs: _tabs,
        bakedConfig: baked,
        store: store,
        wrapApp: (child) => Builder(
          builder: (context) {
            connection = SchoolBootstrap.connectionOf(context);
            return wrap == null ? child : wrap!(child);
          },
        ),
        startRuntime: (app, config) async {
          started.add(config);
          if (failures > 0) {
            failures--;
            throw StateError('تعذّر التشغيل');
          }
          return runtime;
        },
        stopRuntime: (runtime) async => stopped.add(runtime),
        wipeData: (app) async {
          if (wipeFails) throw StateError('تعذّر المسح');
          wiped.add(app);
        },
      ),
    );
    await tester.pump();
    await tester.pump();
  }
}

/// يمرّر شاشة البداية (900ms) وانتقالات الموجِّه حتى يستقر الإطار.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

/// حافظة وهمية: تُرجع [text] لـ`getData` وتسجّل ما يُنسخ في [copied].
void mockClipboard(WidgetTester tester, {String? text, List<String>? copied}) {
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.getData') {
      return text == null ? null : {'text': text};
    }
    if (call.method == 'Clipboard.setData') {
      copied?.add((call.arguments as Map)['text'] as String);
    }
    return null;
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
}

Future<void> connect(WidgetTester tester, String code) async {
  await tester.enterText(find.byType(TextField), code);
  await tester.tap(find.widgetWithText(ClayButton, 'ربط'));
  await settle(tester);
}

void main() {
  group('إقلاع الجهاز', () {
    appTest('بناء مضمَّن الإعداد يتجاوز الربط ولا يسمح بتغيير المدرسة', (
      tester,
    ) async {
      final h = _Harness(
        tester,
        app: AppIdentity.teacher,
        baked: const AppConfig(supabaseUrl: _urlA, supabaseAnonKey: _key),
      );
      await h.mount();
      await settle(tester);
      expect(h.started.single?.supabaseUrl, _urlA);
      expect(find.text('تسجيل الدخول'), findsOneWidget);
      expect(h.connection!.canChangeSchool, isFalse);
      expect(h.store.calls, isEmpty, reason: 'لا يُكتب ربط لبناء مضمَّن');
    });

    appTest('جهاز غير مربوط يعرض الربط، ولا تجربة محلية للأستاذ', (
      tester,
    ) async {
      final h = _Harness(tester, app: AppIdentity.teacher);
      await h.mount();
      expect(find.text('ربط التطبيق بمدرستك'), findsOneWidget);
      expect(find.text('تجربة محلية بلا خادم'), findsNothing);
      expect(find.widgetWithText(ClayButton, 'مسح رمز QR'), findsNothing);
      expect(h.started, isEmpty);
    });

    appTest('لصق رمز صحيح يحفظ الربط ويشغّل التطبيق على مدرسته', (
      tester,
    ) async {
      final h = _Harness(tester, app: AppIdentity.teacher);
      await h.mount();
      await connect(tester, _a.code);
      expect(h.started.single?.supabaseUrl, _urlA);
      expect(h.started.single?.supabaseAnonKey, _key);
      expect(h.started.single?.schoolName, 'مدرسة أ');
      expect(h.store.pairing, _a);
      expect(find.text('تسجيل الدخول'), findsOneWidget);
      expect(h.connection!.pairing, _a);
      expect(h.connection!.canChangeSchool, isTrue);
    });

    appTest('رمز غير صالح: رسالة عربية ولا يُشغَّل شيء ولا يُحفظ', (
      tester,
    ) async {
      final h = _Harness(tester, app: AppIdentity.teacher);
      await h.mount();
      await tester.enterText(find.byType(TextField), 'abc');
      await tester.tap(find.widgetWithText(ClayButton, 'ربط'));
      await tester.pump();
      expect(find.text(PairingFailure.malformed.message), findsOneWidget);
      expect(h.started, isEmpty);
      expect(h.store.pairing, isNull);
    });

    appTest('مفتاح سري في الرمز يُرفض برسالة صريحة', (tester) async {
      final h = _Harness(tester, app: AppIdentity.teacher);
      await h.mount();
      final payload = jsonEncode({
        'v': 1,
        'u': _urlA,
        'k': 'sb_secret_abcdefghijklmnopqrstuv',
      });
      final code =
          'SCH1.${base64Url.encode(utf8.encode(payload)).replaceAll('=', '')}';
      await tester.enterText(find.byType(TextField), code);
      await tester.tap(find.widgetWithText(ClayButton, 'ربط'));
      await tester.pump();
      expect(find.text(PairingFailure.secretKey.message), findsOneWidget);
      expect(h.started, isEmpty);
    });

    appTest('ربط محفوظ يُستعمل عند الإقلاع دون سؤال', (tester) async {
      final store = MemoryPairingStore()..pairing = _a;
      final h = _Harness(tester, app: AppIdentity.student, store: store);
      await h.mount();
      await settle(tester);
      expect(h.started.single?.supabaseUrl, _urlA);
      expect(find.text('تسجيل الدخول'), findsOneWidget);
    });

    appTest('شاشة الدخول بعد الربط برمز: «ربط الجهاز بمدرسة أخرى» يفكّ الربط', (
      tester,
    ) async {
      final store = MemoryPairingStore()..pairing = _a;
      final h = _Harness(tester, app: AppIdentity.admin, store: store);
      await h.mount();
      await settle(tester);
      expect(find.text('تسجيل الدخول'), findsOneWidget);
      expect(find.text('تغيير المدرسة'), findsNothing, reason: 'لا دليل');
      final link = find.text('ربط الجهاز بمدرسة أخرى');
      expect(link, findsOneWidget);

      await tester.ensureVisible(link);
      await tester.tap(link);
      await settle(tester);
      expect(store.calls, contains('clear'));
      expect(h.stopped, [h.runtime]);
      expect(find.text('ربط التطبيق بمدرستك'), findsOneWidget);
    });

    appTest('بناء مضمَّن الإعداد: شاشة الدخول بلا رابط تغيير الربط', (
      tester,
    ) async {
      final h = _Harness(
        tester,
        app: AppIdentity.student,
        baked: const AppConfig(supabaseUrl: _urlA, supabaseAnonKey: _key),
      );
      await h.mount();
      await settle(tester);
      expect(find.text('تسجيل الدخول'), findsOneWidget);
      expect(find.text('ربط الجهاز بمدرسة أخرى'), findsNothing);
      expect(find.text('تغيير المدرسة'), findsNothing);
    });

    appTest('الإدارة: التجربة المحلية تُحفظ فلا تعود شاشة الربط', (
      tester,
    ) async {
      final store = MemoryPairingStore();
      final h = _Harness(tester, app: AppIdentity.admin, store: store);
      await h.mount();
      final preview = find.widgetWithText(ClayButton, 'تجربة محلية بلا خادم');
      await tester.ensureVisible(preview);
      await tester.tap(preview);
      await settle(tester);
      expect(store.localPreview, isTrue);
      expect(h.started.single, isNull, reason: 'معاينة بلا إعدادات خادم');
      expect(h.connection!.pairing, isNull);
      expect(h.connection!.canChangeSchool, isTrue);

      // إقلاع ثانٍ بالمخزن نفسه يذهب إلى المعاينة دون شاشة الربط.
      await tester.pumpWidget(const SizedBox());
      final again = _Harness(
        tester,
        app: AppIdentity.admin,
        store: store,
        reuse: h.runtime,
      );
      await again.mount();
      await settle(tester);
      expect(again.started.single, isNull);
      expect(find.text('ربط التطبيق بمدرستك'), findsNothing);
    });
  });

  group('تغيير المدرسة', () {
    appTest('يغلق القديمة ويفكّ الربط ثم يبدأ الجديدة', (tester) async {
      final store = MemoryPairingStore()..pairing = _a;
      final h = _Harness(tester, app: AppIdentity.teacher, store: store);
      await h.mount();
      await settle(tester);

      unawaited(h.connection!.leaveSchool());
      await tester.pump();
      await tester.pump();
      expect(h.stopped, [h.runtime], reason: 'يُغلق بعد فكّ الواجهة');
      expect(store.calls, contains('clear'));
      expect(store.pairing, isNull);
      expect(find.text('ربط التطبيق بمدرستك'), findsOneWidget);

      await connect(tester, _b.code);
      expect(h.started.map((c) => c?.supabaseUrl), [_urlA, _urlB]);
      expect(store.pairing, _b);
      expect(h.connection!.pairing, _b);
    });

    appTest('فشل التشغيل: شاشة خطأ ثم تنجح إعادة المحاولة', (tester) async {
      final store = MemoryPairingStore()..pairing = _a;
      final h = _Harness(
        tester,
        app: AppIdentity.teacher,
        store: store,
        failures: 1,
      );
      await h.mount();
      expect(find.text('تعذّر تشغيل التطبيق'), findsOneWidget);
      expect(find.widgetWithText(ClayButton, 'تغيير المدرسة'), findsOneWidget);
      await tester.tap(find.widgetWithText(ClayButton, 'إعادة المحاولة'));
      await settle(tester);
      expect(find.text('تسجيل الدخول'), findsOneWidget);
      expect(h.started.length, 2);
    });

    appTest('فشل التشغيل في بناء مضمَّن لا يعرض تغيير المدرسة', (tester) async {
      final h = _Harness(
        tester,
        app: AppIdentity.teacher,
        baked: const AppConfig(supabaseUrl: _urlA, supabaseAnonKey: _key),
        failures: 1,
      );
      await h.mount();
      expect(find.text('تعذّر تشغيل التطبيق'), findsOneWidget);
      expect(find.widgetWithText(ClayButton, 'تغيير المدرسة'), findsNothing);
    });
  });

  group('مسح بيانات هذا الجهاز', () {
    const reset = 'مسح بيانات هذا الجهاز';

    appTest('من شاشة الدخول: تأكيد ثم مسح كل شيء والعودة إلى الربط', (
      tester,
    ) async {
      final store = MemoryPairingStore()..pairing = _a;
      final h = _Harness(tester, app: AppIdentity.student, store: store);
      await h.mount();
      await settle(tester);
      expect(find.text('تسجيل الدخول'), findsOneWidget);

      final link = find.text(reset);
      await tester.ensureVisible(link);
      await tester.tap(link);
      await tester.pumpAndSettle();
      expect(find.textContaining('لا يُمسّ شيء على خادم المدرسة'), findsOne);
      expect(
        find.text('هل أنت متأكد؟'),
        findsNothing,
        reason: 'لا بيانات معرّضة',
      );

      await tester.tap(find.widgetWithText(ClayButton, 'مسح وإعادة التعيين'));
      await settle(tester);

      expect(h.stopped, [h.runtime], reason: 'أُغلق وقت التشغيل قبل المسح');
      expect(h.wiped, [AppIdentity.student]);
      expect(store.calls, contains('clear'));
      expect(store.pairing, isNull);
      expect(find.text('ربط التطبيق بمدرستك'), findsOneWidget);
    });

    appTest('الإلغاء لا يمسح شيئاً', (tester) async {
      final store = MemoryPairingStore()..pairing = _a;
      final h = _Harness(tester, app: AppIdentity.student, store: store);
      await h.mount();
      await settle(tester);
      final link = find.text(reset);
      await tester.ensureVisible(link);
      await tester.tap(link);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ClayButton, 'إلغاء'));
      await tester.pumpAndSettle();

      expect(h.wiped, isEmpty);
      expect(h.stopped, isEmpty);
      expect(store.pairing, _a);
      expect(find.text('تسجيل الدخول'), findsOneWidget);
    });

    appTest('تغييرات لم تُرسل: تحذير بعددها وتأكيد من خطوتين', (tester) async {
      final store = MemoryPairingStore()..pairing = _a;
      final h = _Harness(tester, app: AppIdentity.student, store: store);
      await h.mount();
      await settle(tester);
      // صف في طابور الإرسال كأن تغييراً كُتب ولم يصل الخادم بعد.
      await runDb(
        tester,
        () => h.runtime.db
            .into(h.runtime.db.outbox)
            .insert(
              OutboxCompanion.insert(
                targetTable: 'subjects',
                rowId: 's1',
                payload: '{}',
                createdAt: 1,
              ),
            ),
      );
      final pending = await runDb(
        tester,
        () => countUnsyncedChanges(h.runtime.db),
      );
      expect(pending, greaterThan(0));

      final link = find.text(reset);
      await tester.ensureVisible(link);
      await tester.tap(link);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('لم يصل إلى الخادم بعد $pending تغيير'),
        findsOne,
      );

      await tester.tap(find.widgetWithText(ClayButton, 'متابعة'));
      await tester.pumpAndSettle();
      expect(find.text('هل أنت متأكد؟'), findsOneWidget);
      expect(h.wiped, isEmpty, reason: 'لم يؤكَّد بعد');

      await tester.tap(find.widgetWithText(ClayButton, 'نعم، امسح كل شيء'));
      await settle(tester);
      expect(h.wiped, [AppIdentity.student]);
    });

    appTest('فشل المسح: شاشة العطل وملف الربط ممسوح مع ذلك', (tester) async {
      final store = MemoryPairingStore()..pairing = _a;
      final h = _Harness(
        tester,
        app: AppIdentity.student,
        store: store,
        wipeFails: true,
      );
      await h.mount();
      await settle(tester);
      final link = find.text(reset);
      await tester.ensureVisible(link);
      await tester.tap(link);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ClayButton, 'مسح وإعادة التعيين'));
      await settle(tester);

      expect(find.text('تعذّر تشغيل التطبيق'), findsOneWidget);
      expect(store.pairing, isNull, reason: 'لا يعود الجهاز إلى مدرسة قديمة');
      expect(find.text(reset), findsOneWidget, reason: 'يمكن المحاولة ثانية');
    });

    appTest('شاشة العطل تعرض الزر: قاعدة تالفة تُصلح بالمسح', (tester) async {
      final store = MemoryPairingStore()..pairing = _a;
      final h = _Harness(
        tester,
        app: AppIdentity.student,
        store: store,
        failures: 1,
      );
      await h.mount();
      await settle(tester);
      expect(find.text('تعذّر تشغيل التطبيق'), findsOneWidget);

      await tester.tap(find.text(reset));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ClayButton, 'مسح وإعادة التعيين'));
      await settle(tester);

      expect(h.wiped, [AppIdentity.student]);
      expect(find.text('ربط التطبيق بمدرستك'), findsOneWidget);
    });
  });

  group('شاشة الربط', () {
    appTest('اللصق من الحافظة يربط مباشرة', (tester) async {
      mockClipboard(tester, text: '  ${_a.code}\n');
      final paired = <SchoolPairing>[];
      await tester.pumpWidget(
        ClayApp(
          app: AppIdentity.teacher,
          home: PairingScreen(
            app: AppIdentity.teacher,
            onPair: (p) async => paired.add(p),
          ),
        ),
      );
      await tester.tap(find.widgetWithText(ClayButton, 'لصق الرمز من الحافظة'));
      await tester.pumpAndSettle();
      expect(paired, [_a]);
    });

    appTest('حافظة فارغة تعطي رسالة لا ربطاً', (tester) async {
      mockClipboard(tester);
      final paired = <SchoolPairing>[];
      await tester.pumpWidget(
        ClayApp(
          app: AppIdentity.teacher,
          home: PairingScreen(
            app: AppIdentity.teacher,
            onPair: (p) async => paired.add(p),
          ),
        ),
      );
      await tester.tap(find.widgetWithText(ClayButton, 'لصق الرمز من الحافظة'));
      await tester.pumpAndSettle();
      expect(find.text(PairingFailure.empty.message), findsOneWidget);
      expect(paired, isEmpty);
    });

    appTest('فشل الاتصال بعد الربط يُعرض ويبقى الزر قابلاً للمحاولة', (
      tester,
    ) async {
      await tester.pumpWidget(
        ClayApp(
          app: AppIdentity.teacher,
          home: PairingScreen(
            app: AppIdentity.teacher,
            onPair: (_) async => throw StateError('لا شبكة'),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), _a.code);
      await tester.tap(find.widgetWithText(ClayButton, 'ربط'));
      await tester.pumpAndSettle();
      expect(find.textContaining('تعذّر تشغيل التطبيق'), findsOneWidget);
      expect(
        tester
            .widget<ClayButton>(find.widgetWithText(ClayButton, 'ربط'))
            .enabled,
        isTrue,
      );
    });

    appTest('المسح بالكاميرا: يتجاهل ما ليس رمز مدرسة ثم يربط بالصحيح', (
      tester,
    ) async {
      final source = FakeQrSource();
      final paired = <SchoolPairing>[];
      await tester.pumpWidget(
        ClayApp(
          app: AppIdentity.teacher,
          home: PairingScreen(
            app: AppIdentity.teacher,
            onPair: (p) async => paired.add(p),
            cameraFactory: () => source,
          ),
        ),
      );
      await tester.tap(find.widgetWithText(ClayButton, 'مسح رمز QR'));
      await tester.pumpAndSettle();
      expect(find.text('امسح رمز المدرسة'), findsOneWidget);
      expect(source.started, isTrue);

      source.emit('T-ABCDEFGHJK');
      // بمدة: pump بلا مدة لا يفرّغ microtasks إن لم يكن هناك إطار مجدول.
      await tester.pump(const Duration(milliseconds: 10));
      expect(find.text(PairingFailure.malformed.message), findsOneWidget);
      expect(paired, isEmpty);

      source.emit(_a.code);
      await tester.pumpAndSettle();
      expect(paired, [_a]);
      expect(source.disposed, isTrue);
      expect(find.text('امسح رمز المدرسة'), findsNothing);
    });
  });

  group('قسم المدرسة في حسابي', () {
    Widget section(Widget _) => const ClayApp(
      app: AppIdentity.admin,
      home: Scaffold(body: SchoolConnectionSection()),
    );

    appTest('الإدارة ترى رمز الربط وتنسخه ثم تغيّر المدرسة', (tester) async {
      final copied = <String>[];
      mockClipboard(tester, copied: copied);
      final store = MemoryPairingStore()..pairing = _a;
      final h = _Harness(
        tester,
        app: AppIdentity.admin,
        store: store,
        wrap: section,
      );
      await h.mount();
      await settle(tester);

      await tester.tap(
        find.widgetWithText(ClayButton, 'رمز ربط الأجهزة الأخرى'),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<ClayQrCode>(find.byType(ClayQrCode)).data,
        _a.code,
        reason: 'رمز QR هو الرمز نفسه الذي يُلصق',
      );
      await tester.tap(find.widgetWithText(ClayButton, 'نسخ الرمز'));
      await tester.pump();
      expect(copied, [_a.code]);
      await tester.tap(find.widgetWithText(ClayButton, 'إغلاق'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ClayButton, 'تغيير المدرسة'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ClayButton, 'متابعة'));
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(store.calls, contains('clear'));
      expect(h.stopped, [h.runtime]);
      expect(find.text('ربط التطبيق بمدرستك'), findsOneWidget);
    });

    appTest('الأستاذ يغيّر المدرسة فقط ولا يرى رمز الربط', (tester) async {
      final store = MemoryPairingStore()..pairing = _a;
      final h = _Harness(
        tester,
        app: AppIdentity.teacher,
        store: store,
        wrap: (_) => const ClayApp(
          app: AppIdentity.teacher,
          home: Scaffold(body: SchoolConnectionSection()),
        ),
      );
      await h.mount();
      await settle(tester);
      expect(find.text('رمز ربط الأجهزة الأخرى'), findsNothing);
      expect(find.text('تغيير المدرسة'), findsOneWidget);
    });

    appTest('بناء مضمَّن الإعداد لا يعرض القسم', (tester) async {
      final h = _Harness(
        tester,
        app: AppIdentity.admin,
        baked: const AppConfig(supabaseUrl: _urlA, supabaseAnonKey: _key),
        wrap: section,
      );
      await h.mount();
      await settle(tester);
      expect(find.text('رمز ربط الأجهزة الأخرى'), findsNothing);
      expect(find.text('تغيير المدرسة'), findsNothing);
    });

    appTest('المعاينة المحلية: «ربط بمدرسة» ولا رمز ربط', (tester) async {
      final store = MemoryPairingStore()..localPreview = true;
      final h = _Harness(
        tester,
        app: AppIdentity.admin,
        store: store,
        wrap: section,
      );
      await h.mount();
      await settle(tester);
      expect(find.text('ربط بمدرسة'), findsOneWidget);
      expect(find.text('رمز ربط الأجهزة الأخرى'), findsNothing);
    });
  });
}
