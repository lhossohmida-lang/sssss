import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

import 'screens/catalog_screens.dart';
import 'screens/more_page.dart';
import 'screens/registration_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/students_screen.dart';
import 'screens/teachers_screens.dart';

/// تبويبات تطبيق الإدارة. العامل لا يرى إلا ما فعّله له المدير؛ وبقية
/// الأقسام (الأساتذة، القاعات، المصاريف...) تحت «المزيد» (المهمة 2.26).
final List<AppTab> adminTabs = [
  AppTab(
    path: '/dashboard',
    destination: const ClayDestination(label: 'الرئيسية', icon: ClayIcons.home),
    builder: (_) => const TabPlaceholder(title: 'لوحة التحكم'),
  ),
  AppTab(
    path: '/students',
    destination: const ClayDestination(
      label: 'التلاميذ',
      icon: ClayIcons.students,
    ),
    requires: PermissionModule.students,
    builder: (_) => const StudentsScreen(),
  ),
  AppTab(
    path: '/groups',
    destination: const ClayDestination(
      label: 'المجموعات',
      icon: ClayIcons.groups,
    ),
    requires: PermissionModule.groups,
    builder: (_) => const TabPlaceholder(title: 'المجموعات'),
  ),
  AppTab(
    path: '/payments',
    destination: const ClayDestination(
      label: 'المدفوعات',
      icon: ClayIcons.payments,
    ),
    requires: PermissionModule.payments,
    builder: (_) => const TabPlaceholder(title: 'المدفوعات'),
  ),
  AppTab(
    path: '/more',
    destination: const ClayDestination(label: 'المزيد', icon: ClayIcons.more),
    builder: (_) => const MorePage(),
  ),
];

/// صفحات بملء الشاشة خارج التبويبات؛ كل مهمة لاحقة تضيف صفحتها هنا.
final List<AppPage> adminPages = [
  AppPage(
    path: '/students/new',
    requires: PermissionModule.students,
    action: PermissionAction.add,
    builder: (context, state) => const RegistrationScreen(),
  ),
  AppPage(
    path: '/teachers',
    requires: PermissionModule.teachers,
    builder: (context, state) => const TeachersScreen(),
  ),
  AppPage(
    path: '/teachers/:id',
    requires: PermissionModule.teachers,
    builder: (context, state) =>
        TeacherProfileScreen(teacherId: state.pathParameters['id']!),
  ),
  AppPage(
    path: '/subjects',
    requires: PermissionModule.subjects,
    builder: (context, state) => const SubjectsScreen(),
  ),
  AppPage(
    path: '/rooms',
    requires: PermissionModule.rooms,
    builder: (context, state) => const RoomsScreen(),
  ),
  AppPage(
    path: '/settings',
    requires: PermissionModule.settings,
    builder: (context, state) => const SettingsScreen(),
  ),
];
