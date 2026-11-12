import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'money.dart';

/// بيانات وصل الاستلام.
class ReceiptData {
  const ReceiptData({
    required this.schoolName,
    required this.receiptNumber,
    required this.dateText,
    required this.studentName,
    required this.description,
    required this.amount,
    required this.receivedByName,
    this.schoolAddress = '',
    this.schoolPhone = '',
    this.remaining,
    this.note = '',
    this.logo,
  });

  final String schoolName;
  final String schoolAddress;
  final String schoolPhone;

  /// رقم الوصل مثل `ABC-000123`.
  final String receiptNumber;

  /// التاريخ والوقت بنص جاهز للعرض.
  final String dateText;
  final String studentName;

  /// ما دُفع عنه (شهر، نقل، حقوق تسجيل) بتفصيله.
  final String description;
  final int amount;

  /// الباقي من هذا البند بعد الدفعة، و`null` إن لم يُعرض.
  final int? remaining;
  final String receivedByName;
  final String note;
  final Uint8List? logo;
}

/// وصل الاستلام PDF بمقاس A5 عمودياً، بالعربية من اليمين إلى اليسار، جاهز
/// للطباعة والمشاركة (الإجابة 59).
abstract final class ReceiptPdf {
  /// المقاس A5 (148×210 مم) بهوامش 12 مم.
  static const PdfPageFormat format = PdfPageFormat(
    148 * PdfPageFormat.mm,
    210 * PdfPageFormat.mm,
    marginAll: 12 * PdfPageFormat.mm,
  );

  /// يبني ملف PDF لوصل واحد. [fontData] خط Cairo يشكّل الحروف العربية.
  static Future<Uint8List> build(
    ReceiptData data, {
    required Uint8List fontData,
  }) async {
    final font = pw.Font.ttf(ByteData.sublistView(fontData));
    final theme = pw.ThemeData.withFont(base: font, bold: font);
    final doc = pw.Document(
      title: 'وصل ${data.receiptNumber}',
      author: data.schoolName,
      theme: theme,
    );
    doc.addPage(
      pw.Page(
        pageFormat: format,
        textDirection: pw.TextDirection.rtl,
        build: (context) => _page(data),
      ),
    );
    return doc.save();
  }

  static final PdfColor _ink = PdfColor.fromHex('#1E2433');
  static final PdfColor _accent = PdfColor.fromHex('#4F52C9');
  static final PdfColor _muted = PdfColor.fromHex('#5A6378');
  static final PdfColor _line = PdfColor.fromHex('#C9CEDB');

  static pw.Widget _page(ReceiptData data) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _header(data),
        pw.SizedBox(height: 14),
        pw.Row(
          children: [
            pw.Expanded(
              child: pw.Text(
                'وصل استلام',
                style: pw.TextStyle(
                  color: _accent,
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.Directionality(
              textDirection: pw.TextDirection.ltr,
              child: pw.Text(
                data.receiptNumber,
                style: pw.TextStyle(
                  color: _ink,
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Directionality(
          textDirection: pw.TextDirection.ltr,
          child: pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              data.dateText,
              style: pw.TextStyle(color: _muted, fontSize: 10),
            ),
          ),
        ),
        pw.SizedBox(height: 14),
        _row('استلمنا من وليّ التلميذ', data.studentName),
        _row('عن', data.description),
        if (data.note.isNotEmpty) _row('ملاحظة', data.note),
        pw.SizedBox(height: 14),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _accent, width: 1.5),
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(
                  'المبلغ المستلَم',
                  style: pw.TextStyle(color: _muted, fontSize: 12),
                ),
              ),
              pw.Text(
                Money.format(data.amount),
                style: pw.TextStyle(
                  color: _ink,
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        if (data.remaining != null) ...[
          pw.SizedBox(height: 8),
          _row(
            'الباقي من هذا البند',
            data.remaining == 0
                ? 'مسدَّد بالكامل'
                : Money.format(data.remaining!),
          ),
        ],
        pw.Spacer(),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'المستلِم',
                    style: pw.TextStyle(color: _muted, fontSize: 10),
                  ),
                  pw.Text(
                    data.receivedByName,
                    style: pw.TextStyle(
                      color: _ink,
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 26),
                  pw.Container(width: 120, height: 0.8, color: _line),
                  pw.SizedBox(height: 3),
                  pw.Text(
                    'التوقيع والختم',
                    style: pw.TextStyle(color: _muted, fontSize: 9),
                  ),
                ],
              ),
            ),
            pw.BarcodeWidget(
              barcode: pw.Barcode.qrCode(
                errorCorrectLevel: pw.BarcodeQRCorrectionLevel.medium,
              ),
              data: data.receiptNumber,
              width: 24 * PdfPageFormat.mm,
              height: 24 * PdfPageFormat.mm,
              drawText: false,
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _header(ReceiptData data) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 10),
      decoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _accent, width: 1.5)),
      ),
      child: pw.Row(
        children: [
          if (data.logo != null) ...[
            pw.Image(
              pw.MemoryImage(data.logo!),
              width: 16 * PdfPageFormat.mm,
              height: 16 * PdfPageFormat.mm,
              fit: pw.BoxFit.contain,
            ),
            pw.SizedBox(width: 10),
          ],
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  data.schoolName,
                  maxLines: 2,
                  style: pw.TextStyle(
                    color: _ink,
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                if (data.schoolAddress.isNotEmpty)
                  pw.Text(
                    data.schoolAddress,
                    maxLines: 2,
                    style: pw.TextStyle(color: _muted, fontSize: 9),
                  ),
                if (data.schoolPhone.isNotEmpty)
                  pw.Directionality(
                    textDirection: pw.TextDirection.ltr,
                    child: pw.Text(
                      data.schoolPhone,
                      style: pw.TextStyle(color: _muted, fontSize: 9),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _row(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 105,
            child: pw.Text(
              label,
              style: pw.TextStyle(color: _muted, fontSize: 11),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(
                color: _ink,
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
