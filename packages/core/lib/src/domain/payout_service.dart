import 'dart:convert';

import 'package:drift/drift.dart';

import '../data/local/app_database.dart';
import '../data/local/sync_writer.dart';
import 'dues_service.dart';
import 'money.dart';
import 'pricing.dart';

/// نصيب الأستاذ من تلميذ واحد في دورة.
class PayoutLine {
  const PayoutLine({
    required this.studentId,
    required this.attended,
    required this.covered,
    required this.earned,
    required this.full,
  });

  factory PayoutLine.fromJson(Map<String, Object?> json) => PayoutLine(
    studentId: json['student_id']! as String,
    attended: json['attended']! as int,
    covered: json['covered']! as int,
    earned: json['earned']! as int,
    full: json['full']! as int,
  );

  final String studentId;

  /// عدد الحصص التي حضرها التلميذ في الدورة.
  final int attended;

  /// عدد الحصص التي غطّاها ما دفعه التلميذ (أو كل الحصص للمعفى).
  final int covered;

  /// المبلغ المستحق للأستاذ الآن: عن الحصص المحضورة والمدفوعة معاً.
  final int earned;

  /// المبلغ الكامل حسب الحضور لو سُدّدت الدورة كلها.
  final int full;

  /// النصيب المعلّق حتى يدفع التلميذ.
  int get pending => full - earned;

  Map<String, Object?> toJson() => {
    'student_id': studentId,
    'attended': attended,
    'covered': covered,
    'earned': earned,
    'full': full,
  };
}

/// حساب خلاص أستاذ عن (مجموعة + دورة).
class CyclePayout {
  const CyclePayout({
    required this.teacherId,
    required this.groupId,
    required this.cycleNumber,
    required this.ratePerStudent,
    required this.lines,
  });

  final String teacherId;
  final String groupId;
  final int cycleNumber;
  final int ratePerStudent;
  final List<PayoutLine> lines;

  /// مجموع المستحق للأستاذ الآن.
  int get earned => lines.fold(0, (sum, line) => sum + line.earned);

  /// مجموع النصيب المعلّق حتى يدفع التلاميذ.
  int get pending => lines.fold(0, (sum, line) => sum + line.pending);
}

/// قواعد خلاص الأستاذ (دوال صافية).
abstract final class PayoutRules {
  /// عدد الحصص التي يغطيها ما دُفع.
  ///
  /// [netPrice] سعر الدورة بعد التخفيض، و[settled] ما سُدّد منه (المدفوع
  /// زائد الأرصدة). المعفى أو من سعره صفر تُعتبر كل حصصه مغطاة.
  static int coveredSessions({
    required int netPrice,
    required int settled,
    required int sessionsPerCycle,
    required bool exempt,
  }) {
    if (exempt || netPrice <= 0) return sessionsPerCycle;
    if (settled <= 0) return 0;
    if (settled >= netPrice) return sessionsPerCycle;
    return (settled * sessionsPerCycle) ~/ netPrice;
  }

  /// نصيب الأستاذ من تلميذ:
  /// `rate × min(الحصص المحضورة، الحصص المغطاة) ÷ حصص الدورة`.
  static PayoutLine line({
    required String studentId,
    required int ratePerStudent,
    required int attended,
    required int covered,
    required int sessionsPerCycle,
  }) {
    if (sessionsPerCycle <= 0) {
      throw ArgumentError.value(sessionsPerCycle, 'sessionsPerCycle');
    }
    final present = attended.clamp(0, sessionsPerCycle);
    final paidFor = covered.clamp(0, sessionsPerCycle);
    final payable = present < paidFor ? present : paidFor;
    return PayoutLine(
      studentId: studentId,
      attended: present,
      covered: paidFor,
      earned: Money.roundToTen(ratePerStudent * payable / sessionsPerCycle),
      full: Money.roundToTen(ratePerStudent * present / sessionsPerCycle),
    );
  }
}

/// خلاص الأساتذة.
///
/// الأستاذ يأخذ نصيبه عن الحصص التي حضرها التلميذ **ودُفعت قيمتها**.
/// الغياب (برخصة أو بدونها) لا يُحسب له. ما لم يُدفع بعد يبقى معلّقاً
/// ويُصرف في خلاص لاحق (`release`) عندما يدفع التلميذ.
class PayoutService {
  PayoutService(this.db, this.writer, this.dues);

  final AppDatabase db;
  final SyncWriter writer;
  final DuesService dues;

  static const String kindCycle = 'cycle';
  static const String kindRelease = 'release';

  /// يحسب خلاص الدورة حسب الحضور والمدفوعات الحالية، دون أن يحفظ شيئاً.
  Future<CyclePayout> compute(String groupId, int cycleNumber) async {
    final group = await (db.select(
      db.groups,
    )..where((g) => g.id.equals(groupId))).getSingle();
    final teacher = await (db.select(
      db.teachers,
    )..where((t) => t.id.equals(group.teacherId))).getSingle();
    final rate = group.ratePerStudent ?? teacher.ratePerStudent;

    final attendedRows = await db
        .customSelect(
          'SELECT a.student_id, COUNT(*) AS attended '
          'FROM attendance a JOIN sessions s ON s.id = a.session_id '
          'WHERE s.group_id = ? AND s.cycle_number = ? '
          "AND s.deleted_at IS NULL AND s.status <> 'cancelled' "
          "AND a.deleted_at IS NULL AND a.status = 'present' "
          'GROUP BY a.student_id',
          variables: [Variable<String>(groupId), Variable<int>(cycleNumber)],
          readsFrom: {db.attendance, db.sessions},
        )
        .get();
    final attended = {
      for (final row in attendedRows)
        row.read<String>('student_id'): row.read<int>('attended'),
    };

    final cycleDues = {
      for (final due in await dues.cycleDues(
        groupId: groupId,
        cycleNumber: cycleNumber,
      ))
        due.studentId: due,
    };

    final studentIds = {...attended.keys, ...cycleDues.keys}.toList()..sort();
    final lines = <PayoutLine>[];
    for (final studentId in studentIds) {
      final due = cycleDues[studentId];
      lines.add(
        PayoutRules.line(
          studentId: studentId,
          ratePerStudent: rate,
          attended: attended[studentId] ?? 0,
          covered: due == null ? 0 : _covered(due, group.sessionsPerCycle),
          sessionsPerCycle: group.sessionsPerCycle,
        ),
      );
    }
    return CyclePayout(
      teacherId: group.teacherId,
      groupId: groupId,
      cycleNumber: cycleNumber,
      ratePerStudent: rate,
      lines: lines,
    );
  }

  /// ينشئ خلاص اكتمال الدورة ويحفظ التفصيل لكل تلميذ. آمن عند التكرار:
  /// إن وُجد خلاص الدورة يُعاد كما هو.
  Future<TeacherPayoutRow> createCyclePayout(String groupId, int cycleNumber) {
    return db.transaction(() async {
      final existing =
          await (db.select(db.teacherPayouts)..where(
                (p) =>
                    p.groupId.equals(groupId) &
                    p.cycleNumber.equals(cycleNumber) &
                    p.kind.equals(kindCycle) &
                    p.deletedAt.isNull(),
              ))
              .getSingleOrNull();
      if (existing != null) return existing;
      final payout = await compute(groupId, cycleNumber);
      return _insert(payout, kindCycle, payout.lines);
    });
  }

  /// يصرف ما أُفرج عنه من النصيب المعلّق في الدورات المنتهية بعد أن دفع
  /// التلاميذ. يعيد الخلاصات الجديدة (واحد لكل دورة فيها إفراج).
  Future<List<TeacherPayoutRow>> releasePending(String groupId) {
    return db.transaction(() async {
      final cyclePayouts =
          await (db.select(db.teacherPayouts)
                ..where(
                  (p) =>
                      p.groupId.equals(groupId) &
                      p.kind.equals(kindCycle) &
                      p.deletedAt.isNull(),
                )
                ..orderBy([(p) => OrderingTerm(expression: p.cycleNumber)]))
              .get();
      final created = <TeacherPayoutRow>[];
      for (final cyclePayout in cyclePayouts) {
        final cycle = cyclePayout.cycleNumber;
        final alreadyPaid = await _paidOutPerStudent(groupId, cycle);
        final current = await compute(groupId, cycle);
        final released = <PayoutLine>[];
        for (final line in current.lines) {
          final delta = line.earned - (alreadyPaid[line.studentId] ?? 0);
          if (delta > 0) {
            released.add(
              PayoutLine(
                studentId: line.studentId,
                attended: line.attended,
                covered: line.covered,
                earned: delta,
                full: line.full,
              ),
            );
          }
        }
        if (released.isNotEmpty) {
          created.add(await _insert(current, kindRelease, released));
        }
      }
      return created;
    });
  }

  /// يسجّل تسليم المال للأستاذ. يعيد `false` إن كان مسلَّماً من قبل.
  Future<bool> markPaid(String payoutId, {required String paidBy}) {
    return db.transaction(() async {
      final payout = await (db.select(
        db.teacherPayouts,
      )..where((p) => p.id.equals(payoutId))).getSingle();
      if (payout.paidAt != null) return false;
      await writer.save(
        db.teacherPayouts,
        payout.copyWith(paidAt: Value(writer.now()), paidBy: Value(paidBy)),
        key: {'id': payout.id},
        action: 'pay_teacher',
      );
      return true;
    });
  }

  /// تفصيل خلاص محفوظ.
  static List<PayoutLine> linesOf(TeacherPayoutRow payout) => [
    for (final item in jsonDecode(payout.details) as List<Object?>)
      PayoutLine.fromJson((item! as Map).cast<String, Object?>()),
  ];

  static int _covered(CycleDue due, int sessionsPerCycle) {
    final credits = due.credits > due.netPrice ? due.netPrice : due.credits;
    return PayoutRules.coveredSessions(
      netPrice: due.netPrice,
      settled: credits + due.paid,
      sessionsPerCycle: sessionsPerCycle,
      exempt: due.exempt,
    );
  }

  Future<Map<String, int>> _paidOutPerStudent(String groupId, int cycle) async {
    final payouts =
        await (db.select(db.teacherPayouts)..where(
              (p) =>
                  p.groupId.equals(groupId) &
                  p.cycleNumber.equals(cycle) &
                  p.deletedAt.isNull(),
            ))
            .get();
    final totals = <String, int>{};
    for (final payout in payouts) {
      for (final line in linesOf(payout)) {
        totals[line.studentId] = (totals[line.studentId] ?? 0) + line.earned;
      }
    }
    return totals;
  }

  Future<TeacherPayoutRow> _insert(
    CyclePayout payout,
    String kind,
    List<PayoutLine> lines,
  ) async {
    final stamp = writer.now();
    final row = TeacherPayoutRow(
      id: writer.newId(),
      createdAt: stamp,
      updatedAt: stamp,
      teacherId: payout.teacherId,
      groupId: payout.groupId,
      cycleNumber: payout.cycleNumber,
      kind: kind,
      amount: lines.fold(0, (sum, line) => sum + line.earned),
      details: jsonEncode([for (final line in lines) line.toJson()]),
    );
    await writer.save(db.teacherPayouts, row, key: {'id': row.id});
    return row;
  }
}
