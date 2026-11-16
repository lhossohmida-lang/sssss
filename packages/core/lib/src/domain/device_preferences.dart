import '../data/local/app_database.dart';

/// تفضيلات هذا الجهاز لمدرسته: قيم نصية صغيرة في جدول `device_info` المحلي.
///
/// لا تُزامَن، فلا تصل بقية أجهزة المدرسة ولا تُقرأ من حسابات المعلمين والأولياء (جدول
/// `settings` مقروء للجميع)؛ وهي لمدرسة واحدة لأن لكل مدرسة قاعدة محلية مستقلة، وتبقى عند
/// استعادة نسخة احتياطية. لا تُحفظ فيها أسرار.
class DevicePreferences {
  DevicePreferences(this.db);

  final AppDatabase db;

  /// بريد حساب Google الذي يُسمح له بربط Drive على هذا الجهاز (صاحب المدرسة).
  static const String driveOwnerEmailKey = 'drive_owner_email';

  /// القيمة المحفوظة، أو `null` إن لم تُحفظ.
  Future<String?> read(String key) async {
    final row = await (db.select(
      db.deviceInfo,
    )..where((d) => d.key.equals(key))).getSingleOrNull();
    return _clean(row?.value);
  }

  /// القيمة وتتحدث مع كل تغيير.
  Stream<String?> watch(String key) =>
      (db.select(db.deviceInfo)..where((d) => d.key.equals(key)))
          .watchSingleOrNull()
          .map((row) => _clean(row?.value));

  /// يحفظ [value]، ويحذف المفتاح إن كانت فارغة أو `null`.
  Future<void> write(String key, String? value) async {
    final text = _clean(value);
    if (text == null) {
      await (db.delete(db.deviceInfo)..where((d) => d.key.equals(key))).go();
      return;
    }
    await db
        .into(db.deviceInfo)
        .insertOnConflictUpdate(
          DeviceInfoCompanion.insert(key: key, value: text),
        );
  }

  /// بريد مالك Drive المحفوظ على هذا الجهاز.
  Future<String?> driveOwnerEmail() => read(driveOwnerEmailKey);

  /// يحفظ بريد مالك Drive بعد تنظيفه. يرمي [FormatException] برسالة عربية إن لم يكن بريداً
  /// صالحاً؛ والفارغ يمسح المحفوظ.
  Future<String?> saveDriveOwnerEmail(String? value) async {
    final email = GoogleAccountEmail.normalize(value);
    await write(driveOwnerEmailKey, email);
    return email;
  }
}

/// تنظيف بريد حساب Google والتحقق من شكله (يُقارَن بالأحرف الصغيرة).
abstract final class GoogleAccountEmail {
  static final RegExp _shape = RegExp(
    r'^[a-z0-9._%+\-]+@[a-z0-9\-]+(\.[a-z0-9\-]+)*\.[a-z]{2,}$',
  );

  /// البريد بأحرف صغيرة ودون مسافات، أو `null` إن كان فارغاً. يرمي [FormatException]
  /// إن كان غير فارغ وشكله غير صالح.
  static String? normalize(String? value) {
    final text = value?.trim().toLowerCase() ?? '';
    if (text.isEmpty) return null;
    if (text.length > 254 || !_shape.hasMatch(text)) {
      throw const FormatException(
        'أدخل بريد حساب Google صالحاً، مثل name@gmail.com',
      );
    }
    return text;
  }
}

String? _clean(String? value) {
  final text = value?.trim();
  return text == null || text.isEmpty ? null : text;
}
