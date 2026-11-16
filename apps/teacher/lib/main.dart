import 'package:flutter/widgets.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

import 'teacher_tabs.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    SchoolBootstrap(
      app: AppIdentity.teacher,
      tabs: teacherTabs,
      pages: teacherPages,
      // مسح رمز ربط المدرسة بكاميرا الهاتف (Android).
      cameraFactory: cameraScanningSupported ? MobileScannerSource.new : null,
    ),
  );
}
