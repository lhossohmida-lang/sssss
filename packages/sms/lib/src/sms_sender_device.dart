import 'package:school_core/school_core.dart';

/// أي جهاز إدارة يرسل رسائل SMS تلقائياً: واحد فقط، لئلا تُرسل رسالة مرتين.
///
/// معرّف الجهاز المعتمد يُحفظ في إعدادات المدرسة المتزامنة ليعرفه كل جهاز، ومعرّف هذا
/// الجهاز في تفضيلاته المحلية. أول هاتف Android يفتح الإدارة بصلاحية الإعدادات يصير
/// المرسل تلقائياً إن لم يوجد مرسل، ويمكن تغييره من مركز الرسائل.
class SmsSenderDevice {
  SmsSenderDevice(this.db, this.writer) : _preferences = DevicePreferences(db);

  final AppDatabase db;
  final SyncWriter writer;
  final DevicePreferences _preferences;

  /// معرّف هذا الجهاز.
  Future<String> deviceId() => _preferences.deviceId();

  /// معرّف الجهاز المعيَّن للإرسال، أو `null` إن لم يُعيَّن أحد.
  Future<String?> designated() async {
    final row =
        await (db.select(db.settings)
              ..where((s) => s.key.equals(SettingKeys.smsSenderDevice)))
            .getSingleOrNull();
    return _clean(row?.value);
  }

  /// المعيَّن للإرسال، ويتحدث عند تغييره (من هذا الجهاز أو من المزامنة).
  Stream<String?> watchDesignated() =>
      (db.select(db.settings)
            ..where((s) => s.key.equals(SettingKeys.smsSenderDevice)))
          .watchSingleOrNull()
          .map((row) => _clean(row?.value))
          .distinct();

  /// هل هذا الجهاز هو المعيَّن للإرسال الآن؟
  Future<bool> isThisDevice() async => await designated() == await deviceId();

  /// هل هذا الجهاز هو المعيَّن؟ ويتحدث عند تغيير التعيين.
  Stream<bool> watchIsThisDevice() async* {
    final me = await deviceId();
    yield* watchDesignated().map((id) => id == me).distinct();
  }

  /// يعيّن هذا الجهاز للإرسال إن لم يكن هناك مرسل. يعيد هل صار هذا الجهاز هو المرسل.
  Future<bool> claimIfUnassigned() async {
    if (await designated() == null) await claim();
    return isThisDevice();
  }

  /// يجعل هذا الجهاز هو المرسل (ويحلّ محل غيره).
  Future<void> claim() => _save(deviceId());

  /// يزيل التعيين فلا يرسل أي جهاز حتى يُعيَّن جهاز.
  Future<void> release() => _save(Future<String>.value(''));

  Future<void> _save(Future<String> value) async {
    final id = await value;
    await writer.save(
      db.settings,
      SettingsCompanion.insert(
        key: SettingKeys.smsSenderDevice,
        value: id,
        updatedAt: writer.now(),
      ),
      key: {'key': SettingKeys.smsSenderDevice},
    );
  }

  String? _clean(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }
}
