import 'package:drift/drift.dart';

import 'people_tables.dart';
import 'sync_columns.dart';
import 'teaching_tables.dart';

/// طابور الرسائل القصيرة. أي جهاز يضيف، وهاتف المدير يرسل.
@DataClassName('SmsQueueRow')
@TableIndex(name: 'idx_sms_queue_status', columns: {#status, #createdAt})
@TableIndex(name: 'idx_sms_queue_sent', columns: {#sentAt})
@TableIndex(name: 'idx_sms_queue_updated', columns: {#updatedAt})
class SmsQueue extends Table with SyncColumns {
  TextColumn get phone => text()();

  TextColumn get message => text()();

  /// `pending` / `sending` / `sent` / `failed`.
  TextColumn get status => text().withDefault(const Constant('pending'))();

  /// مفتاح القالب الذي نشأت منه الرسالة (للسجل والإحصاء).
  TextColumn get kind => text().withDefault(const Constant('custom'))();

  IntColumn get attempts => integer().withDefault(const Constant(0))();

  TextColumn get lastError => text().nullable()();

  /// لا تُرسل قبل هذا الوقت (ساعات الهدوء أو التأجيل).
  IntColumn get notBefore => integer().nullable()();

  IntColumn get sentAt => integer().nullable()();

  /// حساب من وضع الرسالة في الطابور (يحق له متابعتها).
  TextColumn get createdBy => text().nullable()();
}

/// قوالب الرسائل القابلة للتعديل.
@DataClassName('SmsTemplateRow')
@TableIndex(name: 'idx_sms_templates_updated', columns: {#updatedAt})
class SmsTemplates extends Table {
  TextColumn get key => text()();

  TextColumn get body => text()();

  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {key};
}

/// غرف المحادثة.
@DataClassName('ChatRoomRow')
@TableIndex(name: 'idx_chat_rooms_group', columns: {#groupId})
@TableIndex(name: 'idx_chat_rooms_last', columns: {#lastMessageAt})
@TableIndex(name: 'idx_chat_rooms_updated', columns: {#updatedAt})
class ChatRooms extends Table with SyncColumns {
  /// `private` / `group`.
  TextColumn get type => text()();

  TextColumn get groupId => text().nullable().references(Groups, #id)();

  TextColumn get title => text().withDefault(const Constant(''))();

  TextColumn get createdBy => text()();

  BoolColumn get isClosed => boolean().withDefault(const Constant(false))();

  IntColumn get lastMessageAt => integer().nullable()();
}

/// أعضاء غرف المحادثة.
@DataClassName('ChatMemberRow')
@TableIndex(
  name: 'idx_chat_members_pair',
  columns: {#roomId, #userId},
  unique: true,
)
@TableIndex(name: 'idx_chat_members_user', columns: {#userId})
@TableIndex(name: 'idx_chat_members_updated', columns: {#updatedAt})
class ChatMembers extends Table with SyncColumns {
  TextColumn get roomId => text().references(ChatRooms, #id)();

  TextColumn get userId => text()();

  /// `owner` / `worker` / `teacher` / `parent`.
  TextColumn get userRole => text()();

  IntColumn get lastReadAt => integer().withDefault(const Constant(0))();

  BoolColumn get muted => boolean().withDefault(const Constant(false))();
}

/// رسائل المحادثة، مخزّنة محلياً لتُفتح فوراً ودون إنترنت.
@DataClassName('ChatMessageRow')
@TableIndex(name: 'idx_chat_messages_room', columns: {#roomId, #createdAt})
@TableIndex(name: 'idx_chat_messages_updated', columns: {#updatedAt})
class ChatMessages extends Table with SyncColumns {
  TextColumn get roomId => text().references(ChatRooms, #id)();

  TextColumn get senderId => text()();

  TextColumn get senderRole => text()();

  TextColumn get content => text().withDefault(const Constant(''))();

  TextColumn get attachmentUrl => text().nullable()();

  TextColumn get attachmentName => text().nullable()();

  /// `image` / `file`.
  TextColumn get attachmentType => text().nullable()();

  /// مسار المرفق على الجهاز قبل اكتمال الرفع.
  TextColumn get attachmentLocalPath => text().nullable()();
}

/// النتائج والملاحظات.
@DataClassName('GradeRow')
@TableIndex(name: 'idx_grades_student', columns: {#studentId, #date})
@TableIndex(name: 'idx_grades_group', columns: {#groupId, #date})
@TableIndex(name: 'idx_grades_updated', columns: {#updatedAt})
class Grades extends Table with SyncColumns {
  TextColumn get studentId => text().references(Students, #id)();

  TextColumn get groupId => text().references(Groups, #id)();

  TextColumn get title => text()();

  RealColumn get score => real()();

  RealColumn get maxScore => real().withDefault(const Constant(20))();

  TextColumn get note => text().withDefault(const Constant(''))();

  TextColumn get date => text()();
}

/// ملفات المجموعة (PDF وتمارين).
@DataClassName('GroupFileRow')
@TableIndex(name: 'idx_group_files_group', columns: {#groupId, #createdAt})
@TableIndex(name: 'idx_group_files_updated', columns: {#updatedAt})
class GroupFiles extends Table with SyncColumns {
  TextColumn get groupId => text().references(Groups, #id)();

  TextColumn get title => text()();

  TextColumn get fileUrl => text().nullable()();

  TextColumn get fileName => text()();

  IntColumn get sizeBytes => integer().withDefault(const Constant(0))();

  TextColumn get localPath => text().nullable()();

  TextColumn get uploadedBy => text()();
}

/// الإشعارات داخل التطبيق.
@DataClassName('NotificationRow')
@TableIndex(name: 'idx_notifications_user', columns: {#userId, #createdAt})
@TableIndex(name: 'idx_notifications_unread', columns: {#userId, #readAt})
@TableIndex(name: 'idx_notifications_updated', columns: {#updatedAt})
class Notifications extends Table with SyncColumns {
  /// المستلم.
  TextColumn get userId => text()();

  /// حساب من أرسل الإشعار.
  TextColumn get senderId => text().nullable()();

  TextColumn get title => text()();

  TextColumn get body => text()();

  /// نوع الإشعار، مثل `request_pending` أو `waiting_threshold`.
  TextColumn get kind => text()();

  /// الكيان المرتبط للانتقال إليه عند الضغط.
  TextColumn get entity => text().nullable()();

  TextColumn get entityId => text().nullable()();

  IntColumn get readAt => integer().nullable()();
}

/// حسابات الدخول وربطها بأصحابها.
@DataClassName('UserAccountRow')
@TableIndex(name: 'idx_user_accounts_email', columns: {#email}, unique: true)
@TableIndex(name: 'idx_user_accounts_entity', columns: {#role, #entityId})
@TableIndex(name: 'idx_user_accounts_updated', columns: {#updatedAt})
class UserAccounts extends Table with SyncColumns {
  TextColumn get email => text()();

  /// `owner` / `worker` / `teacher` / `parent`.
  TextColumn get role => text()();

  /// معرّف السجل في جدول الدور (عامل، أستاذ، وليّ)؛ فارغ لصاحب المدرسة.
  TextColumn get entityId => text().nullable()();

  TextColumn get displayName => text().withDefault(const Constant(''))();

  BoolColumn get mustChangePassword =>
      boolean().withDefault(const Constant(true))();
}
