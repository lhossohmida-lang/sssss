/// فشل في الاتصال بالخادم أو رفض منه.
class RemoteException implements Exception {
  const RemoteException(this.message, {required this.permanent});

  final String message;

  /// `true`: الخادم رفض البيانات (صلاحيات أو قيد)، وإعادة المحاولة لن تنفع.
  /// `false`: عطل مؤقت (لا إنترنت، مهلة، خطأ في الخادم) وتُعاد المحاولة.
  final bool permanent;

  @override
  String toString() => message;
}

/// واجهة مجرّدة للخادم. محرك المزامنة لا يعرف غيرها، فيُختبر بخادم وهمي
/// ويعمل في الإنتاج على Supabase.
abstract interface class RemoteStore {
  /// يرسل صفوفاً إلى جدول (إضافة أو تحديث). الخادم يطبّق «آخر تعديل يفوز».
  ///
  /// مع [insertOnly] تُتجاهل الصفوف الموجودة (جداول لا تُعدَّل مثل السجل).
  Future<void> upsert(
    String table,
    List<Map<String, Object?>> rows, {
    bool insertOnly = false,
  });

  /// يسحب الصفوف التي `synced_at` أكبر من [afterSyncedAt]، مرتبة تصاعدياً،
  /// بحد أقصى [limit] صفاً.
  Future<List<Map<String, Object?>>> pull(
    String table, {
    required int afterSyncedAt,
    required int limit,
  });
}
