import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:school_core/school_core.dart';

/// صفحة بملء الشاشة خارج التبويبات (الإعدادات، تفاصيل تلميذ...). يُمنع
/// الوصول إليها، حتى برابط مباشر، إن لم يملك المستخدم صلاحية [requires].
class AppPage {
  const AppPage({required this.path, required this.builder, this.requires});

  /// مسار الصفحة، ويقبل معاملات مثل `/students/:id`.
  final String path;
  final Widget Function(BuildContext context, GoRouterState state) builder;

  /// الوحدة التي يشترط فيها فعلاً واحداً على الأقل؛ دونها لأي مستخدم.
  final PermissionModule? requires;

  /// هل تنطبق هذه الصفحة على [location]؟ (للتحقق من الصلاحية)
  bool matches(String location) {
    final pattern = path.split('/');
    final actual = location.split('?').first.split('/');
    if (pattern.length != actual.length) return false;
    for (var i = 0; i < pattern.length; i++) {
      if (!pattern[i].startsWith(':') && pattern[i] != actual[i]) return false;
    }
    return true;
  }

  bool visibleTo(AccessPolicy policy) {
    final module = requires;
    return module == null || policy.canAnyOf(module);
  }
}
