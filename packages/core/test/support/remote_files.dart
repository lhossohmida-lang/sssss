import 'dart:typed_data';

import 'package:school_core/school_core.dart';

/// مخزن ملفات وهمي: يحفظ ما يُرفع في الذاكرة ويسجّل ما يُجلب.
class RecordingFileStore implements FileStore {
  /// `bucket/path` ← بيانات الملف.
  final Map<String, Uint8List> stored = {};

  /// ما جُلب بالترتيب.
  final List<String> downloads = [];

  @override
  Future<String> upload({
    required String bucket,
    required String remotePath,
    required String localPath,
  }) async {
    stored['$bucket/$remotePath'] = Uint8List(0);
    return '$bucket/$remotePath';
  }

  @override
  Future<Uint8List> download({
    required String bucket,
    required String remotePath,
  }) async {
    final key = '$bucket/$remotePath';
    final bytes = stored[key];
    if (bytes == null) {
      throw const RemoteException('الملف غير موجود', permanent: true);
    }
    downloads.add(key);
    return bytes;
  }
}
