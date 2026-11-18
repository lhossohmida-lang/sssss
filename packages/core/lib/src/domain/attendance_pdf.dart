import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'date_key.dart';
import 'enums.dart';
import 'group_service.dart';

/// سطر تلميذ في سجل حضور حصة.
class AttendanceSheetRow {
  const AttendanceSheetRow({required this.name, this.status, this.method});

  final String name;

  /// حالته المسجَّلة، و`null` إن لم يُسجَّل له شيء.
  final AttendanceStatus? status;
  final AttendanceMethod? method;
}

/// بيانات سجل حضور حصة واحدة قبل تنسيقه للطباعة.
class AttendanceSheetData {
  const AttendanceSheetData({
    required this.schoolName,
    required this.subjectName,
    required this.groupNumber,
    required this.teacherName,
    required this.date,
    required this.startMinutes,
    required this.endMinutes,
    required this.rows,
    required this.generatedAt,
    this.roomName,
    this.sessionNumber,
    this.cycleNumber,
    this.schoolAddress = '',
    this.schoolPhone = '',
  });

  final String schoolName;
  final String schoolAddress;
  final String schoolPhone;
  final String subjectName;
  final int groupNumber;
  final String teacherName;

  /// تاريخ الحصة `YYYY-MM-DD`.
  final String date;
  final int startMinutes;
  final int endMinutes;
  final String? roomName;
  final int? sessionNumber;
  final int? cycleNumber;
  final List<AttendanceSheetRow> rows;

  /// وقت إنشاء هذه النسخة (لا يتغير بعدها: النسخة لا تُحدَّث).
  final DateTime generatedAt;

  int count(AttendanceStatus status) =>
      rows.where((row) => row.status == status).length;

  int get unmarked => rows.where((row) => row.status == null).length;
}

/// سجل حضور حصة بصيغة PDF (A4 عمودياً، بالعربية من اليمين إلى اليسار).
///
/// تُنتَج نسخة جديدة مع كل حصة تنتهي، ولا تُحدَّث نسخة سابقة أبداً؛ فهي «صورة» الحصة كما أُغلقت.
abstract final class AttendancePdf {
  static final PdfColor _accent = PdfColor.fromHex('#4F52C9');
  static final PdfColor _muted = PdfColor.fromHex('#5A6378');
  static final PdfColor _line = PdfColor.fromHex('#C9CEDB');

  static Future<Uint8List> build(
    AttendanceSheetData data, {
    required Uint8List fontData,
  }) async {
    final font = pw.Font.ttf(ByteData.sublistView(fontData));
    final doc = pw.Document(
      title:
          'سجل حضور ${data.subjectName} · الفوج ${data.groupNumber} · ${data.date}',
      author: data.schoolName,
      theme: pw.ThemeData.withFont(base: font, bold: font),
    );
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        margin: const pw.EdgeInsets.all(28),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.center,
          child: pw.Text(
            'صفحة ${context.pageNumber} من ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8),
          ),
        ),
        build: (_) => [
          _header(data),
          pw.SizedBox(height: 12),
          _summary(data),
          pw.SizedBox(height: 12),
          _table(data),
        ],
      ),
    );
    return doc.save();
  }

  static pw.Widget _header(AttendanceSheetData data) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Text(
        data.schoolName.trim().isEmpty ? 'المدرسة' : data.schoolName,
        style: const pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
      ),
      if (data.schoolAddress.trim().isNotEmpty) pw.Text(data.schoolAddress),
      if (data.schoolPhone.trim().isNotEmpty) pw.Text(data.schoolPhone),
      pw.SizedBox(height: 10),
      pw.Text(
        'سجل حضور حصة',
        style: pw.TextStyle(
          color: _accent,
          fontSize: 22,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
      pw.SizedBox(height: 6),
      pw.Text(
        '${data.subjectName} · الفوج ${data.groupNumber}',
        style: const pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
      ),
      pw.Text(
        'الأستاذ: ${data.teacherName}'
        '${data.roomName == null ? '' : ' · القاعة: ${data.roomName}'}',
      ),
      pw.Text(
        '${GroupService.weekdayName(DateKey.weekday(data.date))} ${data.date}'
        ' · ${DateKey.formatMinutes(data.startMinutes)}'
        '–${DateKey.formatMinutes(data.endMinutes)}'
        '${data.cycleNumber == null ? '' : ' · الدورة ${data.cycleNumber}'}'
        '${data.sessionNumber == null ? '' : ' · الحصة ${data.sessionNumber}'}',
      ),
      pw.SizedBox(height: 4),
      pw.Text(
        'أُنشئت هذه النسخة في ${_stamp(data.generatedAt)} ولا تُحدَّث بعد ذلك.',
        style: pw.TextStyle(fontSize: 8, color: _muted),
      ),
      pw.Divider(color: _line),
    ],
  );

  static pw.Widget _summary(AttendanceSheetData data) => pw.Text(
    'حاضر ${data.count(AttendanceStatus.present)} · '
    'غائب ${data.count(AttendanceStatus.absent)} · '
    'غائب برخصة ${data.count(AttendanceStatus.excused)} · '
    'لم يُسجَّل ${data.unmarked} · المجموع ${data.rows.length}',
    style: const pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
  );

  static pw.Widget _table(AttendanceSheetData data) => pw.Table(
    border: pw.TableBorder.all(color: PdfColor.fromHex('#D9DDE7'), width: .5),
    columnWidths: const {
      0: pw.FlexColumnWidth(1),
      1: pw.FlexColumnWidth(6),
      2: pw.FlexColumnWidth(3),
      3: pw.FlexColumnWidth(2),
    },
    children: [
      _tableRow(['#', 'التلميذ', 'الحالة', 'التسجيل'], header: true),
      for (var i = 0; i < data.rows.length; i++)
        _tableRow([
          '${i + 1}',
          data.rows[i].name,
          statusLabel(data.rows[i].status),
          switch (data.rows[i].method) {
            AttendanceMethod.qr => 'مسح الرمز',
            AttendanceMethod.manual => 'يدوي',
            null => '',
          },
        ]),
      if (data.rows.isEmpty) _tableRow(['', 'لا تلاميذ في هذه الحصة', '', '']),
    ],
  );

  /// نص حالة الحضور في السجل.
  static String statusLabel(AttendanceStatus? status) =>
      status?.label ?? 'لم يُسجَّل';

  static pw.TableRow _tableRow(
    List<String> cells, {
    bool header = false,
  }) => pw.TableRow(
    decoration: header
        ? pw.BoxDecoration(color: PdfColor.fromHex('#F3F4FA'))
        : null,
    children: [
      for (var i = 0; i < cells.length; i++)
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 5),
          child: pw.Text(
            cells[i],
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
            textAlign: pw.TextAlign.right,
          ),
        ),
    ],
  );

  static String _stamp(DateTime value) =>
      '${DateKey.of(value)} ${DateKey.formatMinutes(DateKey.minutesOf(value))}';
}
