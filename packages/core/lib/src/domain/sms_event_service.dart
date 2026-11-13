import 'package:drift/drift.dart';

import '../data/local/app_database.dart';
import '../data/local/sync_writer.dart';
import 'date_key.dart';
import 'dues_service.dart';
import 'enums.dart';
import 'money.dart';
import 'phone.dart';
import 'setting_keys.dart';
import 'sms_templates.dart';

/// يربط أحداث النظام بقوالب SMS ويضع الرسائل في الطابور المحلي.
///
/// لا يرسل مباشرةً؛ عامل `packages/sms` يتولى الإرسال وساعات الهدوء. وكل
/// رسالة مرتبطة بمفتاح حدث ثابت لمنع تكرارها عبر إعادة معالجة الحدث.
class SmsEventService {
  SmsEventService(this.db, this.writer);

  final AppDatabase db;
  final SyncWriter writer;

  static const Duration absenceDelay = Duration(minutes: 15);
  static const String correctedAbsenceMessage =
      'صُحّح تسجيل الحضور قبل موعد إرسال التنبيه.';

  static const List<String> _weekdays = [
    '',
    'الاثنين',
    'الثلاثاء',
    'الأربعاء',
    'الخميس',
    'الجمعة',
    'السبت',
    'الأحد',
  ];

  /// يضع تنبيهاً لكل غياب سجله الإغلاق التلقائي، بعد 15 دقيقة.
  Future<int> attendanceAbsent({
    required String sessionId,
    required Iterable<String> studentIds,
  }) async {
    final session = await db
        .customSelect(
          'SELECT se.date, se.end_minutes, sub.name AS subject FROM sessions se '
          'JOIN groups g ON g.id = se.group_id '
          'JOIN subjects sub ON sub.id = g.subject_id WHERE se.id = ?',
          variables: [Variable<String>(sessionId)],
          readsFrom: {db.sessions, db.groups, db.subjects},
        )
        .getSingleOrNull();
    if (session == null) return 0;

    final wantedStudents = studentIds.toSet();
    final absentStudents = await db
        .customSelect(
          'SELECT s.id, s.first_name, s.last_name, s.parent_phone '
          'FROM attendance a JOIN students s ON s.id = a.student_id '
          'WHERE a.session_id = ? AND a.status = ? AND a.deleted_at IS NULL '
          'AND s.deleted_at IS NULL',
          variables: [
            Variable<String>(sessionId),
            Variable<String>(AttendanceStatus.absent.code),
          ],
          readsFrom: {db.attendance, db.students},
        )
        .get();
    var queued = 0;
    for (final student in absentStudents) {
      final studentId = student.read<String>('id');
      if (!wantedStudents.contains(studentId)) continue;
      final name =
          '${student.read<String>('first_name')} '
          '${student.read<String>('last_name')}';
      final notBeforeAt = DateKey.parse(session.read<String>('date')).add(
        Duration(
          minutes: session.read<int>('end_minutes') + absenceDelay.inMinutes,
        ),
      );
      final didQueue = await _enqueueTemplate(
        phone: student.read<String>('parent_phone'),
        key: SmsTemplateKeys.attendanceAbsent,
        eventKey: 'attendance_absent:$sessionId:$studentId',
        values: {
          'name': name,
          'subject': session.read<String>('subject'),
          'date': session.read<String>('date'),
        },
        notBeforeAt: notBeforeAt,
      );
      if (didQueue) queued++;
    }
    return queued;
  }

  /// يلغي تنبيه الغياب المؤجل إذا صُحّح الحضور قبل موعد الإرسال.
  Future<bool> cancelPendingAbsence({
    required String sessionId,
    required String studentId,
  }) async {
    final row =
        await (db.select(db.smsQueue)..where(
              (sms) =>
                  sms.eventKey.equals(
                    'attendance_absent:$sessionId:$studentId',
                  ) &
                  sms.status.equals(SmsStatus.pending.code),
            ))
            .getSingleOrNull();
    if (row == null) return false;
    return writer.patch(
      db.smsQueue,
      key: {'id': row.id},
      values: {
        'status': SmsStatus.cancelled.code,
        'last_error': correctedAbsenceMessage,
        'not_before': null,
      },
    );
  }

  /// عند بلوغ الحد، يخبر كل وليّ منتظراً مرة واحدة في هذا الحدث.
  Future<int> waitingThreshold({
    required String listId,
    required int reachedAt,
  }) async {
    final list = await db
        .customSelect(
          'SELECT sub.name AS subject, lv.name AS level '
          'FROM waiting_lists l JOIN subjects sub ON sub.id = l.subject_id '
          'LEFT JOIN levels lv ON lv.id = l.level_id WHERE l.id = ?',
          variables: [Variable<String>(listId)],
          readsFrom: {db.waitingLists, db.subjects, db.levels},
        )
        .getSingleOrNull();
    if (list == null) return 0;
    final level = list.read<String?>('level');
    final subject = level == null
        ? list.read<String>('subject')
        : '${list.read<String>('subject')} · $level';
    final students = await db
        .customSelect(
          'SELECT s.id, s.first_name, s.last_name, s.parent_phone '
          'FROM waiting_entries e JOIN students s ON s.id = e.student_id '
          'WHERE e.waiting_list_id = ? AND e.deleted_at IS NULL '
          'AND s.deleted_at IS NULL ORDER BY e.added_at, e.id',
          variables: [Variable<String>(listId)],
          readsFrom: {db.waitingEntries, db.students},
        )
        .get();
    final namesByPhone = <String, Set<String>>{};
    for (final student in students) {
      final phone = student.read<String>('parent_phone');
      if (!PhoneNumbers.isValid(phone)) continue;
      namesByPhone
          .putIfAbsent(PhoneNumbers.toInternational(phone), () => <String>{})
          .add(
            '${student.read<String>('first_name')} '
            '${student.read<String>('last_name')}',
          );
    }
    var queued = 0;
    for (final entry in namesByPhone.entries) {
      final didQueue = await _enqueueTemplate(
        phone: entry.key,
        key: SmsTemplateKeys.waitingThreshold,
        eventKey: 'waiting_threshold:$listId:$reachedAt:${entry.key}',
        values: {
          'name': entry.value.join('، '),
          'subject': subject,
          'count': '${students.length}',
        },
      );
      if (didQueue) queued++;
    }
    return queued;
  }

  /// عند إنشاء مجموعة جديدة، يخبر أولياء التلاميذ المنتظرين للمادة.
  Future<int> groupCreated(String groupId) async {
    final group = await db
        .customSelect(
          'SELECT g.number, g.subject_id, sub.name AS subject '
          'FROM groups g JOIN subjects sub ON sub.id = g.subject_id '
          'WHERE g.id = ?',
          variables: [Variable<String>(groupId)],
          readsFrom: {db.groups, db.subjects},
        )
        .getSingleOrNull();
    if (group == null) return 0;
    final rows = await db
        .customSelect(
          'SELECT DISTINCT s.id, s.first_name, s.last_name, s.parent_phone '
          'FROM waiting_lists l JOIN waiting_entries e '
          'ON e.waiting_list_id = l.id AND e.deleted_at IS NULL '
          'JOIN students s ON s.id = e.student_id AND s.deleted_at IS NULL '
          'WHERE l.subject_id = ? AND l.deleted_at IS NULL '
          'ORDER BY s.last_name, s.first_name, s.id',
          variables: [Variable<String>(group.read<String>('subject_id'))],
          readsFrom: {db.waitingLists, db.waitingEntries, db.students},
        )
        .get();
    final slots =
        await (db.select(db.groupSlots)
              ..where(
                (slot) =>
                    slot.groupId.equals(groupId) & slot.deletedAt.isNull(),
              )
              ..orderBy([
                (slot) => OrderingTerm.asc(slot.weekday),
                (slot) => OrderingTerm.asc(slot.startMinutes),
              ]))
            .get();
    final schedule = slots
        .map(
          (slot) =>
              '${_weekdays[slot.weekday]} '
              '${DateKey.formatMinutes(slot.startMinutes)}–'
              '${DateKey.formatMinutes(slot.endMinutes)}',
        )
        .join('، ');

    final namesByPhone = <String, Set<String>>{};
    for (final student in rows) {
      final phone = student.read<String>('parent_phone');
      if (!PhoneNumbers.isValid(phone)) continue;
      namesByPhone
          .putIfAbsent(PhoneNumbers.toInternational(phone), () => <String>{})
          .add(
            '${student.read<String>('first_name')} '
            '${student.read<String>('last_name')}',
          );
    }
    var queued = 0;
    for (final entry in namesByPhone.entries) {
      final didQueue = await _enqueueTemplate(
        phone: entry.key,
        key: SmsTemplateKeys.groupCreated,
        eventKey: 'group_created:$groupId:${entry.key}',
        values: {
          'name': entry.value.join('، '),
          'subject': group.read<String>('subject'),
          'group': '${group.read<int>('number')}',
          'schedule': schedule.isEmpty ? 'يُحدَّد لاحقاً' : schedule,
        },
      );
      if (didQueue) queued++;
    }
    return queued;
  }

  /// يخبر أولياء المجموعة باكتمال الدورة، مع الباقي على كل تلميذ.
  Future<int> cycleCompleted({
    required String groupId,
    required int cycleNumber,
  }) async {
    final group = await db
        .customSelect(
          'SELECT g.subject_id, sub.name AS subject FROM groups g '
          'JOIN subjects sub ON sub.id = g.subject_id WHERE g.id = ?',
          variables: [Variable<String>(groupId)],
          readsFrom: {db.groups, db.subjects},
        )
        .getSingleOrNull();
    if (group == null) return 0;
    final dues = await DuesService(
      db,
      writer,
    ).cycleDues(groupId: groupId, cycleNumber: cycleNumber);
    final contacts = await _groupStudentContacts(groupId);
    final namesByPhone = <String, Set<String>>{};
    final amountsByPhone = <String, int>{};
    for (final due in dues) {
      final student = contacts[due.studentId];
      if (student == null || !PhoneNumbers.isValid(student.phone)) continue;
      final phone = PhoneNumbers.toInternational(student.phone);
      namesByPhone.putIfAbsent(phone, () => <String>{}).add(student.name);
      amountsByPhone.update(
        phone,
        (amount) => amount + due.remaining,
        ifAbsent: () => due.remaining,
      );
    }
    var queued = 0;
    for (final entry in namesByPhone.entries) {
      final didQueue = await _enqueueTemplate(
        phone: entry.key,
        key: SmsTemplateKeys.cycleCompleted,
        eventKey: 'cycle_completed:$groupId:$cycleNumber:${entry.key}',
        values: {
          'name': entry.value.join('، '),
          'subject': group.read<String>('subject'),
          'cycle': '$cycleNumber',
          'amount': Money.format(amountsByPhone[entry.key]!),
        },
      );
      if (didQueue) queued++;
    }
    return queued;
  }

  /// يذكّر مرة واحدة بعد بلوغ عدد الحصص المحدد في إعدادات المدرسة.
  Future<int> paymentReminders({
    required String groupId,
    required int cycleNumber,
  }) async {
    final group = await db
        .customSelect(
          'SELECT sub.name AS subject FROM groups g '
          'JOIN subjects sub ON sub.id = g.subject_id WHERE g.id = ?',
          variables: [Variable<String>(groupId)],
          readsFrom: {db.groups, db.subjects},
        )
        .getSingleOrNull();
    if (group == null) return 0;
    final dues = await DuesService(
      db,
      writer,
    ).cycleDues(groupId: groupId, cycleNumber: cycleNumber, unpaidOnly: true);
    final contacts = await _groupStudentContacts(groupId);
    final namesByPhone = <String, Set<String>>{};
    final amountsByPhone = <String, int>{};
    for (final due in dues) {
      final student = contacts[due.studentId];
      if (student == null || !PhoneNumbers.isValid(student.phone)) continue;
      final phone = PhoneNumbers.toInternational(student.phone);
      namesByPhone.putIfAbsent(phone, () => <String>{}).add(student.name);
      amountsByPhone.update(
        phone,
        (amount) => amount + due.remaining,
        ifAbsent: () => due.remaining,
      );
    }
    var queued = 0;
    for (final entry in namesByPhone.entries) {
      final didQueue = await _enqueueTemplate(
        phone: entry.key,
        key: SmsTemplateKeys.paymentReminder,
        eventKey: 'payment_reminder:$groupId:$cycleNumber:${entry.key}',
        values: {
          'name': entry.value.join('، '),
          'subject': group.read<String>('subject'),
          'cycle': '$cycleNumber',
          'amount': Money.format(amountsByPhone[entry.key]!),
        },
      );
      if (didQueue) queued++;
    }
    return queued;
  }

  /// يضع رسالة الوصل لولي التلميذ بعد حفظ الدفعة بنجاح.
  Future<bool> paymentReceipt(PaymentRow payment) async {
    final student = await _studentContact(payment.studentId);
    if (student == null) return false;
    final type = PaymentType.fromCode(payment.type);
    var item = type.label;
    var subject = '';
    switch (type) {
      case PaymentType.month:
        final row = await db
            .customSelect(
              'SELECT sub.name FROM groups g JOIN subjects sub '
              'ON sub.id = g.subject_id WHERE g.id = ?',
              variables: [Variable<String>(payment.groupId!)],
              readsFrom: {db.groups, db.subjects},
            )
            .getSingleOrNull();
        subject = row?.read<String>('name') ?? '';
        item = '$subject · الدورة ${payment.cycleNumber}';
      case PaymentType.registrationFee:
        item = 'حقوق التسجيل ${payment.periodKey}';
      case PaymentType.transport:
        item = 'النقل ${payment.periodKey}';
    }
    return _enqueueTemplate(
      phone: student.phone,
      key: SmsTemplateKeys.paymentReceipt,
      eventKey: 'payment_receipt:${payment.id}',
      values: {
        'name': student.name,
        'receipt': payment.receiptNumber,
        'amount': Money.format(payment.amount),
        'item': item,
        'subject': subject,
      },
    );
  }

  /// يرسل قرار الموافقة لوليّ كل مجموعة، برسالة واحدة لكل رقم هاتف.
  Future<int> requestApproved({
    required String requestId,
    required String groupId,
    required String summary,
  }) async {
    final group = await db
        .customSelect(
          'SELECT g.number, sub.name AS subject FROM groups g '
          'JOIN subjects sub ON sub.id = g.subject_id WHERE g.id = ?',
          variables: [Variable<String>(groupId)],
          readsFrom: {db.groups, db.subjects},
        )
        .getSingleOrNull();
    if (group == null) return 0;
    final rows = await db
        .customSelect(
          'SELECT s.first_name, s.last_name, s.parent_phone '
          'FROM group_students gs JOIN students s ON s.id = gs.student_id '
          'WHERE gs.group_id = ? AND gs.deleted_at IS NULL '
          'AND gs.left_at IS NULL AND s.deleted_at IS NULL',
          variables: [Variable<String>(groupId)],
          readsFrom: {db.groupStudents, db.students},
        )
        .get();
    final namesByPhone = <String, Set<String>>{};
    for (final row in rows) {
      final phone = row.read<String>('parent_phone');
      if (!PhoneNumbers.isValid(phone)) continue;
      namesByPhone
          .putIfAbsent(PhoneNumbers.toInternational(phone), () => <String>{})
          .add(
            '${row.read<String>('first_name')} ${row.read<String>('last_name')}',
          );
    }
    var queued = 0;
    for (final entry in namesByPhone.entries) {
      final didQueue = await _enqueueTemplate(
        phone: entry.key,
        key: SmsTemplateKeys.requestApproved,
        eventKey: 'request_approved:$requestId:${entry.key}',
        values: {
          'name': entry.value.join('، '),
          'subject': group.read<String>('subject'),
          'group': '${group.read<int>('number')}',
          'summary': summary,
        },
      );
      if (didQueue) queued++;
    }
    return queued;
  }

  /// يرسل الرفض إلى هاتف الأستاذ صاحب الطلب.
  Future<bool> requestRejected({
    required String requestId,
    required String teacherId,
    required String request,
    required String note,
  }) async {
    final teacher =
        await (db.select(db.teachers)..where(
              (row) => row.id.equals(teacherId) & row.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    if (teacher == null) return false;
    return _enqueueTemplate(
      phone: teacher.phone,
      key: SmsTemplateKeys.requestRejected,
      eventKey: 'request_rejected:$requestId',
      values: {
        'name': teacher.name,
        'request': request,
        'note': note.trim().isEmpty ? 'دون ملاحظة' : note.trim(),
      },
    );
  }

  Future<_StudentContact?> _studentContact(String studentId) async {
    final row =
        await (db.select(db.students)..where(
              (student) =>
                  student.id.equals(studentId) & student.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    if (row == null) return null;
    return _StudentContact(
      name: '${row.firstName} ${row.lastName}',
      phone: row.parentPhone,
    );
  }

  Future<Map<String, _StudentContact>> _groupStudentContacts(
    String groupId,
  ) async {
    final rows = await db
        .customSelect(
          'SELECT s.id, s.first_name, s.last_name, s.parent_phone '
          'FROM group_students gs JOIN students s ON s.id = gs.student_id '
          'WHERE gs.group_id = ? AND gs.deleted_at IS NULL '
          'AND s.deleted_at IS NULL',
          variables: [Variable<String>(groupId)],
          readsFrom: {db.groupStudents, db.students},
        )
        .get();
    return {
      for (final row in rows)
        row.read<String>('id'): _StudentContact(
          name:
              '${row.read<String>('first_name')} '
              '${row.read<String>('last_name')}',
          phone: row.read<String>('parent_phone'),
        ),
    };
  }

  Future<bool> _enqueueTemplate({
    required String phone,
    required String key,
    required String eventKey,
    required Map<String, String> values,
    DateTime? notBeforeAt,
  }) async {
    if (!PhoneNumbers.isValid(phone)) return false;
    final existing = await (db.select(
      db.smsQueue,
    )..where((row) => row.eventKey.equals(eventKey))).getSingleOrNull();
    if (existing != null) return false;
    final school =
        await (db.select(db.settings)
              ..where((setting) => setting.key.equals(SettingKeys.schoolName)))
            .getSingleOrNull();
    final schoolName = school?.value.trim() ?? '';
    final message = await SmsTemplateRenderer(db).render(key, {
      'school': schoolName.isEmpty ? 'المدرسة' : schoolName,
      ...values,
    });
    if (message.trim().isEmpty) return false;
    final stamp = writer.now();
    final id = writer.newId();
    await writer.save(
      db.smsQueue,
      SmsQueueCompanion.insert(
        id: id,
        createdAt: stamp,
        updatedAt: stamp,
        phone: PhoneNumbers.toInternational(phone),
        message: message.trim(),
        status: Value(SmsStatus.pending.code),
        kind: Value(key),
        notBefore: Value(
          notBeforeAt != null && notBeforeAt.millisecondsSinceEpoch > stamp
              ? notBeforeAt.millisecondsSinceEpoch
              : null,
        ),
        createdBy: Value(writer.actor().userId),
        eventKey: Value(eventKey),
      ),
      key: {'id': id},
    );
    return true;
  }
}

class _StudentContact {
  const _StudentContact({required this.name, required this.phone});

  final String name;
  final String phone;
}
