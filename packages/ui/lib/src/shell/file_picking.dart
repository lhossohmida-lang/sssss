import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// ملف اختاره المستخدم: اسمه وبياناته.
class PickedFile {
  const PickedFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

/// مصدر الملفات: يفتح منتقي ملفات المنصة ويعيد الملف المختار، أو `null` عند
/// الإلغاء. التطبيق الحقيقي منتقي النظام (Android وWindows)، وتُستبدل في
/// الاختبارات بنسخة وهمية.
abstract interface class FileSource {
  /// يختار ملفاً من [extensions] (بلا نقطة). يرمي [FileSystemException] إن
  /// تعذّرت قراءة الملف.
  Future<PickedFile?> pick(
    BuildContext context, {
    required List<String> extensions,
  });
}

/// منتقي ملفات النظام. الحجم يُفحص في خدمة الملفات (لا هنا) فيظهر خطؤه
/// على الحقل نفسه.
class PlatformFileSource implements FileSource {
  const PlatformFileSource();

  @override
  Future<PickedFile?> pick(
    BuildContext context, {
    required List<String> extensions,
  }) async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: extensions,
    );
    if (files.isEmpty) return null;
    final file = files.first;
    final bytes = await file.readAsBytes();
    return PickedFile(name: file.name, bytes: bytes);
  }
}

final Provider<FileSource> fileSourceProvider = Provider<FileSource>(
  (ref) => const PlatformFileSource(),
);
