import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

import 'screens/attendance_screens.dart';
import 'screens/catalog_screens.dart';
import 'screens/dues_screen.dart';
import 'screens/entrance_screen.dart';
import 'screens/fees_screen.dart';
import 'screens/group_details_screen.dart';
import 'screens/groups_screens.dart';
import 'screens/more_page.dart';
import 'screens/payments_screens.dart';
import 'screens/payouts_screens.dart';
import 'screens/registration_screen.dart';
import 'screens/scanner_screen.dart';
import 'screens/schedule_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/student_profile_screen.dart';
import 'screens/students_screen.dart';
import 'screens/teachers_screens.dart';
import 'screens/waiting_screens.dart';

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
    builder: (_) => const GroupsScreen(),
  ),
  AppTab(
    path: '/payments',
    destination: const ClayDestination(
      label: 'المدفوعات',
      icon: ClayIcons.payments,
    ),
    requires: PermissionModule.payments,
    builder: (_) => const PaymentsScreen(),
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
    path: '/payouts',
    requires: PermissionModule.payouts,
    builder: (context, state) => const PayoutsScreen(),
  ),
  AppPage(
    path: '/payouts/:id',
    requires: PermissionModule.payouts,
    builder: (context, state) =>
        PayoutDetailsScreen(payoutId: state.pathParameters['id']!),
  ),
  AppPage(
    path: '/fees',
    requires: PermissionModule.payments,
    builder: (context, state) => const FeesScreen(),
  ),
  AppPage(
    path: '/dues',
    requires: PermissionModule.payments,
    builder: (context, state) => const DuesScreen(),
  ),
  AppPage(
    path: '/payments/new',
    requires: PermissionModule.receiveMoney,
    action: PermissionAction.use,
    builder: (context, state) =>
        PaymentFormScreen(studentId: state.uri.queryParameters['student']),
  ),
  // بعد `/payments/new` حتى لا يُقرأ «new» معرّفاً لدفعة.
  AppPage(
    path: '/payments/:id',
    requires: PermissionModule.payments,
    builder: (context, state) =>
        PaymentDetailsScreen(paymentId: state.pathParameters['id']!),
  ),
  AppPage(
    path: '/entrance',
    requires: PermissionModule.scanner,
    action: PermissionAction.use,
    builder: (context, state) => const EntranceScreen(),
  ),
  AppPage(
    path: '/scanner',
    requires: PermissionModule.scanner,
    action: PermissionAction.use,
    builder: (context, state) => const ScannerScreen(),
  ),
  AppPage(
    path: '/waiting',
    requires: PermissionModule.waiting,
    builder: (context, state) => const WaitingListsScreen(),
  ),
  AppPage(
    path: '/waiting/:id',
    requires: PermissionModule.waiting,
    builder: (context, state) =>
        WaitingDetailsScreen(listId: state.pathParameters['id']!),
  ),
  AppPage(
    path: '/schedule',
    requires: PermissionModule.groups,
    builder: (context, state) => const ScheduleScreen(),
  ),
  AppPage(
    path: '/attendance',
    requires: PermissionModule.attendance,
    builder: (context, state) => const AttendanceScreen(),
  ),
  AppPage(
    path: '/attendance/:id',
    requires: PermissionModule.attendance,
    builder: (context, state) =>
        SessionRosterScreen(sessionId: state.pathParameters['id']!),
  ),
  AppPage(
    path: '/groups/new',
    requires: PermissionModule.groups,
    action: PermissionAction.add,
    builder: (context, state) => GroupFormScreen(
      initialSubjectId: state.uri.queryParameters['subject'],
      initialTeacherId: state.uri.queryParameters['teacher'],
    ),
  ),
  AppPage(
    path: '/groups/:id/edit',
    requires: PermissionModule.groups,
    action: PermissionAction.edit,
    builder: (context, state) =>
        GroupFormScreen(groupId: state.pathParameters['id']),
  ),
  // بعد `/groups/new` حتى لا يُقرأ «new» معرّفاً لمجموعة.
  AppPage(
    path: '/groups/:id',
    requires: PermissionModule.groups,
    builder: (context, state) =>
        GroupDetailsScreen(groupId: state.pathParameters['id']!),
  ),
  AppPage(
    path: '/students/new',
    requires: PermissionModule.students,
    action: PermissionAction.add,
    builder: (context, state) => const RegistrationScreen(),
  ),
  // بعد `/students/new` حتى لا يُقرأ «new» معرّفاً لتلميذ.
  AppPage(
    path: '/students/:id',
    requires: PermissionModule.students,
    builder: (context, state) =>
        StudentProfileScreen(studentId: state.pathParameters['id']!),
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
