import 'package:school_ui/school_ui.dart';

import 'screens/home_screens.dart';

/// تبويبات تطبيق الأستاذ.
final List<AppTab> teacherTabs = [
  AppTab(
    path: '/home',
    destination: const ClayDestination(label: 'الرئيسية', icon: ClayIcons.home),
    builder: (_) => const TeacherHomeScreen(),
  ),
  AppTab(
    path: '/groups',
    destination: const ClayDestination(
      label: 'مجموعاتي',
      icon: ClayIcons.groups,
    ),
    builder: (_) => const TeacherGroupsScreen(),
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

/// صفحات بملء الشاشة خارج التبويبات؛ كل مهمة لاحقة تضيف صفحتها هنا.
final List<AppPage> teacherPages = [
  AppPage(
    path: '/groups/:id',
    builder: (context, state) =>
        TeacherGroupDetailsScreen(groupId: state.pathParameters['id']!),
  ),
];
