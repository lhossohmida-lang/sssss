import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../theme/clay_tokens.dart';

/// رمز QR مقروء بالماسح: مربعات سوداء على خلفية بيضاء بهامش، في الوضعين
/// الفاتح والداكن (الماسحات لا تقرأ رمزاً معكوس الألوان).
class ClayQrCode extends StatelessWidget {
  const ClayQrCode({
    required this.data,
    this.size = 200,
    this.semanticLabel = 'رمز QR',
    super.key,
  });

  /// النص المرمَّز، مثل `T-ABCDEFGHJK`.
  final String data;

  /// طول ضلع الرمز دون الهامش.
  final double size;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(ClayRadius.md),
        ),
        child: Padding(
          padding: const EdgeInsets.all(ClaySpacing.md),
          child: QrImageView(
            data: data,
            size: size,
            version: QrVersions.auto,
            errorCorrectionLevel: QrErrorCorrectLevel.M,
            backgroundColor: Colors.white,
            eyeStyle: const QrEyeStyle(
              eyeShape: QrEyeShape.square,
              color: Colors.black,
            ),
            dataModuleStyle: const QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: Colors.black,
            ),
          ),
        ),
      ),
    );
  }
}
