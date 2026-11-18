import 'package:drift/drift.dart';

import 'app_database.dart';

/// جداول تخص الجهاز نفسه لا المدرسة: جلسة الدخول المحفوظة، وكلمات سر الوضع المحلي، ومفاتيح الجهاز
/// (معرّفه وبادئة وصولاته). تبقى عند مسح بيانات المدرسة فلا يخرج المالك من حسابه ولا يتغير جهازه.
const Set<String> deviceOnlyTables = {
  'device_session',
  'local_credentials',
  'device_info',
};

/// يفرّغ بيانات المدرسة من قاعدة هذا الجهاز: كل جدول فيه عدا [deviceOnlyTables]، ويشمل طابور الإرسال
/// ومؤشرات السحب وطابور الرفع، فيعود الجهاز كأنه جديد على المدرسة (يسحب ما في الخادم من الصفر).
///
/// معاملة واحدة، والمفاتيح الأجنبية تُفحص عند إتمامها فلا يهمّ ترتيب المسح. وكل جدول يُعلَن عنه
/// مُغيَّراً فتتحدث الواجهة التي تراقبه.
Future<void> wipeSchoolData(AppDatabase db) {
  return db.transaction(() async {
    await db.customStatement('PRAGMA defer_foreign_keys = ON');
    for (final table in db.allTables) {
      final name = table.actualTableName;
      if (deviceOnlyTables.contains(name)) continue;
      await db.customUpdate(
        'DELETE FROM "$name"',
        updates: {table},
        updateKind: UpdateKind.delete,
      );
    }
  });
}
