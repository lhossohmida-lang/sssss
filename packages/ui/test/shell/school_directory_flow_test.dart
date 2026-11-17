import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/testing.dart';
import 'package:school_ui/school_ui.dart';
import 'package:school_ui/testing.dart';

const _key = 'sb_publishable_abcdefghijklmnopqrstuvwxyz012345';

DirectorySchool _school(String id, String name, String letter) =>
    DirectorySchool(
      id: id,
      name: name,
      url: 'https://${letter * 20}.supabase.co',
      key: _key,
    );

final _alnour = _school('1', 'مدرسة النور', 'a');
final _alamal = _school('2', 'مدرسة الأمل', 'b');

const _owner = TestAccount(
  id: 'u-owner',
  email: '0550123456@school.local',
  password: 'owner-pass-1',
  role: UserRole.owner,
  displayName: 'صاحب المدرسة',
);

class _MemoryStore implements PairingStore {
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
  AppTab(
    path: '/students',
    destination: const ClayDestination(
      label: 'التلاميذ',
      icon: ClayIcons.students,
    ),
    builder: (_) => const Text('صفحة التلاميذ'),
  ),
];

/// جذر اختباري بدليل مدارس وهمي ووقت تشغيل جاهز بحساب المالك.
class _Harness {
  _Harness(
    this.tester, {
    required this.app,
    required this.directory,
    _MemoryStore? store,
    this.wrap,
  }) : store = store ?? _MemoryStore();

  final WidgetTester tester;
  final AppIdentity app;
  final FakeSchoolDirectory directory;
  final _MemoryStore store;
  final Widget Function(Widget app)? wrap;
  final List<AppConfig?> started = [];
  final List<AppRuntime> stopped = [];
  SchoolConnection? connection;
  late final AppRuntime runtime;

  Future<void> mount() async {
    runtime = (await tester.runAsync(
      () => startTestRuntime(app: app, accounts: [_owner]),
    ))!;
    addTearDown(() async {
      await tester.runAsync(() async {
        await runtime.auth.dispose();
        await runtime.db.close();
      });
    });
    await tester.pumpWidget(
      SchoolBootstrap(
        app: app,
        tabs: _tabs,
        bakedConfig: const AppConfig(),
        store: store,
        directory: directory,
        wrapApp: (child) => Builder(
          builder: (context) {
            connection = SchoolBootstrap.connectionOf(context);
            return wrap == null ? child : wrap!(child);
          },
        ),
        startRuntime: (app, config) async {
          started.add(config);
          return runtime;
        },
        stopRuntime: (runtime) async => stopped.add(runtime),
      ),
    );
    await tester.pump();
    await tester.pump();
  }
}

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

Finder field(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(Column)).first,
  matching: find.byType(TextField),
);

Future<void> signIn(WidgetTester tester, String phone, String password) async {
  await tester.enterText(field('رقم الهاتف'), phone);
  await tester.enterText(field('كلمة السر'), password);
  await tester.tap(find.widgetWithText(ClayButton, 'دخول'));
  await settle(tester);
}

void main() {
  group('الإدارة: الدخول بالهاتف دون رمز ربط', () {
    appTest('جهاز بلا مدرسة يطلب الهاتف وكلمة السر ولا يعرض الربط', (
      tester,
    ) async {
      final h = _Harness(
        tester,
        app: AppIdentity.admin,
        directory: FakeSchoolDirectory(),
      );
      await h.mount();
      expect(find.text('تسجيل الدخول'), findsOneWidget);
      expect(find.text('رقم الهاتف'), findsOneWidget);
      expect(find.text('كلمة السر'), findsOneWidget);
      expect(find.text('ربط التطبيق بمدرستك'), findsNothing);
      expect(find.text('رمز الربط'), findsNothing);
      expect(find.text('تجربة محلية بلا خادم'), findsOneWidget);
      expect(h.started, isEmpty);
    });

    appTest('رقم معروف: يُعرف المدرسة ويربط الجهاز ويدخل بما كُتب', (
      tester,
    ) async {
      final directory = FakeSchoolDirectory(
        staff: {
          '0550123456': [_alnour],
        },
      );
      final h = _Harness(tester, app: AppIdentity.admin, directory: directory);
      await h.mount();

      await signIn(tester, '0550 123 456', 'owner-pass-1');

      expect(directory.resolved, ['0550 123 456']);
      expect(h.started.single?.supabaseUrl, _alnour.url);
      expect(h.started.single?.schoolName, 'مدرسة النور');
      expect(h.store.pairing, _alnour.toPairing());
      expect(h.runtime.auth.current?.email, '0550123456@school.local');
      expect(find.text('صفحة الرئيسية'), findsOneWidget);
      expect(find.text('تسجيل الدخول'), findsNothing);
      expect(h.connection!.usesDirectory, isTrue);
      expect(h.connection!.pairing, _alnour.toPairing());
    });

    appTest('كلمة سر خاطئة: الجهاز مربوط والخطأ يظهر في شاشة الدخول', (
      tester,
    ) async {
      final directory = FakeSchoolDirectory(
        staff: {
          '0550123456': [_alnour],
        },
      );
      final h = _Harness(tester, app: AppIdentity.admin, directory: directory);
      await h.mount();

      await signIn(tester, '0550123456', 'wrong-pass');

      expect(
        h.started,
        hasLength(1),
        reason: 'عُرفت المدرسة فبدأ التطبيق عليها',
      );
      expect(h.store.pairing, _alnour.toPairing());
      expect(h.runtime.auth.current, isNull);
      expect(find.text('تسجيل الدخول'), findsOneWidget);
      expect(find.text('رقم الهاتف أو كلمة السر غير صحيحة'), findsOneWidget);

      // يصحّح كلمة السر من الشاشة نفسها دون سؤال الدليل ثانية.
      await tester.enterText(field('رقم الهاتف'), '0550123456');
      await tester.enterText(field('كلمة السر'), 'owner-pass-1');
      await tester.tap(find.widgetWithText(ClayButton, 'دخول'));
      await settle(tester);
      expect(find.text('صفحة الرئيسية'), findsOneWidget);
      expect(directory.resolved, hasLength(1));
    });

    appTest('رقم غير مسجّل في أي مدرسة: رسالة ولا يُشغَّل شيء', (tester) async {
      final directory = FakeSchoolDirectory();
      final h = _Harness(tester, app: AppIdentity.admin, directory: directory);
      await h.mount();

      await signIn(tester, '0661234567', 'whatever-1');

      expect(find.textContaining('غير مسجّل في أي مدرسة'), findsOneWidget);
      expect(directory.resolved, ['0661234567']);
      expect(h.started, isEmpty);
      expect(h.store.pairing, isNull);
    });

    appTest('رقم خاطئ الصيغة أو بريد: لا يُسأل الدليل أصلاً', (tester) async {
      final directory = FakeSchoolDirectory();
      final h = _Harness(tester, app: AppIdentity.admin, directory: directory);
      await h.mount();

      await signIn(tester, '12345', 'pass-1234');
      expect(find.textContaining('يبدأ بـ 05 أو 06 أو 07'), findsOneWidget);

      await signIn(tester, 'owner@school.com', 'pass-1234');
      expect(find.text('أدخل رقم هاتفك لا بريداً إلكترونياً'), findsOneWidget);

      await signIn(tester, '', '');
      expect(find.text('أدخل رقم الهاتف'), findsOneWidget);
      expect(find.text('أدخل كلمة السر'), findsOneWidget);
      expect(directory.resolved, isEmpty);
      expect(h.started, isEmpty);
    });

    appTest('عطل الدليل: رسالة عربية وإمكان المحاولة ثانية', (tester) async {
      final directory = FakeSchoolDirectory(
        staff: {
          '0550123456': [_alnour],
        },
        failure: DirectoryFailure.offline,
      );
      final h = _Harness(tester, app: AppIdentity.admin, directory: directory);
      await h.mount();

      await signIn(tester, '0550123456', 'owner-pass-1');
      expect(find.text(DirectoryFailure.offline.message), findsOneWidget);
      expect(h.started, isEmpty);

      directory.failure = null;
      await tester.tap(find.widgetWithText(ClayButton, 'دخول'));
      await settle(tester);
      expect(find.text('صفحة الرئيسية'), findsOneWidget);
    });

    appTest('رقم في مدرستين: حوار اختيار ثم الدخول إلى المختارة', (
      tester,
    ) async {
      final directory = FakeSchoolDirectory(
        staff: {
          '0550123456': [_alnour, _alamal],
        },
      );
      final h = _Harness(tester, app: AppIdentity.admin, directory: directory);
      await h.mount();

      await tester.enterText(field('رقم الهاتف'), '0550123456');
      await tester.enterText(field('كلمة السر'), 'owner-pass-1');
      await tester.tap(find.widgetWithText(ClayButton, 'دخول'));
      // زر الدخول يدور (حالة انتظار) ما دام الحوار مفتوحاً، فلا pumpAndSettle.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('اختر المدرسة'), findsOneWidget);
      expect(h.started, isEmpty);

      await tester.tap(find.widgetWithText(ClayButton, 'مدرسة الأمل'));
      await settle(tester);
      expect(h.started.single?.supabaseUrl, _alamal.url);
      expect(h.store.pairing, _alamal.toPairing());
    });

    appTest('مدرسة محفوظة تُستعمل عند الإقلاع دون سؤال الدليل', (tester) async {
      final directory = FakeSchoolDirectory();
      final store = _MemoryStore()..pairing = _alnour.toPairing();
      final h = _Harness(
        tester,
        app: AppIdentity.admin,
        directory: directory,
        store: store,
      );
      await h.mount();
      await settle(tester);
      expect(h.started.single?.supabaseUrl, _alnour.url);
      expect(find.text('تسجيل الدخول'), findsOneWidget);
      expect(directory.resolved, isEmpty);
      expect(directory.listCalls, 0);
    });

    appTest('«تغيير المدرسة» من شاشة الدخول يعيد طلب الهاتف ويفك الربط', (
      tester,
    ) async {
      final store = _MemoryStore()..pairing = _alnour.toPairing();
      final h = _Harness(
        tester,
        app: AppIdentity.admin,
        directory: FakeSchoolDirectory(),
        store: store,
      );
      await h.mount();
      await settle(tester);

      await tester.tap(find.text('تغيير المدرسة'));
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(store.calls, contains('clear'));
      expect(h.stopped, [h.runtime]);
      expect(find.text('تسجيل الدخول'), findsOneWidget);
      expect(find.text('رقم الهاتف'), findsOneWidget);
      expect(find.text('رمز الربط'), findsNothing);
    });

    appTest('التجربة المحلية تبقى متاحة ولا تمسّ الدليل', (tester) async {
      final directory = FakeSchoolDirectory();
      final h = _Harness(tester, app: AppIdentity.admin, directory: directory);
      await h.mount();
      await tester.tap(find.text('تجربة محلية بلا خادم'));
      await settle(tester);
      expect(h.store.localPreview, isTrue);
      expect(h.started.single, isNull);
      expect(directory.resolved, isEmpty);
    });
  });

  group('الأستاذ والتلميذ: قائمة المدارس', () {
    for (final app in [AppIdentity.teacher, AppIdentity.student]) {
      appTest('${app.name}: المدارس تظهر مباشرة، وبالضغط تُربط ويظهر الدخول', (
        tester,
      ) async {
        final directory = FakeSchoolDirectory(schools: [_alamal, _alnour]);
        final h = _Harness(tester, app: app, directory: directory);
        await h.mount();
        await tester.pump();

        expect(find.text('اختر مدرستك'), findsOneWidget);
        expect(find.widgetWithText(ClayButton, 'مدرسة النور'), findsOneWidget);
        expect(find.widgetWithText(ClayButton, 'مدرسة الأمل'), findsOneWidget);
        expect(find.text('ربط التطبيق بمدرستك'), findsNothing);
        expect(find.text('ابحث عن مدرستك'), findsNothing);
        expect(h.started, isEmpty);

        await tester.tap(find.widgetWithText(ClayButton, 'مدرسة النور'));
        await settle(tester);

        expect(h.started.single?.supabaseUrl, _alnour.url);
        expect(h.started.single?.schoolName, 'مدرسة النور');
        expect(h.store.pairing, _alnour.toPairing());
        expect(find.text('تسجيل الدخول'), findsOneWidget);
        expect(find.text('رقم الهاتف'), findsOneWidget);
        expect(directory.listCalls, 1);
        expect(directory.resolved, isEmpty, reason: 'لا بحث بالهاتف هنا');
      });
    }

    appTest('خانة البحث تظهر حين تكثر المدارس وتصفّي بالاسم', (tester) async {
      final directory = FakeSchoolDirectory(
        schools: [
          for (var i = 0; i < 7; i++)
            _school('$i', 'مدرسة رقم $i', 'cdefghi'[i]),
          _school('x', 'ثانوية الفجر', 'j'),
        ],
      );
      final h = _Harness(
        tester,
        app: AppIdentity.student,
        directory: directory,
      );
      await h.mount();
      await tester.pump();

      expect(find.text('ابحث عن مدرستك'), findsOneWidget);
      await tester.enterText(field('ابحث عن مدرستك'), 'الفجر');
      await tester.pump();
      expect(find.widgetWithText(ClayButton, 'ثانوية الفجر'), findsOneWidget);
      expect(find.widgetWithText(ClayButton, 'مدرسة رقم 3'), findsNothing);

      await tester.enterText(field('ابحث عن مدرستك'), 'لا شيء');
      await tester.pump();
      expect(find.text('لا مدرسة بهذا الاسم'), findsOneWidget);
    });

    appTest('عطل الدليل: رسالة وزر إعادة المحاولة يحمّل القائمة', (
      tester,
    ) async {
      final directory = FakeSchoolDirectory(
        schools: [_alnour],
        failure: DirectoryFailure.offline,
      );
      final h = _Harness(
        tester,
        app: AppIdentity.teacher,
        directory: directory,
      );
      await h.mount();
      await tester.pump();
      expect(find.text(DirectoryFailure.offline.message), findsOneWidget);
      expect(find.widgetWithText(ClayButton, 'مدرسة النور'), findsNothing);

      directory.failure = null;
      await tester.tap(find.widgetWithText(ClayButton, 'إعادة المحاولة'));
      await tester.pump();
      await tester.pump();
      expect(find.widgetWithText(ClayButton, 'مدرسة النور'), findsOneWidget);
      expect(directory.listCalls, 2);
    });

    appTest('قائمة فارغة: رسالة واضحة وزر تحديث', (tester) async {
      final h = _Harness(
        tester,
        app: AppIdentity.student,
        directory: FakeSchoolDirectory(),
      );
      await h.mount();
      await tester.pump();
      expect(find.textContaining('لا توجد مدارس في القائمة'), findsOneWidget);
      expect(find.widgetWithText(ClayButton, 'تحديث'), findsOneWidget);
    });

    appTest('«تغيير المدرسة» من شاشة الدخول يعيد قائمة المدارس', (
      tester,
    ) async {
      final directory = FakeSchoolDirectory(schools: [_alnour, _alamal]);
      final h = _Harness(
        tester,
        app: AppIdentity.teacher,
        directory: directory,
      );
      await h.mount();
      await tester.pump();
      await tester.tap(find.widgetWithText(ClayButton, 'مدرسة الأمل'));
      await settle(tester);
      expect(find.text('تسجيل الدخول'), findsOneWidget);

      await tester.tap(find.text('تغيير المدرسة'));
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(h.store.calls, contains('clear'));
      expect(find.text('اختر مدرستك'), findsOneWidget);
      expect(directory.listCalls, 2);
    });

    appTest('مدرسة محفوظة تُستعمل عند الإقلاع دون عرض القائمة', (tester) async {
      final directory = FakeSchoolDirectory(schools: [_alnour]);
      final store = _MemoryStore()..pairing = _alnour.toPairing();
      final h = _Harness(
        tester,
        app: AppIdentity.student,
        directory: directory,
        store: store,
      );
      await h.mount();
      await settle(tester);
      expect(find.text('تسجيل الدخول'), findsOneWidget);
      expect(directory.listCalls, 0);
    });
  });

  group('حسابي مع الدليل', () {
    appTest('الإدارة لا ترى رمز الربط وترى تغيير المدرسة', (tester) async {
      final store = _MemoryStore()..pairing = _alnour.toPairing();
      final h = _Harness(
        tester,
        app: AppIdentity.admin,
        directory: FakeSchoolDirectory(),
        store: store,
        wrap: (_) => const ClayApp(
          app: AppIdentity.admin,
          home: Scaffold(body: SchoolConnectionSection()),
        ),
      );
      await h.mount();
      await settle(tester);
      expect(find.text('رمز ربط الأجهزة الأخرى'), findsNothing);
      expect(find.text('تغيير المدرسة'), findsOneWidget);

      await tester.tap(find.widgetWithText(ClayButton, 'تغيير المدرسة'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('تدخل برقم هاتفك فتُعرف مدرستك'),
        findsOneWidget,
      );
    });
  });
}
