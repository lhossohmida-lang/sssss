import 'package:flutter/widgets.dart';
import 'package:school_core/school_core.dart';

import '../clay/clay_navigation.dart';

/// تبويب في هيكل التنقل: وجهته وصفحته والصلاحية التي يشترطها.
class AppTab {
  const AppTab({
    required this.path,
    required this.destination,
    required this.builder,
    this.requires,
    this.roles,
  });

  /// مسار التبويب، مثل `/students`.
  final String path;
  final ClayDestination destination;
  final WidgetBuilder builder;

  /// الوحدة التي يجب أن يملك المستخدم فعلاً فيها على الأقل؛ دونها يظهر
  /// التبويب لكل من يدخل التطبيق.
  final PermissionModule? requires;

  /// الأدوار المسموح لها؛ `null` لكل الأدوار التي تدخل التطبيق.
  final Set<UserRole>? roles;

  /// هل يظهر التبويب لهذا المستخدم؟
  bool visibleTo(AccessPolicy policy) {
    final allowed = roles;
    if (allowed != null && !allowed.contains(policy.role)) return false;
    final module = requires;
    return module == null || policy.canAnyOf(module);
  }
}
