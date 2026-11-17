import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_identity.dart';
import '../data/local/app_database.dart';

/// ما مُسح من الجهاز وما تعذّر مسحه.
class DeviceWipeReport {
  const DeviceWipeReport({
    this.files = 0,
    this.directories = 0,
    this.failures = const [],
  });

  /// عدد الملفات المحذوفة.
  final int files;

  /// عدد المجلدات المحذوفة بما فيها.
  final int directories;

  /// أسماء ما تعذّر حذفه (ملف مقفل مثلاً).
  final List<String> failures;

  /// هل مُسح كل شيء؟
  bool get complete => failures.isEmpty;

  /// هل لم يكن هناك ما يُمسح؟
  bool get nothingFound => files == 0 && directories == 0 && failures.isEmpty;
}

/// يمسح كل ما حفظه تطبيق على هذا الجهاز: قاعدة كل مدرسة ربط بها (وملفات sqlite المساعدة)
/// وصورها وملفاتها ومرفقاتها، وملف ربط المدرسة، وما نُزّل من تحديثات وما جُهّز لرفعه إلى
/// Drive. وهو «إعادة تعيين بيانات المصنع» للجهاز وحده: لا يمسّ شيئاً على خادم المدرسة، فتعود
/// بياناته إلى الجهاز بعد الدخول من جديد.
///
/// يُستدعى بعد إغلاق وقت تشغيل التطبيق (قاعدة مفتوحة لا تُحذف على Windows). لا يمسّ ملفات
/// غير ملفاته (مثل ملفات Firebase على Android).
class DeviceDataWiper {
  DeviceDataWiper(this.app, {Future<Directory> Function()? supportDirectory})
    : _support = supportDirectory ?? getApplicationSupportDirectory;

  final AppIdentity app;
  final Future<Directory> Function() _support;

  /// مجلدات يشاركها تطبيق الإدارة وغيره باسمها دون نطاق مدرسة.
  static const List<String> _sharedDirectories = ['updates', 'drive_uploads'];

  /// محاولات الحذف لملف قد يبقى مقفلاً لحظات بعد إغلاق القاعدة (Windows).
  static const int _attempts = 4;

  /// مفاتيح جلسات الدخول التي تحفظها مكتبة Supabase في تفضيلات التطبيق.
  static const String _sessionKeyPrefix = 'sb-';

  late final RegExp _databaseFile = RegExp(
    '^school_${app.name}(_[^.]+)?\\.sqlite(-wal|-shm|-journal)?\$',
  );
  late final RegExp _photosDirectory = RegExp('^photos_${app.name}(_.+)?\$');

  /// يمسح بيانات هذا التطبيق من مجلده على الجهاز.
  Future<DeviceWipeReport> wipe() async {
    final root = await _support();
    if (!await root.exists()) return const DeviceWipeReport();
    var files = 0;
    var directories = 0;
    final failures = <String>[];
    await for (final entity in root.list(followLinks: false)) {
      final name = p.basename(entity.path);
      final isFile = entity is File;
      final matches = isFile
          ? _databaseFile.hasMatch(name) || name == 'pairing_${app.name}.json'
          : entity is Directory &&
                (_photosDirectory.hasMatch(name) ||
                    _sharedDirectories.contains(name));
      if (!matches) continue;
      final counted = isFile ? 1 : await _countFiles(entity as Directory);
      if (await _delete(entity)) {
        if (isFile) {
          files++;
        } else {
          files += counted;
          directories++;
        }
      } else {
        failures.add(name);
      }
    }
    return DeviceWipeReport(
      files: files,
      directories: directories,
      failures: failures,
    );
  }

  /// يحذف [entity] ويعيد المحاولة قليلاً إن كان مقفلاً. يعيد نجاح الحذف.
  Future<bool> _delete(FileSystemEntity entity) async {
    for (var attempt = 1; attempt <= _attempts; attempt++) {
      try {
        await entity.delete(recursive: true);
        return true;
      } on FileSystemException {
        if (attempt == _attempts) return false;
        await Future<void>.delayed(Duration(milliseconds: 150 * attempt));
      }
    }
    return false;
  }

  Future<int> _countFiles(Directory directory) async {
    var count = 0;
    try {
      await for (final entity in directory.list(recursive: true)) {
        if (entity is File) count++;
      }
    } on FileSystemException {
      // العدّ للتقرير فقط.
    }
    return count;
  }

  /// يمسح جلسات الدخول المحفوظة على الجهاز (مفاتيح Supabase)، فلا يعود التطبيق
  /// إلى حساب سابق بعد إعادة التعيين.
  static Future<void> clearAuthSessions() async {
    final preferences = await SharedPreferences.getInstance();
    for (final key in preferences.getKeys().toList()) {
      if (key.startsWith(_sessionKeyPrefix)) await preferences.remove(key);
    }
  }
}

/// عدد التغييرات المحلية التي لم تصل إلى الخادم بعد (طابور الإرسال، منها ما رفضه الخادم).
/// تضيع مع مسح بيانات الجهاز.
Future<int> countUnsyncedChanges(AppDatabase db) async {
  final row = await db
      .customSelect('SELECT COUNT(*) AS c FROM outbox', readsFrom: {db.outbox})
      .getSingle();
  return row.read<int>('c');
}
