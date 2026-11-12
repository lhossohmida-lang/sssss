import 'package:drift/drift.dart';

import '../data/local/app_database.dart';
import 'payout_service.dart';

/// حالة تسليم الخلاص.
enum PayoutStatus {
  all('الكل'),
  unpaid('غير مسلَّم'),
  paid('مسلَّم');

  const PayoutStatus(this.label);
  final String label;
}

/// خلاص أستاذ في القائمة: دورة مكتملة أو إفراج عن نصيب معلّق.
class PayoutItem {
  const PayoutItem({
    required this.payout,
    required this.teacherName,
    required this.groupNumber,
    required this.subjectName,
  });

  final TeacherPayoutRow payout;
  final String teacherName;
  final int groupNumber;
  final String subjectName;

  String get id => payout.id;
  int get amount => payout.amount;
  bool get isPaid => payout.paidAt != null;
  bool get isRelease => payout.kind == PayoutService.kindRelease;

  /// «رياضيات · المجموعة 2 · الدورة 3».
  String get groupLabel =>
      '$subjectName · المجموعة $groupNumber · الدورة ${payout.cycleNumber}';

  String get kindLabel => isRelease ? 'إفراج عن نصيب معلّق' : 'اكتمال الدورة';
}

/// سطر في تفصيل الخلاص: تلميذ ونصيب الأستاذ منه.
class PayoutDetailLine {
  const PayoutDetailLine({required this.name, required this.line});

  final String name;
  final PayoutLine line;
}

/// خلاص بتفصيله لكل تلميذ، مع النصيب المعلّق حتى الآن.
class PayoutDetail {
  const PayoutDetail({
    required this.item,
    required this.lines,
    required this.pending,
    required this.ratePerStudent,
    required this.paidByName,
  });

  final PayoutItem item;
  final List<PayoutDetailLine> lines;

  /// النصيب الذي ما زال معلّقاً لهذه الدورة (ينتظر تسديد التلاميذ).
  final int pending;

  /// نصيب الأستاذ من التلميذ الكامل في الدورة.
  final int ratePerStudent;

  /// اسم من سلّم المال، أو `null` إن لم يُسلَّم.
  final String? paidByName;
}

/// ملخص خلاصات الأساتذة: ما يُسلَّم، وما سُلِّم، وما بقي معلّقاً.
class PayoutSummary {
  const PayoutSummary({
    required this.unpaid,
    required this.paid,
    required this.pending,
  });

  /// مجموع خلاصات لم تُسلَّم بعد.
  final int unpaid;

  /// مجموع ما سُلِّم.
  final int paid;

  /// نصيب معلّق في الدورات المنتهية حتى يدفع التلاميذ.
  final int pending;
}

/// قوائم خلاص الأساتذة وتفصيلها وملخصها.
class PayoutQueries {
  PayoutQueries(this.db, this.payouts);

  final AppDatabase db;
  final PayoutService payouts;

  /// الخلاصات الحديثة أولاً، بحصرها بالحالة أو الأستاذ، ولحظياً.
  Stream<List<PayoutItem>> watch({
    PayoutStatus status = PayoutStatus.all,
    String? teacherId,
  }) {
    return db
        .customSelect(
          'SELECT 1',
          readsFrom: {db.teacherPayouts, db.teachers, db.groups},
        )
        .watch()
        .asyncMap((_) => list(status: status, teacherId: teacherId));
  }

  Future<List<PayoutItem>> list({
    PayoutStatus status = PayoutStatus.all,
    String? teacherId,
  }) async {
    final where = StringBuffer('p.deleted_at IS NULL');
    final vars = <Variable<Object>>[];
    if (status == PayoutStatus.unpaid) where.write(' AND p.paid_at IS NULL');
    if (status == PayoutStatus.paid) where.write(' AND p.paid_at IS NOT NULL');
    if (teacherId != null) {
      where.write(' AND p.teacher_id = ?');
      vars.add(Variable<String>(teacherId));
    }
    final rows = await db
        .customSelect(
          'SELECT p.id, t.name AS teacher, g.number, sub.name AS subject '
          'FROM teacher_payouts p JOIN teachers t ON t.id = p.teacher_id '
          'JOIN groups g ON g.id = p.group_id '
          'JOIN subjects sub ON sub.id = g.subject_id '
          'WHERE $where ORDER BY p.created_at DESC, p.id DESC',
          variables: vars,
          readsFrom: {db.teacherPayouts, db.teachers, db.groups, db.subjects},
        )
        .get();
    if (rows.isEmpty) return const [];
    final byId = {
      for (final p
          in await (db.select(db.teacherPayouts)..where(
                (p) => p.id.isIn([for (final r in rows) r.read<String>('id')]),
              ))
              .get())
        p.id: p,
    };
    return [
      for (final row in rows)
        PayoutItem(
          payout: byId[row.read<String>('id')]!,
          teacherName: row.read<String>('teacher'),
          groupNumber: row.read<int>('number'),
          subjectName: row.read<String>('subject'),
        ),
    ];
  }

  /// ملخص الخلاصات (الكل أو لأستاذ)، ولحظياً.
  Stream<PayoutSummary> watchSummary({String? teacherId}) {
    return db
        .customSelect(
          'SELECT 1',
          readsFrom: {
            db.teacherPayouts,
            db.payments,
            db.attendance,
            db.groupStudents,
          },
        )
        .watch()
        .asyncMap((_) => summary(teacherId: teacherId));
  }

  Future<PayoutSummary> summary({String? teacherId}) async {
    final filter = teacherId == null ? '' : ' AND teacher_id = ?';
    final vars = [if (teacherId != null) Variable<String>(teacherId)];
    final totals = await db
        .customSelect(
          'SELECT COALESCE(SUM(CASE WHEN paid_at IS NULL THEN amount END), 0) '
          'AS unpaid, COALESCE(SUM(CASE WHEN paid_at IS NOT NULL THEN amount '
          'END), 0) AS paid FROM teacher_payouts '
          'WHERE deleted_at IS NULL$filter',
          variables: vars,
          readsFrom: {db.teacherPayouts},
        )
        .getSingle();
    // النصيب المعلّق: لكل دورة منتهية (لها خلاص دورة) ما لم يُفرَج عنه بعد.
    final cycles = await db
        .customSelect(
          'SELECT group_id, cycle_number FROM teacher_payouts '
          "WHERE deleted_at IS NULL AND kind = 'cycle'$filter",
          variables: vars,
          readsFrom: {db.teacherPayouts},
        )
        .get();
    var pending = 0;
    for (final row in cycles) {
      final current = await payouts.compute(
        row.read<String>('group_id'),
        row.read<int>('cycle_number'),
      );
      pending += current.pending;
    }
    return PayoutSummary(
      unpaid: totals.read<int>('unpaid'),
      paid: totals.read<int>('paid'),
      pending: pending,
    );
  }

  /// تفصيل خلاص بأسماء تلاميذه، أو `null` إن لم يوجد.
  Future<PayoutDetail?> detail(String id) async {
    final items = await list();
    final item = items.where((i) => i.id == id).firstOrNull;
    if (item == null) return null;
    final lines = PayoutService.linesOf(item.payout);
    final ids = [for (final l in lines) l.studentId];
    final names = <String, String>{};
    if (ids.isNotEmpty) {
      for (final s in await (db.select(
        db.students,
      )..where((s) => s.id.isIn(ids))).get()) {
        names[s.id] = '${s.firstName} ${s.lastName}';
      }
    }
    final current = await payouts.compute(
      item.payout.groupId,
      item.payout.cycleNumber,
    );
    String? paidBy;
    final paidById = item.payout.paidBy;
    if (paidById != null) {
      final account = await (db.select(
        db.userAccounts,
      )..where((a) => a.id.equals(paidById))).getSingleOrNull();
      paidBy = account == null
          ? '—'
          : (account.displayName.isNotEmpty
                ? account.displayName
                : account.email);
    }
    return PayoutDetail(
      item: item,
      lines: [
        for (final l in lines)
          PayoutDetailLine(name: names[l.studentId] ?? '—', line: l),
      ],
      pending: current.pending,
      ratePerStudent: current.ratePerStudent,
      paidByName: paidBy,
    );
  }
}
