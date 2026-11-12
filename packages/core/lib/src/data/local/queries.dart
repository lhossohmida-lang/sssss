import 'package:drift/drift.dart';

import 'app_database.dart';

/// استعلامات القراءة المشتركة بين التطبيقات (الشاشات تقرأ منها محلياً ولا
/// تنتظر الشبكة). الكتابة لا تمر من هنا بل عبر `SyncWriter`.
extension AppQueries on AppDatabase {
  /// قيمة إعداد من جدول `settings`، وتتحدث مع كل تغيير؛ فارغة إن لم تُحدَّد.
  Stream<String> watchSetting(String key) {
    final query = select(settings)..where((t) => t.key.equals(key));
    return query.watchSingleOrNull().map((row) => row?.value.trim() ?? '');
  }

  /// عدد الإشعارات غير المقروءة للحساب [accountId].
  Stream<int> watchUnreadNotificationCount(String accountId) {
    return customSelect(
      'SELECT COUNT(*) AS n FROM notifications '
      'WHERE user_id = ? AND read_at IS NULL AND deleted_at IS NULL',
      variables: [Variable<String>(accountId)],
      readsFrom: {notifications},
    ).watchSingle().map((row) => row.read<int>('n'));
  }

  /// إشعارات الحساب [accountId]، الأحدث أولاً، بحد أقصى [limit].
  Stream<List<NotificationRow>> watchNotifications(
    String accountId, {
    int limit = 200,
  }) {
    return customSelect(
      'SELECT * FROM notifications '
      'WHERE user_id = ? AND deleted_at IS NULL '
      'ORDER BY created_at DESC LIMIT ?',
      variables: [Variable<String>(accountId), Variable<int>(limit)],
      readsFrom: {notifications},
    ).watch().map(
      (rows) => [for (final row in rows) notifications.map(row.data)],
    );
  }

  /// خطوط النقل الحية مرتبة بالاسم.
  Stream<List<TransportLineRow>> watchTransportLines() {
    final query = select(transportLines)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.asc(t.name)]);
    return query.watch();
  }

  /// الأساتذة الأحياء مرتبون بالاسم (للمرشِّحات والقوائم الخفيفة).
  Stream<List<TeacherRow>> watchTeachers() {
    final query = select(teachers)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.asc(t.name)]);
    return query.watch();
  }

  /// صف أستاذ حي بمعرّفه، ولحظياً (`null` إن لم يوجد أو حُذف).
  Stream<TeacherRow?> watchTeacher(String id) {
    final query = select(teachers)
      ..where((t) => t.id.equals(id) & t.deletedAt.isNull());
    return query.watchSingleOrNull();
  }

  /// أبناء الوليّ [parentId] الأحياء مرتبين بالاسم، ولحظياً.
  Stream<List<StudentRow>> watchChildren(String parentId) {
    final query = select(students)
      ..where((s) => s.parentAccountId.equals(parentId) & s.deletedAt.isNull())
      ..orderBy([
        (s) => OrderingTerm.asc(s.firstName),
        (s) => OrderingTerm.asc(s.lastName),
        (s) => OrderingTerm.asc(s.id),
      ]);
    return query.watch();
  }
}
