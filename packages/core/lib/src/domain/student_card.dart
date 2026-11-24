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

  /// البطاقة كما تُرسم.
  PrintableCard toPrintable() => PrintableCard(
    schoolName: schoolName,
    name: studentName,
    qrCode: qrCode,
    caption: 'يُمسح الرمز عند الدخول',
    subtitle: levelName,
    phone: parentPhone,
    photo: photo,
    logo: logo,
  );
}

/// بطاقة واحدة جاهزة للرسم: تلميذ أو أستاذ أو عامل.
class PrintableCard {
  const PrintableCard({
    required this.schoolName,
    required this.name,
    required this.qrCode,
    required this.caption,
    this.subtitle,
    this.phone,
    this.photo,
    this.logo,
  });

  final String schoolName;
  final String name;
  final String qrCode;

  /// السطر الملوّن تحت البيانات («يُمسح الرمز عند الدخول»).
  final String caption;
  final String? subtitle;
  final String? phone;
  final Uint8List? photo;
  final Uint8List? logo;
}

/// بيانات بطاقة الأستاذ أو العامل.
class StaffCardData {
  const StaffCardData({
    required this.schoolName,
    required this.name,
    required this.role,
    required this.qrCode,
    this.phone,
    this.photo,
    this.logo,
  });

  final String schoolName;
  final String name;

  /// ما يظهر تحت الاسم: «أستاذ · رياضيات» أو «عامل».
  final String role;

  /// نص رمز QR كما يُمسح (`T-…` للأستاذ و`W-…` للعامل).
  final String qrCode;
  final String? phone;
  final Uint8List? photo;
  final Uint8List? logo;

  /// البطاقة كما تُرسم.
  PrintableCard toPrintable() => PrintableCard(
    schoolName: schoolName,
    name: name,
    qrCode: qrCode,
    caption: 'يُمسح الرمز عند الدخول والخروج',
    subtitle: role,
    phone: phone,
    photo: photo,
    logo: logo,
  );
}

/// بطاقة الأستاذ أو العامل PDF بالحجم والتصميم نفسيهما لبطاقة التلميذ؛ مسح
/// رمزها في ماسح المدخل يسجّل الدخول ثم الخروج.
abstract final class StaffCard {
  /// يبني ملف PDF لبطاقة واحدة.
  static Future<Uint8List> build(
    StaffCardData data, {
    required Uint8List fontData,
  }) async {
    final font = pw.Font.ttf(ByteData.sublistView(fontData));
    final theme = pw.ThemeData.withFont(base: font, bold: font);
    final doc = pw.Document(
      title: 'بطاقة ${data.name}',
      author: data.schoolName,
      theme: theme,
    );
    doc.addPage(
      pw.Page(
        pageFormat: StudentCard.format,
        textDirection: pw.TextDirection.rtl,
        build: (context) => StudentCard._card(data.toPrintable()),
      ),
    );
    return doc.save();
  }
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
        build: (context) => _card(data.toPrintable()),
      ),
    );
    return doc.save();
  }

  static final PdfColor _ink = PdfColor.fromHex('#1E2433');
  static final PdfColor _accent = PdfColor.fromHex('#4F52C9');
  static final PdfColor _muted = PdfColor.fromHex('#5A6378');

  static pw.Widget _card(PrintableCard card) {
    final PrintableCard(
      :schoolName,
      :name,
      :qrCode,
      :caption,
      :subtitle,
      :phone,
      :photo,
      :logo,
    ) = card;
    final picture = photo == null
        ? _initials(name)
        : pw.ClipRRect(
            horizontalRadius: 5,
            verticalRadius: 5,
            child: pw.Image(
              pw.MemoryImage(photo),
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
                if (logo != null) ...[
                  pw.Image(
                    pw.MemoryImage(logo),
                    width: 9 * PdfPageFormat.mm,
                    height: 9 * PdfPageFormat.mm,
                    fit: pw.BoxFit.contain,
                  ),
                  pw.SizedBox(width: 6),
                ],
                pw.Expanded(
                  child: pw.Text(
                    schoolName,
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
                  picture,
                  pw.SizedBox(width: 8),
                  pw.Expanded(
                    child: pw.Column(
                      mainAxisAlignment: pw.MainAxisAlignment.center,
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          name,
                          maxLines: 2,
                          style: pw.TextStyle(
                            color: _ink,
                            fontSize: 12,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        if (subtitle != null)
                          pw.Text(
                            subtitle,
                            style: pw.TextStyle(color: _muted, fontSize: 9),
                          ),
                        if (phone != null && phone.isNotEmpty)
                          pw.Directionality(
                            textDirection: pw.TextDirection.ltr,
                            child: pw.Text(
                              phone,
                              style: pw.TextStyle(color: _muted, fontSize: 8),
                            ),
                          ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          caption,
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
                      data: qrCode,
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

/// ورقة A4 فيها عدة بطاقات (تلاميذ أو أساتذة أو عمال) بحجمها الحقيقي 85.6×54 مم: عمودان في خمسة صفوف،
/// أي 10 بطاقات في الورقة، تُقصّ على حدودها. أكثر من 10 بطاقات تأخذ ورقات تالية.
abstract final class CardSheet {
  /// عدد البطاقات في الورقة.
  static const int columns = 2;
  static const int rows = 5;
  static const int perPage = columns * rows;

  /// المسافة بين البطاقات بالمليمتر.
  static const double gapMm = 4;

  /// يبني ملف PDF لكل [cards] بالترتيب.
  static Future<Uint8List> build(
    List<PrintableCard> cards, {
    required Uint8List fontData,
    String title = 'بطاقات',
    String? author,
  }) async {
    final font = pw.Font.ttf(ByteData.sublistView(fontData));
    final theme = pw.ThemeData.withFont(base: font, bold: font);
    final doc = pw.Document(title: title, author: author, theme: theme);
    const mm = PdfPageFormat.mm;
    const cardWidth = StudentCard.widthMm * mm;
    const cardHeight = StudentCard.heightMm * mm;
    const gap = gapMm * mm;
    for (var start = 0; start < cards.length; start += perPage) {
      final page = cards.skip(start).take(perPage).toList();
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.copyWith(
            marginLeft: 0,
            marginRight: 0,
            marginTop: 0,
            marginBottom: 0,
          ),
          textDirection: pw.TextDirection.rtl,
          build: (context) => pw.Center(
            child: pw.Column(
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                for (var r = 0; r < rows; r++)
                  if (r * columns < page.length)
                    pw.Padding(
                      padding: pw.EdgeInsets.only(top: r == 0 ? 0 : gap),
                      child: pw.Row(
                        mainAxisSize: pw.MainAxisSize.min,
                        children: [
                          for (var c = 0; c < columns; c++)
                            pw.Padding(
                              padding: pw.EdgeInsets.only(
                                left: c == 0 ? 0 : gap,
                              ),
                              child: pw.SizedBox(
                                width: cardWidth,
                                height: cardHeight,
                                child: r * columns + c < page.length
                                    ? StudentCard._card(page[r * columns + c])
                                    : null,
                              ),
                            ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
        ),
      );
    }
    return doc.save();
  }
}
