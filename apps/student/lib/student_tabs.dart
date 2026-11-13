import 'package:school_ui/school_ui.dart';

import 'screens/account_screen.dart';
import 'screens/attendance_screen.dart';
import 'screens/home_screen.dart';
import 'screens/payments_screen.dart';
import 'screens/qr_screen.dart';
import 'screens/schedule_screen.dart';
import 'screens/subject_screen.dart';

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
    builder: (_) => const ParentAccountScreen(),
  ),
];

/// صفحات بملء الشاشة خارج التبويبات؛ كل مهمة لاحقة تضيف صفحتها هنا.
final List<AppPage> studentPages = [
  AppPage(path: '/chat', builder: (context, state) => const ChatInboxScreen()),
  AppPage(
    path: '/chat/new',
    builder: (context, state) => const ChatCreateScreen(),
  ),
  AppPage(
    path: '/chat/:roomId',
    builder: (context, state) =>
        ChatRoomScreen(roomId: state.pathParameters['roomId']!),
  ),
  AppPage(path: '/qr', builder: (context, state) => const ChildQrScreen()),
  AppPage(
    path: '/subjects/:groupId',
    builder: (context, state) =>
        SubjectScreen(groupId: state.pathParameters['groupId']!),
  ),
];
