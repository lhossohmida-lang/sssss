import 'package:drift/drift.dart';

/// سجل العمليات: من أضاف أو عدّل أو حذف أو استلم مالاً ومتى.
@DataClassName('AuditLogRow')
@TableIndex(name: 'idx_audit_log_created', columns: {#createdAt})
@TableIndex(name: 'idx_audit_log_entity', columns: {#entity, #entityId})
@TableIndex(name: 'idx_audit_log_user', columns: {#userId, #createdAt})
@TableIndex(name: 'idx_audit_log_updated', columns: {#updatedAt})
class AuditLog extends Table {
  TextColumn get id => text()();

  TextColumn get userId => text()();

  TextColumn get userName => text().withDefault(const Constant(''))();

  /// `create` / `update` / `delete` / `receive_money` ...
  TextColumn get action => text()();

  /// اسم الجدول المعني.
  TextColumn get entity => text()();

  TextColumn get entityId => text()();

  /// حالة السجل قبل العملية (JSON)، أو `null` عند الإضافة.
  TextColumn get before => text().nullable()();

  /// حالة السجل بعد العملية (JSON)، أو `null` عند الحذف.
  TextColumn get after => text().nullable()();

  IntColumn get createdAt => integer()();

  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// طابور العمليات المنتظرة للدفع إلى الخادم (لا يُزامَن هو نفسه).
@DataClassName('OutboxRow')
@TableIndex(name: 'idx_outbox_row', columns: {#targetTable, #rowId})
class Outbox extends Table {
  IntColumn get seq => integer().autoIncrement()();

  TextColumn get targetTable => text()();

  /// المفتاح الأساسي للسجل (أو مفتاح مركّب بصيغة JSON).
  TextColumn get rowId => text()();

  /// السجل كاملاً بصيغة JSON كما يُرسل إلى الخادم.
  TextColumn get payload => text()();

  IntColumn get createdAt => integer()();

  IntColumn get attempts => integer().withDefault(const Constant(0))();

  TextColumn get lastError => text().nullable()();

  /// لا يُعاد المحاولة قبل هذا الوقت.
  IntColumn get nextAttemptAt => integer().withDefault(const Constant(0))();
}

/// حالة السحب من الخادم لكل جدول.
@DataClassName('SyncStateRow')
class SyncState extends Table {
  TextColumn get targetTable => text()();

  /// أحدث `updated_at` سُحب من الخادم لهذا الجدول.
  IntColumn get lastPulledAt => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {targetTable};
}

/// طابور رفع الملفات (صور، مرفقات، Excel الحضور، النسخ الاحتياطية).
@DataClassName('UploadQueueRow')
@TableIndex(name: 'idx_upload_queue_status', columns: {#status, #createdAt})
@TableIndex(
  name: 'idx_upload_queue_dedupe',
  columns: {#dedupeKey},
  unique: true,
)
class UploadQueue extends Table {
  TextColumn get id => text()();

  /// `photo` / `attachment` / `group_file` / `attendance_excel` / `backup`.
  TextColumn get kind => text()();

  TextColumn get localPath => text()();

  /// الوجهة: مسار في تخزين الخادم أو في Google Drive.
  TextColumn get remotePath => text()();

  /// مفتاح يمنع رفع نفس الملف مرتين.
  TextColumn get dedupeKey => text()();

  /// المخزن الوجهة: `photos` / `files` على الخادم، أو `drive`.
  TextColumn get bucket => text().withDefault(const Constant('files'))();

  /// السجل الذي يُكتب فيه رابط الملف بعد اكتمال الرفع (اختياري).
  TextColumn get targetTable => text().nullable()();

  TextColumn get targetRowId => text().nullable()();

  TextColumn get targetColumn => text().nullable()();

  /// لا تُعاد المحاولة قبل هذا الوقت.
  IntColumn get nextAttemptAt => integer().withDefault(const Constant(0))();

  /// `pending` / `uploading` / `done` / `failed`.
  TextColumn get status => text().withDefault(const Constant('pending'))();

  IntColumn get attempts => integer().withDefault(const Constant(0))();

  TextColumn get lastError => text().nullable()();

  IntColumn get createdAt => integer()();

  IntColumn get doneAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// جلسة الدخول المحفوظة على الجهاز: صف واحد لا يُزامَن.
///
/// تُحفظ لتفتح الواجهة على دور صاحبها وصلاحياته دون إنترنت وقبل أول
/// مزامنة، فلا تُطلب كلمة السر في كل تشغيل.
@DataClassName('DeviceSessionRow')
class DeviceSession extends Table {
  /// دائماً `1`: جهاز واحد وحساب واحد مسجَّل عليه.
  IntColumn get id => integer()();

  /// معرّف الحساب، وهو نفسه معرّف المستخدم على الخادم.
  TextColumn get accountId => text()();

  TextColumn get email => text()();

  /// `owner` / `worker` / `teacher` / `parent`.
  TextColumn get role => text()();

  /// معرّف السجل في جدول الدور؛ فارغ لصاحب المدرسة.
  TextColumn get entityId => text().nullable()();

  TextColumn get displayName => text().withDefault(const Constant(''))();

  BoolColumn get mustChangePassword =>
      boolean().withDefault(const Constant(true))();

  /// صلاحيات العامل كما كانت عند آخر قراءة (JSON).
  TextColumn get permissions => text().withDefault(const Constant('{}'))();

  IntColumn get savedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// كلمات سر الوضع المحلي (دون خادم): بصمة PBKDF2 لكل حساب، لا تُزامَن.
///
/// في وضع الخادم يتولى Supabase Auth كلمات السر ولا يُكتب هذا الجدول.
@DataClassName('LocalCredentialRow')
class LocalCredentials extends Table {
  TextColumn get accountId => text()();

  TextColumn get salt => text()();

  TextColumn get hash => text()();

  IntColumn get iterations => integer()();

  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {accountId};
}

/// بيانات خاصة بهذا الجهاز لا تُزامَن (مثل بادئة أرقام الوصولات).
@DataClassName('DeviceInfoRow')
class DeviceInfo extends Table {
  TextColumn get key => text()();

  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
