import 'dart:convert';

import '../data/local/app_database.dart';
import '../data/local/sync_writer.dart';
import 'setting_keys.dart';

/// أنواع رسائل SMS التي أوقفها المدير.
///
/// لكل نوع من الرسائل (وصل الدفع، غياب التلميذ، تذكير المستحقات...) مفتاح قالبه. المدير يوقف نوعاً
/// فلا تُوضع رسائله في الطابور ولا تُرسل (ما كان منها منتظراً وقت الإيقاف يُلغى عند أول إرسال). القائمة
/// في جدول `settings` المتزامن، فيسري الإيقاف على كل أجهزة الإدارة.
class SmsKindPolicy {
  SmsKindPolicy(this.db, this.writer);

  final AppDatabase db;
  final SyncWriter writer;

  /// الأنواع المعطَّلة الآن.
  Future<Set<String>> disabled() async {
    final row =
        await (db.select(db.settings)
              ..where((s) => s.key.equals(SettingKeys.smsDisabledKinds)))
            .getSingleOrNull();
    return parse(row?.value);
  }

  /// الأنواع المعطَّلة، وتتحدث عند تغييرها من أي جهاز.
  Stream<Set<String>> watchDisabled() =>
      (db.select(db.settings)
            ..where((s) => s.key.equals(SettingKeys.smsDisabledKinds)))
          .watchSingleOrNull()
          .map((row) => parse(row?.value));

  /// هل تُرسل رسائل النوع [kind]؟
  Future<bool> isEnabled(String kind) async =>
      !(await disabled()).contains(kind);

  /// يفعّل النوع [kind] أو يوقفه.
  Future<void> setEnabled(String kind, {required bool enabled}) async {
    final current = {...await disabled()};
    if (enabled) {
      current.remove(kind);
    } else {
      current.add(kind);
    }
    await writer.save(
      db.settings,
      SettingsCompanion.insert(
        key: SettingKeys.smsDisabledKinds,
        value: jsonEncode(current.toList()..sort()),
        updatedAt: writer.now(),
      ),
      key: {'key': SettingKeys.smsDisabledKinds},
    );
  }

  /// يقرأ القائمة من نص الإعداد؛ التالف أو الفارغ يعني «لا شيء معطَّل».
  static Set<String> parse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return {
          for (final item in decoded)
            if (item is String && item.isNotEmpty) item,
        };
      }
    } on FormatException {
      // قائمة تالفة تُعامل كأنها فارغة فلا يُحرم أحد من رسائله بخطأ في التخزين.
    }
    return const {};
  }
}
