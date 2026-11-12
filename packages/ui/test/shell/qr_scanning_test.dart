import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';
import 'package:school_ui/testing.dart';

void main() {
  ScanPresentation present(
    ScanOutcome outcome, {
    int late = 0,
    int? group,
    String? subject,
    String? room,
  }) => ScanPresentation.of(
    ScanResult(
      outcome: outcome,
      lateMinutes: late,
      groupNumber: group,
      subjectName: subject,
      roomName: room,
    ),
  )!;

  test('التلميذ: أخضر للحاضر وبرتقالي لمن عليه مستحقات وأحمر بلا حصة', () {
    final ok = present(
      ScanOutcome.studentOk,
      group: 2,
      subject: 'رياضيات',
      room: 'القاعة 1',
    );
    expect(ok.tone, ClayTone.success);
    expect(ok.headline, 'حاضر');
    expect(ok.detail, 'المجموعة 2 · رياضيات · القاعة 1');
    expect(ok.isSuccess, isTrue);

    final dues = present(ScanOutcome.studentDues, group: 2);
    expect(dues.tone, ClayTone.warning);
    expect(dues.headline, contains('مستحقات'));
    expect(dues.detail, contains('المجموعة 2'));
    expect(dues.isSuccess, isFalse);
    expect(dues.isFailure, isFalse);

    final none = present(ScanOutcome.studentNoSession);
    expect(none.tone, ClayTone.danger);
    expect(none.isFailure, isTrue);
  });

  test('تلميذ حاضر مسبقاً: معلومة لا خطأ', () {
    final again = present(ScanOutcome.studentAlreadyPresent, group: 1);
    expect(again.tone, ClayTone.info);
    expect(again.headline, 'حضوره مسجَّل مسبقاً');
  });

  test('الأستاذ والعامل: الدخول بتأخره، والخروج معلومة، والعام تنبيه', () {
    expect(present(ScanOutcome.teacherIn, late: 12).detail, contains('12'));
    expect(present(ScanOutcome.teacherIn).detail, 'في الوقت');
    expect(present(ScanOutcome.teacherOut).tone, ClayTone.info);
    expect(present(ScanOutcome.teacherGeneralIn).tone, ClayTone.warning);
    expect(present(ScanOutcome.workerIn, late: 3).detail, 'متأخر 3 د');
    expect(present(ScanOutcome.workerOut).headline, 'خروج العامل');
  });

  test('الرمز المجهول أحمر، والقراءة المزدوجة لا تُعرض', () {
    expect(present(ScanOutcome.unknown).isFailure, isTrue);
    expect(
      ScanPresentation.of(const ScanResult(outcome: ScanOutcome.repeated)),
      isNull,
    );
  });

  test('لكل نتيجة معروضة نص وأيقونة', () {
    for (final outcome in ScanOutcome.values) {
      if (outcome == ScanOutcome.repeated) continue;
      final p = present(outcome);
      expect(p.headline, isNotEmpty, reason: '$outcome');
    }
  });

  test('التغذية الراجعة: نجاح ثم تنبيه ثم خطأ حسب اللون', () async {
    final feedback = RecordingScanFeedback();
    await present(ScanOutcome.studentOk).play(feedback);
    await present(ScanOutcome.studentDues).play(feedback);
    await present(ScanOutcome.unknown).play(feedback);
    await present(ScanOutcome.teacherOut).play(feedback);
    expect(feedback.events, ['success', 'warning', 'failure', 'warning']);
  });
}
