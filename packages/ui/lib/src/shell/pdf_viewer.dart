import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../clay/clay_navigation.dart';

/// يعرض ملف PDF بمعاينة وطباعة ومشاركة. التطبيق الحقيقي معاينة المنصة
/// (`printing`)، وتُستبدل في الاختبارات بنسخة تسجّل ما عُرض.
abstract interface class PdfPresenter {
  /// يعرض [bytes] باسم ملف [fileName] (للمشاركة والحفظ).
  Future<void> show(
    BuildContext context, {
    required Uint8List bytes,
    required String fileName,
    required String title,
  });
}

/// المعاينة الحقيقية: صفحة فيها صورة الملف وأزرار الطباعة والمشاركة.
class PrintingPdfPresenter implements PdfPresenter {
  const PrintingPdfPresenter();

  @override
  Future<void> show(
    BuildContext context, {
    required Uint8List bytes,
    required String fileName,
    required String title,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: ClayAppBar(title: title, showBack: true),
          body: PdfPreview(
            build: (_) async => bytes,
            pdfFileName: fileName,
            canChangePageFormat: false,
            canChangeOrientation: false,
            canDebug: false,
            allowSharing: true,
            allowPrinting: true,
          ),
        ),
      ),
    );
  }
}

final Provider<PdfPresenter> pdfPresenterProvider = Provider<PdfPresenter>(
  (ref) => const PrintingPdfPresenter(),
);
