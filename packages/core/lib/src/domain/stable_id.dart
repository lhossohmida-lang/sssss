import 'package:uuid/uuid.dart';

/// معرّفات محسومة (UUID v5) للسجلات ذات المفتاح الطبيعي.
///
/// جهازان يعملان دون إنترنت قد يسجّلان نفس الحضور أو ينشئان نفس الحصة.
/// بمعرّف محسوم ينتجان نفس السجل، فيندمجان عند المزامنة بدل أن يرفض الخادم
/// أحدهما لتكرار المفتاح.
abstract final class StableId {
  static const String _namespace = '6f1d3c52-8b0a-5e1f-9c44-2a7b61d0e9aa';
  static const Uuid _uuid = Uuid();

  static String _of(String kind, List<Object> parts) =>
      _uuid.v5(_namespace, '$kind|${parts.join('|')}');

  /// حصة مجموعة في تاريخ ووقت بداية.
  static String session(String groupId, String date, int startMinutes) =>
      _of('session', [groupId, date, startMinutes]);

  /// حضور تلميذ في حصة.
  static String attendance(String sessionId, String studentId) =>
      _of('attendance', [sessionId, studentId]);

  /// حضور أستاذ لحصة.
  static String teacherAttendance(String teacherId, String sessionId) =>
      _of('teacher_attendance', [teacherId, sessionId]);

  /// سجل حضور عامل في يوم.
  static String workerAttendance(String workerId, String date) =>
      _of('worker_attendance', [workerId, date]);

  /// انتساب تلميذ إلى مجموعة.
  static String groupStudent(String groupId, String studentId) =>
      _of('group_student', [groupId, studentId]);

  /// تلميذ في قائمة انتظار.
  static String waitingEntry(String waitingListId, String studentId) =>
      _of('waiting_entry', [waitingListId, studentId]);

  /// حقوق تسجيل تلميذ في فترة.
  static String registrationFee(String studentId, String periodKey) =>
      _of('registration_fee', [studentId, periodKey]);

  /// رصيد غياب برخصة لتلميذ في حصة.
  static String excusedCredit(String sessionId, String studentId) =>
      _of('excused_credit', [sessionId, studentId]);

  /// رصيد الملتحق في منتصف دورة.
  static String midJoinCredit(String groupId, String studentId, int cycle) =>
      _of('mid_join_credit', [groupId, studentId, cycle]);

  /// خلاص اكتمال دورة لمجموعة.
  static String cyclePayout(String groupId, int cycle) =>
      _of('cycle_payout', [groupId, cycle]);

  /// عضو في غرفة محادثة.
  static String chatMember(String roomId, String userId) =>
      _of('chat_member', [roomId, userId]);

  /// غرفة خاصة واحدة بين حسابين، بصرف النظر عن أيّهما بدأ المحادثة.
  static String chatPrivateRoom(String firstUserId, String secondUserId) {
    final participants = [firstUserId, secondUserId]..sort();
    return _of('chat_private_room', participants);
  }

  /// غرفة المجموعة الوحيدة.
  static String chatGroupRoom(String groupId) =>
      _of('chat_group_room', [groupId]);

  /// مستوى دراسي افتراضي (طور ورقم)، فيتطابق على كل الأجهزة عند الإعداد الأول.
  static String defaultLevel(String stage, int grade) =>
      _of('default_level', [stage, grade]);

  /// قائمة انتظار مادة في مستوى ([levelId] فارغ = كل المستويات).
  static String waitingList(String subjectId, String? levelId) =>
      _of('waiting_list', [subjectId, levelId ?? '']);

  /// نوع المصروف الذي له اسم طبيعي.
  static String expenseCategory(String normalizedName) =>
      _of('expense_category', [normalizedName]);

  /// نوع أجور العمال المحجوز لكل الأجهزة.
  static String workerWagesCategory() => _of('worker_wages_category', const []);

  /// مصروف أجر عامل لشهر؛ إعادة تسجيله تحدّث السجل نفسه.
  static String workerWageExpense(String workerId, String month) =>
      _of('worker_wage_expense', [workerId, month]);

  /// خط نقل باسم طبيعي؛ يعيد الاسم نفسه معرّفاً على كل جهاز.
  static String transportLine(String normalizedName) =>
      _of('transport_line', [normalizedName]);
}
