import 'dart:typed_data';

/// مخزن الملفات على الخادم (الصور، ملفات المجموعات، مرفقات المحادثات).
abstract interface class FileStore {
  /// يرفع الملف المحلي [localPath] إلى [bucket]/[remotePath] ويعيد المسار
  /// المخزَّن الذي يُكتب في القاعدة. يرمي `RemoteException`.
  Future<String> upload({
    required String bucket,
    required String remotePath,
    required String localPath,
  });

  /// يحمّل ملفاً من المخزن.
  Future<Uint8List> download({
    required String bucket,
    required String remotePath,
  });
}

/// صف تغيّر على الخادم ووصل بالبث اللحظي.
class RemoteChange {
  const RemoteChange({required this.table, required this.row});

  final String table;
  final Map<String, Object?> row;
}

/// مصدر البث اللحظي لتغييرات الخادم.
abstract interface class RealtimeSource {
  /// يبدأ الاستماع ويعيد تدفق التغييرات. إلغاء الاشتراك يوقف الاستماع.
  Stream<RemoteChange> changes();
}
