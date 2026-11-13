import 'dart:isolate';
import 'dart:typed_data';

import 'package:excel_plus/excel_plus.dart';
import 'package:school_core/school_core.dart';

class AttendanceExcelStudent {
  const AttendanceExcelStudent({
    required this.name,
    required this.status,
    required this.method,
  });

  final String name;
  final String status;
  final String method;
}

class AttendanceExcelData {
  const AttendanceExcelData({
    required this.groupNumber,
    required this.subjectName,
    required this.teacherName,
    required this.date,
    required this.startMinutes,
    required this.endMinutes,
    required this.cancelled,
    required this.students,
  });

  factory AttendanceExcelData.fromRoster(SessionRoster roster) =>
      AttendanceExcelData(
        groupNumber: roster.groupNumber,
        subjectName: roster.subjectName,
        teacherName: roster.teacherName,
        date: roster.session.date,
        startMinutes: roster.session.startMinutes,
        endMinutes: roster.session.endMinutes,
        cancelled: roster.cancelled,
        students: [
          for (final student in roster.students)
            AttendanceExcelStudent(
              name: student.name,
              status: student.status?.label ?? 'بلا تسجيل',
              method: student.method?.label ?? '',
            ),
        ],
      );

  final int groupNumber;
  final String subjectName;
  final String teacherName;
  final String date;
  final int startMinutes;
  final int endMinutes;
  final bool cancelled;
  final List<AttendanceExcelStudent> students;
}

/// Builds a right-to-left XLSX workbook away from the UI isolate.
abstract final class AttendanceExcelExporter {
  static String defaultFileName(AttendanceExcelData data) =>
      'حضور مجموعة ${data.groupNumber} - ${data.subjectName} - ${data.date}';

  static String normalizeFileName(String requestedName) {
    var name = requestedName
        .trim()
        .replaceAll(RegExp(r'[<>:"/\\|?*\u0000-\u001F]'), '_')
        .replaceAll(RegExp(r'[. ]+$'), '');
    name = name.replaceFirst(RegExp(r'\.xlsx$', caseSensitive: false), '');
    if (name.isEmpty) throw const FormatException('اكتب اسم الملف');
    if (name.length > 100) name = name.substring(0, 100).trimRight();
    if (RegExp(
      r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$',
      caseSensitive: false,
    ).hasMatch(name)) {
      name = '_$name';
    }
    return '$name.xlsx';
  }

  static Future<Uint8List> generate(AttendanceExcelData data) {
    final rows = [
      for (final student in data.students)
        {
          'name': student.name,
          'status': student.status,
          'method': student.method,
        },
    ];
    return Isolate.run(() {
      final workbook = Excel.createExcel();
      workbook.rename('Sheet1', 'الحضور');
      final sheet = workbook['الحضور']..isRTL = true;

      sheet.appendRow([TextCellValue('كشف حضور حصة')]);
      sheet.appendRow([
        TextCellValue('المجموعة ${data.groupNumber} · ${data.subjectName}'),
      ]);
      sheet.appendRow([TextCellValue('الأستاذ: ${data.teacherName}')]);
      sheet.appendRow([
        TextCellValue(
          '${data.date} · ${DateKey.formatMinutes(data.startMinutes)}–'
          '${DateKey.formatMinutes(data.endMinutes)}',
        ),
      ]);
      if (data.cancelled) sheet.appendRow([TextCellValue('حالة الحصة: ملغاة')]);
      sheet.appendRow([
        TextCellValue('الرقم'),
        TextCellValue('اسم التلميذ'),
        TextCellValue('الحالة'),
        TextCellValue('طريقة التسجيل'),
      ]);
      for (var i = 0; i < rows.length; i++) {
        final row = rows[i];
        sheet.appendRow([
          IntCellValue(i + 1),
          TextCellValue(row['name']!),
          TextCellValue(row['status']!),
          TextCellValue(row['method']!),
        ]);
      }

      final headerRow = data.cancelled ? 5 : 4;
      final headerStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('FFDDEBF7'),
        horizontalAlign: HorizontalAlign.Center,
      );
      for (var column = 0; column < 4; column++) {
        sheet
                .cell(
                  CellIndex.indexByColumnRow(
                    columnIndex: column,
                    rowIndex: headerRow,
                  ),
                )
                .cellStyle =
            headerStyle;
      }

      final counts = <String, int>{
        'حاضر': 0,
        'غائب': 0,
        'غائب برخصة': 0,
        'بلا تسجيل': 0,
      };
      for (final row in rows) {
        counts.update(row['status']!, (value) => value + 1, ifAbsent: () => 0);
      }
      sheet.appendRow([
        TextCellValue('الإجمالي'),
        IntCellValue(rows.length),
        TextCellValue('حاضر: ${counts['حاضر']}'),
        TextCellValue(
          'غائب: ${counts['غائب']} · برخصة: ${counts['غائب برخصة']} · '
          'بلا تسجيل: ${counts['بلا تسجيل']}',
        ),
      ]);

      final bytes = workbook.encode();
      if (bytes == null || bytes.isEmpty) {
        throw StateError('تعذّر إنشاء ملف Excel');
      }
      return Uint8List.fromList(bytes);
    });
  }
}
