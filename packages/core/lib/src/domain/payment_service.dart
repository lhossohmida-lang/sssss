import 'dart:math';

import 'package:drift/drift.dart';

import '../data/local/app_database.dart';
import '../data/local/sync_writer.dart';
import 'catalog_service.dart';
import 'date_key.dart';
import 'dues_service.dart';
import 'enums.dart';
import 'money.dart';

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
  });

  final PaymentType type;

  /// وصف مختصر: «رياضيات · المجموعة 2 · الدورة 3».
  final String label;

  /// المطلوب بعد التخفيض وخصم الأرصدة.
  final int total;
  final int paid;

  /// أرصدة (غياب برخصة أو التحاق في المنتصف) خُصمت من الشهر.
  final int credits;

  final String? groupId;
  final int? cycleNumber;
  final String? periodKey;

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
        return 'شهر — ${subjectName ?? ''} · المجموعة ${groupNumber ?? ''}'
            ' · الدورة ${payment.cycleNumber ?? ''}';
      case PaymentType.transport:
        return 'نقل — ${payment.periodKey ?? ''}';
      case PaymentType.registrationFee:
        return 'حقوق التسجيل — ${payment.periodKey ?? ''}';
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
  PaymentService(this.db, this.writer, this.dues, this.device);

  final AppDatabase db;
  final SyncWriter writer;
  final DuesService dues;
  final DeviceInfoStore device;

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
                '${g?.subject ?? ''} · المجموعة ${g?.number ?? ''}'
                ' · الدورة ${due.cycleNumber}',
            total: due.due,
            paid: due.paid,
            credits: due.credits,
            groupId: due.groupId,
            cycleNumber: due.cycleNumber,
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
      return switch (type) {
        PaymentType.month => dues.recordMonthPayment(
          studentId: studentId,
          groupId: groupId!,
          cycleNumber: cycleNumber!,
          amount: amount,
          receivedBy: receivedBy,
          receiptNumber: receipt,
          note: note.trim(),
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
      };
    });
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
    }
  }

  // ---------------------------------------------------------------------------
  // القوائم
  // ---------------------------------------------------------------------------

  /// مدفوعات مطابقة للبحث (اسم التلميذ أو رقم الوصل)، الأحدث أولاً، وتتحدث
  /// لحظياً. [type] يحصر النوع.
  Stream<PaymentPage> watchPayments({
    String query = '',
    PaymentType? type,
    int limit = pageSize,
  }) {
    return db
        .customSelect(
          'SELECT 1',
          readsFrom: {db.payments, db.students, db.groups, db.subjects},
        )
        .watch()
        .asyncMap((_) => payments(query: query, type: type, limit: limit));
  }

  Future<PaymentPage> payments({
    String query = '',
    PaymentType? type,
    int limit = pageSize,
  }) async {
    final where = StringBuffer('p.deleted_at IS NULL');
    final vars = <Variable<Object>>[];
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
          'SELECT p.id, s.first_name, s.last_name, g.number, sub.name AS subject '
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
          'SELECT s.first_name, s.last_name, g.number, sub.name AS subject, '
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

  Future<Map<String, ({String subject, int number})>> _groupInfos(
    List<String> ids,
  ) async {
    final unique = ids.toSet().toList();
    final marks = List.filled(unique.length, '?').join(', ');
    final rows = await db
        .customSelect(
          'SELECT g.id, g.number, sub.name AS subject FROM groups g '
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
        ),
    };
  }
}
