import 'package:flutter/widgets.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

import 'admin_tabs.dart';
import 'mobile_scanner_source.dart';
import 'screens/drive_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    SchoolBootstrap(
      app: AppIdentity.admin,
      tabs: adminTabs,
      pages: adminPages,
      // مسح الكاميرا على Android؛ على Windows قارئ USB وشاشة المدخل (2.16).
      cameraFactory: cameraScanningSupported ? MobileScannerSource.new : null,
      wrapApp: (app) => DriveBackupLifecycle(child: app),
    ),
  );
}
