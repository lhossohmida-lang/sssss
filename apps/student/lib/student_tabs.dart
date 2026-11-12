import 'package:school_ui/school_ui.dart';

import 'screens/attendance_screen.dart';
import 'screens/home_screen.dart';
import 'screens/payments_screen.dart';
import 'screens/schedule_screen.dart';

/// تبويبات تطبيق الوليّ والتلميذ.
final List<AppTab> studentTabs = [
  AppTab(
    path: '/home',
    destination: const ClayDestination(label: 'الرئيسية', icon: ClayIcons.home),
    builder: (_) => const ParentHomeScreen(),
  ),
  AppTab(
    path: '/attendance',
    destination: const ClayDestination(
      label: 'الحضور',
      icon: ClayIcons.attendance,
    ),
    builder: (_) => const ParentAttendanceScreen(),
  ),
  AppTab(
    path: '/schedule',
    destination: const ClayDestination(
      label: 'الجدول',
      icon: ClayIcons.schedule,
    ),
    builder: (_) => const ParentScheduleScreen(),
  ),
  AppTab(
    path: '/payments',
    destination: const ClayDestination(
      label: 'المدفوعات',
      icon: ClayIcons.payments,
    ),
    builder: (_) => const ParentPaymentsScreen(),
  ),
  AppTab(
    path: '/account',
    destination: const ClayDestination(label: 'حسابي', icon: ClayIcons.parents),
    builder: (_) => const TabPlaceholder(title: 'حسابي'),
  ),
];
