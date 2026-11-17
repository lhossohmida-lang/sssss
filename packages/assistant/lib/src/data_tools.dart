import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show QueryRow;
import 'package:school_core/school_core.dart';

import 'assistant_knowledge.dart';
import 'assistant_models.dart';
import 'assistant_service.dart';
import 'read_only_sql.dart';
import 'schema_catalog.dart';

/// أدوات المعرفة الشاملة: نظرة عامة على المدرسة، ومخطط البيانات، واستعلام للقراءة فقط على كل
/// ما يحق للحساب رؤيته، ودليل التطبيق، واقتراح تغيير اسم المدرسة بتأكيد. لصاحب المدرسة والعمال
/// (والدليل لكل الأدوار)؛ الأستاذ والوليّ يبقيان على أدوات نطاقهما.
List<AssistantTool> createDataAssistantTools() => [
  _SchoolOverviewTool(),
  _DescribeSchemaTool(),
  _QueryDatabaseTool(),
  _AppGuideTool(),
  _ProposeSchoolNameChangeTool(),
];

String _requireText(Map<String, Object?> arguments, String key) {
  final value = arguments[key];
  if (value is! String || value.trim().isEmpty) {
    throw ArgumentError('المعامل «$key» مطلوب');
  }
  return value.trim();
}

String? _optionalText(Map<String, Object?> arguments, String key) {
  final value = arguments[key];
  return value is String && value.trim().isNotEmpty ? value.trim() : null;
}

const Map<String, Object?> _noParameters = {
  'type': 'object',
  'properties': {},
  'additionalProperties': false,
};

Future<int> _count(AppDatabase db, String sql) async {
  final row = await db.customSelect(sql).getSingle();
  return row.read<int>('c');
}

class _SchoolOverviewTool implements AssistantTool {
  @override
  AssistantToolDefinition get definition => const AssistantToolDefinition(
    name: 'school_overview',
    description:
        'أرقام المدرسة الآن: عدد التلاميذ والأولياء والأساتذة والعمال والأفواج والقاعات '
        'والمواد، وحصص اليوم وحضوره، والمقبوضات والمستحقات وخلاصات الأساتذة، والطلبات '
        'المعلّقة. ابدأ بها لأسئلة العدد والمجموع.',
    parameters: _noParameters,
  );

  @override
  bool availableTo(AuthSession session) => AssistantSchema.isStaff(session);

  @override
  Future<AssistantToolResult> execute(
    AssistantContext context,
    Map<String, Object?> arguments,
  ) async {
    final session = context.session;
    final db = context.db;
    bool can(PermissionModule module) =>
        session.can(module, PermissionAction.view);
    final stats = await DashboardQueries(
      db,
      context.writer,
    ).load(now: context.now);
    final settings = await SettingsService(db, context.writer).load();

    final result = <String, Object?>{
      'school_name': settings.schoolName,
      'today': DateKey.of(context.now),
      if (can(PermissionModule.students)) ...{
        'students': stats.students,
        'parents': await _count(
          db,
          'SELECT COUNT(*) AS c FROM parents WHERE deleted_at IS NULL',
        ),
      },
      if (can(PermissionModule.teachers))
        'teachers': await _count(
          db,
          'SELECT COUNT(*) AS c FROM teachers WHERE deleted_at IS NULL',
        ),
      if (can(PermissionModule.workers))
        'workers': await _count(
          db,
          'SELECT COUNT(*) AS c FROM workers WHERE deleted_at IS NULL',
        ),
      if (can(PermissionModule.subjects))
        'subjects': await _count(
          db,
          'SELECT COUNT(*) AS c FROM subjects WHERE deleted_at IS NULL',
        ),
      if (can(PermissionModule.rooms))
        'rooms': await _count(
          db,
          'SELECT COUNT(*) AS c FROM rooms WHERE deleted_at IS NULL',
        ),
      if (can(PermissionModule.groups)) ...{
        'groups_active': stats.activeGroups,
        'groups_archived': await _count(
          db,
          'SELECT COUNT(*) AS c FROM groups WHERE deleted_at IS NULL '
          'AND archived_at IS NOT NULL',
        ),
        'enrolments_active': await _count(
          db,
          'SELECT COUNT(*) AS c FROM group_students '
          'WHERE deleted_at IS NULL AND left_at IS NULL',
        ),
      },
      if (can(PermissionModule.attendance)) ...{
        'sessions_today': stats.todaySessions,
        'present_today': stats.todayPresent,
        'absent_today': await _count(
          db,
          'SELECT COUNT(*) AS c FROM attendance a JOIN sessions s '
          "ON s.id = a.session_id WHERE s.date = '${DateKey.of(context.now)}' "
          "AND s.deleted_at IS NULL AND a.deleted_at IS NULL AND a.status = 'absent'",
        ),
        'teacher_sessions_missed_last_7_days': stats.missedSessions,
      },
      if (can(PermissionModule.payments)) ...{
        'received_today_dzd': stats.receivedToday,
        'received_this_month_dzd': stats.receivedMonth,
        'dues_total_dzd': stats.duesTotal,
        'students_with_dues': stats.duesStudents,
      },
      if (can(PermissionModule.payouts)) ...{
        'teacher_payouts_unpaid_dzd': stats.payoutsUnpaid,
        'teacher_payouts_unpaid_count': stats.payoutsUnpaidCount,
      },
      if (can(PermissionModule.requests))
        'teacher_requests_pending': stats.pendingRequests,
      if (can(PermissionModule.waiting))
        'waiting_lists_ready': stats.waitingReady,
      if (can(PermissionModule.sms))
        'sms_pending': await _count(
          db,
          "SELECT COUNT(*) AS c FROM sms_queue WHERE status = 'pending' "
          'AND deleted_at IS NULL',
        ),
      'unsynced_changes': await countUnsyncedChanges(db),
    };
    return AssistantToolResult.data(result);
  }
}

class _DescribeSchemaTool implements AssistantTool {
  @override
  AssistantToolDefinition get definition => const AssistantToolDefinition(
    name: 'describe_schema',
    description:
        'يصف بيانات المدرسة: بلا معامل يعدّد الجداول المتاحة وما فيها وعدد صفوفها ومعاني '
        'الرموز؛ ومع table يعرض أعمدته وأنواعها. استعملها قبل query_database.',
    parameters: {
      'type': 'object',
      'properties': {
        'table': {
          'type': 'string',
          'description': 'اسم جدول لعرض أعمدته (اختياري)',
        },
      },
      'additionalProperties': false,
    },
  );

  @override
  bool availableTo(AuthSession session) => AssistantSchema.isStaff(session);

  @override
  Future<AssistantToolResult> execute(
    AssistantContext context,
    Map<String, Object?> arguments,
  ) async {
    final db = context.db;
    final visible = AssistantSchema.visibleTo(context.session);
    final wanted = _optionalText(arguments, 'table');

    Future<int> rows(String name) async {
      final columns = AssistantSchema.columnsOf(db, name);
      final soft = columns.any((c) => c['name'] == 'deleted_at');
      return _count(
        db,
        'SELECT COUNT(*) AS c FROM $name${soft ? ' WHERE deleted_at IS NULL' : ''}',
      );
    }

    if (wanted != null) {
      final table = visible.where((t) => t.name == wanted).firstOrNull;
      if (table == null) {
        return AssistantToolResult.data({
          'error':
              'الجدول «$wanted» غير متاح لهذا الحساب أو غير موجود. الجداول المتاحة: '
              '${visible.map((t) => t.name).join('، ')}',
        });
      }
      return AssistantToolResult.data({
        'name': table.name,
        'description': table.description,
        'rows': await rows(table.name),
        'columns': AssistantSchema.columnsOf(db, table.name),
      });
    }
    return AssistantToolResult.data({
      'conventions': AssistantSchema.conventions,
      'codes': AssistantKnowledge.codes(),
      'tables': [
        for (final table in visible)
          {
            'name': table.name,
            'description': table.description,
            'rows': await rows(table.name),
          },
      ],
    });
  }
}

class _QueryDatabaseTool implements AssistantTool {
  @override
  AssistantToolDefinition get definition => const AssistantToolDefinition(
    name: 'query_database',
    description:
        'ينفّذ استعلام SQLite واحداً (SELECT أو WITH) للقراءة فقط على جداول المدرسة المتاحة '
        'لهذا الحساب، ويعيد حتى 100 صف. للعدّ والمجاميع والتجميع والربط بين الجداول. '
        'استعمل deleted_at IS NULL وأسماء الأعمدة من describe_schema.',
    parameters: {
      'type': 'object',
      'properties': {
        'sql': {
          'type': 'string',
          'description':
              'استعلام SELECT واحد، بلا تعليقات ولا فاصلة منقوطة داخله، مثل: '
              'SELECT COUNT(*) AS n FROM students WHERE deleted_at IS NULL',
        },
      },
      'required': ['sql'],
      'additionalProperties': false,
    },
  );

  @override
  bool availableTo(AuthSession session) => AssistantSchema.isStaff(session);

  /// أقصى حجم لنتيجة واحدة تُرسل إلى النموذج (حرفاً من JSON)؛ أقل من نصف سقف المحادثة حتى
  /// تتسع نتيجتان متتاليتان قبل أن تُختصر أقدمهما.
  static const int _maxResultChars = 16000;

  /// أقصى طول لقيمة نصية واحدة.
  static const int _maxValueChars = 300;

  @override
  Future<AssistantToolResult> execute(
    AssistantContext context,
    Map<String, Object?> arguments,
  ) async {
    final db = context.db;
    final guard = ReadOnlySql(
      allowedTables: {
        for (final table in AssistantSchema.visibleTo(context.session))
          table.name,
      },
      knownTables: AssistantSchema.knownTables(db),
      hiddenColumns: AssistantSchema.hiddenColumns,
    );
    final String prepared;
    try {
      prepared = guard.prepare(_requireText(arguments, 'sql'));
    } on ArgumentError catch (e) {
      return AssistantToolResult.data({'error': '${e.message}'});
    }
    final List<QueryRow> found;
    try {
      found = await db
          .customSelect(prepared)
          .get()
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      return const AssistantToolResult.data({
        'error': 'استغرق الاستعلام أكثر من 10 ثوانٍ: ضيّقه بشروط أو بتجميع',
      });
    } on Object catch (e) {
      final text = '$e'.replaceAll(RegExp(r'\s+'), ' ');
      return AssistantToolResult.data({
        'error':
            'خطأ في الاستعلام: ${text.length > 240 ? '${text.substring(0, 240)}…' : text}',
      });
    }

    final limited = found.take(ReadOnlySql.maxRows).toList();
    final rows = <Map<String, Object?>>[];
    var size = 0;
    var truncated = found.length > ReadOnlySql.maxRows;
    for (final row in limited) {
      final data = <String, Object?>{
        for (final entry in row.data.entries) entry.key: _clean(entry.value),
      };
      size += jsonEncode(data).length;
      if (size > _maxResultChars) {
        truncated = true;
        break;
      }
      rows.add(data);
    }
    return AssistantToolResult.data({
      'columns': rows.isEmpty
          ? const <String>[]
          : rows.first.keys.toList(growable: false),
      'row_count': rows.length,
      'truncated': truncated,
      if (truncated) 'note': 'اقتُطعت النتيجة: ضيّق الاستعلام أو استعمل التجميع (GROUP BY) والعدّ',
      'rows': rows,
    });
  }

  static Object? _clean(Object? value) {
    if (value is Uint8List) return '[binary]';
    if (value is String && value.length > _maxValueChars) {
      return '${value.substring(0, _maxValueChars)}…';
    }
    if (value is num || value is bool || value == null) return value;
    return '$value';
  }
}

class _AppGuideTool implements AssistantTool {
  @override
  AssistantToolDefinition get definition => AssistantToolDefinition(
    name: 'app_guide',
    description:
        'دليل التطبيق: كيف يعمل وقواعده (الدورات، المدفوعات والمستحقات، الحضور، الخلاص، '
        'الرسائل، الصلاحيات) وأين تجد كل شيء. بلا معامل تعرض قائمة المواضيع. استعملها لأسئلة '
        '«كيف» و«أين» و«لماذا».',
    parameters: {
      'type': 'object',
      'properties': {
        'topic': {
          'type': 'string',
          'description':
              'معرّف الموضوع: ${AssistantKnowledge.topics.map((t) => t.id).join('، ')}، codes',
        },
      },
      'additionalProperties': false,
    },
  );

  @override
  bool availableTo(AuthSession session) => true;

  @override
  Future<AssistantToolResult> execute(
    AssistantContext context,
    Map<String, Object?> arguments,
  ) async {
    final session = context.session;
    final topics = AssistantKnowledge.forRole(session.role);
    final staff = AssistantSchema.isStaff(session);
    final id = _optionalText(arguments, 'topic');
    if (id == null) {
      return AssistantToolResult.data({
        'topics': [
          for (final topic in topics) {'id': topic.id, 'title': topic.title},
          if (staff) {'id': 'codes', 'title': 'الرموز وقيم الحقول والاصطلاحات'},
        ],
        'hint': 'استدعِ app_guide مع topic لقراءة موضوع.',
      });
    }
    if (id == 'codes' && staff) {
      return AssistantToolResult.data({
        'id': 'codes',
        'title': 'الرموز وقيم الحقول والاصطلاحات',
        'text': '${AssistantSchema.conventions}\n${AssistantKnowledge.codes()}',
      });
    }
    final topic = topics.where((t) => t.id == id).firstOrNull;
    if (topic == null) {
      return AssistantToolResult.data({
        'error':
            'موضوع غير معروف. المواضيع: ${topics.map((t) => t.id).join('، ')}',
      });
    }
    return AssistantToolResult.data({
      'id': topic.id,
      'title': topic.title,
      'text': topic.text,
    });
  }
}

class _ProposeSchoolNameChangeTool implements AssistantTool {
  static const int _minLength = 2;
  static const int _maxLength = 80;

  @override
  AssistantToolDefinition get definition => const AssistantToolDefinition(
    name: 'propose_school_name_change',
    description:
        'يقترح تغيير اسم المدرسة إلى new_name. لا يُنفَّذ شيء إلا بعد تأكيد المستخدم في '
        'التطبيق.',
    parameters: {
      'type': 'object',
      'properties': {
        'new_name': {'type': 'string', 'description': 'الاسم الجديد للمدرسة'},
      },
      'required': ['new_name'],
      'additionalProperties': false,
    },
  );

  @override
  bool availableTo(AuthSession session) => switch (session.role) {
    UserRole.owner => true,
    UserRole.worker => session.can(
      PermissionModule.settings,
      PermissionAction.edit,
    ),
    UserRole.teacher || UserRole.parent => false,
  };

  @override
  Future<AssistantToolResult> execute(
    AssistantContext context,
    Map<String, Object?> arguments,
  ) async {
    final name = _requireText(arguments, 'new_name');
    if (name.length < _minLength || name.length > _maxLength) {
      throw ArgumentError('اسم المدرسة من $_minLength إلى $_maxLength حرفاً');
    }
    final service = SettingsService(context.db, context.writer);
    final current = await service.load();
    if (current.schoolName == name) {
      return AssistantToolResult.data({
        'unchanged': true,
        'school_name': current.schoolName,
      });
    }
    final old = current.schoolName.isEmpty
        ? 'غير محدد'
        : '«${current.schoolName}»';
    return AssistantToolResult.action(
      AssistantActionDraft(
        title: 'تغيير اسم المدرسة',
        summary:
            'تغيير اسم المدرسة من $old إلى «$name». يظهر الاسم الجديد في التطبيقات '
            'والوصولات والمطبوعات.',
        confirm: () async {
          await service.save(current.copyWith(schoolName: name));
          return {'school_name': name};
        },
      ),
    );
  }
}
