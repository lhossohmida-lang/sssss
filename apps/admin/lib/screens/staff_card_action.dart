import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

/// يبني بطاقة الأستاذ أو العامل PDF (اسم المدرسة وشعارها من الإعدادات، وصورته
/// المحلية إن وُجدت) ويعرضها للمعاينة والطباعة والمشاركة. رمزها يُمسح في ماسح
/// المدخل فيسجّل الدخول ثم الخروج.
Future<void> showStaffCard(
  BuildContext context,
  WidgetRef ref, {
  required String id,
  required String name,
  required String role,
  required String qrCode,
  String? phone,
  String? photoLocalPath,
}) async {
  final settings = await ref.read(settingsServiceProvider).load();
  final logoFile = await ref.read(logoServiceProvider).resolve();
  final photoFile = photoLocalPath == null || photoLocalPath.isEmpty
      ? null
      : File(photoLocalPath);
  final data = StaffCardData(
    schoolName: settings.schoolName.isEmpty ? 'المدرسة' : settings.schoolName,
    name: name,
    role: role,
    qrCode: qrCode,
    phone: phone,
    logo: logoFile == null ? null : await logoFile.readAsBytes(),
    photo: photoFile != null && photoFile.existsSync()
        ? await photoFile.readAsBytes()
        : null,
  );
  final font = await rootBundle.load(
    'packages/school_ui/assets/fonts/Cairo.ttf',
  );
  final bytes = await StaffCard.build(
    data,
    fontData: font.buffer.asUint8List(font.offsetInBytes, font.lengthInBytes),
  );
  if (!context.mounted) return;
  await ref
      .read(pdfPresenterProvider)
      .show(
        context,
        bytes: bytes,
        fileName: 'staff-card-$id.pdf',
        title: 'بطاقة $name',
      );
}
