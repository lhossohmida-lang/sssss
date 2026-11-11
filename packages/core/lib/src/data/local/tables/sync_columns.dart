import 'package:drift/drift.dart';

/// أعمدة مشتركة لكل جدول يُزامَن مع الخادم.
///
/// الأوقات أعداد صحيحة بالميلي ثانية منذ 1970 (UTC) حتى يكون
/// «آخر تعديل يفوز» دقيقاً وقابلاً للفهرسة.
mixin SyncColumns on Table {
  /// معرّف UUID يُولَّد على الجهاز.
  TextColumn get id => text()();

  IntColumn get createdAt => integer()();

  IntColumn get updatedAt => integer()();

  /// وقت الحذف الناعم؛ `null` يعني أن السجل حيّ.
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
