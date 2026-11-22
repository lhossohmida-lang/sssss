import 'package:admin/main.dart' as app;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/device_smoke.dart';

/// اختبار دخان على محاكي iPhone (مسار `ios`): التطبيق الحقيقي بإضافاته الأصلية
/// يصل شاشته الأولى بلا انهيار. يعوّض غياب جهاز iPhone حقيقي.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('يبدأ التطبيق على شاشته الأولى', (tester) async {
    await expectAppReachesFirstScreen(
      tester,
      app: AppIdentity.admin,
      main: app.main,
    );
  });
}
