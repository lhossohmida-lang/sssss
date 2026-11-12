import 'package:school_ui/school_ui.dart';

import 'screens/account_screen.dart';
import 'screens/files_screens.dart';
import 'screens/grades_screens.dart';
import 'screens/home_screens.dart';
import 'screens/payout_screens.dart';
import 'screens/requests_screens.dart';

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
    builder: (_) => const TeacherRequestsScreen(),
  ),
  AppTab(
    path: '/payout',
    destination: const ClayDestination(
      label: 'خلاصي',
      icon: ClayIcons.payments,
    ),
    builder: (_) => const TeacherPayoutScreen(),
  ),
  AppTab(
    path: '/account',
    destination: const ClayDestination(
      label: 'حسابي',
      icon: ClayIcons.teachers,
    ),
    builder: (_) => const TeacherAccountScreen(),
  ),
];

/// صفحات بملء الشاشة خارج التبويبات؛ كل مهمة لاحقة تضيف صفحتها هنا.
final List<AppPage> teacherPages = [
  AppPage(
    path: '/groups/:id/files',
    builder: (context, state) =>
        GroupFilesScreen(groupId: state.pathParameters['id']!),
  ),
  AppPage(
    path: '/groups/:id/files/new',
    builder: (context, state) =>
        AddGroupFileScreen(groupId: state.pathParameters['id']!),
  ),
  AppPage(
    path: '/groups/:id/grades',
    builder: (context, state) =>
        GradesScreen(groupId: state.pathParameters['id']!),
  ),
  AppPage(
    path: '/groups/:id/grades/edit',
    builder: (context, state) => AssessmentFormScreen(
      groupId: state.pathParameters['id']!,
      title: state.uri.queryParameters['title'],
      date: state.uri.queryParameters['date'],
      maxScore: state.uri.queryParameters['max'],
    ),
  ),
  AppPage(
    path: '/payouts/:id',
    builder: (context, state) =>
        TeacherPayoutDetailsScreen(payoutId: state.pathParameters['id']!),
  ),
  AppPage(
    path: '/requests/new',
    builder: (context, state) => const NewRequestScreen(),
  ),
  AppPage(path: '/my-qr', builder: (context, state) => const MyQrScreen()),
  AppPage(
    path: '/my-attendance',
    builder: (context, state) => const MyAttendanceScreen(),
  ),
  AppPage(
    path: '/attendance/:id',
    builder: (context, state) =>
        TeacherSessionRoster(sessionId: state.pathParameters['id']!),
  ),
  AppPage(
    path: '/groups/:id',
    builder: (context, state) =>
        TeacherGroupDetailsScreen(groupId: state.pathParameters['id']!),
  ),
];
