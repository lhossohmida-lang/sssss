import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';

import 'app_database.dart';

/// على الهاتف والحاسوب وحدهما؛ في المتصفح [openWebAppDatabase].
AppDatabase openAppDatabase(File file) =>
    throw UnsupportedError('ملف القاعدة لا يوجد في المتصفح');

/// يفتح القاعدة المحلية في المتصفح: SQLite مترجَم إلى WebAssembly (`sqlite3.wasm`) يعمل في عامل
/// خلفي (`drift_worker.js`) ويحفظ في ذاكرة المتصفح الدائمة (OPFS، أو IndexedDB في المتصفحات الأقدم)،
/// فتبقى البيانات بعد الإغلاق ويعمل التطبيق دون إنترنت كما على الهاتف. الملفان بجانب `index.html`.
AppDatabase openWebAppDatabase(String name) => AppDatabase(
  DatabaseConnection.delayed(
    Future(() async {
      final result = await WasmDatabase.open(
        databaseName: name,
        sqlite3Uri: Uri.parse('sqlite3.wasm'),
        driftWorkerUri: Uri.parse('drift_worker.js'),
      );
      return result.resolvedExecutor;
    }),
  ),
);
