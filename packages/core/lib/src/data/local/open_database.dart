import 'dart:io';

import 'package:drift/native.dart';

import 'app_database.dart';

/// يفتح القاعدة المحلية في isolate خلفي: كل استعلامات SQL (ومنها المزامنة
/// والحسابات المجمّعة) تعمل خارج خيط الواجهة.
AppDatabase openAppDatabase(File file) {
  return AppDatabase(
    NativeDatabase.createInBackground(
      file,
      setup: (database) {
        // WAL: القراءة لا تنتظر الكتابة، والكتابة أسرع.
        database.execute('PRAGMA journal_mode = WAL');
        database.execute('PRAGMA synchronous = NORMAL');
      },
    ),
  );
}
