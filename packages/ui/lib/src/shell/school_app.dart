import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:school_core/school_core.dart';

import '../clay/clay_button.dart';
import '../clay/clay_display.dart';
import '../clay/clay_icons.dart';
import '../clay/clay_navigation.dart';
import '../theme/clay_theme.dart';
import '../theme/clay_tokens.dart';
import 'app_page.dart';
import 'app_tab.dart';
import 'auth_screens.dart';
import 'notifications_screen.dart';
import 'providers.dart';

/// ينبّه الموجِّه عند تغيّر الجلسة ليعيد حساب إعادة التوجيه.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(AuthService auth) {
    _subscription = auth.changes.listen((_) => notifyListeners());
  }

  late final StreamSubscription<AuthSession?> _subscription;

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}

/// مسارات التطبيق الثابتة.
abstract final class AppRoutes {
  static const String splash = '/splash';
  static const String login = '/login';
  static const String changePassword = '/change-password';
  static const String notifications = '/notifications';
}

/// يبني موجِّه تطبيق من [tabs] لكل دور يدخله.
///
/// التبويبات كلها تُسجَّل مساراتٍ، ويُخفى ما لا يملك المستخدم صلاحيته من
/// التنقل ويُمنع الوصول إليه برابط مباشر.
GoRouter buildAppRouter({
  required AppRuntime runtime,
  required List<AppTab> tabs,
  required Listenable refresh,
  List<AppPage> pages = const [],
}) {
  final auth = runtime.auth;
  assert(tabs.isNotEmpty, 'تطبيق بلا تبويبات');
  assert(tabs.length <= 5, 'الشريط السفلي يتسع لخمسة تبويبات');

  AppTab? tabAt(String location) {
    for (final tab in tabs) {
      if (location == tab.path || location.startsWith('${tab.path}/')) {
        return tab;
      }
    }
    return null;
  }

  String firstTabFor(AuthSession session) {
    final tab = tabs.firstWhere(
      (t) => t.visibleTo(session.policy),
      orElse: () => tabs.first,
    );
    return tab.path;
  }

  String? redirect(BuildContext context, GoRouterState state) {
    final location = state.matchedLocation;
    if (location == AppRoutes.splash) return null;
    final session = auth.current;
    if (session == null) {
      return location == AppRoutes.login ? null : AppRoutes.login;
    }
    if (session.mustChangePassword) {
      return location == AppRoutes.changePassword
          ? null
          : AppRoutes.changePassword;
    }
    if (location == AppRoutes.login ||
        location == AppRoutes.changePassword ||
        location == '/') {
      return firstTabFor(session);
    }
    final tab = tabAt(location);
    if (tab != null && !tab.visibleTo(session.policy)) {
      return firstTabFor(session);
    }
    for (final page in pages) {
      if (page.matches(location) && !page.visibleTo(session.policy)) {
        return firstTabFor(session);
      }
    }
    return null;
  }

  return GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: refresh,
    redirect: redirect,
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) =>
            SplashScreen(app: runtime.app, onFinished: () => context.go('/')),
      ),
      GoRoute(path: '/', redirect: (_, _) => AppRoutes.login),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => LoginScreen(app: runtime.app),
      ),
      GoRoute(
        path: AppRoutes.changePassword,
        builder: (context, state) => ChangePasswordScreen(app: runtime.app),
      ),
      GoRoute(
        path: AppRoutes.notifications,
        builder: (context, state) => const NotificationsScreen(),
      ),
      for (final page in pages) GoRoute(path: page.path, builder: page.builder),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => ShellPage(tabs: tabs, shell: shell),
        branches: [
          for (final tab in tabs)
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: tab.path,
                  builder: (context, state) => tab.builder(context),
                ),
              ],
            ),
        ],
      ),
    ],
  );
}

/// هيكل التنقل بعد الدخول: شريط سفلي أو قائمة جانبية، وجرس الإشعارات.
class ShellPage extends ConsumerWidget {
  const ShellPage({required this.tabs, required this.shell, super.key});

  final List<AppTab> tabs;
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider.select((s) => s.value));
    if (session == null) return const SizedBox.shrink();

    final visible = [
      for (var i = 0; i < tabs.length; i++)
        if (tabs[i].visibleTo(session.policy)) i,
    ];
    final current = visible.indexOf(shell.currentIndex);
    final tab = tabs[shell.currentIndex];
    final school = ref.watch(schoolNameProvider).value ?? '';
    final unread = ref.watch(unreadCountProvider).value ?? 0;
    final hasChat =
        session.role == UserRole.teacher || session.role == UserRole.parent;
    final chatUnread = hasChat
        ? ref.watch(chatUnreadCountProvider).value ?? 0
        : 0;
    final p = context.palette;
    final text = Theme.of(context).textTheme;

    return ClayAdaptiveScaffold(
      destinations: [for (final i in visible) tabs[i].destination],
      currentIndex: current < 0 ? 0 : current,
      onSelected: (index) => shell.goBranch(
        visible[index],
        initialLocation: visible[index] == shell.currentIndex,
      ),
      appBar: ClayAppBar(
        title: tab.destination.label,
        actions: [
          if (hasChat)
            IconButton(
              tooltip: chatUnread > 0
                  ? 'المحادثات ($chatUnread غير مقروءة)'
                  : 'المحادثات',
              icon: Badge(
                isLabelVisible: chatUnread > 0,
                label: Text(chatUnread > 99 ? '99+' : '$chatUnread'),
                child: Icon(ClayIcons.chat, color: p.text),
              ),
              onPressed: () => context.push('/chat'),
            ),
          IconButton(
            tooltip: unread > 0
                ? 'الإشعارات ($unread غير مقروءة)'
                : 'الإشعارات',
            icon: Badge(
              isLabelVisible: unread > 0,
              label: Text(unread > 99 ? '99+' : '$unread'),
              child: Icon(ClayIcons.notifications, color: p.text),
            ),
            onPressed: () => context.push(AppRoutes.notifications),
          ),
        ],
      ),
      sidebarHeader: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            school.isEmpty ? session.role.label : school,
            style: text.titleLarge,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      sidebarFooter: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            session.displayName,
            style: text.titleSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(session.role.label, style: text.bodySmall),
          const SizedBox(height: ClaySpacing.sm),
          ClayButton(
            label: 'خروج',
            icon: ClayIcons.logout,
            kind: ClayButtonKind.secondary,
            onPressed: () => ref.read(runtimeProvider).auth.signOut(),
          ),
        ],
      ),
      body: shell,
    );
  }
}

/// صفحة تبويب لم تُبنَ شاشتها بعد: تُستبدل في مراحل الخطة اللاحقة.
class TabPlaceholder extends StatelessWidget {
  const TabPlaceholder({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) => ClayEmptyView(
    title: title,
    message: 'تُبنى هذه الشاشة في مرحلة لاحقة من الخطة',
    icon: Icons.construction_rounded,
  );
}

/// جذر أي من التطبيقات الثلاثة.
///
/// يُركَّب داخل `ProviderScope` يمرِّر [runtimeProvider]. وللمستخدم الخروج
/// من أي شاشة: خروجه يعيده إلى الدخول عبر إعادة توجيه الموجِّه.
class SchoolApp extends ConsumerStatefulWidget {
  const SchoolApp({required this.tabs, this.pages = const [], super.key});

  final List<AppTab> tabs;

  /// صفحات بملء الشاشة خارج التبويبات.
  final List<AppPage> pages;

  @override
  ConsumerState<SchoolApp> createState() => _SchoolAppState();
}

class _SchoolAppState extends ConsumerState<SchoolApp> {
  late final AppRuntime _runtime = ref.read(runtimeProvider);
  late final _AuthRefresh _refresh = _AuthRefresh(_runtime.auth);
  late final GoRouter _router = buildAppRouter(
    runtime: _runtime,
    tabs: widget.tabs,
    refresh: _refresh,
    pages: widget.pages,
  );

  @override
  void dispose() {
    _router.dispose();
    _refresh.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // مهام الخلفية (التغييب التلقائي) تعيش ما دام التطبيق مفتوحاً.
    ref.watch(sessionCloserProvider);
    return ClayApp(app: _runtime.app, routerConfig: _router);
  }
}
