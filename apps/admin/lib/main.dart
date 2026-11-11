import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

import 'admin_tabs.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final runtime = await AppRuntime.start(app: AppIdentity.admin);
  runApp(
    ProviderScope(
      overrides: [runtimeProvider.overrideWithValue(runtime)],
      child: SchoolApp(tabs: adminTabs, pages: adminPages),
    ),
  );
}
