import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../data/local/app_database.dart';
import 'attendance_pdf.dart';
import 'attendance_service.dart';
import 'date_key.dart';
import 'device_preferences.dart';
import 'settings_service.dart';

/// نتيجة جولة أرشفة: عدد النسخ الجديدة، وخطأ إن توقفت.
class AttendanceArchiveReport {
  const AttendanceArchiveReport({this.written = 0, this.error});

  final int written;
  final String? error;
}

/// أرشيف سجل الحضور: نسخة PDF من سجل كل حصة تنتهي، في مجلد يحدده المدير من الإعدادات.
///
/// - تُنتَج **نسخة جديدة** لكل حصة جديدة، ولا تُحدَّث نسخة قائمة ولا تُستبدل (تصحيح الحضور بعد
///   إغلاق الحصة لا يغيّر نسختها؛ فهي صورة الحصة كما أُغلقت).
/// - لكل أفواج المدرسة، بلا استثناء، ما دامت الحصة أُغلقت على أي جهاز وبلغ هذا الجهاز.
/// - المجلد خاص بهذا الجهاز (مسار على قرصه) فلا يُزامَن: يضبطه المدير على الحاسوب الذي يريد الأرشيف
///   عليه (انظر [DevicePreferences]).
/// - لا تُنسخ حصص أُغلقت قبل ضبط المجلد؛ تبدأ النسخ من لحظة الضبط.
class AttendanceArchiveService {
  AttendanceArchiveService({
    required this.db,
    required this.attendance,
    required this.settings,
    required this.preferences,
    required this.fontLoader,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase db;
  final AttendanceService attendance;
  final SettingsService settings;
  final DevicePreferences preferences;

  /// يحمّل خط Cairo (من أصول التطبيق) لتشكيل الحروف العربية في الملف.
  final Future<Uint8List> Function() fontLoader;
  final DateTime Function() _clock;

  /// مفتاح مجلد الأرشيف في تفضيلات الجهاز.
  static const String folderKey = 'attendance_pdf_folder';

  /// وقت ضبط المجلد (مللي ثانية): لا تُنسخ حصص أُغلقت قبله.
  static const String sinceKey = 'attendance_pdf_since';

  /// علامة «نُسخت» لكل حصة: `attendance_pdf:<sessionId>`.
  static const String doneKeyPrefix = 'attendance_pdf:';

  /// أقدم إغلاق تُراجَع حصته في كل جولة: يلحق بها ما وصل متأخراً من أجهزة أخرى.
  static const Duration lookback = Duration(days: 60);

  bool _running = false;

  /// المجلد المضبوط، أو `null` إن لم يُضبط (الأرشفة متوقفة).
  Future<String?> folder() => preferences.read(folderKey);

  /// المجلد وتتحدث عند تغييره.
  Stream<String?> watchFolder() => preferences.watch(folderKey);

  /// يضبط مجلد الأرشيف (يُنشأ إن لم يوجد ويُجرَّب الكتابة فيه)، أو يوقف الأرشفة إن كان فارغاً.
  /// يرمي [FileSystemException] إن تعذّرت الكتابة فيه.
  Future<void> setFolder(String? path) async {
    final clean = path?.trim() ?? '';
    if (clean.isEmpty) {
      await preferences.write(folderKey, null);
      return;
    }
    final directory = Directory(clean);
    await directory.create(recursive: true);
    final probe = File(p.join(clean, '.write-test'));
    await probe.writeAsString('ok', flush: true);
    await probe.delete();
    await preferences.write(folderKey, clean);
    if (await preferences.read(sinceKey) == null) {
      await preferences.write(sinceKey, '${_nowMillis()}');
    }
  }

  /// ينسخ سجل كل حصة أُغلقت ولم تُنسخ بعد. آمن عند التكرار ولا يتداخل تشغيلان.
  Future<AttendanceArchiveReport> archiveNew() async {
    if (_running) return const AttendanceArchiveReport();
    _running = true;
    try {
      final target = await folder();
      if (target == null) return const AttendanceArchiveReport();
      final since = int.tryParse(await preferences.read(sinceKey) ?? '') ?? 0;
      final windowStart = _max(since, _nowMillis() - lookback.inMilliseconds);

      final closed = await db
          .customSelect(
            'SELECT se.id, se.closed_at FROM sessions se '
            'WHERE se.deleted_at IS NULL AND se.closed_at IS NOT NULL '
            "AND se.closed_at >= ? AND se.status <> 'cancelled' "
            'ORDER BY se.closed_at, se.id',
            variables: [Variable<int>(windowStart)],
            readsFrom: {db.sessions},
          )
          .get();
      if (closed.isEmpty) return const AttendanceArchiveReport();

      final done = await _doneIds([
        for (final row in closed) row.read<String>('id'),
      ]);
      final pending = [
        for (final row in closed)
          if (!done.contains(row.read<String>('id'))) row.read<String>('id'),
      ];
      if (pending.isEmpty) return const AttendanceArchiveReport();

      final config = await settings.load();
      final font = await fontLoader();
      var written = 0;
      for (final id in pending) {
        try {
          final roster = await attendance.roster(id);
          if (roster == null) continue;
          final file = File(
            p.join(target, roster.session.date, _fileName(roster)),
          );
          // نسخة موجودة لا تُستبدل أبداً.
          if (!file.existsSync()) {
            final bytes = await AttendancePdf.build(
              AttendanceSheetData(
                schoolName: config.schoolName,
                schoolAddress: config.schoolAddress,
                schoolPhone: config.schoolPhone,
                subjectName: roster.subjectName,
                groupNumber: roster.groupNumber,
                teacherName: roster.teacherName,
                date: roster.session.date,
                startMinutes: roster.session.startMinutes,
                endMinutes: roster.session.endMinutes,
                sessionNumber: roster.session.sessionNumber,
                cycleNumber: roster.session.cycleNumber,
                generatedAt: _clock(),
                rows: [
                  for (final student in roster.students)
                    AttendanceSheetRow(
                      name: student.name,
                      status: student.status,
                      method: student.method,
                    ),
                ],
              ),
              fontData: font,
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes, flush: true);
            written++;
          }
          await preferences.write('$doneKeyPrefix$id', '1');
        } on Object catch (error) {
          // لا تُعلَّم الحصة منسوخة: تُعاد المحاولة في الجولة التالية.
          return AttendanceArchiveReport(written: written, error: '$error');
        }
      }
      return AttendanceArchiveReport(written: written);
    } finally {
      _running = false;
    }
  }

  /// اسم الملف: المادة والفوج والوقت ثم أول أحرف معرّف الحصة ليبقى فريداً.
  static String _fileName(SessionRoster roster) {
    final session = roster.session;
    final time = DateKey.formatMinutes(session.startMinutes)
        .replaceAll(':', '');
    final subject = safeName(roster.subjectName);
    final id = session.id.length > 6 ? session.id.substring(0, 6) : session.id;
    return '$subject-فوج${roster.groupNumber}-$time-$id.pdf';
  }

  /// نص صالح اسماً لملف على ويندوز وأندرويد.
  static String safeName(String value) {
    final cleaned = value
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|\u0000-\u001f]'), '-')
        .replaceAll(RegExp(r'\s+'), '_');
    if (cleaned.isEmpty) return 'حصة';
    return cleaned.length > 40 ? cleaned.substring(0, 40) : cleaned;
  }

  Future<Set<String>> _doneIds(List<String> ids) async {
    final done = <String>{};
    for (var start = 0; start < ids.length; start += 300) {
      final chunk = ids.sublist(start, (start + 300).clamp(0, ids.length));
      final marks = List.filled(chunk.length, '?').join(', ');
      final rows = await db
          .customSelect(
            'SELECT key FROM device_info WHERE key IN ($marks)',
            variables: [
              for (final id in chunk) Variable<String>('$doneKeyPrefix$id'),
            ],
            readsFrom: {db.deviceInfo},
          )
          .get();
      for (final row in rows) {
        done.add(row.read<String>('key').substring(doneKeyPrefix.length));
      }
    }
    return done;
  }

  int _nowMillis() => _clock().toUtc().millisecondsSinceEpoch;

  static int _max(int a, int b) => a > b ? a : b;
}
