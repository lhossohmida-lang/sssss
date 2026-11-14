import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'money.dart';
import 'monthly_finance_report.dart';

/// بيانات التقرير المالي الشهري قبل تنسيقه للطباعة.
class MonthlyFinanceReportPdfData {
  const MonthlyFinanceReportPdfData({
    required this.report,
    required this.schoolName,
    required this.generatedAt,
    this.schoolAddress = '',
    this.schoolPhone = '',
  });

  final MonthlyFinanceReport report;
  final String schoolName;
  final String schoolAddress;
  final String schoolPhone;
  final DateTime generatedAt;
}

/// ملف التقرير المالي الشهري بالعربية، بخط Cairo المضمَّن.
abstract final class MonthlyFinanceReportPdf {
  static Future<Uint8List> build(
    MonthlyFinanceReportPdfData data, {
    required Uint8List fontData,
  }) async {
    final font = pw.Font.ttf(ByteData.sublistView(fontData));
    final doc = pw.Document(
      title: 'التقرير المالي ${data.report.month}',
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
          pw.SizedBox(height: 18),
          _sectionTitle('المقبوضات'),
          _table(
            [
              for (final payment in data.report.payments)
                _row(
                  payment.type.label,
                  '${payment.count} وصل',
                  Money.format(payment.amount),
                ),
            ],
            totalLabel: 'إجمالي المقبوضات',
            total: data.report.receivedAmount,
          ),
          pw.SizedBox(height: 16),
          _sectionTitle('المصاريف'),
          _table(
            [
              for (final expense in data.report.expenses)
                _row(
                  expense.categoryName,
                  '${expense.count} مصروف',
                  Money.format(expense.amount),
                ),
              if (data.report.expenses.isEmpty)
                _row('لا توجد مصاريف مسجّلة', '', Money.format(0)),
            ],
            totalLabel: 'إجمالي المصاريف',
            total: data.report.expenseAmount,
          ),
          pw.SizedBox(height: 16),
          _table(
            [
              _row(
                'خلاص الأساتذة المسلّم',
                '${data.report.teacherPayoutCount} عملية',
                Money.format(data.report.teacherPayoutAmount),
              ),
            ],
            totalLabel: 'إجمالي الخارج',
            total: data.report.outgoingAmount,
          ),
          pw.SizedBox(height: 14),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(
              vertical: 12,
              horizontal: 14,
            ),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#EEF0FF'),
              borderRadius: pw.BorderRadius.circular(8),
              border: pw.Border.all(color: PdfColor.fromHex('#4F52C9')),
            ),
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Text(
                    'الصافي (المقبوضات - الخارج)',
                    style: const pw.TextStyle(
                      fontSize: 13,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.Text(
                  Money.format(data.report.netAmount),
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColor.fromHex('#272B66'),
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            'احتُسبت المقبوضات بتاريخ تسجيل الوصل، والمصاريف بتاريخها، '
            'وخلاص الأساتذة بتاريخ تسليم المال.',
            style: pw.TextStyle(
              fontSize: 8,
              color: PdfColor.fromHex('#5A6378'),
            ),
          ),
        ],
      ),
    );
    return doc.save();
  }

  static pw.Widget _header(MonthlyFinanceReportPdfData data) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Text(
        data.schoolName.trim().isEmpty ? 'اسم المدرسة' : data.schoolName,
        style: const pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
      ),
      if (data.schoolAddress.trim().isNotEmpty) pw.Text(data.schoolAddress),
      if (data.schoolPhone.trim().isNotEmpty) pw.Text(data.schoolPhone),
      pw.SizedBox(height: 12),
      pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              'التقرير المالي الشهري',
              style: pw.TextStyle(
                color: PdfColor.fromHex('#4F52C9'),
                fontSize: 22,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Text('الفترة: ${_monthName(data.report.month)}'),
        ],
      ),
      pw.SizedBox(height: 4),
      pw.Text(
        'أُنشئ في ${_date(data.generatedAt)}',
        style: pw.TextStyle(fontSize: 8, color: PdfColor.fromHex('#5A6378')),
      ),
      pw.Divider(color: PdfColor.fromHex('#C9CEDB')),
    ],
  );

  static pw.Widget _sectionTitle(String value) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 6),
    child: pw.Text(
      value,
      style: const pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
    ),
  );

  static pw.Widget _table(
    List<List<String>> rows, {
    required String totalLabel,
    required int total,
  }) => pw.Table(
    border: pw.TableBorder.all(color: PdfColor.fromHex('#D9DDE7'), width: .5),
    columnWidths: const {
      0: pw.FlexColumnWidth(4),
      1: pw.FlexColumnWidth(2),
      2: pw.FlexColumnWidth(2),
    },
    children: [
      _tableRow(['البيان', 'العدد', 'المبلغ'], header: true),
      for (final row in rows) _tableRow(row),
      _tableRow([totalLabel, '', Money.format(total)], header: true),
    ],
  );

  static List<String> _row(String name, String count, String amount) => [
    name,
    count,
    amount,
  ];

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
          padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 6),
          child: pw.Text(
            cells[i],
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
            textAlign: i == 2 ? pw.TextAlign.left : pw.TextAlign.right,
          ),
        ),
    ],
  );

  static String _monthName(String month) {
    const names = [
      'يناير',
      'فبراير',
      'مارس',
      'أبريل',
      'مايو',
      'يونيو',
      'يوليو',
      'أغسطس',
      'سبتمبر',
      'أكتوبر',
      'نوفمبر',
      'ديسمبر',
    ];
    final year = month.substring(0, 4);
    final index = int.parse(month.substring(5, 7)) - 1;
    return '${names[index]} $year';
  }

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
