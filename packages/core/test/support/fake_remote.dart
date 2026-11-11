import 'package:school_core/school_core.dart';

/// خادم وهمي في الذاكرة يحاكي الخادم الحقيقي: «آخر تعديل يفوز»، رقم مزامنة
/// متزايد، وإمكانية محاكاة انقطاع الإنترنت أو رفض الصلاحيات.
class FakeRemote implements RemoteStore {
  final Map<String, Map<String, Map<String, Object?>>> _tables = {};
  int _sequence = 0;

  /// `true`: كل الطلبات تفشل فشلاً مؤقتاً (لا إنترنت).
  bool offline = false;

  /// يعيد سبب الرفض النهائي لصف، أو `null` لقبوله (يحاكي الصلاحيات).
  String? Function(String table, Map<String, Object?> row)? reject;

  /// عروض على الخادم: اسم العرض ← دالة تبني صفوفه من الجداول.
  final Map<String, List<Map<String, Object?>> Function()> views = {};

  /// سجل الطلبات للتحقق من الترتيب والتجميع.
  final List<String> calls = [];

  List<Map<String, Object?>> rows(String table) =>
      (_tables[table]?.values ?? const <Map<String, Object?>>[]).toList();

  Map<String, Object?>? row(String table, String key) => _tables[table]?[key];

  static String _key(Map<String, Object?> row) {
    if (row['id'] != null) return row['id']! as String;
    if (row['key'] != null) return row['key']! as String;
    return '${row['teacher_id']}|${row['subject_id']}';
  }

  @override
  Future<void> upsert(
    String table,
    List<Map<String, Object?>> rows, {
    bool insertOnly = false,
  }) async {
    calls.add('upsert:$table:${rows.length}');
    if (offline) {
      throw const RemoteException('لا يوجد اتصال', permanent: false);
    }
    for (final row in rows) {
      final reason = reject?.call(table, row);
      if (reason != null) throw RemoteException(reason, permanent: true);
    }
    final store = _tables.putIfAbsent(table, () => {});
    for (final row in rows) {
      final key = _key(row);
      final existing = store[key];
      if (existing != null) {
        if (insertOnly) continue;
        if ((row['updated_at']! as int) < (existing['updated_at']! as int)) {
          continue;
        }
      }
      store[key] = {...row, 'synced_at': ++_sequence};
    }
  }

  @override
  Future<List<Map<String, Object?>>> pull(
    String table, {
    required int afterSyncedAt,
    required int limit,
  }) async {
    calls.add('pull:$table');
    if (offline) {
      throw const RemoteException('لا يوجد اتصال', permanent: false);
    }
    final source = views[table]?.call() ?? rows(table);
    final changed =
        source.where((r) => (r['synced_at']! as int) > afterSyncedAt).toList()
          ..sort(
            (a, b) =>
                (a['synced_at']! as int).compareTo(b['synced_at']! as int),
          );
    return changed.take(limit).toList();
  }
}
