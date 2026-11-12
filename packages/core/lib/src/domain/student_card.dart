import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// بيانات بطاقة التلميذ.
class StudentCardData {
  const StudentCardData({
    required this.schoolName,
    required this.studentName,
    required this.qrCode,
    this.levelName,
    this.parentPhone,
    this.photo,
    this.logo,
  });

  final String schoolName;
  final String studentName;

  /// نص رمز QR كما يُمسح (`S-…`).
  final String qrCode;
  final String? levelName;
  final String? parentPhone;

  /// بيانات الصورة (JPEG أو PNG)، أو `null` فتُرسم الأحرف الأولى.
  final Uint8List? photo;
  final Uint8List? logo;
}

/// بطاقة التلميذ PDF بحجم بطاقة الائتمان 85×54 مم، بالعربية من اليمين إلى
/// اليسار، جاهزة للطباعة والمشاركة.
///
/// الخط يُمرَّر بياناته (Cairo من حزمة الواجهة) ليشكّل الحروف العربية ويدمجها.
abstract final class StudentCard {
  /// عرض البطاقة وارتفاعها بالمليمتر.
  static const double widthMm = 85.6;
  static const double heightMm = 54;

  /// حجم الصفحة: بطاقة أفقية.
  static const PdfPageFormat format = PdfPageFormat(
    widthMm * PdfPageFormat.mm,
    heightMm * PdfPageFormat.mm,
    marginAll: 0,
  );

  /// يبني ملف PDF لبطاقة واحدة.
  static Future<Uint8List> build(
    StudentCardData data, {
    required Uint8List fontData,
  }) async {
    final font = pw.Font.ttf(ByteData.sublistView(fontData));
    final theme = pw.ThemeData.withFont(base: font, bold: font);
    final doc = pw.Document(
      title: 'بطاقة ${data.studentName}',
      author: data.schoolName,
      theme: theme,
    );
    doc.addPage(
      pw.Page(
        pageFormat: format,
        textDirection: pw.TextDirection.rtl,
        build: (context) => _card(data),
      ),
    );
    return doc.save();
  }

  static final PdfColor _ink = PdfColor.fromHex('#1E2433');
  static final PdfColor _accent = PdfColor.fromHex('#4F52C9');
  static final PdfColor _muted = PdfColor.fromHex('#5A6378');

  static pw.Widget _card(StudentCardData data) {
    final photo = data.photo == null
        ? _initials(data.studentName)
        : pw.ClipRRect(
            horizontalRadius: 5,
            verticalRadius: 5,
            child: pw.Image(
              pw.MemoryImage(data.photo!),
              width: 22 * PdfPageFormat.mm,
              height: 28 * PdfPageFormat.mm,
              fit: pw.BoxFit.cover,
            ),
          );
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _accent, width: 1.5),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        children: [
          pw.Container(
            width: double.infinity,
            color: _accent,
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: pw.Row(
              children: [
                if (data.logo != null) ...[
                  pw.Image(
                    pw.MemoryImage(data.logo!),
                    width: 9 * PdfPageFormat.mm,
                    height: 9 * PdfPageFormat.mm,
                    fit: pw.BoxFit.contain,
                  ),
                  pw.SizedBox(width: 6),
                ],
                pw.Expanded(
                  child: pw.Text(
                    data.schoolName,
                    maxLines: 1,
                    style: const pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          pw.Expanded(
            child: pw.Padding(
              padding: const pw.EdgeInsets.all(8),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  photo,
                  pw.SizedBox(width: 8),
                  pw.Expanded(
                    child: pw.Column(
                      mainAxisAlignment: pw.MainAxisAlignment.center,
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          data.studentName,
                          maxLines: 2,
                          style: pw.TextStyle(
                            color: _ink,
                            fontSize: 12,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        if (data.levelName != null)
                          pw.Text(
                            data.levelName!,
                            style: pw.TextStyle(color: _muted, fontSize: 9),
                          ),
                        if (data.parentPhone != null)
                          pw.Directionality(
                            textDirection: pw.TextDirection.ltr,
                            child: pw.Text(
                              data.parentPhone!,
                              style: pw.TextStyle(color: _muted, fontSize: 8),
                            ),
                          ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          'يُمسح الرمز عند الدخول',
                          style: pw.TextStyle(color: _accent, fontSize: 7),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 8),
                  pw.Container(
                    padding: const pw.EdgeInsets.all(3),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.white,
                      border: pw.Border.all(color: PdfColors.grey400),
                    ),
                    child: pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(
                        errorCorrectLevel: pw.BarcodeQRCorrectionLevel.medium,
                      ),
                      data: data.qrCode,
                      width: 26 * PdfPageFormat.mm,
                      height: 26 * PdfPageFormat.mm,
                      drawText: false,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// الأحرف الأولى من الاسم داخل مربع بدل الصورة.
  static pw.Widget _initials(String name) {
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => String.fromCharCode(w.runes.first))
        .join();
    return pw.Container(
      width: 22 * PdfPageFormat.mm,
      height: 28 * PdfPageFormat.mm,
      alignment: pw.Alignment.center,
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#E9EDF5'),
        borderRadius: pw.BorderRadius.circular(5),
      ),
      child: pw.Text(
        words.isEmpty ? '؟' : words,
        style: pw.TextStyle(color: _accent, fontSize: 20),
      ),
    );
  }
}
