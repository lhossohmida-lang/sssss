import 'package:drift/drift.dart';

import '../data/local/app_database.dart';
import '../data/local/sync_writer.dart';
import 'cycle_service.dart';
import 'date_key.dart';
import 'enums.dart';
import 'phone.dart';
import 'schedule_service.dart';

/// الموعد المطلوب يتعارض مع قاعة أو أستاذ.
class ScheduleConflictException implements Exception {
  const ScheduleConflictException(this.conflicts);

  final List<ScheduleConflict> conflicts;

  @override
  String toString() => conflicts.map((c) => c.message).join('، ');
}

/// طلب غير صالح (بيانات ناقصة أو حالة لا تسمح).
class InvalidRequestException implements Exception {
  const InvalidRequestException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// نتيجة الموافقة على طلب.
class ApprovalResult {
  const ApprovalResult({required this.request, required this.smsQueued});

  final SessionRequestRow request;

  /// عدد رسائل SMS التي وُضعت في الطابور لأولياء المجموعة.
  final int smsQueued;
}

/// نتيجة فحص طلب قبل إرساله: تعارضه، والقاعة المقترحة، وما يمنع إرساله.
class RequestPreview {
  const RequestPreview({
    this.conflicts = const [],
    this.suggestedRoom,
    this.error,
  });

  /// تعارضات الموعد مع الأستاذ أو القاعة.
  final List<ScheduleConflict> conflicts;

  /// القاعة التي ستُحجز تلقائياً حين لا يحدد الأستاذ قاعة (قد تكون `null` إن
  /// لم توجد قاعة متاحة).
  final RoomRow? suggestedRoom;

  /// سبب آخر يمنع الإرسال (بيانات ناقصة أو حصة منعقدة...).
  final String? error;

  /// هل يمكن إرسال الطلب؟
  bool get ok => error == null && conflicts.isEmpty;
}

/// طلب في قائمة الأستاذ مع وصف مجموعته وحصته.
class RequestItem {
  const RequestItem({
    required this.request,
    required this.groupNumber,
    required this.subjectName,
    this.sessionDate,
    this.sessionStart,
  });

  final SessionRequestRow request;
  final int groupNumber;
  final String subjectName;
  final String? sessionDate;
  final int? sessionStart;

  String get id => request.id;
  SessionRequestType get type => SessionRequestType.fromCode(request.type);
  SessionRequestStatus get status =>
      SessionRequestStatus.fromCode(request.status);
  String get groupLabel => 'المجموعة $groupNumber · $subjectName';
}

/// دورة حياة طلبات الأستاذ: إنشاء ← (موافقة مع تعديل | رفض).
///
/// لا يتغير أي موعد دون موافقة المدير.
class RequestService {
  RequestService(this.db, this.writer, this.schedule, this.cycles);

  final AppDatabase db;
  final SyncWriter writer;
  final ScheduleService schedule;
  final CycleService cycles;

  static const String notifyPending = 'request_pending';
  static const String notifyApproved = 'request_approved';
  static const String notifyRejected = 'request_rejected';
  static const String notifyScheduleChange = 'schedule_change';
  static const String smsKind = 'schedule_change';

  /// الأستاذ يرسل طلباً. يُفحص التعارض فوراً:
  /// - تعارض الأستاذ يرفض الطلب.
  /// - إن لم تُحدَّد قاعة تُقترح قاعة متاحة تلقائياً.
  /// - القاعة المحددة إن كانت محجوزة يُرفض الطلب.
  Future<SessionRequestRow> submit({
    required String teacherId,
    required String groupId,
    required SessionRequestType type,
    String? sessionId,
    String? newDate,
    int? newStartMinutes,
    int? newEndMinutes,
    String? newRoomId,
    String reason = '',
  }) {
    return db.transaction(() async {
      final group = await _group(groupId);
      if (group.teacherId != teacherId) {
        throw const InvalidRequestException('هذه المجموعة ليست من مجموعاتك');
      }
      final session = await _targetSession(type, sessionId, groupId);
      String? roomId = newRoomId;
      if (type.needsNewSlot) {
        if (newDate == null ||
            newStartMinutes == null ||
            newEndMinutes == null) {
          throw const InvalidRequestException('حدّد التاريخ والوقت الجديدين');
        }
        if (type == SessionRequestType.advance &&
            !_isEarlier(newDate, newStartMinutes, session!)) {
          throw const InvalidRequestException(
            'تسبيق الحصة يكون إلى موعد قبل موعدها الحالي',
          );
        }
        roomId = await _resolveRoom(
          group: group,
          date: newDate,
          start: newStartMinutes,
          end: newEndMinutes,
          roomId: newRoomId,
          excludeSessionId: session?.id,
        );
      }

      final stamp = writer.now();
      final request = SessionRequestRow(
        id: writer.newId(),
        createdAt: stamp,
        updatedAt: stamp,
        teacherId: teacherId,
        groupId: groupId,
        type: type.code,
        sessionId: session?.id,
        newDate: type.needsNewSlot ? newDate : null,
        newStartMinutes: type.needsNewSlot ? newStartMinutes : null,
        newEndMinutes: type.needsNewSlot ? newEndMinutes : null,
        newRoomId: type.needsNewSlot ? roomId : null,
        reason: reason.trim(),
        status: SessionRequestStatus.pending.code,
        adminNote: '',
      );
      await writer.save(db.sessionRequests, request, key: {'id': request.id});

      final teacher = await _teacher(teacherId);
      for (final owner in await _accounts(UserRole.owner)) {
        await _notify(
          userId: owner.id,
          kind: notifyPending,
          title: 'طلب جديد من ${teacher.name}',
          body: '${type.label} — المجموعة ${group.number}',
          entityId: request.id,
        );
      }
      return request;
    });
  }

  /// يفحص طلباً دون إرساله: تعارض الموعد مع الأستاذ أو القاعة، والقاعة
  /// المقترحة إن لم تُحدَّد قاعة، وأي سبب آخر يمنع الإرسال. لا يكتب شيئاً.
  Future<RequestPreview> preview({
    required String teacherId,
    required String groupId,
    required SessionRequestType type,
    String? sessionId,
    String? newDate,
    int? newStartMinutes,
    int? newEndMinutes,
    String? newRoomId,
  }) async {
    try {
      final group = await _group(groupId);
      if (group.teacherId != teacherId) {
        return const RequestPreview(error: 'هذه المجموعة ليست من مجموعاتك');
      }
      final session = await _targetSession(type, sessionId, groupId);
      if (!type.needsNewSlot) return const RequestPreview();
      if (newDate == null || newStartMinutes == null || newEndMinutes == null) {
        return const RequestPreview(error: 'حدّد التاريخ والوقت الجديدين');
      }
      if (newEndMinutes <= newStartMinutes) {
        return const RequestPreview(error: 'نهاية الحصة بعد بدايتها');
      }
      if (type == SessionRequestType.advance &&
          !_isEarlier(newDate, newStartMinutes, session!)) {
        return const RequestPreview(
          error: 'تسبيق الحصة يكون إلى موعد قبل موعدها الحالي',
        );
      }
      final conflicts = await schedule.dateConflicts(
        date: newDate,
        startMinutes: newStartMinutes,
        endMinutes: newEndMinutes,
        teacherId: teacherId,
        roomId: newRoomId,
        excludeSessionId: session?.id,
      );
      if (conflicts.isNotEmpty) return RequestPreview(conflicts: conflicts);
      if (newRoomId != null) return const RequestPreview();
      return RequestPreview(
        suggestedRoom: await schedule.suggestRoom(
          date: newDate,
          startMinutes: newStartMinutes,
          endMinutes: newEndMinutes,
          preferredRoomId: group.roomId,
          excludeSessionId: session?.id,
        ),
      );
    } on InvalidRequestException catch (e) {
      return RequestPreview(error: e.message);
    }
  }

  /// حصص المجموعة التي يمكن طلب تغييرها: غير المنعقدة ولا الملغاة من اليوم
  /// فصاعداً، الأقرب أولاً.
  Future<List<SessionRow>> openSessions(
    String groupId, {
    required String fromDate,
    int limit = 30,
  }) =>
      (db.select(db.sessions)
            ..where(
              (s) =>
                  s.groupId.equals(groupId) &
                  s.deletedAt.isNull() &
                  s.closedAt.isNull() &
                  s.status.equals(SessionStatus.cancelled.code).not() &
                  s.date.isBiggerOrEqualValue(fromDate),
            )
            ..orderBy([
              (s) => OrderingTerm(expression: s.date),
              (s) => OrderingTerm(expression: s.startMinutes),
            ])
            ..limit(limit))
          .get();

  /// طلبات الأستاذ، الأحدث أولاً، ولحظياً.
  Stream<List<RequestItem>> watchMine(String teacherId) {
    return db
        .customSelect(
          'SELECT 1',
          readsFrom: {db.sessionRequests, db.groups, db.subjects, db.sessions},
        )
        .watch()
        .asyncMap((_) => mine(teacherId));
  }

  Future<List<RequestItem>> mine(String teacherId) async {
    final rows = await db
        .customSelect(
          'SELECT r.id, g.number, sub.name AS subject, se.date, '
          'se.start_minutes FROM session_requests r '
          'JOIN groups g ON g.id = r.group_id '
          'JOIN subjects sub ON sub.id = g.subject_id '
          'LEFT JOIN sessions se ON se.id = r.session_id '
          'WHERE r.teacher_id = ? AND r.deleted_at IS NULL '
          'ORDER BY r.created_at DESC, r.id DESC',
          variables: [Variable<String>(teacherId)],
          readsFrom: {db.sessionRequests, db.groups, db.subjects, db.sessions},
        )
        .get();
    if (rows.isEmpty) return const [];
    final byId = {
      for (final r
          in await (db.select(db.sessionRequests)..where(
                (r) => r.id.isIn([for (final x in rows) x.read<String>('id')]),
              ))
              .get())
        r.id: r,
    };
    return [
      for (final row in rows)
        RequestItem(
          request: byId[row.read<String>('id')]!,
          groupNumber: row.read<int>('number'),
          subjectName: row.read<String>('subject'),
          sessionDate: row.read<String?>('date'),
          sessionStart: row.read<int?>('start_minutes'),
        ),
    ];
  }

  /// عدد الطلبات المعلّقة (للشارة عند صاحب المدرسة).
  Future<int> pendingCount() async {
    final row = await db
        .customSelect(
          "SELECT COUNT(*) AS c FROM session_requests WHERE status = 'pending' "
          'AND deleted_at IS NULL',
          readsFrom: {db.sessionRequests},
        )
        .getSingle();
    return row.read<int>('c');
  }

  /// المدير يوافق، ويمكنه تعديل التاريخ أو الوقت أو القاعة.
  ///
  /// يُحدَّث الجدول، وتُرسل SMS وإشعار لأولياء كل تلاميذ المجموعة، وإشعار
  /// للأستاذ. يُعاد فحص التعارض لأن الجدول قد تغيّر منذ إرسال الطلب.
  Future<ApprovalResult> approve(
    String requestId, {
    required String reviewerId,
    String? date,
    int? startMinutes,
    int? endMinutes,
    String? roomId,
    String note = '',
  }) {
    return db.transaction(() async {
      final request = await _pending(requestId);
      final type = SessionRequestType.fromCode(request.type);
      final group = await _group(request.groupId);
      final session = request.sessionId == null
          ? null
          : await _session(request.sessionId!);

      final finalDate = date ?? request.newDate;
      final finalStart = startMinutes ?? request.newStartMinutes;
      final finalEnd = endMinutes ?? request.newEndMinutes;
      String? finalRoom = roomId ?? request.newRoomId;
      final String summary;

      if (type.needsNewSlot) {
        finalRoom = await _resolveRoom(
          group: group,
          date: finalDate!,
          start: finalStart!,
          end: finalEnd!,
          roomId: finalRoom,
          excludeSessionId: session?.id,
        );
        final slot =
            '${_dayLabel(finalDate)} $finalDate من '
            '${DateKey.formatMinutes(finalStart)} إلى '
            '${DateKey.formatMinutes(finalEnd)}';
        if (type == SessionRequestType.addSession) {
          await cycles.addSession(
            groupId: group.id,
            date: finalDate,
            startMinutes: finalStart,
            endMinutes: finalEnd,
            roomId: finalRoom,
          );
          summary = 'حصة إضافية يوم $slot';
        } else {
          _ensureOpen(session!);
          await writer.save(
            db.sessions,
            session.copyWith(
              date: finalDate,
              startMinutes: finalStart,
              endMinutes: finalEnd,
              roomId: Value(finalRoom),
            ),
            key: {'id': session.id},
          );
          await cycles.renumber(group.id, session.cycleNumber);
          summary =
              'حصة ${session.date} '
              '${type == SessionRequestType.advance ? 'سُبّقت' : 'نُقلت'} '
              'إلى $slot';
        }
      } else {
        _ensureOpen(session!);
        await cycles.cancelSession(session.id);
        summary =
            'أُلغيت حصة ${_dayLabel(session.date)} ${session.date} '
            'على ${DateKey.formatMinutes(session.startMinutes)}';
      }

      final updated = request.copyWith(
        status: SessionRequestStatus.approved.code,
        reviewedBy: Value(reviewerId),
        reviewedAt: Value(writer.now()),
        adminNote: note.trim(),
        newDate: Value(type.needsNewSlot ? finalDate : null),
        newStartMinutes: Value(type.needsNewSlot ? finalStart : null),
        newEndMinutes: Value(type.needsNewSlot ? finalEnd : null),
        newRoomId: Value(type.needsNewSlot ? finalRoom : null),
      );
      await writer.save(db.sessionRequests, updated, key: {'id': updated.id});

      final subject = await (db.select(
        db.subjects,
      )..where((s) => s.id.equals(group.subjectId))).getSingle();
      final message = '${subject.name} (المجموعة ${group.number}): $summary';
      final smsQueued = await _informParents(group.id, message, updated.id);

      final teacherAccount = await _account(
        UserRole.teacher,
        request.teacherId,
      );
      if (teacherAccount != null) {
        await _notify(
          userId: teacherAccount.id,
          kind: notifyApproved,
          title: 'قُبل طلبك: ${type.label}',
          body: note.trim().isEmpty ? summary : '$summary — ${note.trim()}',
          entityId: updated.id,
        );
      }
      return ApprovalResult(request: updated, smsQueued: smsQueued);
    });
  }

  /// المدير يرفض مع ملاحظة. يُشعَر الأستاذ بالسبب ولا يتغير شيء في الجدول.
  Future<SessionRequestRow> reject(
    String requestId, {
    required String reviewerId,
    required String note,
  }) {
    return db.transaction(() async {
      final request = await _pending(requestId);
      final type = SessionRequestType.fromCode(request.type);
      final updated = request.copyWith(
        status: SessionRequestStatus.rejected.code,
        reviewedBy: Value(reviewerId),
        reviewedAt: Value(writer.now()),
        adminNote: note.trim(),
      );
      await writer.save(db.sessionRequests, updated, key: {'id': updated.id});

      final teacherAccount = await _account(
        UserRole.teacher,
        request.teacherId,
      );
      if (teacherAccount != null) {
        await _notify(
          userId: teacherAccount.id,
          kind: notifyRejected,
          title: 'رُفض طلبك: ${type.label}',
          body: note.trim().isEmpty ? 'دون ملاحظة' : note.trim(),
          entityId: updated.id,
        );
      }
      return updated;
    });
  }

  // ---------------------------------------------------------------------------

  /// يضع SMS لكل وليّ (رقم واحد مهما كان عدد أبنائه) وإشعاراً لحسابه.
  Future<int> _informParents(
    String groupId,
    String message,
    String requestId,
  ) async {
    final rows = await db
        .customSelect(
          'SELECT DISTINCT s.parent_phone, s.parent_account_id '
          'FROM group_students gs JOIN students s ON s.id = gs.student_id '
          'WHERE gs.group_id = ? AND gs.deleted_at IS NULL '
          'AND gs.left_at IS NULL AND s.deleted_at IS NULL',
          variables: [Variable<String>(groupId)],
          readsFrom: {db.groupStudents, db.students},
        )
        .get();

    final phones = <String>{};
    final parentIds = <String>{};
    for (final row in rows) {
      final phone = row.read<String>('parent_phone');
      if (PhoneNumbers.isValid(phone)) {
        phones.add(PhoneNumbers.toInternational(phone));
      }
      final parentId = row.read<String?>('parent_account_id');
      if (parentId != null) parentIds.add(parentId);
    }

    for (final phone in phones) {
      final stamp = writer.now();
      final sms = SmsQueueRow(
        id: writer.newId(),
        createdAt: stamp,
        updatedAt: stamp,
        phone: phone,
        message: message,
        status: SmsStatus.pending.code,
        kind: smsKind,
        attempts: 0,
        createdBy: writer.actor().userId,
      );
      await writer.save(db.smsQueue, sms, key: {'id': sms.id});
    }
    for (final parentId in parentIds) {
      final account = await _account(UserRole.parent, parentId);
      if (account == null) continue;
      await _notify(
        userId: account.id,
        kind: notifyScheduleChange,
        title: 'تغيير في جدول الحصص',
        body: message,
        entityId: requestId,
      );
    }
    return phones.length;
  }

  Future<String?> _resolveRoom({
    required GroupRow group,
    required String date,
    required int start,
    required int end,
    required String? roomId,
    required String? excludeSessionId,
  }) async {
    if (roomId == null) {
      final teacherBusy = await schedule.dateConflicts(
        date: date,
        startMinutes: start,
        endMinutes: end,
        teacherId: group.teacherId,
        excludeSessionId: excludeSessionId,
      );
      if (teacherBusy.isNotEmpty) throw ScheduleConflictException(teacherBusy);
      final suggested = await schedule.suggestRoom(
        date: date,
        startMinutes: start,
        endMinutes: end,
        preferredRoomId: group.roomId,
        excludeSessionId: excludeSessionId,
      );
      return suggested?.id;
    }
    final conflicts = await schedule.dateConflicts(
      date: date,
      startMinutes: start,
      endMinutes: end,
      teacherId: group.teacherId,
      roomId: roomId,
      excludeSessionId: excludeSessionId,
    );
    if (conflicts.isNotEmpty) throw ScheduleConflictException(conflicts);
    return roomId;
  }

  Future<SessionRow?> _targetSession(
    SessionRequestType type,
    String? sessionId,
    String groupId,
  ) async {
    if (!type.targetsExistingSession) return null;
    if (sessionId == null) {
      throw const InvalidRequestException('اختر الحصة المعنية بالطلب');
    }
    final session = await _session(sessionId);
    if (session.groupId != groupId) {
      throw const InvalidRequestException('الحصة ليست من هذه المجموعة');
    }
    _ensureOpen(session);
    return session;
  }

  static void _ensureOpen(SessionRow session) {
    if (session.closedAt != null) {
      throw const InvalidRequestException('الحصة انعقدت ولا يمكن تغييرها');
    }
    if (session.status == SessionStatus.cancelled.code) {
      throw const InvalidRequestException('الحصة ملغاة');
    }
  }

  static bool _isEarlier(String date, int start, SessionRow session) {
    final byDate = date.compareTo(session.date);
    return byDate < 0 || (byDate == 0 && start < session.startMinutes);
  }

  static String _dayLabel(String date) => const [
    'الاثنين',
    'الثلاثاء',
    'الأربعاء',
    'الخميس',
    'الجمعة',
    'السبت',
    'الأحد',
  ][DateKey.weekday(date) - 1];

  Future<SessionRequestRow> _pending(String id) async {
    final request = await (db.select(
      db.sessionRequests,
    )..where((r) => r.id.equals(id))).getSingle();
    if (request.status != SessionRequestStatus.pending.code) {
      throw const InvalidRequestException('الطلب رُوجع من قبل');
    }
    return request;
  }

  Future<void> _notify({
    required String userId,
    required String kind,
    required String title,
    required String body,
    required String entityId,
  }) {
    final stamp = writer.now();
    final notification = NotificationRow(
      id: writer.newId(),
      createdAt: stamp,
      updatedAt: stamp,
      userId: userId,
      senderId: writer.actor().userId,
      title: title,
      body: body,
      kind: kind,
      entity: 'session_requests',
      entityId: entityId,
    );
    return writer.save(
      db.notifications,
      notification,
      key: {'id': notification.id},
    );
  }

  Future<List<UserAccountRow>> _accounts(UserRole role) => (db.select(
    db.userAccounts,
  )..where((a) => a.role.equals(role.code) & a.deletedAt.isNull())).get();

  Future<UserAccountRow?> _account(UserRole role, String entityId) =>
      (db.select(db.userAccounts)..where(
            (a) =>
                a.role.equals(role.code) &
                a.entityId.equals(entityId) &
                a.deletedAt.isNull(),
          ))
          .getSingleOrNull();

  Future<GroupRow> _group(String id) =>
      (db.select(db.groups)..where((g) => g.id.equals(id))).getSingle();

  Future<TeacherRow> _teacher(String id) =>
      (db.select(db.teachers)..where((t) => t.id.equals(id))).getSingle();

  Future<SessionRow> _session(String id) =>
      (db.select(db.sessions)..where((s) => s.id.equals(id))).getSingle();
}
