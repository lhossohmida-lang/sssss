// القاعدة المحلية: ملف SQLite على الهاتف والحاسوب، وSQLite بـWebAssembly في المتصفح (نسخة الويب PWA)،
// بالمخطط والاستعلامات نفسها.
export 'open_database_web.dart'
    if (dart.library.ffi) 'open_database_native.dart';
