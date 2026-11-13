import 'package:excel_plus/excel_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_ui/school_ui.dart';

void main() {
  test(
    'creates a right-to-left XLSX with the requested attendance data',
    () async {
      final bytes = await AttendanceExcelExporter.generate(
        const AttendanceExcelData(
          groupNumber: 4,
          subjectName: 'الرياضيات',
          teacherName: 'أمين',
          date: '2026-11-13',
          startMinutes: 540,
          endMinutes: 630,
          cancelled: false,
          students: [
            AttendanceExcelStudent(
              name: 'مريم',
              status: 'حاضر',
              method: 'مسح الرمز',
            ),
            AttendanceExcelStudent(
              name: 'ياسين',
              status: 'بلا تسجيل',
              method: '',
            ),
          ],
        ),
      );
      final workbook = Excel.decodeBytes(bytes);
      final sheet = workbook.tables['الحضور']!;
      final rows = sheet.rows;

      expect(sheet.isRTL, isTrue);
      expect((rows[0][0]!.value as TextCellValue).value.text, 'كشف حضور حصة');
      expect(
        (rows[1][0]!.value as TextCellValue).value.text,
        'المجموعة 4 · الرياضيات',
      );
      expect((rows[4][1]!.value as TextCellValue).value.text, 'اسم التلميذ');
      expect((rows[5][1]!.value as TextCellValue).value.text, 'مريم');
      expect((rows[5][2]!.value as TextCellValue).value.text, 'حاضر');
      expect((rows[6][2]!.value as TextCellValue).value.text, 'بلا تسجيل');
      expect((rows[7][1]!.value as IntCellValue).value, 2);
    },
  );

  test('normalizes the selected name into a safe XLSX filename', () {
    expect(
      AttendanceExcelExporter.normalizeFileName('كشف/نوفمبر.xlsx'),
      'كشف_نوفمبر.xlsx',
    );
    expect(AttendanceExcelExporter.normalizeFileName('نتائج  '), 'نتائج.xlsx');
    expect(AttendanceExcelExporter.normalizeFileName('CON.xlsx'), '_CON.xlsx');
    expect(
      () => AttendanceExcelExporter.normalizeFileName(' .xlsx '),
      throwsFormatException,
    );
  });
}
