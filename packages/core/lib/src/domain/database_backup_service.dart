// النسخ الاحتياطي للقاعدة (SQLite Backup API) على الهاتف والحاسوب؛ لا ملف قاعدة في المتصفح.
export 'database_backup_service_web.dart'
    if (dart.library.ffi) 'database_backup_service_native.dart';
