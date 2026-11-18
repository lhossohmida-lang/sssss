import '../data/local/app_database.dart';

/// سعر الشهر (الدورة) الذي يُنسب به تلميذ إلى فوج.
///
/// السعر يُعيَّن عند إنشاء الفوج فقط (`groups.monthly_price`)، فلكل فوج سعره بحسب مادته وسنته، ويظهر
/// كما كُتب عند ربط التلميذ به. فوج أُنشئ قبل هذا الحقل ولم يُملأ بعد (`0`) يأخذ سعر مادته.
abstract final class GroupPrice {
  /// سعر شهر [group] للتلميذ قبل التخفيض.
  static Future<int> of(AppDatabase db, GroupRow group) async {
    if (group.monthlyPrice > 0) return group.monthlyPrice;
    final subject = await (db.select(
      db.subjects,
    )..where((s) => s.id.equals(group.subjectId))).getSingleOrNull();
    return subject?.monthlyPrice ?? 0;
  }

  /// سعر شهر الفوج [groupId]، أو `null` إن لم يوجد الفوج.
  static Future<int?> ofId(AppDatabase db, String groupId) async {
    final group = await (db.select(
      db.groups,
    )..where((g) => g.id.equals(groupId))).getSingleOrNull();
    return group == null ? null : of(db, group);
  }
}
