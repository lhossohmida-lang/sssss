import 'package:drift/drift.dart';
import 'package:school_core/school_core.dart';

import 'assistant_models.dart';
import 'assistant_service.dart';

/// الأدوات المحلية المتاحة حسب الدور، وتعيد حقولاً لازمة للإجابة فقط.
List<AssistantTool> createLocalAssistantTools() => [
  _MyChildrenTool(),
  _SearchStudentsTool(),
  _StudentAttendanceTool(),
  _StudentDuesTool(),
  _MyScheduleTool(),
  _ProposeSessionRequestTool(),
];

bool _isDateKey(String? value) {
  if (value == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    return false;
  }
  try {
    return DateKey.of(DateKey.parse(value)) == value;
  } on Object {
    return false;
  }
}

abstract class _LocalTool implements AssistantTool {
  const _LocalTool();

  String? _string(Map<String, Object?> arguments, String key) {
    final value = arguments[key];
    if (value is! String || value.trim().isEmpty) {
      return null;
    }
    return value.trim();
  }

  String _requireString(Map<String, Object?> arguments, String key) {
    final value = _string(arguments, key);
    if (value == null) {
      throw ArgumentError.value(key, 'arguments', 'قيمة مطلوبة');
    }
    return value;
  }

  Future<bool> _studentVisible(
    AssistantContext context,
    String studentId,
  ) async {
    final session = context.session;
    final scope = switch (session.role) {
      UserRole.owner || UserRole.worker =>
        session.can(PermissionModule.students, PermissionAction.view)
            ? 's.deleted_at IS NULL'
            : '0 = 1',
      UserRole.parent =>
        'EXISTS (SELECT 1 FROM parents p WHERE p.id = s.parent_account_id '
            'AND p.auth_user_id = ? AND p.deleted_at IS NULL)',
      UserRole.teacher =>
        'EXISTS (SELECT 1 FROM group_students gs '
            'JOIN groups g ON g.id = gs.group_id '
            'JOIN teachers t ON t.id = g.teacher_id '
            'WHERE gs.student_id = s.id AND gs.deleted_at IS NULL '
            'AND gs.left_at IS NULL AND g.deleted_at IS NULL '
            'AND g.archived_at IS NULL AND t.auth_user_id = ? '
            'AND t.deleted_at IS NULL)',
    };
    final needsAccount =
        session.role == UserRole.parent || session.role == UserRole.teacher;
    final row = await context.db
        .customSelect(
          'SELECT 1 AS visible FROM students s '
          'WHERE s.id = ? AND $scope LIMIT 1',
          variables: [
            Variable<String>(studentId),
            if (needsAccount) Variable<String>(session.accountId),
          ],
          readsFrom: {
            context.db.students,
            context.db.parents,
            context.db.groupStudents,
            context.db.groups,
            context.db.teachers,
          },
        )
        .getSingleOrNull();
    return row != null;
  }
}

class _MyChildrenTool extends _LocalTool {
  @override
  AssistantToolDefinition get definition => const AssistantToolDefinition(
    name: 'my_children',
    description: 'أسماء أبناء وليّ الحساب ومستوياتهم فقط.',
    parameters: {
      'type': 'object',
      'properties': {},
      'additionalProperties': false,
    },
  );

  @override
  bool availableTo(AuthSession session) => session.role == UserRole.parent;

  @override
  Future<AssistantToolResult> execute(
    AssistantContext context,
    Map<String, Object?> arguments,
  ) async {
    final rows = await context.db
        .customSelect(
          'SELECT s.id, s.first_name, s.last_name, l.name AS level_name '
          'FROM students s JOIN parents p ON p.id = s.parent_account_id '
          'LEFT JOIN levels l ON l.id = s.level_id AND l.deleted_at IS NULL '
          'WHERE p.auth_user_id = ? AND p.deleted_at IS NULL '
          'AND s.deleted_at IS NULL '
          'ORDER BY s.last_name, s.first_name, s.id LIMIT 30',
          variables: [Variable<String>(context.session.accountId)],
          readsFrom: {
            context.db.students,
            context.db.parents,
            context.db.levels,
          },
        )
        .get();
    return AssistantToolResult.data([
      for (final row in rows)
        {
          'student_id': row.read<String>('id'),
          'name':
              '${row.read<String>('first_name')} ${row.read<String>('last_name')}',
          'level': row.read<String?>('level_name'),
        },
    ]);
  }
}

class _SearchStudentsTool extends _LocalTool {
  @override
  AssistantToolDefinition get definition => const AssistantToolDefinition(
    name: 'search_students',
    description: 'يبحث بالاسم عن التلاميذ الذين يحق لهذا الحساب رؤيتهم.',
    parameters: {
      'type': 'object',
      'properties': {
        'query': {'type': 'string'},
      },
      'required': ['query'],
      'additionalProperties': false,
    },
  );

  @override
  bool availableTo(AuthSession session) => switch (session.role) {
    UserRole.owner || UserRole.worker => session.can(
      PermissionModule.students,
      PermissionAction.view,
    ),
    UserRole.teacher || UserRole.parent => true,
  };

  @override
  Future<AssistantToolResult> execute(
    AssistantContext context,
    Map<String, Object?> arguments,
  ) async {
    final query = _requireString(arguments, 'query');
    if (query.length < 2 || query.length > 60) {
      throw ArgumentError.value(query, 'query', 'طول البحث غير صالح');
    }
    final session = context.session;
    final scope = switch (session.role) {
      UserRole.owner || UserRole.worker => 's.deleted_at IS NULL',
      UserRole.parent =>
        's.deleted_at IS NULL AND EXISTS (SELECT 1 FROM parents p '
            'WHERE p.id = s.parent_account_id AND p.auth_user_id = ? '
            'AND p.deleted_at IS NULL)',
      UserRole.teacher =>
        's.deleted_at IS NULL AND EXISTS (SELECT 1 FROM group_students gs '
            'JOIN groups g ON g.id = gs.group_id '
            'JOIN teachers t ON t.id = g.teacher_id '
            'WHERE gs.student_id = s.id AND gs.deleted_at IS NULL '
            'AND gs.left_at IS NULL AND g.deleted_at IS NULL '
            'AND g.archived_at IS NULL AND t.auth_user_id = ? '
            'AND t.deleted_at IS NULL)',
    };
    final pattern = '$query%';
    final rows = await context.db
        .customSelect(
          'SELECT s.id, s.first_name, s.last_name, l.name AS level_name '
          'FROM students s LEFT JOIN levels l ON l.id = s.level_id '
          'WHERE $scope AND (s.first_name LIKE ? OR s.last_name LIKE ?) '
          'ORDER BY s.last_name, s.first_name, s.id LIMIT 20',
          variables: [
            if (session.role == UserRole.parent ||
                session.role == UserRole.teacher)
              Variable<String>(session.accountId),
            Variable<String>(pattern),
            Variable<String>(pattern),
          ],
          readsFrom: {
            context.db.students,
            context.db.levels,
            context.db.parents,
            context.db.groupStudents,
            context.db.groups,
            context.db.teachers,
          },
        )
        .get();
    return AssistantToolResult.data([
      for (final row in rows)
        {
          'student_id': row.read<String>('id'),
          'name':
              '${row.read<String>('first_name')} ${row.read<String>('last_name')}',
          'level': row.read<String?>('level_name'),
        },
    ]);
  }
}

class _StudentAttendanceTool extends _LocalTool {
  @override
  AssistantToolDefinition get definition => const AssistantToolDefinition(
    name: 'student_attendance',
    description: 'ملخص آخر 30 تسجيلاً لحضور تلميذ ضمن نطاق الحساب.',
    parameters: {
      'type': 'object',
      'properties': {
        'student_id': {'type': 'string'},
      },
      'required': ['student_id'],
      'additionalProperties': false,
    },
  );

  @override
  bool availableTo(AuthSession session) => switch (session.role) {
    UserRole.owner || UserRole.worker =>
      session.can(PermissionModule.students, PermissionAction.view) &&
          session.can(PermissionModule.attendance, PermissionAction.view),
    UserRole.teacher || UserRole.parent => true,
  };

  @override
  Future<AssistantToolResult> execute(
    AssistantContext context,
    Map<String, Object?> arguments,
  ) async {
    final studentId = _requireString(arguments, 'student_id');
    if (!await _studentVisible(context, studentId)) {
      return const AssistantToolResult.data({
        'error': 'التلميذ غير متاح لهذا الحساب',
      });
    }
    final rows = await context.db
        .customSelect(
          'SELECT se.date, sub.name AS subject_name, g.number AS group_number, '
          'a.status FROM attendance a JOIN sessions se ON se.id = a.session_id '
          'JOIN groups g ON g.id = se.group_id '
          'JOIN subjects sub ON sub.id = g.subject_id '
          'WHERE a.student_id = ? AND a.deleted_at IS NULL '
          'AND se.deleted_at IS NULL AND g.deleted_at IS NULL '
          'ORDER BY se.date DESC, se.start_minutes DESC LIMIT 30',
          variables: [Variable<String>(studentId)],
          readsFrom: {
            context.db.attendance,
            context.db.sessions,
            context.db.groups,
            context.db.subjects,
          },
        )
        .get();
    return AssistantToolResult.data([
      for (final row in rows)
        {
          'date': row.read<String>('date'),
          'subject': row.read<String>('subject_name'),
          'group_number': row.read<int>('group_number'),
          'status': row.read<String>('status'),
        },
    ]);
  }
}

class _StudentDuesTool extends _LocalTool {
  @override
  AssistantToolDefinition get definition => const AssistantToolDefinition(
    name: 'student_unpaid_dues',
    description:
        'المبالغ المتبقية على تلميذ ضمن نطاق الحساب، بالدينار الجزائري.',
    parameters: {
      'type': 'object',
      'properties': {
        'student_id': {'type': 'string'},
      },
      'required': ['student_id'],
      'additionalProperties': false,
    },
  );

  @override
  bool availableTo(AuthSession session) => switch (session.role) {
    UserRole.owner || UserRole.worker =>
      session.can(PermissionModule.students, PermissionAction.view) &&
          session.can(PermissionModule.payments, PermissionAction.view),
    UserRole.parent => true,
    UserRole.teacher => false,
  };

  @override
  Future<AssistantToolResult> execute(
    AssistantContext context,
    Map<String, Object?> arguments,
  ) async {
    final studentId = _requireString(arguments, 'student_id');
    if (!await _studentVisible(context, studentId)) {
      return const AssistantToolResult.data({
        'error': 'التلميذ غير متاح لهذا الحساب',
      });
    }
    final dues = await DuesService(
      context.db,
      context.writer,
    ).cycleDues(studentId: studentId, unpaidOnly: true);
    final groups = await context.db
        .customSelect(
          'SELECT g.id, g.number, sub.name AS subject_name '
          'FROM groups g JOIN subjects sub ON sub.id = g.subject_id '
          'WHERE g.deleted_at IS NULL',
          readsFrom: {context.db.groups, context.db.subjects},
        )
        .get();
    final groupInfo = {
      for (final group in groups)
        group.read<String>('id'): {
          'number': group.read<int>('number'),
          'subject': group.read<String>('subject_name'),
        },
    };
    return AssistantToolResult.data([
      for (final due in dues)
        {
          'group': groupInfo[due.groupId],
          'cycle': due.cycleNumber,
          'remaining_dzd': due.remaining,
        },
    ]);
  }
}

class _MyScheduleTool extends _LocalTool {
  @override
  AssistantToolDefinition get definition => const AssistantToolDefinition(
    name: 'my_schedule',
    description: 'أقرب الحصص القادمة ضمن نطاق المستخدم.',
    parameters: {
      'type': 'object',
      'properties': {},
      'additionalProperties': false,
    },
  );

  @override
  bool availableTo(AuthSession session) => switch (session.role) {
    UserRole.owner || UserRole.worker => session.can(
      PermissionModule.groups,
      PermissionAction.view,
    ),
    UserRole.teacher || UserRole.parent => true,
  };

  @override
  Future<AssistantToolResult> execute(
    AssistantContext context,
    Map<String, Object?> arguments,
  ) async {
    final session = context.session;
    final scope = switch (session.role) {
      UserRole.owner || UserRole.worker => '1 = 1',
      UserRole.teacher =>
        'EXISTS (SELECT 1 FROM teachers t WHERE t.id = g.teacher_id '
            'AND t.auth_user_id = ? AND t.deleted_at IS NULL)',
      UserRole.parent =>
        'EXISTS (SELECT 1 FROM group_students gs '
            'JOIN students s ON s.id = gs.student_id '
            'JOIN parents p ON p.id = s.parent_account_id '
            'WHERE gs.group_id = g.id AND gs.deleted_at IS NULL '
            'AND gs.left_at IS NULL AND s.deleted_at IS NULL '
            'AND p.auth_user_id = ? AND p.deleted_at IS NULL)',
    };
    final needsAccount =
        session.role == UserRole.parent || session.role == UserRole.teacher;
    final today = DateKey.of(context.now);
    final rows = await context.db
        .customSelect(
          'SELECT se.date, se.start_minutes, se.end_minutes, se.status, '
          'g.number AS group_number, sub.name AS subject_name, t.name AS teacher_name '
          'FROM sessions se JOIN groups g ON g.id = se.group_id '
          'JOIN subjects sub ON sub.id = g.subject_id '
          'JOIN teachers t ON t.id = g.teacher_id '
          'WHERE $scope AND se.deleted_at IS NULL AND g.deleted_at IS NULL '
          'AND g.archived_at IS NULL '
          'AND (se.date > ? OR (se.date = ? AND se.end_minutes > ?)) '
          'ORDER BY se.date, se.start_minutes, g.number LIMIT 20',
          variables: [
            if (needsAccount) Variable<String>(session.accountId),
            Variable<String>(today),
            Variable<String>(today),
            Variable<int>(DateKey.minutesOf(context.now)),
          ],
          readsFrom: {
            context.db.sessions,
            context.db.groups,
            context.db.groupStudents,
            context.db.students,
            context.db.parents,
            context.db.subjects,
            context.db.teachers,
          },
        )
        .get();
    return AssistantToolResult.data([
      for (final row in rows)
        {
          'date': row.read<String>('date'),
          'start_minutes': row.read<int>('start_minutes'),
          'end_minutes': row.read<int>('end_minutes'),
          'status': row.read<String>('status'),
          'group_number': row.read<int>('group_number'),
          'subject': row.read<String>('subject_name'),
          'teacher': row.read<String>('teacher_name'),
        },
    ]);
  }
}

class _ProposeSessionRequestTool extends _LocalTool {
  @override
  AssistantToolDefinition get definition => const AssistantToolDefinition(
    name: 'propose_session_request',
    description: 'يقترح إرسال طلب تغيير حصة؛ لا يرسله قبل تأكيد الأستاذ.',
    parameters: {
      'type': 'object',
      'properties': {
        'group_id': {'type': 'string'},
        'type': {
          'type': 'string',
          'enum': ['reschedule', 'add', 'advance', 'cancel'],
        },
        'session_id': {'type': 'string'},
        'new_date': {
          'type': 'string',
          'description': 'تاريخ صالح بصيغة YYYY-MM-DD',
        },
        'new_start_minutes': {'type': 'integer'},
        'new_end_minutes': {'type': 'integer'},
        'reason': {'type': 'string'},
      },
      'required': ['group_id', 'type'],
      'additionalProperties': false,
    },
  );

  @override
  bool availableTo(AuthSession session) => session.role == UserRole.teacher;

  @override
  Future<AssistantToolResult> execute(
    AssistantContext context,
    Map<String, Object?> arguments,
  ) async {
    final groupId = _requireString(arguments, 'group_id');
    final type = SessionRequestType.fromCode(_requireString(arguments, 'type'));
    final sessionId = _string(arguments, 'session_id');
    final newDate = _string(arguments, 'new_date');
    final start = _integer(arguments, 'new_start_minutes');
    final end = _integer(arguments, 'new_end_minutes');
    final reason = _string(arguments, 'reason') ?? '';
    if (reason.length > 500) throw ArgumentError.value(reason, 'reason');
    if (type.targetsExistingSession && sessionId == null) {
      throw ArgumentError('حدّد الحصة المراد تغييرها.');
    }
    if (type.needsNewSlot &&
        (!_isDateKey(newDate) ||
            start == null ||
            end == null ||
            start < 0 ||
            start >= 1440 ||
            end < 1 ||
            end > 1440 ||
            end <= start)) {
      throw ArgumentError('التاريخ والوقت الجديدان غير صالحين.');
    }
    final teacher = await context.db
        .customSelect(
          'SELECT id FROM teachers WHERE auth_user_id = ? AND deleted_at IS NULL LIMIT 1',
          variables: [Variable<String>(context.session.accountId)],
          readsFrom: {context.db.teachers},
        )
        .getSingleOrNull();
    if (teacher == null) {
      return const AssistantToolResult.data({
        'error': 'حساب الأستاذ غير مربوط بالسجل',
      });
    }
    final teacherId = teacher.read<String>('id');
    final service = _requestService(context);
    final preview = await service.preview(
      teacherId: teacherId,
      groupId: groupId,
      type: type,
      sessionId: sessionId,
      newDate: newDate,
      newStartMinutes: start,
      newEndMinutes: end,
    );
    if (!preview.ok) {
      return AssistantToolResult.data({
        'error':
            preview.error ??
            preview.conflicts.map((conflict) => conflict.message).join('، '),
      });
    }
    final group =
        await (context.db.select(context.db.groups)
              ..where((row) => row.id.equals(groupId) & row.deletedAt.isNull()))
            .getSingleOrNull();
    if (group == null || group.teacherId != teacherId) {
      return const AssistantToolResult.data({
        'error': 'هذا الفوج ليس من أفواجك',
      });
    }
    final summary = StringBuffer('${type.label} للفوج ${group.number}.');
    if (type.needsNewSlot) {
      summary.write(
        ' الموعد المقترح: $newDate، ${DateKey.formatMinutes(start!)}–${DateKey.formatMinutes(end!)}.',
      );
      if (preview.suggestedRoom != null) {
        summary.write(' القاعة: ${preview.suggestedRoom!.name}.');
      }
    }
    if (reason.isNotEmpty) summary.write(' السبب: $reason');

    return AssistantToolResult.action(
      AssistantActionDraft(
        title: 'تأكيد إرسال طلب الحصة',
        summary: summary.toString(),
        confirm: () async {
          // يعاد فحص الملكية والتعارض لحظة التأكيد قبل أي كتابة.
          final checked = await _requestService(context).preview(
            teacherId: teacherId,
            groupId: groupId,
            type: type,
            sessionId: sessionId,
            newDate: newDate,
            newStartMinutes: start,
            newEndMinutes: end,
          );
          if (!checked.ok) {
            throw StateError(checked.error ?? 'موعد الحصة لم يعد متاحاً.');
          }
          final request = await _requestService(context).submit(
            teacherId: teacherId,
            groupId: groupId,
            type: type,
            sessionId: sessionId,
            newDate: newDate,
            newStartMinutes: start,
            newEndMinutes: end,
            newRoomId: checked.suggestedRoom?.id,
            reason: reason,
          );
          return {'request_id': request.id, 'status': request.status};
        },
      ),
    );
  }

  RequestService _requestService(AssistantContext context) => RequestService(
    context.db,
    context.writer,
    ScheduleService(context.db),
    CycleService(context.db, context.writer),
  );

  int? _integer(Map<String, Object?> arguments, String key) {
    final value = arguments[key];
    return value is int ? value : null;
  }
}
