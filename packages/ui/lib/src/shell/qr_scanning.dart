import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:school_core/school_core.dart';

import '../clay/clay_display.dart';
import '../clay/clay_icons.dart';

/// مصدر رموز QR ممسوحة: كاميرا الهاتف، أو قارئ USB، أو مسح هاتف بعيد.
///
/// تُمرَّر النصوص الخام كما قُرئت، ويعالجها `ScanService`. المصدر الحقيقي
/// يعتمد على عتاد لا يوجد في الاختبارات، فيُستبدل فيها بنسخة وهمية.
abstract interface class QrCodeSource {
  /// الرموز المقروءة بترتيب وصولها.
  Stream<String> get codes;

  /// معاينة تُعرض في الشاشة (كاميرا حية)، أو عنصر فارغ إن لم يكن للمصدر.
  Widget buildPreview(BuildContext context);

  /// يبدأ القراءة.
  Future<void> start();

  /// يوقف القراءة ويحرّر العتاد.
  Future<void> dispose();
}

/// مصنع كاميرا المسح؛ فارغ حيث لا كاميرا مسح (Windows)، ويضبطه تطبيق
/// الإدارة على Android.
final Provider<QrCodeSource Function()?> qrCameraFactoryProvider =
    Provider<QrCodeSource Function()?>((ref) => null);

/// تغذية المسح الراجعة: اهتزاز وصوت يميّزان النجاح من التنبيه من الخطأ.
abstract interface class ScanFeedback {
  Future<void> success();
  Future<void> warning();
  Future<void> failure();
}

/// تغذية الجهاز: اهتزاز خفيف عند النجاح، وأقوى عند الخطأ، مع صوت النظام.
class SystemScanFeedback implements ScanFeedback {
  const SystemScanFeedback();

  @override
  Future<void> success() async {
    await SystemSound.play(SystemSoundType.click);
    await HapticFeedback.lightImpact();
  }

  @override
  Future<void> warning() async {
    await SystemSound.play(SystemSoundType.alert);
    await HapticFeedback.mediumImpact();
  }

  @override
  Future<void> failure() async {
    await SystemSound.play(SystemSoundType.alert);
    await HapticFeedback.heavyImpact();
  }
}

final Provider<ScanFeedback> scanFeedbackProvider = Provider<ScanFeedback>(
  (ref) => const SystemScanFeedback(),
);

/// كيف تُعرض نتيجة مسح: العنوان والتفاصيل ولون الحالة وأيقونتها.
class ScanPresentation {
  const ScanPresentation({
    required this.headline,
    required this.detail,
    required this.tone,
    required this.icon,
  });

  final String headline;
  final String detail;
  final ClayTone tone;
  final IconData icon;

  /// هل يُعدّ نجاحاً (صوت التأكيد)؟
  bool get isSuccess => tone == ClayTone.success;

  /// هل هو خطأ (رمز مجهول أو لا حصة)؟
  bool get isFailure => tone == ClayTone.danger;

  /// ينفّذ التغذية الراجعة المناسبة.
  Future<void> play(ScanFeedback feedback) => isSuccess
      ? feedback.success()
      : isFailure
      ? feedback.failure()
      : feedback.warning();

  /// عرض نتيجة [result]. تُهمل `repeated` (قراءة مزدوجة) فلا تُعرض.
  static ScanPresentation? of(ScanResult result) {
    final group = [
      if (result.groupNumber != null) 'المجموعة ${result.groupNumber}',
      if (result.subjectName != null) result.subjectName!,
      if (result.roomName != null) result.roomName!,
    ].join(' · ');
    final late = result.lateMinutes > 0
        ? 'متأخر ${result.lateMinutes} د'
        : 'في الوقت';
    return switch (result.outcome) {
      ScanOutcome.repeated => null,
      ScanOutcome.studentOk => ScanPresentation(
        headline: 'حاضر',
        detail: group,
        tone: ClayTone.success,
        icon: ClayIcons.check,
      ),
      ScanOutcome.studentDues => ScanPresentation(
        headline: 'حاضر — عليه مستحقات',
        detail: group.isEmpty
            ? 'يُنبَّه وليّه لتسوية المستحقات'
            : '$group\nيُنبَّه وليّه لتسوية المستحقات',
        tone: ClayTone.warning,
        icon: ClayIcons.dues,
      ),
      ScanOutcome.studentNoSession => const ScanPresentation(
        headline: 'لا حصة له الآن',
        detail: 'لم يُسجَّل حضوره',
        tone: ClayTone.danger,
        icon: ClayIcons.close,
      ),
      ScanOutcome.studentAlreadyPresent => ScanPresentation(
        headline: 'حضوره مسجَّل مسبقاً',
        detail: group,
        tone: ClayTone.info,
        icon: ClayIcons.check,
      ),
      ScanOutcome.teacherIn => ScanPresentation(
        headline: 'دخول الأستاذ',
        detail: group.isEmpty ? late : '$group\n$late',
        tone: ClayTone.success,
        icon: ClayIcons.teachers,
      ),
      ScanOutcome.teacherOut => ScanPresentation(
        headline: 'خروج الأستاذ',
        detail: group,
        tone: ClayTone.info,
        icon: ClayIcons.teachers,
      ),
      ScanOutcome.teacherGeneralIn => const ScanPresentation(
        headline: 'دخول عام للأستاذ',
        detail: 'لا حصة له الآن',
        tone: ClayTone.warning,
        icon: ClayIcons.teachers,
      ),
      ScanOutcome.workerIn => ScanPresentation(
        headline: 'دخول العامل',
        detail: late,
        tone: ClayTone.success,
        icon: ClayIcons.workers,
      ),
      ScanOutcome.workerOut => const ScanPresentation(
        headline: 'خروج العامل',
        detail: '',
        tone: ClayTone.info,
        icon: ClayIcons.workers,
      ),
      ScanOutcome.unknown => const ScanPresentation(
        headline: 'رمز غير معروف',
        detail: 'ليس من رموز المدرسة',
        tone: ClayTone.danger,
        icon: ClayIcons.close,
      ),
    };
  }
}
