import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:school_ui/school_ui.dart';

/// مسح رموز QR بكاميرا الهاتف الخلفية (Android). الكاميرا تبقى شغّالة طوال
/// فتح الشاشة، فلا يُنتظر تشغيلها عند كل مسح.
class MobileScannerSource implements QrCodeSource {
  MobileScannerSource()
    : _controller = MobileScannerController(
        autoStart: false,
        formats: const [BarcodeFormat.qrCode],
        detectionSpeed: DetectionSpeed.normal,
        detectionTimeoutMs: 150,
      );

  final MobileScannerController _controller;

  @override
  Stream<String> get codes => _controller.barcodes.expand(
    (capture) => [
      for (final barcode in capture.barcodes)
        if (barcode.rawValue != null) barcode.rawValue!,
    ],
  );

  @override
  Widget buildPreview(BuildContext context) => MobileScanner(
    controller: _controller,
    errorBuilder: (context, error) => ClayEmptyView(
      title: 'تعذّر تشغيل الكاميرا',
      message: error.errorCode == MobileScannerErrorCode.permissionDenied
          ? 'اسمح للتطبيق باستعمال الكاميرا من إعدادات الهاتف'
          : 'أغلق التطبيقات التي تستعمل الكاميرا ثم أعد المحاولة',
      icon: ClayIcons.scan,
    ),
  );

  @override
  Future<void> start() => _controller.start();

  @override
  Future<void> dispose() => _controller.dispose();
}

/// هل يُفعَّل مسح الكاميرا على هذا النظام؟ (Android فقط.)
bool get cameraScanningSupported => Platform.isAndroid;
