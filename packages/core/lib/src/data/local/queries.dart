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
}
