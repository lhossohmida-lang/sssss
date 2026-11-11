import 'package:school_ui/school_ui.dart';

/// تبويبات تطبيق الأستاذ.
final List<AppTab> teacherTabs = [
  AppTab(
    path: '/home',
    destination: const ClayDestination(label: 'الرئيسية', icon: ClayIcons.home),
    builder: (_) => const TabPlaceholder(title: 'الرئيسية'),
  ),
  AppTab(
    path: '/groups',
    destination: const ClayDestination(
      label: 'مجموعاتي',
      icon: ClayIcons.groups,
    ),
    builder: (_) => const TabPlaceholder(title: 'مجموعاتي'),
  ),
  AppTab(
    path: '/requests',
    destination: const ClayDestination(
      label: 'طلباتي',
      icon: ClayIcons.schedule,
    ),
    builder: (_) => const TabPlaceholder(title: 'طلباتي'),
  ),
  AppTab(
    path: '/payout',
    destination: const ClayDestination(
      label: 'خلاصي',
      icon: ClayIcons.payments,
    ),
    builder: (_) => const TabPlaceholder(title: 'خلاصي'),
  ),
  AppTab(
    path: '/account',
    destination: const ClayDestination(
      label: 'حسابي',
      icon: ClayIcons.teachers,
    ),
    builder: (_) => const TabPlaceholder(title: 'حسابي'),
  ),
];
