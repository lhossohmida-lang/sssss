import 'package:school_core/school_core.dart';

/// قراءة وحفظ سياسة الإرسال الاختيارية المشتركة بين أجهزة الإدارة.
class SmsSettingsService {
  SmsSettingsService(this.db, this.writer);

  final AppDatabase db;
  final SyncWriter writer;

  /// `null` يعني أن الإرسال الشهري غير محدود.
  Future<int?> monthlyLimit() async {
    final row =
        await (db.select(db.settings)..where(
              (setting) => setting.key.equals(SettingKeys.smsMonthlyLimit),
            ))
            .getSingleOrNull();
    if (row == null) return null;
    final value = int.tryParse(row.value);
    if (value == null || value < 0) {
      throw FormatException('حد رسائل SMS الشهري غير صالح', row.value);
    }
    return value == 0 ? null : value;
  }

  /// خانة الشريحة المختارة، أو `null` إذا لم يحدد المدير واحدة بعد.
  Future<int?> simSlotIndex() async {
    final row =
        await (db.select(db.settings)..where(
              (setting) => setting.key.equals(SettingKeys.smsSimSlotIndex),
            ))
            .getSingleOrNull();
    if (row == null || row.value == '-1') return null;
    final value = int.tryParse(row.value);
    if (value == null || value < 0) {
      throw FormatException('خانة شريحة SMS غير صالحة', row.value);
    }
    return value;
  }

  /// يحفظ عدداً موجباً، أو صفراً/`null` لتعطيل الحد.
  Future<void> saveMonthlyLimit(int? limit) async {
    if (limit != null && limit < 0) {
      throw ArgumentError.value(limit, 'limit', 'يجب ألا يكون الحد سالباً');
    }
    final stamp = writer.now();
    await writer.save(
      db.settings,
      SettingsCompanion.insert(
        key: SettingKeys.smsMonthlyLimit,
        value: (limit ?? 0).toString(),
        updatedAt: stamp,
      ),
      key: {'key': SettingKeys.smsMonthlyLimit},
    );
  }

  /// يحفظ خانة الشريحة، أو `null` لمسح الاختيار.
  Future<void> saveSimSlotIndex(int? slotIndex) async {
    if (slotIndex != null && slotIndex < 0) {
      throw ArgumentError.value(
        slotIndex,
        'slotIndex',
        'يجب أن تكون خانة الشريحة صفراً أو أكبر',
      );
    }
    await writer.save(
      db.settings,
      SettingsCompanion.insert(
        key: SettingKeys.smsSimSlotIndex,
        value: (slotIndex ?? -1).toString(),
        updatedAt: writer.now(),
      ),
      key: {'key': SettingKeys.smsSimSlotIndex},
    );
  }
}
