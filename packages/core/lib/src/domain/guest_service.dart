import 'package:drift/drift.dart';

import '../data/local/app_database.dart';
import '../data/local/sync_writer.dart';
import 'catalog_service.dart';
import 'contact_service.dart';
import 'enums.dart';
import 'money.dart';
import 'payment_service.dart';
import 'phone.dart';
import 'qr_code.dart';

/// ضيف حصة في قائمتها: تلميذ لمرة واحدة، أو تلميذ منتسب إلى فوج آخر، مع ما دفعه.
class SessionGuestItem {
  const SessionGuestItem({
    required this.guest,
    required this.studentName,
    required this.phone,
    required this.singleUse,
    required this.paid,
    required this.present,
  });

  final SessionGuestRow guest;
  final String studentName;
  final String phone;

  /// تلميذ لمرة واحدة (لا ينتسب إلى فوج) يدخل بتذكرته.
  final bool singleUse;
  final int paid;

  /// هل سُجّل حضوره؟
  final bool present;

  String get id => guest.id;
  String get studentId => guest.studentId;
  int get price => guest.price;
  int get teacherAmount => guest.teacherAmount;
  String? get ticketCode => guest.ticketCode;

  /// الباقي من ثمن الحصة.
  int get remaining => price - paid < 0 ? 0 : price - paid;
  bool get isPaid => remaining == 0;
}

/// سعر مقترح لضيف في حصة ومبلغ أستاذها عنه.
class GuestSuggestion {
  const GuestSuggestion({required this.price, required this.teacherAmount});

  final int price;
  final int teacherAmount;
}

/// ضيوف الحصص: تلميذ يحضر حصة واحدة ويدفع ثمنها وحدها.
///
/// - **تلميذ لمرة واحدة**: ليس منتسباً إلى أي فوج (قد لا يكون عندنا أصلاً). يُنشأ له سجل تلميذ مخفي
///   من القائمة العادية، وتذكرة QR تُستعمل مرة واحدة عند الدخول، ويُسجَّل رقمه في دليل الهواتف.
/// - **تلميذ منتسب إلى فوج آخر** يحضر حصة مراجعة أو حصة فوج غير فوجه: يدخل برمزه العادي، وتظهر الحصة
///   في ملفه ضمن حصص المراجعة التي حضرها.
/// - لكل ضيف **سعر** لهذه الحصة (يحدده المدير ويمكن أن يكون صفراً) و**مبلغ للأستاذ** عنها (من مال المدرسة
///   إن لم يدفع الضيف شيئاً). الدفع بوصل عادي من نوع «حصة واحدة»، كله أو بعضه، الآن أو لاحقاً.
class GuestService {
  GuestService(this.db, this.writer, this.payments);

  final AppDatabase db;
  final SyncWriter writer;
  final PaymentService payments;

  static const String fieldName = 'name';
  static const String fieldPhone = 'phone';
  static const String fieldPrice = 'price';
  static const String fieldTeacherAmount = 'teacher_amount';
  static const String fieldPaid = 'paid';
  static const String fieldStudent = 'student';
  static const String fieldSession = 'session';

  static const int _maxAmount = 1000000;

  /// ضيوف الحصة وتتحدث لحظياً، بترتيب إضافتهم.
  Stream<List<SessionGuestItem>> watch(String sessionId) {
    return db
        .customSelect(
          'SELECT 1',
          readsFrom: {
            db.sessionGuests,
            db.students,
            db.payments,
            db.attendance,
          },
        )
        .watch()
        .asyncMap((_) => guests(sessionId));
  }

  Future<List<SessionGuestItem>> guests(String sessionId) async {
    final rows = await db
        .customSelect(
          'SELECT g.*, s.first_name, s.last_name, s.parent_phone, '
          's.single_use, '
          '(SELECT COALESCE(SUM(p.amount), 0) FROM payments p '
          "WHERE p.student_id = g.student_id AND p.type = 'session' "
          'AND p.period_key = g.session_id AND p.deleted_at IS NULL) AS paid, '
          'EXISTS (SELECT 1 FROM attendance a WHERE a.session_id = g.session_id '
          'AND a.student_id = g.student_id '
          "AND a.status = 'present' AND a.deleted_at IS NULL) AS present "
          'FROM session_guests g JOIN students s ON s.id = g.student_id '
          'WHERE g.session_id = ? AND g.deleted_at IS NULL '
          'ORDER BY g.created_at, g.id',
          variables: [Variable<String>(sessionId)],
          readsFrom: {
            db.sessionGuests,
            db.students,
            db.payments,
            db.attendance,
          },
        )
        .get();
    return [
      for (final row in rows)
        SessionGuestItem(
          guest: db.sessionGuests.map(row.data),
          studentName:
              '${row.read<String>('first_name')} ${row.read<String>('last_name')}'
                  .trim(),
          phone: row.read<String>('parent_phone'),
          singleUse: row.read<int>('single_use') != 0,
          paid: row.read<int>('paid'),
          present: row.read<int>('present') != 0,
        ),
    ];
  }

  /// حصص الفوج التي يمكن إضافة ضيف إليها: غير الملغاة ولا المغلقة، من [today] (`YYYY-MM-DD`) فصاعداً،
  /// بترتيبها الزمني. فيضيف المدير تلميذ حصة واحدة إلى أي حصة قادمة في أي وقت من عمر الفوج، ولو بعد
  /// بدء دورته.
  Future<List<SessionRow>> openSessions(
    String groupId, {
    required String today,
  }) =>
      (db.select(db.sessions)
            ..where(
              (s) =>
                  s.groupId.equals(groupId) &
                  s.deletedAt.isNull() &
                  s.closedAt.isNull() &
                  s.status.equals(SessionStatus.cancelled.code).not() &
                  s.date.isBiggerOrEqualValue(today),
            )
            ..orderBy([
              (s) => OrderingTerm.asc(s.date),
              (s) => OrderingTerm.asc(s.startMinutes),
            ]))
          .get();

  /// سعر الحصة ومبلغ الأستاذ المقترحان لضيف في [sessionId]: لحصة المراجعة ثمنها ونصيب أستاذها كاملين،
  /// ولحصة فوج عادي حصة واحدة من سعر الدورة ومن نصيب الأستاذ (مقرَّبتان لأقرب 10).
  Future<GuestSuggestion> suggest(String sessionId) async {
    final session = await _session(sessionId);
    final group = await (db.select(
      db.groups,
    )..where((g) => g.id.equals(session.groupId))).getSingle();
    final rate = group.ratePerStudent ?? 0;
    if (group.isReview || group.sessionsPerCycle <= 1) {
      return GuestSuggestion(price: group.monthlyPrice, teacherAmount: rate);
    }
    return GuestSuggestion(
      price: Money.roundToTen(group.monthlyPrice / group.sessionsPerCycle),
      teacherAmount: Money.roundToTen(rate / group.sessionsPerCycle),
    );
  }

  /// يضيف **تلميذاً لمرة واحدة** إلى [sessionId]: يُنشأ له سجل تلميذ مخفي وتذكرة QR، ويُسجَّل رقمه في
  /// دليل الهواتف، ويدفع [paidNow] من ثمن الحصة [price] فوراً بوصل إن كان موجباً.
  Future<SessionGuestItem> addOneTime({
    required String sessionId,
    required String name,
    String phone = '',
    required int price,
    required int teacherAmount,
    int paidNow = 0,
  }) async {
    final errors = <String, String>{};
    final trimmed = name.trim();
    if (trimmed.isEmpty) errors[fieldName] = 'أدخل اسم التلميذ';
    final cleanPhone = phone.trim();
    if (cleanPhone.isNotEmpty && !PhoneNumbers.isValid(cleanPhone)) {
      errors[fieldPhone] = 'رقم الهاتف يبدأ بـ 05 أو 06 أو 07 ويتبعه 8 أرقام';
    }
    errors.addAll(_amountErrors(price, teacherAmount, paidNow));
    final session = await _openSession(sessionId);
    if (errors.isNotEmpty) throw ValidationException(errors);

    return db.transaction(() async {
      final studentId = writer.newId();
      final parts = trimmed.split(RegExp(r'\s+'));
      await writer.save(
        db.students,
        StudentsCompanion.insert(
          id: studentId,
          createdAt: 0,
          updatedAt: 0,
          firstName: parts.first,
          lastName: parts.length > 1 ? parts.sublist(1).join(' ') : '',
          parentPhone: cleanPhone.isEmpty
              ? ''
              : PhoneNumbers.normalize(cleanPhone),
          qrCode: await _uniqueStudentQr(),
          singleUse: const Value(true),
        ),
        key: {'id': studentId},
      );
      final guest = await _insertGuest(
        session: session,
        studentId: studentId,
        price: price,
        teacherAmount: teacherAmount,
        ticket: await _uniqueTicket(),
      );
      if (cleanPhone.isNotEmpty) {
        await ContactService(
          db,
          writer,
        ).addIfMissing(name: trimmed, phone: cleanPhone, note: 'حضر حصة واحدة');
      }
      if (paidNow > 0) {
        await _pay(session, studentId, paidNow);
      }
      return (await guests(sessionId)).firstWhere((g) => g.id == guest.id);
    });
  }

  /// يضيف **تلميذاً مسجَّلاً** (منتسباً إلى فوج آخر) ضيفاً على [sessionId]؛ يدخل برمزه العادي. تلميذ
  /// لمرة واحدة سبق أن حضر يأخذ تذكرة جديدة.
  Future<SessionGuestItem> addStudent({
    required String sessionId,
    required String studentId,
    required int price,
    required int teacherAmount,
    int paidNow = 0,
  }) async {
    final errors = _amountErrors(price, teacherAmount, paidNow);
    final session = await _openSession(sessionId);
    final student =
        await (db.select(db.students)
              ..where((s) => s.id.equals(studentId) & s.deletedAt.isNull()))
            .getSingleOrNull();
    if (student == null) {
      errors[fieldStudent] = 'اختر تلميذاً';
    } else {
      final enrolled = await db
          .customSelect(
            'SELECT 1 FROM group_students WHERE group_id = ? AND student_id = ? '
            'AND deleted_at IS NULL AND left_at IS NULL',
            variables: [
              Variable<String>(session.groupId),
              Variable<String>(studentId),
            ],
            readsFrom: {db.groupStudents},
          )
          .getSingleOrNull();
      if (enrolled != null) {
        errors[fieldStudent] = 'التلميذ منتسب إلى فوج هذه الحصة';
      }
      final already =
          await (db.select(db.sessionGuests)..where(
                (g) =>
                    g.sessionId.equals(sessionId) &
                    g.studentId.equals(studentId) &
                    g.deletedAt.isNull(),
              ))
              .getSingleOrNull();
      if (already != null) errors[fieldStudent] = 'مضاف إلى هذه الحصة من قبل';
    }
    if (errors.isNotEmpty) throw ValidationException(errors);

    return db.transaction(() async {
      final guest = await _insertGuest(
        session: session,
        studentId: studentId,
        price: price,
        teacherAmount: teacherAmount,
        ticket: student!.singleUse ? await _uniqueTicket() : null,
      );
      if (paidNow > 0) await _pay(session, studentId, paidNow);
      return (await guests(sessionId)).firstWhere((g) => g.id == guest.id);
    });
  }

  /// يحذف ضيفاً لم يحضر ولم يدفع (إضافة بالخطأ). ضيف حضر أو دفع لا يُحذف: يعيد `false`.
  Future<bool> remove(String guestId) {
    return db.transaction(() async {
      final guest = await (db.select(
        db.sessionGuests,
      )..where((g) => g.id.equals(guestId))).getSingleOrNull();
      if (guest == null || guest.deletedAt != null) return false;
      final used = await db
          .customSelect(
            'SELECT 1 FROM attendance WHERE session_id = ? AND student_id = ? '
            'AND deleted_at IS NULL '
            'UNION SELECT 1 FROM payments WHERE student_id = ? '
            "AND type = 'session' AND period_key = ? AND deleted_at IS NULL",
            variables: [
              Variable<String>(guest.sessionId),
              Variable<String>(guest.studentId),
              Variable<String>(guest.studentId),
              Variable<String>(guest.sessionId),
            ],
            readsFrom: {db.attendance, db.payments},
          )
          .getSingleOrNull();
      if (used != null) return false;
      await writer.softDelete(db.sessionGuests, key: {'id': guestId});
      // تلميذ لمرة واحدة لا ضيافة أخرى له يُحذف سجله كذلك.
      final student = await (db.select(
        db.students,
      )..where((s) => s.id.equals(guest.studentId))).getSingleOrNull();
      if (student != null && student.singleUse) {
        final other = await db
            .customSelect(
              'SELECT 1 FROM session_guests WHERE student_id = ? '
              'AND deleted_at IS NULL LIMIT 1',
              variables: [Variable<String>(student.id)],
              readsFrom: {db.sessionGuests},
            )
            .getSingleOrNull();
        if (other == null) {
          await writer.softDelete(db.students, key: {'id': student.id});
        }
      }
      return true;
    });
  }

  // ---------------------------------------------------------------------------
  // داخلي
  // ---------------------------------------------------------------------------

  static Map<String, String> _amountErrors(
    int price,
    int teacherAmount,
    int paidNow,
  ) {
    final errors = <String, String>{};
    if (price < 0 || price % 10 != 0 || price > _maxAmount) {
      errors[fieldPrice] = 'ثمن الحصة من مضاعفات 10 ${Money.currency}';
    }
    if (teacherAmount < 0 ||
        teacherAmount % 10 != 0 ||
        teacherAmount > _maxAmount) {
      errors[fieldTeacherAmount] =
          'مبلغ الأستاذ من مضاعفات 10 ${Money.currency}';
    }
    if (paidNow < 0) {
      errors[fieldPaid] = 'المبلغ المدفوع لا يكون سالباً';
    } else if (!errors.containsKey(fieldPrice) && paidNow > price) {
      errors[fieldPaid] = 'المدفوع يزيد عن ثمن الحصة (${Money.format(price)})';
    }
    return errors;
  }

  Future<SessionRow> _session(String sessionId) async {
    final session =
        await (db.select(db.sessions)
              ..where((s) => s.id.equals(sessionId) & s.deletedAt.isNull()))
            .getSingleOrNull();
    if (session == null) {
      throw ValidationException.field(fieldSession, 'الحصة غير موجودة');
    }
    return session;
  }

  /// حصة تقبل ضيوفاً: موجودة، غير ملغاة، ولم تُغلق.
  Future<SessionRow> _openSession(String sessionId) async {
    final session = await _session(sessionId);
    if (session.status == SessionStatus.cancelled.code) {
      throw ValidationException.field(fieldSession, 'الحصة ملغاة');
    }
    if (session.closedAt != null) {
      throw ValidationException.field(fieldSession, 'انتهت هذه الحصة');
    }
    return session;
  }

  Future<SessionGuestRow> _insertGuest({
    required SessionRow session,
    required String studentId,
    required int price,
    required int teacherAmount,
    String? ticket,
  }) async {
    final id = writer.newId();
    await writer.save(
      db.sessionGuests,
      SessionGuestsCompanion.insert(
        id: id,
        createdAt: 0,
        updatedAt: 0,
        sessionId: session.id,
        studentId: studentId,
        price: Value(price),
        teacherAmount: Value(teacherAmount),
        ticketCode: Value(ticket),
      ),
      key: {'id': id},
    );
    return (db.select(
      db.sessionGuests,
    )..where((g) => g.id.equals(id))).getSingle();
  }

  Future<void> _pay(SessionRow session, String studentId, int amount) async {
    await payments.record(
      studentId: studentId,
      type: PaymentType.session,
      amount: amount,
      groupId: session.groupId,
      cycleNumber: session.cycleNumber,
      periodKey: session.id,
    );
  }

  Future<String> _uniqueStudentQr() async {
    for (var i = 0; i < 10; i++) {
      final code = QrCodes.generate(QrOwnerKind.student);
      final clash = await (db.select(
        db.students,
      )..where((s) => s.qrCode.equals(code))).get();
      if (clash.isEmpty) return code;
    }
    throw StateError('تعذّر توليد رمز QR فريد');
  }

  Future<String> _uniqueTicket() async {
    for (var i = 0; i < 10; i++) {
      final code = QrCodes.generate(QrOwnerKind.guest);
      final clash = await (db.select(
        db.sessionGuests,
      )..where((g) => g.ticketCode.equals(code))).get();
      if (clash.isEmpty) return code;
    }
    throw StateError('تعذّر توليد تذكرة فريدة');
  }
}
