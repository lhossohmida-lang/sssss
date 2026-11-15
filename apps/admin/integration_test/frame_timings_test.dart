import 'package:admin/admin_tabs.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/testing.dart';
import 'package:school_ui/school_ui.dart';
import 'package:school_ui/testing.dart';

/// قياس زمن الإطارات لأثقل شاشات الإدارة على بيانات بحجم مدرسة ممتلئة
/// (2000 تلميذ و100 مجموعة وسنة حضور و50 ألف رسالة): يُمرَّر كل قائمة تمريراً
/// سريعاً ذهاباً وإياباً ويُقاس زمن بناء الإطار وتحويله إلى صورة.
///
/// يُشغَّل على محاكي Android في مسار `perf` بـGitHub Actions؛ وأرقام المحاكي
/// (معالج برمجي ووضع debug) أبطأ كثيراً من هاتف حقيقي فلا تُقارن به. انظر
/// `PERFORMANCE.md`.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  const owner = TestAccount(
    id: 'perf-owner',
    email: 'owner@perf.local',
    password: 'owner-pass-1',
    role: UserRole.owner,
    displayName: 'المدير',
  );

  testWidgets('زمن الإطارات في أثقل شاشات الإدارة', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    final watch = Stopwatch()..start();
    final summary = await PerfDataGenerator(db).generate();
    final generationMillis = watch.elapsedMilliseconds;
    final runtime = await startTestRuntime(
      app: AppIdentity.admin,
      accounts: [owner],
      database: db,
    );
    addTearDown(() async {
      await runtime.auth.dispose();
      await runtime.db.close();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          runtimeProvider.overrideWithValue(runtime),
          sessionCloserEnabledProvider.overrideWithValue(false),
        ],
        child: SchoolApp(tabs: adminTabs, pages: adminPages),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    await loginWith(tester, owner.email, owner.password);

    /// يمرّر أول قائمة على الشاشة إلى الأسفل ثم إلى الأعلى [rounds] مرات.
    Future<void> scrollList(int rounds) async {
      // أول قائمة رأسية على الشاشة (لا شريط أفقي كشرائح التصفية).
      final list = find
          .byWidgetPredicate((w) => w is Scrollable && w.axis == Axis.vertical)
          .first;
      for (var i = 0; i < rounds; i++) {
        await tester.fling(list, const Offset(0, -400), 2500);
        await tester.pumpAndSettle();
      }
      for (var i = 0; i < rounds; i++) {
        await tester.fling(list, const Offset(0, 400), 2500);
        await tester.pumpAndSettle();
      }
    }

    Future<void> openTab(String label) async {
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    await binding.watchPerformance(() async {
      await openTab('التلاميذ');
      await scrollList(6);
    }, reportKey: 'students_list');
    await binding.watchPerformance(() async {
      await openTab('المجموعات');
      await scrollList(4);
    }, reportKey: 'groups_list');
    await binding.watchPerformance(() async {
      await openTab('المدفوعات');
      await scrollList(6);
    }, reportKey: 'payments_list');
    await binding.watchPerformance(() async {
      await openTab('الرئيسية');
      await tester.pumpAndSettle();
      await scrollList(2);
    }, reportKey: 'dashboard');

    binding.reportData = <String, dynamic>{
      ...?binding.reportData,
      'data': <String, Object?>{
        'students': summary.students,
        'groups': summary.groups,
        'sessions': summary.sessions,
        'attendance': summary.attendance,
        'payments': summary.payments,
        'sms_messages': summary.smsMessages,
        'generation_millis': generationMillis,
      },
    };
  });
}
