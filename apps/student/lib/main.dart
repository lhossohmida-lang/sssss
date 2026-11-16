import 'package:flutter/widgets.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

import 'student_tabs.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    SchoolBootstrap(
      app: AppIdentity.student,
      tabs: studentTabs,
      pages: studentPages,
    ),
  );
}
