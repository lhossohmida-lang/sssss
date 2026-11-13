import '../../domain/enums.dart';

/// كيف يُزامَن جدول محلي.
class SyncTable {
  const SyncTable(this.local, {String? remote, this.push = true})
    : remote = remote ?? local;

  /// اسم الجدول المحلي.
  final String local;

  /// اسم الجدول أو العرض على الخادم الذي يُسحب منه.
  final String remote;

  /// هل يدفع هذا الدور تغييراته على هذا الجدول؟
  final bool push;
}

/// ترتيب الجداول في السحب (الآباء قبل الأبناء) وما يخص كل دور.
abstract final class SyncProfile {
  static const List<String> _order = [
    'settings',
    'levels',
    'subjects',
    'rooms',
    'transport_lines',
    'user_accounts',
    'parents',
    'teachers',
    'workers',
    'students',
    'teacher_subjects',
    'groups',
    'group_slots',
    'group_students',
    'waiting_lists',
    'waiting_entries',
    'sessions',
    'attendance',
    'teacher_attendance',
    'worker_attendance',
    'session_requests',
    'payments',
    'student_credits',
    'registration_fees',
    'teacher_payouts',
    'expense_categories',
    'expenses',
    'sms_templates',
    'sms_queue',
    'chat_rooms',
    'chat_members',
    'chat_messages',
    'grades',
    'group_files',
    'notifications',
    'audit_log',
  ];

  /// الجداول التي يُضاف إليها فقط ولا تُعدَّل على الخادم.
  static const Set<String> insertOnly = {'audit_log'};

  /// أسماء كل الجداول المزامَنة بترتيب السحب.
  static List<String> get tableNames => List.unmodifiable(_order);

  /// جداول المزامنة لدور المستخدم.
  ///
  /// الأستاذ والوليّ يسحبان حسابات المراسلة من العرض المحدود
  /// `chat_user_accounts`. الوليّ أيضاً يسحب الأستاذ والمجموعة من بطاقتين
  /// تحجبان البيانات المالية والتعريفية الحساسة.
  static List<SyncTable> forRole(UserRole role) {
    if (role != UserRole.parent && role != UserRole.teacher) {
      return [for (final name in _order) SyncTable(name)];
    }
    return [
      for (final name in _order)
        switch (name) {
          'user_accounts'
              when role == UserRole.teacher || role == UserRole.parent =>
            const SyncTable('user_accounts', remote: 'chat_user_accounts'),
          'teachers' when role == UserRole.parent => const SyncTable(
            'teachers',
            remote: 'teacher_cards',
            push: false,
          ),
          'groups' when role == UserRole.parent => const SyncTable(
            'groups',
            remote: 'group_cards',
            push: false,
          ),
          _ => SyncTable(name),
        },
    ];
  }
}
