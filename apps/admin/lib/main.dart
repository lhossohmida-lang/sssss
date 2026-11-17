import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

import 'admin_tabs.dart';
import 'screens/drive_screen.dart';
import 'screens/sms_auto_sender.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    SchoolBootstrap(
      app: AppIdentity.admin,
      tabs: adminTabs,
      pages: adminPages,
      // مسح الكاميرا على Android؛ على Windows قارئ USB وشاشة المدخل (2.16).
      cameraFactory: cameraScanningSupported ? MobileScannerSource.new : null,
      // النسخ الاحتياطي لـDrive، وإرسال الرسائل القصيرة تلقائياً من هاتف Android.
      wrapApp: (app) =>
          DriveBackupLifecycle(child: SmsAutoSenderLifecycle(child: app)),
      // «إعادة تعيين بيانات الجهاز» تمسح أيضاً رموز Drive المحفوظة في التخزين الآمن.
      wipeData: (app) async {
        try {
          await const FlutterSecureStorage().deleteAll();
        } on Object {
          // لا يمنع مسح بقية البيانات.
        }
        await SchoolBootstrap.defaultWipe(app);
      },
    ),
  );
}
