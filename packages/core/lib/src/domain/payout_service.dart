import 'dart:convert';

import 'package:drift/drift.dart';

import '../data/local/app_database.dart';
import '../data/local/sync_writer.dart';
import 'dues_service.dart';
import 'money.dart';
import 'pricing.dart';
import 'stable_id.dart';

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

/// مال فوج في دورة: ما دفعه تلاميذه، وحق الأستاذ منه، وما يبقى للمدير.
class GroupMoney {
  const GroupMoney({
    required this.paid,
    required this.teacher,
    required this.teacherPending,
  });

  /// ما دفعه التلاميذ عن هذه الدورة (أشهرهم وأثمان حصص ضيوفها).
  final int paid;

  /// حق الأستاذ: عن الحصص التي حضرها التلاميذ ودُفعت (وتلميذ مجاني على المدرسة يأخذ عنه حقه كاملاً).
  final int teacher;

  /// حق الأستاذ المعلّق حتى يدفع التلاميذ ما عليهم.
  final int teacherPending;

  /// ما يبقى للمدير: ما دفعه التلاميذ ناقص حق الأستاذ.
  int get admin => paid - teacher;
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
///
/// - نصيب الأستاذ عن تلميذ هو مبلغ الفوج، إلا إن عُيِّن له مبلغ آخر عند انتسابه (`teacherAmount`):
///   فإن بقي كاملاً مع تخفيض أو إعفاء فالتخفيض على حساب المدرسة (الأستاذ يأخذ حقه من مالها)، وإن نقص
///   فالأستاذ يتحمل من التخفيض (والمدرسة تأخذ من حقه).
/// - ضيف الحصة (تلميذ لمرة واحدة أو تلميذ يحضر حصة فوج آخر) يأخذ الأستاذ عنه مبلغه المسجَّل لحصته إن
///   حضرها، بقدر ما دفعه من ثمنها.
class PayoutService {
  PayoutService(this.db, this.writer, this.dues);

  final AppDatabase db;
  final SyncWriter writer;
  final DuesService dues;

  static const String kindCycle = 'cycle';
  static const String kindRelease = 'release';

  /// يحسب خلاص الدورة حسب الحضور والمدفوعات الحالية، دون أن يحفظ شيئاً.
  Future<CyclePayout> compute(String groupId, int cycleNumber) async =>
      (await computeCycles(groupId, [cycleNumber]))[cycleNumber]!;

  /// يحسب خلاص عدة دورات من مجموعة واحدة باستعلامات مجمّعة (الحضور لكل الدورات
  /// في استعلام واحد، والمستحقات في استعلام واحد)، فلا يتضاعف عدد الاستعلامات
  /// بعدد الدورات (ملخص الخلاصات يمرّ على كل دورة منتهية).
  Future<Map<int, CyclePayout>> computeCycles(
    String groupId,
    Iterable<int> cycleNumbers,
  ) async {
    final wanted = cycleNumbers.toSet();
    if (wanted.isEmpty) return const {};
    final group = await (db.select(
      db.groups,
    )..where((g) => g.id.equals(groupId))).getSingle();
    final teacher = await (db.select(
      db.teachers,
    )..where((t) => t.id.equals(group.teacherId))).getSingle();
    final rate = group.ratePerStudent ?? teacher.ratePerStudent;
    final amounts = await _teacherAmounts(groupId);
    final guests = await _guestLines(groupId, wanted);

    final attendedRows = await db
        .customSelect(
          'SELECT a.student_id, s.cycle_number, COUNT(*) AS attended '
          'FROM attendance a JOIN sessions s ON s.id = a.session_id '
          'WHERE s.group_id = ? '
          "AND s.deleted_at IS NULL AND s.status <> 'cancelled' "
          "AND a.deleted_at IS NULL AND a.status = 'present' "
          'GROUP BY a.student_id, s.cycle_number',
          variables: [Variable<String>(groupId)],
          readsFrom: {db.attendance, db.sessions},
        )
        .get();
    // الحضور حسب الدورة ثم التلميذ.
    final attended = <int, Map<String, int>>{};
    for (final row in attendedRows) {
      final cycle = row.read<int>('cycle_number');
      if (!wanted.contains(cycle)) continue;
      attended.putIfAbsent(cycle, () => {})[row.read<String>('student_id')] =
          row.read<int>('attended');
    }

    // دورة واحدة: مستحقاتها وحدها؛ عدة دورات: كل دورات المجموعة مرة واحدة.
    final dueRows = await dues.cycleDues(
      groupId: groupId,
      cycleNumber: wanted.length == 1 ? wanted.single : null,
    );
    final duesByCycle = <int, Map<String, CycleDue>>{};
    for (final due in dueRows) {
      if (!wanted.contains(due.cycleNumber)) continue;
      duesByCycle.putIfAbsent(due.cycleNumber, () => {})[due.studentId] = due;
    }

    final result = <int, CyclePayout>{};
    for (final cycle in wanted) {
      final cycleAttended = attended[cycle] ?? const <String, int>{};
      final cycleDues = duesByCycle[cycle] ?? const <String, CycleDue>{};
      final guestLines = guests[cycle] ?? const <String, PayoutLine>{};
      // الضيوف لهم خطوطهم الخاصة؛ حضورهم لا يُحسب بنسبة حصص الدورة.
      final studentIds = {
        ...cycleAttended.keys,
        ...cycleDues.keys,
      }.where((id) => !guestLines.containsKey(id)).toList()..sort();
      final lines = <PayoutLine>[];
      for (final studentId in studentIds) {
        final due = cycleDues[studentId];
        lines.add(
          PayoutRules.line(
            studentId: studentId,
            ratePerStudent: amounts[studentId] ?? rate,
            attended: cycleAttended[studentId] ?? 0,
            covered: due == null ? 0 : _covered(due, group.sessionsPerCycle),
            sessionsPerCycle: group.sessionsPerCycle,
          ),
        );
      }
      final guestIds = guestLines.keys.toList()..sort();
      for (final id in guestIds) {
        lines.add(guestLines[id]!);
      }
      result[cycle] = CyclePayout(
        teacherId: group.teacherId,
        groupId: groupId,
        cycleNumber: cycle,
        ratePerStudent: rate,
        lines: lines,
      );
    }
    return result;
  }

  /// ما دفعه تلاميذ [groupId] في دورة [cycleNumber]، وحق أستاذه، وما يبقى للمدير.
  Future<GroupMoney> groupMoney(String groupId, int cycleNumber) async {
    final paid = await db
        .customSelect(
          'SELECT COALESCE(SUM(amount), 0) AS total FROM payments '
          'WHERE group_id = ? AND cycle_number = ? AND deleted_at IS NULL '
          "AND type IN ('month', 'session')",
          variables: [Variable<String>(groupId), Variable<int>(cycleNumber)],
          readsFrom: {db.payments},
        )
        .getSingle();
    final payout = await compute(groupId, cycleNumber);
    return GroupMoney(
      paid: paid.read<int>('total'),
      teacher: payout.earned,
      teacherPending: payout.pending,
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
      // كل دورات المجموعة المنتهية تُحسب معاً باستعلامات مجمّعة.
      final computed = await computeCycles(groupId, [
        for (final p in cyclePayouts) p.cycleNumber,
      ]);
      for (final cyclePayout in cyclePayouts) {
        final cycle = cyclePayout.cycleNumber;
        final alreadyPaid = await _paidOutPerStudent(groupId, cycle);
        final current = computed[cycle]!;
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

  /// ما يأخذه الأستاذ عن تلاميذ عُيِّن لهم مبلغ غير مبلغ الفوج: معرّف التلميذ ← المبلغ.
  Future<Map<String, int>> _teacherAmounts(String groupId) async {
    final rows = await db
        .customSelect(
          'SELECT student_id, teacher_amount FROM group_students '
          'WHERE group_id = ? AND teacher_amount IS NOT NULL '
          'AND deleted_at IS NULL',
          variables: [Variable<String>(groupId)],
          readsFrom: {db.groupStudents},
        )
        .get();
    return {
      for (final row in rows)
        row.read<String>('student_id'): row.read<int>('teacher_amount'),
    };
  }

  /// خطوط ضيوف حصص الفوج لكل دورة: ما يأخذه الأستاذ عن كل ضيف حضر ودفع، مجموعاً لكل تلميذ.
  Future<Map<int, Map<String, PayoutLine>>> _guestLines(
    String groupId,
    Set<int> cycles,
  ) async {
    final rows = await db
        .customSelect(
          'SELECT g.student_id, g.price, g.teacher_amount, se.cycle_number, '
          '(SELECT COUNT(*) FROM attendance a WHERE a.session_id = se.id '
          "AND a.student_id = g.student_id AND a.status = 'present' "
          'AND a.deleted_at IS NULL) AS present, '
          '(SELECT COALESCE(SUM(p.amount), 0) FROM payments p '
          "WHERE p.student_id = g.student_id AND p.type = 'session' "
          'AND p.period_key = se.id AND p.deleted_at IS NULL) AS paid '
          'FROM session_guests g JOIN sessions se ON se.id = g.session_id '
          'WHERE se.group_id = ? AND g.deleted_at IS NULL '
          'AND se.deleted_at IS NULL',
          variables: [Variable<String>(groupId)],
          readsFrom: {
            db.sessionGuests,
            db.sessions,
            db.attendance,
            db.payments,
          },
        )
        .get();
    final result = <int, Map<String, PayoutLine>>{};
    for (final row in rows) {
      final cycle = row.read<int>('cycle_number');
      if (!cycles.contains(cycle)) continue;
      final studentId = row.read<String>('student_id');
      final present = row.read<int>('present') > 0;
      final price = row.read<int>('price');
      final teacherAmount = row.read<int>('teacher_amount');
      final paid = row.read<int>('paid');
      final earned = !present
          ? 0
          : price <= 0
          ? teacherAmount
          : Money.roundToTen(
              teacherAmount * (paid > price ? price : paid) / price,
            );
      final line = PayoutLine(
        studentId: studentId,
        attended: present ? 1 : 0,
        covered: price <= 0 || paid >= price ? 1 : 0,
        earned: earned,
        full: present ? teacherAmount : 0,
      );
      final byStudent = result.putIfAbsent(cycle, () => {});
      final existing = byStudent[studentId];
      byStudent[studentId] = existing == null
          ? line
          : PayoutLine(
              studentId: studentId,
              attended: existing.attended + line.attended,
              covered: existing.covered + line.covered,
              earned: existing.earned + line.earned,
              full: existing.full + line.full,
            );
    }
    return result;
  }

  static int _covered(CycleDue due, int sessionsPerCycle) =>
      due.coveredSessions(sessionsPerCycle);

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
      id: kind == kindCycle
          ? StableId.cyclePayout(payout.groupId, payout.cycleNumber)
          : writer.newId(),
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
