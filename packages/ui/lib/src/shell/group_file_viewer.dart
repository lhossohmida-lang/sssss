import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:school_core/school_core.dart';

import '../clay/clay_overlays.dart';
import 'pdf_viewer.dart';
import 'providers.dart';

/// «2.5 ك.ب» أو «1.2 م.ب» من حجم بالبايت (أرقام لاتينية).
String fileSizeText(int bytes) {
  if (bytes < 1024) return '$bytes بايت';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} ك.ب';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} م.ب';
}

/// يفتح ملف مجموعة: PDF في عارض الملفات، وصورة في نافذة تكبير. النسخة
/// المحلية أولاً، وإن لم توجد (رُفع الملف من جهاز آخر) جُلب من مخزن الخادم.
/// يُظهر رسالة إن تعذّر الفتح.
Future<void> openGroupFile(
  BuildContext context,
  WidgetRef ref,
  GroupFileItem item,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final service = ref.read(groupFileServiceProvider);
  Uint8List? bytes = await service.readLocal(item.file);
  if (bytes == null) {
    final url = item.file.fileUrl;
    final store = ref.read(runtimeProvider).fileStore;
    if (url != null && store != null) {
      final slash = url.indexOf('/');
      try {
        bytes = await store.download(
          bucket: url.substring(0, slash),
          remotePath: url.substring(slash + 1),
        );
      } on RemoteException {
        bytes = null;
      }
    }
  }
  if (bytes == null) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('تعذّر فتح الملف الآن؛ تحقّق من الاتصال وأعد المحاولة'),
      ),
    );
    return;
  }
  if (!context.mounted) return;
  if (item.isPdf) {
    await ref
        .read(pdfPresenterProvider)
        .show(
          context,
          bytes: bytes,
          fileName: item.fileName,
          title: item.title,
        );
  } else {
    await showClayDialog<void>(
      context,
      title: item.title,
      content: InteractiveViewer(child: Image.memory(bytes)),
    );
  }
}
