import 'package:school_core/school_core.dart';

/// وصف قالب متاح للتعديل والمعاينة في واجهة الإدارة.
class SmsTemplateDefinition {
  const SmsTemplateDefinition({
    required this.key,
    required this.title,
    required this.variables,
  });

  final String key;
  final String title;
  final Set<String> variables;
}

/// القوالب التي يعرفها النظام، مع أسماء المتغيرات التي يقبلها كل قالب.
abstract final class SmsTemplateCatalog {
  static const List<SmsTemplateDefinition> definitions = [
    SmsTemplateDefinition(
      key: SmsTemplateKeys.accountCreated,
      title: 'بيانات الحساب الجديد',
      variables: {'name', 'school', 'email', 'password'},
    ),
    SmsTemplateDefinition(
      key: SmsTemplateKeys.passwordReset,
      title: 'كلمة السر الجديدة',
      variables: {'school', 'email', 'password'},
    ),
    SmsTemplateDefinition(
      key: SmsTemplateKeys.attendanceAbsent,
      title: 'غياب التلميذ',
      variables: {'school', 'name', 'subject', 'date'},
    ),
    SmsTemplateDefinition(
      key: SmsTemplateKeys.waitingThreshold,
      title: 'بلوغ حد قائمة الانتظار',
      variables: {'school', 'name', 'subject', 'count'},
    ),
    SmsTemplateDefinition(
      key: SmsTemplateKeys.groupCreated,
      title: 'إنشاء مجموعة',
      variables: {'school', 'name', 'subject', 'group', 'schedule'},
    ),
    SmsTemplateDefinition(
      key: SmsTemplateKeys.cycleCompleted,
      title: 'اكتمال الدورة',
      variables: {'school', 'name', 'subject', 'cycle', 'amount'},
    ),
    SmsTemplateDefinition(
      key: SmsTemplateKeys.scheduleChange,
      title: 'تغيير موعد حصة',
      variables: {'school', 'name', 'subject', 'date', 'time', 'room'},
    ),
    SmsTemplateDefinition(
      key: SmsTemplateKeys.requestApproved,
      title: 'الموافقة على طلب أستاذ',
      variables: {'school', 'name', 'subject', 'group', 'summary'},
    ),
    SmsTemplateDefinition(
      key: SmsTemplateKeys.requestRejected,
      title: 'رفض طلب أستاذ',
      variables: {'school', 'name', 'request', 'note'},
    ),
    SmsTemplateDefinition(
      key: SmsTemplateKeys.paymentReceipt,
      title: 'وصل الدفع',
      variables: {'school', 'receipt', 'amount', 'name', 'item', 'subject'},
    ),
    SmsTemplateDefinition(
      key: SmsTemplateKeys.paymentReminder,
      title: 'تذكير بالمستحقات',
      variables: {'school', 'name', 'subject', 'cycle', 'amount'},
    ),
    SmsTemplateDefinition(
      key: SmsTemplateKeys.broadcast,
      title: 'رسالة جماعية',
      variables: {'school', 'name'},
    ),
  ];

  static SmsTemplateDefinition? find(String key) {
    for (final definition in definitions) {
      if (definition.key == key) return definition;
    }
    return null;
  }
}

/// قالب جاهز للعرض والتحرير.
class SmsTemplateView {
  const SmsTemplateView({
    required this.definition,
    required this.body,
    required this.isCustomized,
  });

  final SmsTemplateDefinition definition;
  final String body;
  final bool isCustomized;
}

/// حفظ القوالب المتزامنة، وإرجاع الافتراضي عند عدم وجود تخصيص.
class SmsTemplateService {
  SmsTemplateService(this.db, this.writer);

  final AppDatabase db;
  final SyncWriter writer;

  Future<List<SmsTemplateView>> load() async {
    final rows = await db.select(db.smsTemplates).get();
    final stored = {for (final row in rows) row.key: row.body};
    return [
      for (final definition in SmsTemplateCatalog.definitions)
        _view(definition, stored[definition.key]),
    ];
  }

  Future<SmsTemplateView> get(String key) async {
    final definition = _requireDefinition(key);
    final row = await (db.select(
      db.smsTemplates,
    )..where((template) => template.key.equals(key))).getSingleOrNull();
    return _view(definition, row?.body);
  }

  /// يحفظ نصاً غير فارغ. يظل التعويض عن المتغيرات وقت الإرسال.
  Future<void> save(String key, String body) async {
    _requireDefinition(key);
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('نص القالب لا يمكن أن يكون فارغاً');
    }
    await writer.save(
      db.smsTemplates,
      SmsTemplatesCompanion.insert(
        key: key,
        body: trimmed,
        updatedAt: writer.now(),
      ),
      key: {'key': key},
    );
  }

  /// يعيد القالب الافتراضي ويزامنه إلى بقية الأجهزة.
  Future<void> reset(String key) async {
    final defaultBody = SmsTemplateKeys.defaults[key];
    if (defaultBody == null) _requireDefinition(key);
    await save(key, defaultBody!);
  }

  Future<String> render(String key, Map<String, String> values) =>
      SmsTemplateRenderer(db).render(key, values);

  SmsTemplateDefinition _requireDefinition(String key) {
    final definition = SmsTemplateCatalog.find(key);
    if (definition == null || !SmsTemplateKeys.defaults.containsKey(key)) {
      throw ArgumentError.value(key, 'key', 'قالب SMS غير معروف');
    }
    return definition;
  }

  SmsTemplateView _view(SmsTemplateDefinition definition, String? body) {
    final defaultBody = SmsTemplateKeys.defaults[definition.key]!;
    return SmsTemplateView(
      definition: definition,
      body: body?.trim().isNotEmpty == true ? body! : defaultBody,
      isCustomized: body?.trim().isNotEmpty == true && body != defaultBody,
    );
  }
}
