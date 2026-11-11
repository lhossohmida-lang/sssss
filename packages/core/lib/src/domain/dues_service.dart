import 'package:drift/drift.dart';

import '../data/local/app_database.dart';
import '../data/local/sync_writer.dart';
import 'enums.dart';
import 'pricing.dart';

/// مستحقات التلاميذ ومدفوعاتهم.
///
/// - الشهر (الدورة) يُدفع كاملاً ومسبقاً حتى لو غاب التلميذ.
/// - الغياب برخصة يصير رصيداً يُخصم من الدورة التالية.
/// - الملتحق في منتصف الدورة يدفع الشهر كاملاً، وقيمة ما فاته رصيد للدورة
///   التالية.
/// - حقوق التسجيل مرة واحدة لكل تلميذ في الفترة مهما كان عدد المواد.
/// - النقل سعر شهري منفصل حسب شهر التقويم.
class DuesService {
  DuesService(this.db, this.writer);

  final AppDatabase db;
  final SyncWriter writer;

  static const String reasonExcused = 'excused';
  static const String reasonMidJoin = 'mid_join';
  static const String reasonManual = 'manual';

  // ---------------------------------------------------------------------------
  // مستحقات الدورات
  // ---------------------------------------------------------------------------

  /// مستحقات الدورات (من دورة الالتحاق إلى الدورة الحالية) باستعلام مجمّع.
  ///
  /// يمكن الحصر بتلميذ أو مجموعة أو دورة. مع [unpaidOnly] تُعاد غير المسدَّدة
  /// فقط.
  Future<List<CycleDue>> cycleDues({
    String? studentId,
    String? groupId,
    int? cycleNumber,
    bool unpaidOnly = false,
  }) async {
    final filters = StringBuffer();
    final variables = <Variable<Object>>[];
    if (studentId != null) {
      filters.write(' AND gs.student_id = ?');
      variables.add(Variable<String>(studentId));
    }
    if (groupId != null) {
      filters.write(' AND gs.group_id = ?');
      variables.add(Variable<String>(groupId));
    }
    final cycleFilter = cycleNumber == null ? '' : ' WHERE l.cycle = ?';
    if (cycleNumber != null) variables.add(Variable<int>(cycleNumber));

    final rows = await db
        .customSelect(
          '''
WITH RECURSIVE liability(student_id, group_id, cycle, last_cycle, price,
                         discount_type, discount_value) AS (
  SELECT gs.student_id, gs.group_id, gs.joined_at_cycle_number,
         CASE
           WHEN gs.left_at IS NULL THEN g.current_cycle_number
           ELSE MIN(
             g.current_cycle_number,
             COALESCE(
               (SELECT MAX(s.cycle_number) FROM sessions s
                 WHERE s.group_id = gs.group_id AND s.deleted_at IS NULL
                   AND s.date <= strftime('%Y-%m-%d', gs.left_at / 1000,
                                          'unixepoch', 'localtime')),
               gs.joined_at_cycle_number))
         END,
         gs.monthly_price, gs.discount_type, gs.discount_value
    FROM group_students gs
    JOIN groups g ON g.id = gs.group_id
   WHERE gs.deleted_at IS NULL AND g.deleted_at IS NULL$filters
  UNION ALL
  SELECT student_id, group_id, cycle + 1, last_cycle, price,
         discount_type, discount_value
    FROM liability
   WHERE cycle < last_cycle
)
SELECT l.student_id, l.group_id, l.cycle, l.price, l.discount_type,
       l.discount_value,
       COALESCE((SELECT SUM(c.amount) FROM student_credits c
                  WHERE c.student_id = l.student_id
                    AND c.group_id = l.group_id
                    AND c.target_cycle_number = l.cycle
                    AND c.deleted_at IS NULL), 0) AS credits,
       COALESCE((SELECT SUM(p.amount) FROM payments p
                  WHERE p.group_id = l.group_id
                    AND p.cycle_number = l.cycle
                    AND p.student_id = l.student_id
                    AND p.type = 'month'
                    AND p.deleted_at IS NULL), 0) AS paid
  FROM liability l$cycleFilter
 ORDER BY l.student_id, l.group_id, l.cycle
''',
          variables: variables,
          readsFrom: {
            db.groupStudents,
            db.groups,
            db.sessions,
            db.studentCredits,
            db.payments,
          },
        )
        .get();

    final dues = <CycleDue>[];
    for (final row in rows) {
      final type = DiscountType.fromCode(row.read<String>('discount_type'));
      final due = CycleDue(
        studentId: row.read<String>('student_id'),
        groupId: row.read<String>('group_id'),
        cycleNumber: row.read<int>('cycle'),
        netPrice: Pricing.netPrice(
          price: row.read<int>('price'),
          discountType: type,
          discountValue: row.read<int>('discount_value'),
        ),
        credits: row.read<int>('credits'),
        paid: row.read<int>('paid'),
        exempt: type == DiscountType.exempt,
      );
      if (!unpaidOnly || !due.isSettled) dues.add(due);
    }
    return dues;
  }

  /// مستحق تلميذ في مجموعة عن دورة محددة، أو `null` إن لم يكن ملزَماً بها.
  Future<CycleDue?> cycleDue({
    required String studentId,
    required String groupId,
    required int cycleNumber,
  }) async {
    final dues = await cycleDues(
      studentId: studentId,
      groupId: groupId,
      cycleNumber: cycleNumber,
    );
    return dues.isEmpty ? null : dues.single;
  }

  /// هل «عليه مستحقات» في هذه المجموعة؟ (اللون البرتقالي عند المسح)
  ///
  /// نعم إن لم يسدّد دورة سابقة، أو لم يسدّد الدورة الحالية وقد انعقد منها
  /// [graceSessions] حصة أو أكثر.
  Future<bool> hasOutstanding({
    required String studentId,
    required String groupId,
    int graceSessions = 2,
  }) async {
    final unpaid = await cycleDues(
      studentId: studentId,
      groupId: groupId,
      unpaidOnly: true,
    );
    if (unpaid.isEmpty) return false;
    final group = await (db.select(
      db.groups,
    )..where((g) => g.id.equals(groupId))).getSingle();
    if (unpaid.any((d) => d.cycleNumber < group.currentCycleNumber)) {
      return true;
    }
    final held = await db
        .customSelect(
          'SELECT COUNT(*) AS c FROM sessions WHERE group_id = ? '
          'AND cycle_number = ? AND deleted_at IS NULL '
          "AND status <> 'cancelled' AND closed_at IS NOT NULL",
          variables: [
            Variable<String>(groupId),
            Variable<int>(group.currentCycleNumber),
          ],
          readsFrom: {db.sessions},
        )
        .getSingle();
    return held.read<int>('c') >= graceSessions;
  }

  /// يسجّل دفعة (كاملة أو جزئية) عن دورة. يرفض ما يزيد عن الباقي.
  Future<PaymentRow> recordMonthPayment({
    required String studentId,
    required String groupId,
    required int cycleNumber,
    required int amount,
    required String receivedBy,
    required String receiptNumber,
    String note = '',
  }) {
    return db.transaction(() async {
      final due = await cycleDue(
        studentId: studentId,
        groupId: groupId,
        cycleNumber: cycleNumber,
      );
      if (due == null) {
        throw StateError('التلميذ غير ملزَم بهذه الدورة في هذه المجموعة');
      }
      _checkAmount(amount, due.remaining);
      return _insertPayment(
        studentId: studentId,
        type: PaymentType.month,
        groupId: groupId,
        cycleNumber: cycleNumber,
        amount: amount,
        receivedBy: receivedBy,
        receiptNumber: receiptNumber,
        note: note,
      );
    });
  }

  // ---------------------------------------------------------------------------
  // الأرصدة
  // ---------------------------------------------------------------------------

  /// يطابق رصيد الغياب برخصة مع حالة الحضور: ينشئه إن صار الغياب برخصة،
  /// ويحذفه إن تغيّرت الحالة. آمن عند التكرار.
  Future<void> syncExcusedCredit({
    required String sessionId,
    required String studentId,
  }) {
    return db.transaction(() async {
      final session = await (db.select(
        db.sessions,
      )..where((s) => s.id.equals(sessionId))).getSingle();
      final attendance =
          await (db.select(db.attendance)..where(
                (a) =>
                    a.sessionId.equals(sessionId) &
                    a.studentId.equals(studentId) &
                    a.deletedAt.isNull(),
              ))
              .getSingleOrNull();
      final existing =
          await (db.select(db.studentCredits)..where(
                (c) =>
                    c.sessionId.equals(sessionId) &
                    c.studentId.equals(studentId) &
                    c.reason.equals(reasonExcused) &
                    c.deletedAt.isNull(),
              ))
              .getSingleOrNull();
      final excused = attendance?.status == AttendanceStatus.excused.code;

      if (!excused) {
        if (existing != null) {
          await writer.softDelete(db.studentCredits, key: {'id': existing.id});
        }
        return;
      }
      if (existing != null) return;

      final enrolment = await _enrolment(studentId, session.groupId);
      if (enrolment == null) return;
      final group = await _group(session.groupId);
      final amount = Pricing.sessionsValue(
        netPrice: _net(enrolment),
        sessions: 1,
        sessionsPerCycle: group.sessionsPerCycle,
      );
      if (amount == 0) return;
      await _insertCredit(
        studentId: studentId,
        groupId: session.groupId,
        amount: amount,
        reason: reasonExcused,
        sourceCycle: session.cycleNumber,
        sessionId: sessionId,
      );
    });
  }

  /// ينشئ رصيد الملتحق في منتصف الدورة: قيمة الحصص التي فاتته قبل التحاقه
  /// تُخصم من الدورة التالية. يعيد المبلغ (0 إن التحق من بداية الدورة).
  Future<int> createMidJoinCredit({
    required String studentId,
    required String groupId,
  }) {
    return db.transaction(() async {
      final enrolment = await _enrolment(studentId, groupId);
      if (enrolment == null) {
        throw StateError('التلميذ غير منتسب إلى هذه المجموعة');
      }
      final already =
          await (db.select(db.studentCredits)..where(
                (c) =>
                    c.studentId.equals(studentId) &
                    c.groupId.equals(groupId) &
                    c.reason.equals(reasonMidJoin) &
                    c.sourceCycleNumber.equals(enrolment.joinedAtCycleNumber) &
                    c.deletedAt.isNull(),
              ))
              .getSingleOrNull();
      if (already != null) return already.amount;

      final group = await _group(groupId);
      final amount = Pricing.sessionsValue(
        netPrice: _net(enrolment),
        sessions: enrolment.joinedAtSessionNumber - 1,
        sessionsPerCycle: group.sessionsPerCycle,
      );
      if (amount == 0) return 0;
      await _insertCredit(
        studentId: studentId,
        groupId: groupId,
        amount: amount,
        reason: reasonMidJoin,
        sourceCycle: enrolment.joinedAtCycleNumber,
      );
      return amount;
    });
  }

  // ---------------------------------------------------------------------------
  // حقوق التسجيل
  // ---------------------------------------------------------------------------

  /// يضمن وجود حقوق التسجيل للتلميذ في الفترة مرة واحدة فقط، مهما تكرر
  /// الاستدعاء ومهما كان عدد المواد.
  Future<RegistrationFeeRow> ensureRegistrationFee({
    required String studentId,
    required String periodKey,
    required int amount,
  }) {
    return db.transaction(() async {
      final existing = await _fee(studentId, periodKey);
      if (existing != null) return existing;
      final stamp = writer.now();
      final fee = RegistrationFeeRow(
        id: writer.newId(),
        createdAt: stamp,
        updatedAt: stamp,
        studentId: studentId,
        periodKey: periodKey,
        amount: amount,
        paid: amount == 0,
      );
      await writer.save(db.registrationFees, fee, key: {'id': fee.id});
      return fee;
    });
  }

  /// الباقي من حقوق التسجيل للتلميذ في الفترة.
  Future<int> registrationFeeRemaining({
    required String studentId,
    required String periodKey,
  }) async {
    final fee = await _fee(studentId, periodKey);
    if (fee == null) return 0;
    final paid = await _paidFor(
      studentId: studentId,
      type: PaymentType.registrationFee,
      periodKey: periodKey,
    );
    final remaining = fee.amount - paid;
    return remaining < 0 ? 0 : remaining;
  }

  /// يسجّل دفع حقوق التسجيل ويعلّمها مدفوعة عند اكتمال المبلغ.
  Future<PaymentRow> payRegistrationFee({
    required String studentId,
    required String periodKey,
    required int amount,
    required String receivedBy,
    required String receiptNumber,
  }) {
    return db.transaction(() async {
      final fee = await _fee(studentId, periodKey);
      if (fee == null) {
        throw StateError('لا توجد حقوق تسجيل لهذا التلميذ في هذه الفترة');
      }
      final remaining = await registrationFeeRemaining(
        studentId: studentId,
        periodKey: periodKey,
      );
      _checkAmount(amount, remaining);
      final payment = await _insertPayment(
        studentId: studentId,
        type: PaymentType.registrationFee,
        periodKey: periodKey,
        amount: amount,
        receivedBy: receivedBy,
        receiptNumber: receiptNumber,
      );
      if (amount == remaining) {
        await writer.save(
          db.registrationFees,
          fee.copyWith(paid: true),
          key: {'id': fee.id},
        );
      }
      return payment;
    });
  }

  // ---------------------------------------------------------------------------
  // النقل
  // ---------------------------------------------------------------------------

  /// الباقي من سعر النقل لشهر التقويم [month] بصيغة `YYYY-MM`.
  Future<int> transportRemaining({
    required String studentId,
    required String month,
  }) async {
    final student = await (db.select(
      db.students,
    )..where((s) => s.id.equals(studentId))).getSingle();
    if (!student.usesTransport) return 0;
    final paid = await _paidFor(
      studentId: studentId,
      type: PaymentType.transport,
      periodKey: month,
    );
    final remaining = student.transportPrice - paid;
    return remaining < 0 ? 0 : remaining;
  }

  /// يسجّل دفع النقل لشهر التقويم [month].
  Future<PaymentRow> payTransport({
    required String studentId,
    required String month,
    required int amount,
    required String receivedBy,
    required String receiptNumber,
  }) {
    return db.transaction(() async {
      final remaining = await transportRemaining(
        studentId: studentId,
        month: month,
      );
      _checkAmount(amount, remaining);
      return _insertPayment(
        studentId: studentId,
        type: PaymentType.transport,
        periodKey: month,
        amount: amount,
        receivedBy: receivedBy,
        receiptNumber: receiptNumber,
      );
    });
  }

  // ---------------------------------------------------------------------------
  // أرقام الوصولات
  // ---------------------------------------------------------------------------

  /// رقم الوصل التالي لبادئة الجهاز [prefix]، مثل `A-000124`.
  Future<String> nextReceiptNumber(String prefix) async {
    final row = await db
        .customSelect(
          'SELECT MAX(CAST(substr(receipt_number, ?) AS INTEGER)) AS last '
          'FROM payments WHERE receipt_number LIKE ?',
          variables: [
            Variable<int>(prefix.length + 2),
            Variable<String>('$prefix-%'),
          ],
          readsFrom: {db.payments},
        )
        .getSingle();
    final next = (row.read<int?>('last') ?? 0) + 1;
    return '$prefix-${next.toString().padLeft(6, '0')}';
  }

  // ---------------------------------------------------------------------------

  static void _checkAmount(int amount, int remaining) {
    if (amount <= 0) {
      throw ArgumentError.value(amount, 'amount', 'المبلغ يجب أن يكون موجباً');
    }
    if (amount > remaining) {
      throw ArgumentError.value(
        amount,
        'amount',
        'المبلغ أكبر من الباقي ($remaining)',
      );
    }
  }

  static int _net(GroupStudentRow enrolment) => Pricing.netPrice(
    price: enrolment.monthlyPrice,
    discountType: DiscountType.fromCode(enrolment.discountType),
    discountValue: enrolment.discountValue,
  );

  Future<GroupRow> _group(String id) =>
      (db.select(db.groups)..where((g) => g.id.equals(id))).getSingle();

  Future<GroupStudentRow?> _enrolment(String studentId, String groupId) =>
      (db.select(db.groupStudents)..where(
            (gs) =>
                gs.studentId.equals(studentId) &
                gs.groupId.equals(groupId) &
                gs.deletedAt.isNull(),
          ))
          .getSingleOrNull();

  Future<RegistrationFeeRow?> _fee(String studentId, String periodKey) =>
      (db.select(db.registrationFees)..where(
            (f) =>
                f.studentId.equals(studentId) &
                f.periodKey.equals(periodKey) &
                f.deletedAt.isNull(),
          ))
          .getSingleOrNull();

  Future<int> _paidFor({
    required String studentId,
    required PaymentType type,
    required String periodKey,
  }) async {
    final row = await db
        .customSelect(
          'SELECT COALESCE(SUM(amount), 0) AS total FROM payments '
          'WHERE student_id = ? AND type = ? AND period_key = ? '
          'AND deleted_at IS NULL',
          variables: [
            Variable<String>(studentId),
            Variable<String>(type.code),
            Variable<String>(periodKey),
          ],
          readsFrom: {db.payments},
        )
        .getSingle();
    return row.read<int>('total');
  }

  Future<void> _insertCredit({
    required String studentId,
    required String groupId,
    required int amount,
    required String reason,
    required int sourceCycle,
    String? sessionId,
  }) {
    final stamp = writer.now();
    final credit = StudentCreditRow(
      id: writer.newId(),
      createdAt: stamp,
      updatedAt: stamp,
      studentId: studentId,
      groupId: groupId,
      amount: amount,
      reason: reason,
      sourceCycleNumber: sourceCycle,
      targetCycleNumber: sourceCycle + 1,
      sessionId: sessionId,
    );
    return writer.save(db.studentCredits, credit, key: {'id': credit.id});
  }

  Future<PaymentRow> _insertPayment({
    required String studentId,
    required PaymentType type,
    required int amount,
    required String receivedBy,
    required String receiptNumber,
    String? groupId,
    int? cycleNumber,
    String? periodKey,
    String note = '',
  }) async {
    final stamp = writer.now();
    final payment = PaymentRow(
      id: writer.newId(),
      createdAt: stamp,
      updatedAt: stamp,
      studentId: studentId,
      type: type.code,
      groupId: groupId,
      cycleNumber: cycleNumber,
      periodKey: periodKey,
      amount: amount,
      receivedBy: receivedBy,
      receiptNumber: receiptNumber,
      note: note,
    );
    await writer.save(
      db.payments,
      payment,
      key: {'id': payment.id},
      action: 'receive_money',
    );
    return (db.select(
      db.payments,
    )..where((p) => p.id.equals(payment.id))).getSingle();
  }
}
