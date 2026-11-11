import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

void main() {
  test('كل قيمة تُسترجع من رمزها المخزَّن', () {
    for (final v in UserRole.values) {
      expect(UserRole.fromCode(v.code), v);
    }
    for (final v in SessionStatus.values) {
      expect(SessionStatus.fromCode(v.code), v);
    }
    for (final v in AttendanceStatus.values) {
      expect(AttendanceStatus.fromCode(v.code), v);
    }
    for (final v in AttendanceMethod.values) {
      expect(AttendanceMethod.fromCode(v.code), v);
    }
    for (final v in SessionRequestType.values) {
      expect(SessionRequestType.fromCode(v.code), v);
    }
    for (final v in SessionRequestStatus.values) {
      expect(SessionRequestStatus.fromCode(v.code), v);
    }
    for (final v in PaymentType.values) {
      expect(PaymentType.fromCode(v.code), v);
    }
    for (final v in DiscountType.values) {
      expect(DiscountType.fromCode(v.code), v);
    }
    for (final v in WorkDayKind.values) {
      expect(WorkDayKind.fromCode(v.code), v);
    }
    for (final v in SmsStatus.values) {
      expect(SmsStatus.fromCode(v.code), v);
    }
    for (final v in ChatRoomType.values) {
      expect(ChatRoomType.fromCode(v.code), v);
    }
    for (final v in FeePeriod.values) {
      expect(FeePeriod.fromCode(v.code), v);
    }
  });

  test('الرموز المخزَّنة فريدة داخل كل نوع', () {
    expect(SessionStatus.values.map((v) => v.code).toSet(), hasLength(4));
    expect(SessionRequestType.values.map((v) => v.code).toSet(), hasLength(4));
    expect(PaymentType.values.map((v) => v.code).toSet(), hasLength(3));
  });

  test('الرمز المجهول يرمي خطأ', () {
    expect(() => UserRole.fromCode('x'), throwsArgumentError);
  });

  test('الحصة الملغاة وحدها لا تُحسب ضمن الدورة', () {
    expect(SessionStatus.cancelled.countsInCycle, isFalse);
    expect(SessionStatus.normal.countsInCycle, isTrue);
    expect(SessionStatus.makeup.countsInCycle, isTrue);
    expect(SessionStatus.added.countsInCycle, isTrue);
  });

  test('خصائص أنواع الطلبات', () {
    expect(SessionRequestType.cancel.needsNewSlot, isFalse);
    expect(SessionRequestType.reschedule.needsNewSlot, isTrue);
    expect(SessionRequestType.addSession.targetsExistingSession, isFalse);
    expect(SessionRequestType.advance.targetsExistingSession, isTrue);
  });

  test('المدير والعامل يستعملان تطبيق الإدارة', () {
    expect(UserRole.owner.usesAdminApp, isTrue);
    expect(UserRole.worker.usesAdminApp, isTrue);
    expect(UserRole.teacher.usesAdminApp, isFalse);
    expect(UserRole.parent.usesAdminApp, isFalse);
  });
}
