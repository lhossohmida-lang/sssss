import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

/// بيانات بطاقة التلميذ من ملفه: اسم المدرسة وشعارها من الإعدادات وصورته
/// المحلية إن وُجدت.
Future<StudentCardData> studentCardData(
  WidgetRef ref,
  StudentProfile profile,
) async {
  final settings = await ref.read(settingsServiceProvider).load();
  final logoFile = await ref.read(logoServiceProvider).resolve();
  final photoPath = profile.student.photoLocalPath;
  final photoFile = photoPath == null || photoPath.isEmpty
      ? null
      : File(photoPath);
  return StudentCardData(
    schoolName: settings.schoolName.isEmpty ? 'المدرسة' : settings.schoolName,
    studentName: profile.fullName,
    qrCode: profile.student.qrCode,
    levelName: profile.levelName,
    parentPhone: profile.student.parentPhone,
    logo: logoFile == null ? null : await logoFile.readAsBytes(),
    photo: photoFile != null && photoFile.existsSync()
        ? await photoFile.readAsBytes()
        : null,
  );
}

/// يبني بطاقة التلميذ PDF ويعرضها للمعاينة والطباعة والمشاركة.
Future<void> showStudentCard(
  BuildContext context,
  WidgetRef ref,
  StudentProfile profile,
) async {
  final data = await studentCardData(ref, profile);
  final font = await rootBundle.load(
    'packages/school_ui/assets/fonts/Cairo.ttf',
  );
  final bytes = await StudentCard.build(
    data,
    fontData: font.buffer.asUint8List(font.offsetInBytes, font.lengthInBytes),
  );
  if (!context.mounted) return;
  await ref
      .read(pdfPresenterProvider)
      .show(
        context,
        bytes: bytes,
        fileName: 'student-card-${profile.student.id}.pdf',
        title: 'بطاقة ${profile.fullName}',
      );
}
