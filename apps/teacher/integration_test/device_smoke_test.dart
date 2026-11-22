import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/device_smoke.dart';
import 'package:teacher/main.dart' as app;

/// اختبار دخان على محاكي iPhone (مسار `ios`): التطبيق الحقيقي بإضافاته الأصلية
/// يصل شاشته الأولى بلا انهيار. يعوّض غياب جهاز iPhone حقيقي.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('يبدأ التطبيق على شاشته الأولى', (tester) async {
    await expectAppReachesFirstScreen(
      tester,
      app: AppIdentity.teacher,
      main: app.main,
    );
  });
}
