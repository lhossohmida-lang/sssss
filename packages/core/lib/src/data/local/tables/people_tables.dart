import 'package:drift/drift.dart';

import 'sync_columns.dart';

/// إعدادات المدرسة (الاسم، الشعار، حقوق التسجيل، الهوامش...) كأزواج مفتاح وقيمة.
@DataClassName('SettingRow')
@TableIndex(name: 'idx_settings_updated', columns: {#updatedAt})
class Settings extends Table {
  TextColumn get key => text()();

  TextColumn get value => text()();

  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {key};
}

/// المستويات الدراسية (ابتدائي، متوسط، ثانوي) قابلة للتعديل.
@DataClassName('LevelRow')
@TableIndex(name: 'idx_levels_sort', columns: {#sortOrder})
@TableIndex(name: 'idx_levels_updated', columns: {#updatedAt})
class Levels extends Table with SyncColumns {
  TextColumn get name => text()();

  /// الطور: ابتدائي / متوسط / ثانوي.
  TextColumn get stage => text()();

  IntColumn get sortOrder => integer()();
}

/// خطوط النقل.
@DataClassName('TransportLineRow')
@TableIndex(name: 'idx_transport_lines_name', columns: {#name})
@TableIndex(name: 'idx_transport_lines_updated', columns: {#updatedAt})
class TransportLines extends Table with SyncColumns {
  TextColumn get name => text()();

  TextColumn get driverName => text().withDefault(const Constant(''))();

  TextColumn get driverPhone => text().withDefault(const Constant(''))();

  TextColumn get busNumber => text().withDefault(const Constant(''))();
}

/// حسابات الأولياء. كلمة السر يديرها الخادم ولا تُخزَّن محلياً.
@DataClassName('ParentRow')
@TableIndex(name: 'idx_parents_phone', columns: {#phone}, unique: true)
@TableIndex(name: 'idx_parents_email', columns: {#email})
@TableIndex(name: 'idx_parents_updated', columns: {#updatedAt})
class Parents extends Table with SyncColumns {
  TextColumn get phone => text()();

  /// بريد الدخول المولَّد من تطبيق الإدارة.
  TextColumn get email => text()();

  TextColumn get name => text().withDefault(const Constant(''))();

  /// معرّف المستخدم في خدمة المصادقة، ويُملأ بعد إنشاء الحساب على الخادم.
  TextColumn get authUserId => text().nullable()();
}

/// التلاميذ.
@DataClassName('StudentRow')
@TableIndex(name: 'idx_students_name', columns: {#lastName, #firstName})
@TableIndex(name: 'idx_students_first_name', columns: {#firstName})
@TableIndex(name: 'idx_students_qr', columns: {#qrCode}, unique: true)
@TableIndex(name: 'idx_students_parent_phone', columns: {#parentPhone})
@TableIndex(name: 'idx_students_parent_account', columns: {#parentAccountId})
@TableIndex(name: 'idx_students_level', columns: {#levelId})
@TableIndex(name: 'idx_students_transport_line', columns: {#transportLineId})
@TableIndex(name: 'idx_students_updated', columns: {#updatedAt})
class Students extends Table with SyncColumns {
  TextColumn get firstName => text()();

  TextColumn get lastName => text()();

  TextColumn get parentPhone => text()();

  /// رابط الصورة على الخادم.
  TextColumn get photoUrl => text().nullable()();

  /// مسار الصورة المضغوطة على الجهاز (تُعرض فوراً قبل اكتمال الرفع).
  TextColumn get photoLocalPath => text().nullable()();

  TextColumn get levelId => text().nullable().references(Levels, #id)();

  BoolColumn get usesTransport =>
      boolean().withDefault(const Constant(false))();

  /// سعر النقل الشهري بالدينار.
  IntColumn get transportPrice => integer().withDefault(const Constant(0))();

  TextColumn get transportLineId =>
      text().nullable().references(TransportLines, #id)();

  TextColumn get qrCode => text()();

  TextColumn get parentAccountId =>
      text().nullable().references(Parents, #id)();
}

/// المواد.
@DataClassName('SubjectRow')
@TableIndex(name: 'idx_subjects_name', columns: {#name})
@TableIndex(name: 'idx_subjects_level', columns: {#levelId})
@TableIndex(name: 'idx_subjects_updated', columns: {#updatedAt})
class Subjects extends Table with SyncColumns {
  TextColumn get name => text()();

  TextColumn get levelId => text().nullable().references(Levels, #id)();

  /// سعر الشهر (الدورة) الافتراضي بالدينار.
  IntColumn get monthlyPrice => integer().withDefault(const Constant(0))();
}

/// القاعات.
@DataClassName('RoomRow')
@TableIndex(name: 'idx_rooms_name', columns: {#name})
@TableIndex(name: 'idx_rooms_updated', columns: {#updatedAt})
class Rooms extends Table with SyncColumns {
  TextColumn get name => text()();

  IntColumn get capacity => integer().withDefault(const Constant(0))();
}

/// الأساتذة.
@DataClassName('TeacherRow')
@TableIndex(name: 'idx_teachers_name', columns: {#name})
@TableIndex(name: 'idx_teachers_qr', columns: {#qrCode}, unique: true)
@TableIndex(name: 'idx_teachers_phone', columns: {#phone})
@TableIndex(name: 'idx_teachers_updated', columns: {#updatedAt})
class Teachers extends Table with SyncColumns {
  TextColumn get name => text()();

  TextColumn get phone => text()();

  TextColumn get email => text()();

  TextColumn get photoUrl => text().nullable()();

  TextColumn get photoLocalPath => text().nullable()();

  /// المبلغ الافتراضي لكل تلميذ في الدورة، ويمكن تغييره لكل مجموعة.
  IntColumn get ratePerStudent => integer().withDefault(const Constant(0))();

  TextColumn get qrCode => text()();

  TextColumn get authUserId => text().nullable()();
}

/// المواد التي يدرّسها كل أستاذ (بديل مفهرس عن الحقل `subjects[]`).
@DataClassName('TeacherSubjectRow')
@TableIndex(name: 'idx_teacher_subjects_subject', columns: {#subjectId})
@TableIndex(name: 'idx_teacher_subjects_updated', columns: {#updatedAt})
class TeacherSubjects extends Table {
  TextColumn get teacherId => text().references(Teachers, #id)();

  TextColumn get subjectId => text().references(Subjects, #id)();

  IntColumn get updatedAt => integer()();

  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {teacherId, subjectId};
}

/// العمال.
@DataClassName('WorkerRow')
@TableIndex(name: 'idx_workers_name', columns: {#name})
@TableIndex(name: 'idx_workers_qr', columns: {#qrCode}, unique: true)
@TableIndex(name: 'idx_workers_updated', columns: {#updatedAt})
class Workers extends Table with SyncColumns {
  TextColumn get name => text()();

  TextColumn get phone => text()();

  TextColumn get email => text()();

  TextColumn get qrCode => text()();

  /// وقت بداية العمل المتوقع بالدقائق منذ منتصف الليل.
  IntColumn get expectedStartMinutes =>
      integer().withDefault(const Constant(480))();

  /// وقت نهاية العمل المتوقع بالدقائق منذ منتصف الليل.
  IntColumn get expectedEndMinutes =>
      integer().withDefault(const Constant(1020))();

  /// أجر اليوم الكامل بالدينار.
  IntColumn get fullDayWage => integer().withDefault(const Constant(0))();

  /// أجر نصف اليوم بالدينار (مبلغ مستقل يحدده المدير).
  IntColumn get halfDayWage => integer().withDefault(const Constant(0))();

  /// برنامج العمل الأسبوعي: JSON من رقم اليوم (1 = الاثنين … 7 = الأحد)
  /// إلى `off` / `half` / `full`.
  TextColumn get weeklySchedule => text().withDefault(const Constant('{}'))();

  /// الصلاحيات: JSON من اسم الوحدة إلى قائمة الأفعال المسموحة.
  TextColumn get permissions => text().withDefault(const Constant('{}'))();

  TextColumn get authUserId => text().nullable()();
}
