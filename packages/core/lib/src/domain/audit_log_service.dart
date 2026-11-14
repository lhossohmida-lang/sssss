import 'package:drift/drift.dart';

import '../data/local/app_database.dart';

/// محددات قراءة سجل العمليات.
class AuditLogFilters {
  const AuditLogFilters({this.query = '', this.action});

  /// يبحث في اسم المنفّذ والجدول ومعرّف السجل.
  final String query;

  /// رمز العملية كما حُفظ في `audit_log.action`.
  final String? action;
}

/// صفحة من السجل مرتبة من الأحدث إلى الأقدم.
class AuditLogPage {
  AuditLogPage({
    required List<AuditLogRow> entries,
    required this.totalCount,
    required this.page,
    required this.pageSize,
  }) : entries = List.unmodifiable(entries);

  final List<AuditLogRow> entries;
  final int totalCount;
  final int page;
  final int pageSize;

  int get pageCount =>
      totalCount == 0 ? 0 : (totalCount + pageSize - 1) ~/ pageSize;
  bool get hasPrevious => page > 0;
  bool get hasNext => page + 1 < pageCount;
}

/// قراءة محلية للعمليات مع ترشيح SQL وصفحات ثابتة الحجم.
class AuditLogService {
  AuditLogService(this.db);

  static const int defaultPageSize = 50;
  static const int maxPageSize = 100;

  final AppDatabase db;

  Stream<AuditLogPage> watch({
    AuditLogFilters filters = const AuditLogFilters(),
    int page = 0,
    int pageSize = defaultPageSize,
  }) {
    _validate(page, pageSize);
    return db
        .customSelect('SELECT 1', readsFrom: {db.auditLog})
        .watch()
        .asyncMap(
          (_) => load(filters: filters, page: page, pageSize: pageSize),
        );
  }

  Future<AuditLogPage> load({
    AuditLogFilters filters = const AuditLogFilters(),
    int page = 0,
    int pageSize = defaultPageSize,
  }) async {
    _validate(page, pageSize);
    final filter = _where(filters);
    final count = await db
        .customSelect(
          'SELECT COUNT(*) AS total FROM audit_log ${filter.sql}',
          variables: filter.variables,
          readsFrom: {db.auditLog},
        )
        .getSingle();
    final offset = page * pageSize;
    final rows = await db
        .customSelect(
          'SELECT id, user_id, user_name, action, entity, entity_id, '
          '"before", "after", created_at, updated_at FROM audit_log '
          '${filter.sql} ORDER BY created_at DESC, id DESC LIMIT ? OFFSET ?',
          variables: [
            ...filter.variables,
            Variable<int>(pageSize),
            Variable<int>(offset),
          ],
          readsFrom: {db.auditLog},
        )
        .get();
    return AuditLogPage(
      entries: [
        for (final row in rows)
          AuditLogRow(
            id: row.read<String>('id'),
            userId: row.read<String>('user_id'),
            userName: row.read<String>('user_name'),
            action: row.read<String>('action'),
            entity: row.read<String>('entity'),
            entityId: row.read<String>('entity_id'),
            before: row.readNullable<String>('before'),
            after: row.readNullable<String>('after'),
            createdAt: row.read<int>('created_at'),
            updatedAt: row.read<int>('updated_at'),
          ),
      ],
      totalCount: count.read<int>('total'),
      page: page,
      pageSize: pageSize,
    );
  }

  ({String sql, List<Variable<Object>> variables}) _where(
    AuditLogFilters filters,
  ) {
    final conditions = <String>[];
    final variables = <Variable<Object>>[];
    final action = filters.action?.trim();
    if (action != null && action.isNotEmpty) {
      conditions.add('action = ?');
      variables.add(Variable<String>(action));
    }
    final query = filters.query.trim();
    if (query.isNotEmpty) {
      conditions.add(
        '(instr(lower(user_name), lower(?)) > 0 OR '
        'instr(lower(entity), lower(?)) > 0 OR '
        'instr(lower(entity_id), lower(?)) > 0)',
      );
      variables
        ..add(Variable<String>(query))
        ..add(Variable<String>(query))
        ..add(Variable<String>(query));
    }
    return (
      sql: conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}',
      variables: variables,
    );
  }

  void _validate(int page, int pageSize) {
    if (page < 0) throw ArgumentError.value(page, 'page', 'صفحة غير صالحة');
    if (pageSize < 1 || pageSize > maxPageSize) {
      throw ArgumentError.value(
        pageSize,
        'pageSize',
        'حجم الصفحة يجب أن يكون بين 1 و$maxPageSize',
      );
    }
  }
}
