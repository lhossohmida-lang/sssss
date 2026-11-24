import 'dart:io';

/// في المتصفح لا ملف قاعدة يُنسخ: بيانات المدرسة محفوظة على خادمها وتُسترجع بالمزامنة. الواجهة نفسها
/// لنسخة الهاتف والحاسوب حتى يُبنى الكود نفسه، وكل عملية ترمي [UnsupportedError].
class DatabaseBackupService {
  DatabaseBackupService({required this.databaseFile, this.schemaVersion = 3});

  final File databaseFile;
  final int schemaVersion;

  Future<void> createSnapshot(File destination) =>
      throw UnsupportedError('النسخ الاحتياطي للقاعدة غير متاح في المتصفح');

  Future<void> restoreFrom(File backup) =>
      throw UnsupportedError('الاستعادة غير متاحة في المتصفح');
}
