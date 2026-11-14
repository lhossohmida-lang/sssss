import 'package:drift/drift.dart';

import '../data/local/app_database.dart';
import '../data/local/sync_writer.dart';
import 'phone.dart';
import 'stable_id.dart';

/// خط نقل مع عدد التلاميذ الذين يستعملونه.
class TransportLineItem {
  const TransportLineItem({required this.line, required this.studentCount});

  final TransportLineRow line;
  final int studentCount;

  String get id => line.id;
  String get name => line.name;
  String get driverName => line.driverName;
  String get driverPhone => line.driverPhone;
  String get busNumber => line.busNumber;
}

/// تلميذ يستعمل نقل المدرسة.
class TransportStudentItem {
  const TransportStudentItem({
    required this.id,
    required this.name,
    required this.parentPhone,
    required this.price,
    this.lineId,
    this.lineName,
  });

  final String id;
  final String name;
  final String parentPhone;
  final int price;
  final String? lineId;
  final String? lineName;
}

/// إدارة خطوط النقل والسائقين والحافلات وإسناد التلاميذ.
///
/// بيانات السائق والحافلة محفوظة مع الخط، وربط التلميذ موجود في سجله
/// (`transport_line_id`). كل كتابة تمر عبر [SyncWriter].
class TransportService {
  TransportService(this.db, this.writer);

  final AppDatabase db;
  final SyncWriter writer;

  Stream<List<TransportLineItem>> watchLines() =>
      _lineQuery().watch().map(_lineItems);

  Future<List<TransportLineItem>> lines() async =>
      _lineItems(await _lineQuery().get());

  Selectable<QueryRow> _lineQuery() => db.customSelect(
    'SELECT t.id, t.name, t.driver_name, t.driver_phone, t.bus_number, '
    't.created_at, t.updated_at, t.deleted_at, COUNT(s.id) AS student_count '
    'FROM transport_lines t LEFT JOIN students s '
    'ON s.transport_line_id = t.id AND s.uses_transport = 1 '
    'AND s.deleted_at IS NULL WHERE t.deleted_at IS NULL '
    'GROUP BY t.id, t.name, t.driver_name, t.driver_phone, t.bus_number, '
    't.created_at, t.updated_at, t.deleted_at ORDER BY t.name, t.id',
    readsFrom: {db.transportLines, db.students},
  );

  List<TransportLineItem> _lineItems(List<QueryRow> rows) => [
    for (final row in rows)
      TransportLineItem(
        line: TransportLineRow(
          id: row.read<String>('id'),
          name: row.read<String>('name'),
          driverName: row.read<String>('driver_name'),
          driverPhone: row.read<String>('driver_phone'),
          busNumber: row.read<String>('bus_number'),
          createdAt: row.read<int>('created_at'),
          updatedAt: row.read<int>('updated_at'),
          deletedAt: row.read<int?>('deleted_at'),
        ),
        studentCount: row.read<int>('student_count'),
      ),
  ];

  Stream<TransportLineItem?> watchLine(String id) => watchLines().map(
    (items) => items.where((item) => item.id == id).firstOrNull,
  );

  Future<TransportLineItem?> line(String id) async =>
      (await lines()).where((item) => item.id == id).firstOrNull;

  Stream<List<TransportStudentItem>> watchStudents(String lineId) =>
      _studentQuery(lineId).watch().map((rows) => _studentItems(rows, lineId));

  Future<List<TransportStudentItem>> students(String lineId) async {
    return _studentItems(await _studentQuery(lineId).get(), lineId);
  }

  Selectable<QueryRow> _studentQuery(String lineId) => db.customSelect(
    'SELECT s.id, s.first_name, s.last_name, s.parent_phone, '
    's.transport_price FROM students s '
    'WHERE s.deleted_at IS NULL AND s.uses_transport = 1 '
    'AND s.transport_line_id = ? '
    'ORDER BY s.last_name, s.first_name, s.id',
    variables: [Variable<String>(lineId)],
    readsFrom: {db.students},
  );

  List<TransportStudentItem> _studentItems(
    List<QueryRow> rows,
    String lineId,
  ) => [
    for (final row in rows)
      TransportStudentItem(
        id: row.read<String>('id'),
        name:
            '${row.read<String>('first_name')} '
            '${row.read<String>('last_name')}',
        parentPhone: row.read<String>('parent_phone'),
        price: row.read<int>('transport_price'),
        lineId: lineId,
      ),
  ];

  /// كل مستعملي النقل غير الموجودين حالياً في [exceptLineId]؛ من خط آخر
  /// يظهر مع اسمه كي يكون نقله صريحاً.
  Stream<List<TransportStudentItem>> watchOtherStudents(
    String exceptLineId, {
    String query = '',
  }) => _otherStudentQuery(exceptLineId, query).watch().map(_otherStudentItems);

  Future<List<TransportStudentItem>> otherStudents(
    String exceptLineId, {
    String query = '',
  }) async {
    return _otherStudentItems(
      await _otherStudentQuery(exceptLineId, query).get(),
    );
  }

  Selectable<QueryRow> _otherStudentQuery(String exceptLineId, String query) {
    final cleanQuery = query.trim();
    return db.customSelect(
      'SELECT s.id, s.first_name, s.last_name, s.parent_phone, '
      's.transport_price, s.transport_line_id, t.name AS line_name '
      'FROM students s LEFT JOIN transport_lines t '
      'ON t.id = s.transport_line_id WHERE s.deleted_at IS NULL '
      'AND s.uses_transport = 1 AND (s.transport_line_id IS NULL '
      'OR s.transport_line_id <> ?) '
      'AND (? = \'\' OR s.first_name LIKE ? OR s.last_name LIKE ? '
      'OR s.parent_phone LIKE ?) '
      'ORDER BY s.last_name, s.first_name, s.id LIMIT 500',
      variables: [
        Variable<String>(exceptLineId),
        Variable<String>(cleanQuery),
        Variable<String>('%$cleanQuery%'),
        Variable<String>('%$cleanQuery%'),
        Variable<String>('%$cleanQuery%'),
      ],
      readsFrom: {db.students, db.transportLines},
    );
  }

  List<TransportStudentItem> _otherStudentItems(List<QueryRow> rows) => [
    for (final row in rows)
      TransportStudentItem(
        id: row.read<String>('id'),
        name:
            '${row.read<String>('first_name')} '
            '${row.read<String>('last_name')}',
        parentPhone: row.read<String>('parent_phone'),
        price: row.read<int>('transport_price'),
        lineId: row.read<String?>('transport_line_id'),
        lineName: row.read<String?>('line_name'),
      ),
  ];

  Future<String> addLine({
    required String name,
    String driverName = '',
    String driverPhone = '',
    String busNumber = '',
  }) async {
    final clean = _lineName(name);
    final cleanDriver = driverName.trim();
    final phone = _driverPhone(driverPhone);
    final bus = _busNumber(busNumber);
    await _ensureUniqueName(clean);
    final id = StableId.transportLine(clean.toLowerCase());
    final previous = await (db.select(
      db.transportLines,
    )..where((line) => line.id.equals(id))).getSingleOrNull();
    if (previous != null) {
      // استعمل المفتاح الطبيعي نفسه لإحياء خط حُذف ثم أُعيدت إضافته.
      await writer.patch(
        db.transportLines,
        key: {'id': id},
        values: {
          'name': clean,
          'driver_name': cleanDriver,
          'driver_phone': phone,
          'bus_number': bus,
          'deleted_at': null,
        },
      );
      return id;
    }
    final stamp = writer.now();
    await writer.save(
      db.transportLines,
      TransportLinesCompanion.insert(
        id: id,
        createdAt: stamp,
        updatedAt: stamp,
        deletedAt: const Value(null),
        name: clean,
        driverName: Value(cleanDriver),
        driverPhone: Value(phone),
        busNumber: Value(bus),
      ),
      key: {'id': id},
    );
    return id;
  }

  Future<void> updateLine({
    required String id,
    required String name,
    String driverName = '',
    String driverPhone = '',
    String busNumber = '',
  }) async {
    final clean = _lineName(name);
    final cleanDriver = driverName.trim();
    final phone = _driverPhone(driverPhone);
    final bus = _busNumber(busNumber);
    await _ensureUniqueName(clean, exceptId: id);
    final existing = await _lineRow(id);
    if (existing == null) throw StateError('خط النقل غير موجود');
    await writer.patch(
      db.transportLines,
      key: {'id': id},
      values: {
        'name': clean,
        'driver_name': cleanDriver,
        'driver_phone': phone,
        'bus_number': bus,
      },
    );
  }

  Future<void> deleteLine(String id) async {
    final existing = await _lineRow(id);
    if (existing == null) return;
    final assigned =
        await (db.select(db.students)
              ..where(
                (student) =>
                    student.transportLineId.equals(id) &
                    student.deletedAt.isNull(),
              )
              ..limit(1))
            .get();
    if (assigned.isNotEmpty) {
      throw StateError('انقل التلاميذ إلى خط آخر قبل حذف الخط');
    }
    await writer.softDelete(db.transportLines, key: {'id': id});
  }

  Future<bool> assignStudent({
    required String lineId,
    required String studentId,
  }) async {
    if (await _lineRow(lineId) == null) {
      throw StateError('خط النقل غير موجود');
    }
    final student =
        await (db.select(db.students)..where(
              (row) => row.id.equals(studentId) & row.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    if (student == null) throw StateError('التلميذ غير موجود أو محذوف');
    if (!student.usesTransport) {
      throw StateError('فعّل نقل التلميذ قبل إسناده إلى خط');
    }
    return writer.patch(
      db.students,
      key: {'id': studentId},
      values: {'transport_line_id': lineId},
    );
  }

  Future<bool> unassignStudent({
    required String lineId,
    required String studentId,
  }) async {
    final student =
        await (db.select(db.students)..where(
              (row) =>
                  row.id.equals(studentId) &
                  row.transportLineId.equals(lineId) &
                  row.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    if (student == null) return false;
    return writer.patch(
      db.students,
      key: {'id': studentId},
      values: {'transport_line_id': null},
    );
  }

  Future<TransportLineRow?> _lineRow(String id) =>
      (db.select(db.transportLines)
            ..where((line) => line.id.equals(id) & line.deletedAt.isNull()))
          .getSingleOrNull();

  Future<void> _ensureUniqueName(String name, {String? exceptId}) async {
    final rows = await (db.select(
      db.transportLines,
    )..where((line) => line.deletedAt.isNull())).get();
    if (rows.any(
      (line) =>
          line.id != exceptId &&
          line.name.trim().toLowerCase() == name.toLowerCase(),
    )) {
      throw StateError('اسم خط النقل مسجَّل من قبل');
    }
  }

  String _lineName(String value) {
    final name = value.trim();
    if (name.isEmpty) throw const FormatException('اكتب اسم خط النقل');
    if (name.length > 60) {
      throw const FormatException('اسم الخط أطول من 60 حرفاً');
    }
    return name;
  }

  String _driverPhone(String value) {
    final phone = value.trim();
    if (phone.isEmpty) return '';
    if (!PhoneNumbers.isValid(phone)) {
      throw const FormatException('رقم السائق غير صالح');
    }
    return PhoneNumbers.normalize(phone);
  }

  String _busNumber(String value) {
    final number = value.trim();
    if (number.length > 40) {
      throw const FormatException('رقم الحافلة أطول من 40 حرفاً');
    }
    return number;
  }
}
