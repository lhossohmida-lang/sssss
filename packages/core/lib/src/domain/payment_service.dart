import 'dart:math';

import 'package:drift/drift.dart';

import '../data/local/app_database.dart';
import '../data/local/sync_writer.dart';
import 'catalog_service.dart';
import 'date_key.dart';
import 'dues_service.dart';
import 'enums.dart';
import 'group_sql.dart';
import 'money.dart';
import 'payout_service.dart';
import 'pricing.dart';
import 'sms_event_service.dart';

/// بيانات هذا الجهاز التي لا تُزامَن: بادئة أرقام الوصولات.
class DeviceInfoStore {
  DeviceInfoStore(this.db, {Random? random})
    : _random = random ?? Random.secure();

  final AppDatabase db;
  final Random _random;

  static const String receiptPrefixKey = 'receipt_prefix';

  /// حروف بلا الملتبسة (I، O) لتُقرأ على الوصل دون التباس.
  static const String _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ';

  /// بادئة وصولات هذا الجهاز: ثلاثة أحرف تُولَّد عشوائياً أول مرة وتبقى،
  /// فلا يصدر جهازان (يعملان دون إنترنت) الرقم نفسه.
  Future<String> receiptPrefix() async {
    final existing = await (db.select(
      db.deviceInfo,
    )..where((d) => d.key.equals(receiptPrefixKey))).getSingleOrNull();
    if (existing != null) return existing.value;
    final prefix = String.fromCharCodes([
      for (var i = 0; i < 3; i++)
        _alphabet.codeUnitAt(_random.nextInt(_alphabet.length)),
    ]);
    await db
        .into(db.deviceInfo)
        .insert(
          DeviceInfoCompanion.insert(key: receiptPrefixKey, value: prefix),
          mode: InsertMode.insertOrIgnore,
        );
    // سباق تهيئة نادر: نقرأ ما استقر فعلاً.
    final stored = await (db.select(
      db.deviceInfo,
    )..where((d) => d.key.equals(receiptPrefixKey))).getSingle();
    return stored.value;
  }
}

/// ما يمكن للتلميذ دفعه الآن: شهر دورة، أو حقوق تسجيل، أو نقل.
class PayableItem {
  const PayableItem({
    required this.type,
    required this.label,
    required this.total,
    required this.paid,
    this.groupId,
    this.cycleNumber,
    this.periodKey,
    this.credits = 0,
    this.creditSessions = 0,
    this.netPrice = 0,
    this.sessionsPerCycle = 0,
  });

  final PaymentType type;

  /// وصف مختصر: «رياضيات · المجموعة 2 · الدورة 3».
  final String label;

  /// المطلوب بعد التخفيض وخصم الأرصدة.
  final int total;
  final int paid;

  /// أرصدة (غياب برخصة أو التحاق في المنتصف) خُصمت من الشهر.
  final int credits;

  /// الرصيد بالحصص: كم حصة من الشهر دُفعت مقدماً (مثل 4 لتلميذ التحق في الحصة 5 من 8 فدفع
  /// الشهر الأول كاملاً). مقرَّباً لأقرب حصة، وصفر إن لم يكن رصيد.
  final int creditSessions;

  final String? groupId;
  final int? cycleNumber;
  final String? periodKey;

  /// للشهر: سعر الدورة بعد التخفيض وعدد حصصها، لدفع عدد من الحصص (3 أو 5 مثلاً).
  final int netPrice;
  final int sessionsPerCycle;

  /// ثمن [sessions] حصة من هذا الشهر (لا يزيد عن الباقي)؛ صفر لغير الشهر.
  int sessionsAmount(int sessions) {
    if (type != PaymentType.month || sessionsPerCycle <= 0) return 0;
    final value = Pricing.sessionsValue(
      netPrice: netPrice,
      sessions: sessions,
      sessionsPerCycle: sessionsPerCycle,
    );
    return value > remaining ? remaining : value;
  }

  int get remaining => total - paid < 0 ? 0 : total - paid;

  /// مفتاح فريد للعنصر لاختياره في القوائم.
  String get key =>
      '${type.code}|${groupId ?? ''}|${cycleNumber ?? ''}|'
      '${periodKey ?? ''}';
}

/// دفعة في قائمة المدفوعات مع اسم تلميذها.
class PaymentListItem {
  const PaymentListItem({
    required this.payment,
    required this.studentName,
    this.groupNumber,
    this.subjectName,
  });

  final PaymentRow payment;
  final String studentName;
  final int? groupNumber;
  final String? subjectName;

  String get id => payment.id;
  PaymentType get type => PaymentType.fromCode(payment.type);

  /// ما دُفع عنه: «شهر — رياضيات · المجموعة 2 · الدورة 3» أو الفترة.
  String get description {
    switch (type) {
      case PaymentType.month:
        return 'شهر — ${subjectName ?? ''} · الفوج ${groupNumber ?? ''}'
            ' · الدورة ${payment.cycleNumber ?? ''}';
      case PaymentType.transport:
        return 'نقل — ${payment.periodKey ?? ''}';
      case PaymentType.registrationFee:
        return 'حقوق التسجيل — ${payment.periodKey ?? ''}';
      case PaymentType.session:
        return 'حصة واحدة — ${subjectName ?? ''} · الفوج ${groupNumber ?? ''}';
    }
  }
}

/// دفعة واحدة بتفاصيلها (للوصل): التلميذ والمستلِم وما دُفع عنه.
class PaymentDetail {
  const PaymentDetail({
    required this.item,
    required this.receivedByName,
    required this.studentId,
    this.remaining,
  });

  final PaymentListItem item;
  final String receivedByName;
  final String studentId;

  /// الباقي الآن من البند الذي دُفع عنه (يساوي الباقي بعد هذه الدفعة إن
  /// كانت آخر دفعاته)، و`null` إن تعذّر حسابه.
  final int? remaining;

  PaymentRow get payment => item.payment;
}

/// صفحة من قائمة المدفوعات مع الإجمالي.
class PaymentPage {
  const PaymentPage({required this.items, required this.total});

  final List<PaymentListItem> items;

  /// عدد المدفوعات المطابقة كلها.
  final int total;

  bool get hasMore => items.length < total;
}

/// تسجيل المدفوعات (شهر / نقل / حقوق تسجيل) بوصل مرقَّم، وقوائمها.
///
/// المنطق المالي نفسه في [DuesService]؛ هذه الخدمة تضيف رقم الوصل التسلسلي
/// لهذا الجهاز، والمستلِم من الجلسة، والتحقق بالعربية، وما يمكن دفعه الآن.
class PaymentService {
  PaymentService(
    this.db,
    this.writer,
    this.dues,
    this.device, {
    SmsEventService? sms,
  }) : sms = sms ?? SmsEventService(db, writer);

  final AppDatabase db;
  final SyncWriter writer;
  final DuesService dues;
  final DeviceInfoStore device;
  final SmsEventService sms;

  late final PayoutService _payouts = PayoutService(db, writer, dues);

  static const String fieldAmount = 'amount';
  static const String fieldItem = 'item';
  static const int pageSize = 50;

  // ---------------------------------------------------------------------------
  // ما يُدفع
  // ---------------------------------------------------------------------------

  /// ما على التلميذ الآن: دورات غير مسدَّدة (الأقدم أولاً)، وحقوق تسجيل
  /// غير مسدَّدة، ونقل الشهر الجاري. لا تظهر العناصر المسدَّدة.
  Future<List<PayableItem>> payables(
    String studentId, {
    required DateTime now,
  }) async {
    final items = <PayableItem>[];

    final dueList = await dues.cycleDues(
      studentId: studentId,
      unpaidOnly: true,
    );
    if (dueList.isNotEmpty) {
      final info = await _groupInfos([for (final d in dueList) d.groupId]);
      dueList.sort((a, b) {
        final byCycle = a.cycleNumber.compareTo(b.cycleNumber);
        return byCycle != 0 ? byCycle : a.groupId.compareTo(b.groupId);
      });
      for (final due in dueList) {
        final g = info[due.groupId];
        items.add(
          PayableItem(
            type: PaymentType.month,
            label:
                '${g?.subject ?? ''} · الفوج ${g?.number ?? ''}'
                ' · الدورة ${due.cycleNumber}',
            total: due.due,
            paid: due.paid,
            credits: due.credits,
            creditSessions: due.creditSessions(g?.sessionsPerCycle ?? 0),
            groupId: due.groupId,
            cycleNumber: due.cycleNumber,
            netPrice: due.netPrice,
            sessionsPerCycle: g?.sessionsPerCycle ?? 0,
          ),
        );
      }
    }

    final fees =
        await (db.select(db.registrationFees)
              ..where(
                (f) =>
                    f.studentId.equals(studentId) &
                    f.deletedAt.isNull() &
                    f.paid.equals(false),
              )
              ..orderBy([(f) => OrderingTerm(expression: f.periodKey)]))
            .get();
    for (final fee in fees) {
      final remaining = await dues.registrationFeeRemaining(
        studentId: studentId,
        periodKey: fee.periodKey,
      );
      if (remaining == 0) continue;
      items.add(
        PayableItem(
          type: PaymentType.registrationFee,
          label: 'حقوق التسجيل ${fee.periodKey}',
          total: fee.amount,
          paid: fee.amount - remaining,
          periodKey: fee.periodKey,
        ),
      );
    }

    items.addAll(await _guestSessionItems(studentId));

    final student = await (db.select(
      db.students,
    )..where((s) => s.id.equals(studentId))).getSingle();
    if (student.usesTransport) {
      final month = DateKey.of(now).substring(0, 7);
      final remaining = await dues.transportRemaining(
        studentId: studentId,
        month: month,
      );
      if (remaining > 0) {
        items.add(
          PayableItem(
            type: PaymentType.transport,
            label: 'النقل $month',
            total: student.transportPrice,
            paid: student.transportPrice - remaining,
            periodKey: month,
          ),
        );
      }
    }
    return items;
  }

  // ---------------------------------------------------------------------------
  // التسجيل
  // ---------------------------------------------------------------------------

  /// رقم الوصل التالي لهذا الجهاز.
  Future<String> nextReceiptNumber() async =>
      dues.nextReceiptNumber(await device.receiptPrefix());

  /// يسجّل دفعة بوصل مرقَّم، باسم صاحب الجلسة مستلِماً. يعيد الدفعة.
  ///
  /// المبلغ موجب ولا يزيد عن الباقي (الدفع الجزئي مسموح، والباقي يبقى في
  /// المستحقات).
  Future<PaymentRow> record({
    required String studentId,
    required PaymentType type,
    required int amount,
    String? groupId,
    int? cycleNumber,
    String? periodKey,
    String note = '',
  }) {
    return db.transaction(() async {
      final remaining = await _remaining(
        studentId: studentId,
        type: type,
        groupId: groupId,
        cycleNumber: cycleNumber,
        periodKey: periodKey,
      );
      if (amount <= 0) {
        throw ValidationException.field(fieldAmount, 'أدخل مبلغاً أكبر من صفر');
      }
      if (amount > remaining) {
        throw ValidationException.field(
          fieldAmount,
          'المبلغ يزيد عن الباقي (${Money.format(remaining)})',
        );
      }
      final receivedBy = writer.actor().userId;
      final receipt = await nextReceiptNumber();
      final payment = await switch (type) {
        PaymentType.month => _recordMonth(
          studentId: studentId,
          groupId: groupId!,
          cycleNumber: cycleNumber!,
          amount: amount,
          receivedBy: receivedBy,
          receipt: receipt,
          note: note.trim(),
          periodKey: periodKey,
        ),
        PaymentType.registrationFee => dues.payRegistrationFee(
          studentId: studentId,
          periodKey: periodKey!,
          amount: amount,
          receivedBy: receivedBy,
          receiptNumber: receipt,
        ),
        PaymentType.transport => dues.payTransport(
          studentId: studentId,
          month: periodKey!,
          amount: amount,
          receivedBy: receivedBy,
          receiptNumber: receipt,
        ),
        PaymentType.session => _recordSession(
          studentId: studentId,
          sessionId: periodKey!,
          amount: amount,
          receivedBy: receivedBy,
          receipt: receipt,
        ),
      };
      await sms.paymentReceipt(payment);
      return payment;
    });
  }

  /// يدفع حصة [sessionId] بعينها لتلميذ ملزَم بدورتها: دفعة شهر بثمن حصة معيَّنة لهذه الحصة، فتظهر
  /// هي مدفوعة (بالأزرق) في الشبكة. يرمي [ValidationException] إن كانت مدفوعة أو الدورة مسدَّدة.
  Future<PaymentRow> paySession({
    required String studentId,
    required String sessionId,
    String note = '',
  }) async {
    final session = await (db.select(
      db.sessions,
    )..where((s) => s.id.equals(sessionId))).getSingle();
    final due = await dues.cycleDue(
      studentId: studentId,
      groupId: session.groupId,
      cycleNumber: session.cycleNumber,
    );
    if (due == null || due.exempt || due.remaining == 0) {
      throw ValidationException.field(
        fieldAmount,
        due == null
            ? 'التلميذ غير ملزَم بهذه الدورة'
            : due.exempt
            ? 'التلميذ معفى'
            : 'الدورة مسدَّدة',
      );
    }
    final coverage = await dues.sessionCoverage(
      studentId: studentId,
      groupId: session.groupId,
      cycleNumber: session.cycleNumber,
    );
    if (coverage != null && coverage.paid.contains(sessionId)) {
      throw ValidationException.field(fieldAmount, 'الحصة مدفوعة');
    }
    final group = await (db.select(
      db.groups,
    )..where((g) => g.id.equals(session.groupId))).getSingle();
    final value = Pricing.sessionsValue(
      netPrice: due.netPrice,
      sessions: 1,
      sessionsPerCycle: group.sessionsPerCycle,
    );
    return record(
      studentId: studentId,
      type: PaymentType.month,
      amount: min(value, due.remaining),
      groupId: session.groupId,
      cycleNumber: session.cycleNumber,
      periodKey: sessionId,
      note: note.isEmpty ? 'حصة ${session.date}' : note,
    );
  }

  /// يلغي دفع حصة [sessionId] بعينها (الضغط الثاني على «دفع هذه الحصة»): تُنقص دفعتها بثمن حصة أو
  /// تُحذف، فتعود الحصة غير مدفوعة وحدها. إن كانت مدفوعة من دفعة لم تُعيَّن لحصص، تُعيَّن تلك الدفعات
  /// أولاً للحصص التي كانت تغطيها حتى لا تنتقل التغطية إلى حصة أخرى. لا يُلغى ما دُفع من رصيد الشهر
  /// السابق.
  Future<void> unpaySession({
    required String studentId,
    required String sessionId,
  }) {
    return db.transaction(() async {
      final session = await (db.select(
        db.sessions,
      )..where((s) => s.id.equals(sessionId))).getSingle();
      final due = await dues.cycleDue(
        studentId: studentId,
        groupId: session.groupId,
        cycleNumber: session.cycleNumber,
      );
      if (due == null) {
        throw ValidationException.field(
          fieldAmount,
          'التلميذ غير ملزَم بهذه الدورة',
        );
      }
      if (due.exempt) {
        throw ValidationException.field(fieldAmount, 'التلميذ معفى');
      }
      final group = await (db.select(
        db.groups,
      )..where((g) => g.id.equals(session.groupId))).getSingle();
      final value = Pricing.sessionsValue(
        netPrice: due.netPrice,
        sessions: 1,
        sessionsPerCycle: group.sessionsPerCycle,
      );
      final payments =
          await (db.select(db.payments)
                ..where(
                  (p) =>
                      p.studentId.equals(studentId) &
                      p.groupId.equals(session.groupId) &
                      p.cycleNumber.equals(session.cycleNumber) &
                      p.type.equals(PaymentType.month.code) &
                      p.deletedAt.isNull(),
                )
                ..orderBy([(p) => OrderingTerm(expression: p.createdAt)]))
              .get();

      Future<void> take(PaymentRow payment, Set<String> ids) async {
        final rest = {...ids}..remove(sessionId);
        final amount = payment.amount - value;
        if (amount <= 0) {
          await writer.softDelete(db.payments, key: {'id': payment.id});
        } else {
          await writer.patch(
            db.payments,
            key: {'id': payment.id},
            values: {'amount': amount, 'period_key': rest.join(',')},
          );
        }
      }

      // دفعة معيَّنة لهذه الحصة.
      for (final payment in payments) {
        if (payment.periodKey == null) continue;
        final ids = SessionCoverage.idsOf(payment.periodKey);
        if (ids.contains(sessionId)) {
          await take(payment, ids);
          return;
        }
      }
      final coverage = await dues.sessionCoverage(
        studentId: studentId,
        groupId: session.groupId,
        cycleNumber: session.cycleNumber,
      );
      if (coverage != null && coverage.credit.contains(sessionId)) {
        throw ValidationException.field(
          fieldAmount,
          'هذه الحصة مدفوعة من رصيد الشهر السابق',
        );
      }
      if (coverage == null || !coverage.filled.contains(sessionId)) {
        throw ValidationException.field(fieldAmount, 'الحصة غير مدفوعة');
      }
      // تُعيَّن الدفعات غير المعيَّنة لما تغطيه من حصص بالترتيب، ثم تُنزع هذه الحصة من دفعتها.
      final untagged = [
        for (final payment in payments)
          if (payment.periodKey == null && payment.amount > 0) payment,
      ];
      final filled = coverage.filled;
      final total = untagged.fold<int>(0, (sum, p) => sum + p.amount);
      var before = 0;
      for (final payment in untagged) {
        final start = before * filled.length ~/ total;
        before += payment.amount;
        final end = before * filled.length ~/ total;
        final ids = filled.sublist(start, end).toSet();
        if (ids.contains(sessionId)) {
          await take(payment, ids);
        } else {
          await writer.patch(
            db.payments,
            key: {'id': payment.id},
            values: {'period_key': ids.join(',')},
          );
        }
      }
    });
  }

  /// يدفع عند الانتساب [sessions] حصة من أول حصة له في دورة التحاقه (كل الدورة إن ساوت حصصها):
  /// تُعيَّن الدفعة لتلك الحصص فتظهر هي مدفوعة. يعيد `null` إن كان معفى أو لا شيء عليه.
  Future<PaymentRow?> payAtEnrolment({
    required String studentId,
    required String groupId,
    required int sessions,
  }) async {
    if (sessions <= 0) return null;
    final enrolment =
        await (db.select(db.groupStudents)
              ..where(
                (e) =>
                    e.studentId.equals(studentId) &
                    e.groupId.equals(groupId) &
                    e.deletedAt.isNull() &
                    e.leftAt.isNull(),
              )
              ..orderBy([
                (e) => OrderingTerm(
                  expression: e.joinedAt,
                  mode: OrderingMode.desc,
                ),
              ])
              ..limit(1))
            .getSingleOrNull();
    if (enrolment == null) return null;
    final cycle = enrolment.joinedAtCycleNumber;
    final due = await dues.cycleDue(
      studentId: studentId,
      groupId: groupId,
      cycleNumber: cycle,
    );
    if (due == null || due.exempt || due.remaining == 0) return null;
    final group = await (db.select(
      db.groups,
    )..where((g) => g.id.equals(groupId))).getSingle();
    final perCycle = group.sessionsPerCycle;
    final whole = sessions >= perCycle;
    final amount = whole
        ? due.remaining
        : min(
            Pricing.sessionsValue(
              netPrice: due.netPrice,
              sessions: sessions,
              sessionsPerCycle: perCycle,
            ),
            due.remaining,
          );
    final counted = await dues.countedSessionIds(groupId, cycle);
    final first = max(0, enrolment.joinedAtSessionNumber - 1);
    final ids = counted.skip(first).take(whole ? perCycle : sessions).toList();
    return record(
      studentId: studentId,
      type: PaymentType.month,
      amount: amount,
      groupId: groupId,
      cycleNumber: cycle,
      periodKey: ids.isEmpty ? null : ids.join(','),
      note: whole ? '' : 'دفع ${SessionCount.label(sessions)}',
    );
  }

  /// يسجّل دفع [sessions] حصة من دورة [cycleNumber] (ثمن الحصة سعر الدورة ÷ حصصها)، ولا يزيد عن
  /// الباقي. يرمي [ValidationException] إن كانت الدورة مسدَّدة أو التلميذ غير ملزَم بها.
  Future<PaymentRow> paySessions({
    required String studentId,
    required String groupId,
    required int cycleNumber,
    int sessions = 1,
    String note = '',
  }) async {
    final due = await dues.cycleDue(
      studentId: studentId,
      groupId: groupId,
      cycleNumber: cycleNumber,
    );
    if (due == null || due.exempt || due.remaining == 0) {
      throw ValidationException.field(
        fieldAmount,
        due == null ? 'التلميذ غير ملزَم بهذه الدورة' : 'الدورة مسدَّدة',
      );
    }
    final group = await (db.select(
      db.groups,
    )..where((g) => g.id.equals(groupId))).getSingle();
    final value = Pricing.sessionsValue(
      netPrice: due.netPrice,
      sessions: sessions,
      sessionsPerCycle: group.sessionsPerCycle,
    );
    final amount = value > due.remaining ? due.remaining : value;
    return record(
      studentId: studentId,
      type: PaymentType.month,
      amount: amount,
      groupId: groupId,
      cycleNumber: cycleNumber,
      note: note,
    );
  }

  /// يدفع حصة [sessionId] لكل تلميذ حاضر فيها ولم يسدّد دورته (زر واحد في ورقة الحضور). يعيد
  /// عدد من سُجّلت لهم دفعة.
  Future<int> paySessionForPresent(String sessionId) async {
    final session = await (db.select(
      db.sessions,
    )..where((s) => s.id.equals(sessionId))).getSingle();
    final present =
        await (db.select(db.attendance)..where(
              (a) =>
                  a.sessionId.equals(sessionId) &
                  a.deletedAt.isNull() &
                  a.status.equals(AttendanceStatus.present.code),
            ))
            .get();
    var paid = 0;
    for (final row in present) {
      final due = await dues.cycleDue(
        studentId: row.studentId,
        groupId: session.groupId,
        cycleNumber: session.cycleNumber,
      );
      if (due == null || due.exempt || due.remaining == 0) continue;
      final coverage = await dues.sessionCoverage(
        studentId: row.studentId,
        groupId: session.groupId,
        cycleNumber: session.cycleNumber,
      );
      if (coverage == null || coverage.paid.contains(sessionId)) continue;
      await paySession(studentId: row.studentId, sessionId: sessionId);
      paid++;
    }
    return paid;
  }

  /// دفع شهر: يُفرَج بعده عن نصيب الأستاذ المعلّق في دورات المجموعة
  /// المنتهية، فيظهر في خلاصاته غير المسلَّمة (قرار 54).
  Future<PaymentRow> _recordMonth({
    required String studentId,
    required String groupId,
    required int cycleNumber,
    required int amount,
    required String receivedBy,
    required String receipt,
    required String note,
    String? periodKey,
  }) async {
    final payment = await dues.recordMonthPayment(
      studentId: studentId,
      groupId: groupId,
      cycleNumber: cycleNumber,
      amount: amount,
      receivedBy: receivedBy,
      receiptNumber: receipt,
      note: note,
      periodKey: periodKey,
    );
    await _payouts.releasePending(groupId);
    return payment;
  }

  /// دفع ثمن حصة: يُفرَج بعده عن نصيب أستاذ الحصة المعلّق إن كان الضيف قد حضرها.
  Future<PaymentRow> _recordSession({
    required String studentId,
    required String sessionId,
    required int amount,
    required String receivedBy,
    required String receipt,
  }) async {
    final payment = await dues.paySession(
      studentId: studentId,
      sessionId: sessionId,
      amount: amount,
      receivedBy: receivedBy,
      receiptNumber: receipt,
    );
    final groupId = payment.groupId;
    if (groupId != null) await _payouts.releasePending(groupId);
    return payment;
  }

  /// أثمان الحصص التي لم يُسدِّدها ضيف (تلميذ لمرة واحدة أو تلميذ يحضر حصة فوج آخر).
  Future<List<PayableItem>> _guestSessionItems(String studentId) async {
    final rows = await db
        .customSelect(
          'SELECT g.session_id, g.price, se.group_id, se.cycle_number, '
          'se.date, gr.number, ${GroupSql.subjectLabel} AS subject, '
          '(SELECT COALESCE(SUM(p.amount), 0) FROM payments p '
          "WHERE p.student_id = g.student_id AND p.type = 'session' "
          'AND p.period_key = g.session_id AND p.deleted_at IS NULL) AS paid '
          'FROM session_guests g JOIN sessions se ON se.id = g.session_id '
          'JOIN groups gr ON gr.id = se.group_id '
          'JOIN subjects sub ON sub.id = gr.subject_id '
          'WHERE g.student_id = ? AND g.deleted_at IS NULL '
          'AND se.deleted_at IS NULL ORDER BY se.date, g.session_id',
          variables: [Variable<String>(studentId)],
          readsFrom: {
            db.sessionGuests,
            db.sessions,
            db.groups,
            db.subjects,
            db.payments,
          },
        )
        .get();
    return [
      for (final row in rows)
        if (row.read<int>('price') - row.read<int>('paid') > 0)
          PayableItem(
            type: PaymentType.session,
            label:
                'حصة ${row.read<String>('subject')} · الفوج '
                '${row.read<int>('number')} · ${row.read<String>('date')}',
            total: row.read<int>('price'),
            paid: row.read<int>('paid'),
            groupId: row.read<String>('group_id'),
            cycleNumber: row.read<int>('cycle_number'),
            periodKey: row.read<String>('session_id'),
          ),
    ];
  }

  Future<int> _remaining({
    required String studentId,
    required PaymentType type,
    String? groupId,
    int? cycleNumber,
    String? periodKey,
  }) async {
    switch (type) {
      case PaymentType.month:
        if (groupId == null || cycleNumber == null) {
          throw ValidationException.field(fieldItem, 'اختر الشهر المراد دفعه');
        }
        final due = await dues.cycleDue(
          studentId: studentId,
          groupId: groupId,
          cycleNumber: cycleNumber,
        );
        if (due == null) {
          throw ValidationException.field(
            fieldItem,
            'التلميذ غير ملزَم بهذه الدورة',
          );
        }
        return due.remaining;
      case PaymentType.registrationFee:
        if (periodKey == null) {
          throw ValidationException.field(fieldItem, 'اختر الفترة');
        }
        return dues.registrationFeeRemaining(
          studentId: studentId,
          periodKey: periodKey,
        );
      case PaymentType.transport:
        if (periodKey == null) {
          throw ValidationException.field(fieldItem, 'اختر الشهر');
        }
        return dues.transportRemaining(studentId: studentId, month: periodKey);
      case PaymentType.session:
        if (periodKey == null) {
          throw ValidationException.field(fieldItem, 'اختر الحصة');
        }
        return dues.sessionRemaining(
          studentId: studentId,
          sessionId: periodKey,
        );
    }
  }

  // ---------------------------------------------------------------------------
  // القوائم
  // ---------------------------------------------------------------------------

  /// مدفوعات مطابقة للبحث (اسم التلميذ أو رقم الوصل)، الأحدث أولاً، وتتحدث
  /// لحظياً. [type] يحصر النوع، و[studentId] يحصر دفعات تلميذ بعينه (كشف
  /// الوليّ لابنه).
  Stream<PaymentPage> watchPayments({
    String query = '',
    PaymentType? type,
    String? studentId,
    int limit = pageSize,
  }) {
    return db
        .customSelect(
          'SELECT 1',
          readsFrom: {db.payments, db.students, db.groups, db.subjects},
        )
        .watch()
        .asyncMap(
          (_) => payments(
            query: query,
            type: type,
            studentId: studentId,
            limit: limit,
          ),
        );
  }

  Future<PaymentPage> payments({
    String query = '',
    PaymentType? type,
    String? studentId,
    int limit = pageSize,
  }) async {
    final where = StringBuffer('p.deleted_at IS NULL');
    final vars = <Variable<Object>>[];
    if (studentId != null) {
      where.write(' AND p.student_id = ?');
      vars.add(Variable<String>(studentId));
    }
    if (type != null) {
      where.write(' AND p.type = ?');
      vars.add(Variable<String>(type.code));
    }
    final q = query.trim();
    if (q.isNotEmpty) {
      where.write(
        " AND (p.receipt_number LIKE ? OR (s.first_name || ' ' || s.last_name) "
        'LIKE ?)',
      );
      final like = '%$q%';
      vars
        ..add(Variable<String>(like))
        ..add(Variable<String>(like));
    }
    final rows = await db
        .customSelect(
          'SELECT p.id, s.first_name, s.last_name, g.number, ${GroupSql.subjectLabel} AS subject '
          'FROM payments p JOIN students s ON s.id = p.student_id '
          'LEFT JOIN groups g ON g.id = p.group_id '
          'LEFT JOIN subjects sub ON sub.id = g.subject_id '
          'WHERE $where ORDER BY p.created_at DESC, p.id DESC LIMIT ?',
          variables: [...vars, Variable<int>(limit)],
          readsFrom: {db.payments, db.students, db.groups, db.subjects},
        )
        .get();
    final count = await db
        .customSelect(
          'SELECT COUNT(*) AS n FROM payments p '
          'JOIN students s ON s.id = p.student_id WHERE $where',
          variables: vars,
          readsFrom: {db.payments, db.students},
        )
        .getSingle();
    if (rows.isEmpty) return const PaymentPage(items: [], total: 0);
    final byId = {
      for (final p
          in await (db.select(db.payments)..where(
                (p) => p.id.isIn([for (final r in rows) r.read<String>('id')]),
              ))
              .get())
        p.id: p,
    };
    return PaymentPage(
      total: count.read<int>('n'),
      items: [
        for (final row in rows)
          PaymentListItem(
            payment: byId[row.read<String>('id')]!,
            studentName:
                '${row.read<String>('first_name')} '
                '${row.read<String>('last_name')}',
            groupNumber: row.read<int?>('number'),
            subjectName: row.read<String?>('subject'),
          ),
      ],
    );
  }

  /// دفعة بتفاصيلها، أو `null` إن لم توجد.
  Future<PaymentDetail?> detail(String id) async {
    final payment = await (db.select(
      db.payments,
    )..where((p) => p.id.equals(id) & p.deletedAt.isNull())).getSingleOrNull();
    if (payment == null) return null;
    final row = await db
        .customSelect(
          'SELECT s.first_name, s.last_name, g.number, ${GroupSql.subjectLabel} AS subject, '
          'u.display_name, u.email FROM students s '
          'LEFT JOIN groups g ON g.id = ? '
          'LEFT JOIN subjects sub ON sub.id = g.subject_id '
          'LEFT JOIN user_accounts u ON u.id = ? WHERE s.id = ?',
          variables: [
            Variable<String>(payment.groupId ?? ''),
            Variable<String>(payment.receivedBy),
            Variable<String>(payment.studentId),
          ],
          readsFrom: {db.students, db.groups, db.subjects, db.userAccounts},
        )
        .getSingleOrNull();
    if (row == null) return null;
    final display = row.read<String?>('display_name') ?? '';
    int? remaining;
    try {
      remaining = await _remaining(
        studentId: payment.studentId,
        type: PaymentType.fromCode(payment.type),
        groupId: payment.groupId,
        cycleNumber: payment.cycleNumber,
        periodKey: payment.periodKey,
      );
    } on ValidationException {
      remaining = null;
    }
    return PaymentDetail(
      remaining: remaining,
      studentId: payment.studentId,
      receivedByName: display.isNotEmpty
          ? display
          : (row.read<String?>('email') ?? '—'),
      item: PaymentListItem(
        payment: payment,
        studentName:
            '${row.read<String>('first_name')} ${row.read<String>('last_name')}',
        groupNumber: row.read<int?>('number'),
        subjectName: row.read<String?>('subject'),
      ),
    );
  }

  /// مجموع ما استُلم اليوم، ويتحدث مع كل دفعة.
  Stream<int> watchReceivedOn(DateTime day) {
    return db
        .customSelect('SELECT 1', readsFrom: {db.payments})
        .watch()
        .asyncMap((_) => receivedOn(day));
  }

  /// مجموع ما استُلم بين [from] و[to] (بالمللي ثانية، [to] حصري).
  Future<int> receivedBetween({required int from, required int to}) async {
    final row = await db
        .customSelect(
          'SELECT COALESCE(SUM(amount), 0) AS total FROM payments '
          'WHERE deleted_at IS NULL AND created_at >= ? AND created_at < ?',
          variables: [Variable<int>(from), Variable<int>(to)],
          readsFrom: {db.payments},
        )
        .getSingle();
    return row.read<int>('total');
  }

  /// مجموع ما استُلم اليوم (بالتوقيت المحلي).
  Future<int> receivedOn(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = DateTime(day.year, day.month, day.day + 1);
    return receivedBetween(
      from: start.toUtc().millisecondsSinceEpoch,
      to: end.toUtc().millisecondsSinceEpoch,
    );
  }

  Future<Map<String, ({String subject, int number, int sessionsPerCycle})>>
  _groupInfos(List<String> ids) async {
    final unique = ids.toSet().toList();
    final marks = List.filled(unique.length, '?').join(', ');
    final rows = await db
        .customSelect(
          'SELECT g.id, g.number, g.sessions_per_cycle, ${GroupSql.subjectLabel} AS subject '
          'FROM groups g '
          'JOIN subjects sub ON sub.id = g.subject_id WHERE g.id IN ($marks)',
          variables: [for (final id in unique) Variable<String>(id)],
          readsFrom: {db.groups, db.subjects},
        )
        .get();
    return {
      for (final row in rows)
        row.read<String>('id'): (
          subject: row.read<String>('subject'),
          number: row.read<int>('number'),
          sessionsPerCycle: row.read<int>('sessions_per_cycle'),
        ),
    };
  }
}
