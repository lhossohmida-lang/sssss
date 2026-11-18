import 'package:drift/drift.dart';
import 'package:school_core/school_core.dart';

/// وصف جدول للمساعد: ماذا يحوي، ومن يحق له قراءته.
class AssistantTable {
  const AssistantTable(
    this.name,
    this.description, {
    this.module,
    this.ownerOnly = false,
    this.notes = const {},
  });

  /// اسمه في القاعدة (`snake_case`).
  final String name;

  /// ما يحويه بالعربية.
  final String description;

  /// وحدة الصلاحية التي يلزم «عرضها» لقراءته؛ `null` لما يراه كل موظف.
  final PermissionModule? module;

  /// هل هو لصاحب المدرسة وحده؟
  final bool ownerOnly;

  /// شرح أعمدة بعينها (اسم العمود ← معناه ورموزه).
  final Map<String, String> notes;
}

/// جداول القاعدة التي يقرؤها المساعد لصاحب المدرسة والعمال، بوصفها وصلاحياتها.
///
/// ما ليس هنا لا يُقرأ أبداً: المحادثات والإشعارات (خصوصية)، وحسابات الدخول وبيانات الاعتماد
/// المحلية وطابور المزامنة وحالة الجهاز (تقنية أو حساسة).
abstract final class AssistantSchema {
  /// أعمدة لا تُعرض ولا تُقرأ: رموز QR (تُزوَّر بها بطاقات الحضور)، وروابط الملفات ومساراتها،
  /// ومعرّفات حسابات المصادقة.
  static const Set<String> hiddenColumns = {
    'qr_code',
    'photo_url',
    'photo_local_path',
    'invoice_photo_url',
    'invoice_photo_local_path',
    'file_url',
    'local_path',
    'auth_user_id',
  };

  static const String conventions =
      'كل جدول مزامَن له id (نص) وcreated_at وupdated_at وdeleted_at؛ السجل المحذوف ناعماً '
      'يكون deleted_at فيه ليس NULL فاستعمل deleted_at IS NULL دائماً. الأوقات أعداد '
      'صحيحة بالميلي ثانية منذ 1970 UTC. التواريخ نص بصيغة YYYY-MM-DD. أوقات اليوم '
      'بالدقائق منذ منتصف الليل (600 = 10:00). كل المبالغ أعداد صحيحة بالدينار الجزائري. '
      'الربط بين الجداول بالمعرّفات (مثل group_id وstudent_id). الأيام: 1 = الاثنين … 7 = الأحد.';

  static const List<AssistantTable> tables = [
    AssistantTable(
      'students',
      'التلاميذ: الاسم واللقب وهاتف الوليّ والمستوى والنقل.',
      module: PermissionModule.students,
      notes: {
        'parent_phone': 'هاتف الوليّ',
        'level_id': 'ربط بـlevels',
        'uses_transport': '1 إن كان مشتركاً في النقل',
        'transport_price': 'سعر النقل الشهري',
        'parent_account_id': 'ربط بـparents',
      },
    ),
    AssistantTable(
      'parents',
      'الأولياء: الهاتف والاسم (الأخوة بوليّ واحد).',
      module: PermissionModule.students,
    ),
    AssistantTable(
      'levels',
      'المستويات الدراسية (سنة أولى متوسط ... إلخ).',
      notes: {'stage': 'primary ابتدائي / middle متوسط / secondary ثانوي'},
    ),
    AssistantTable(
      'subjects',
      'المواد وسعر الشهر المقترح لفوج جديد منها (سعر الفوج الفعلي في groups.monthly_price).',
      module: PermissionModule.subjects,
      notes: {
        'monthly_price': 'سعر الدورة المقترح عند إنشاء فوج من المادة، بالدينار',
      },
    ),
    AssistantTable('rooms', 'القاعات وسعتها.', module: PermissionModule.rooms),
    AssistantTable(
      'teachers',
      'الأساتذة: الاسم والهاتف (ونصيبهم عن كل تلميذ يُعيَّن لكل فوج في groups.rate_per_student).',
      module: PermissionModule.teachers,
      notes: {
        'rate_per_student':
            'نصيبه الافتراضي القديم (النصيب الفعلي في groups.rate_per_student)',
      },
    ),
    AssistantTable(
      'teacher_subjects',
      'المواد التي يدرّسها كل أستاذ (teacher_id، subject_id).',
      module: PermissionModule.teachers,
    ),
    AssistantTable(
      'workers',
      'العمال: الاسم والهاتف وأجر اليوم الكامل ونصفه وبرنامجهم الأسبوعي وصلاحياتهم.',
      module: PermissionModule.workers,
      notes: {
        'full_day_wage': 'أجر اليوم الكامل',
        'half_day_wage': 'أجر نصف اليوم',
        'permissions': 'JSON: الوحدة ← الأفعال المسموحة',
      },
    ),
    AssistantTable(
      'transport_lines',
      'خطوط النقل: السائق وهاتفه ورقم الحافلة.',
      module: PermissionModule.transport,
    ),
    AssistantTable(
      'groups',
      'الأفواج: رقم الفوج ومادته وأستاذه وقاعته وعدد حصص الدورة والدورة الحالية وسعر شهره ومبلغ أستاذه.',
      module: PermissionModule.groups,
      notes: {
        'number': 'رقم الفوج',
        'sessions_per_cycle': 'عدد حصص الدورة',
        'current_cycle_number': 'رقم الدورة الحالية',
        'monthly_price': 'سعر الشهر الذي يدفعه كل تلميذ في هذا الفوج (يُعيَّن عند إنشائه، ويختلف من فوج إلى آخر بحسب المادة والسنة)',
        'rate_per_student':
            'ما يأخذه الأستاذ عن كل تلميذ في هذا الفوج (يُعيَّن عند إنشائه)',
        'archived_at': 'NULL = الفوج نشط، وإلا مؤرشف (سنة جديدة)',
      },
    ),
    AssistantTable(
      'group_slots',
      'الجدول الأسبوعي للفوج: يوم وبداية ونهاية بالدقائق وقاعة (group_id).',
      module: PermissionModule.groups,
      notes: {'weekday': '1 = الاثنين … 7 = الأحد'},
    ),
    AssistantTable(
      'group_students',
      'انتساب التلاميذ إلى الأفواج: سعر شهره وتخفيضه ومتى التحق وغادر.',
      module: PermissionModule.groups,
      notes: {
        'monthly_price': 'سعر الشهر لهذا التلميذ قبل التخفيض',
        'discount_type':
            'none دون / percent نسبة / fixed مبلغ ثابت / exempt إعفاء',
        'discount_value': 'النسبة أو المبلغ بحسب discount_type',
        'left_at': 'NULL = ما زال في الفوج',
        'joined_at_cycle_number': 'الدورة التي التحق فيها',
      },
    ),
    AssistantTable(
      'sessions',
      'الحصص: تاريخها ووقتها وفوجها ودورتها وحالتها.',
      module: PermissionModule.groups,
      notes: {
        'status':
            'normal عادية / cancelled ملغاة / makeup تعويضية / added مضافة',
        'session_number': 'ترتيبها في الدورة (NULL للملغاة)',
        'closed_at': 'وقت الإغلاق (غُيّب من لم يحضر)',
      },
    ),
    AssistantTable(
      'attendance',
      'حضور التلاميذ: لكل تلميذ في كل حصة (session_id، student_id).',
      module: PermissionModule.attendance,
      notes: {
        'status': 'present حاضر / absent غائب / excused غائب برخصة',
        'method': 'qr مسح الرمز / manual يدوي',
      },
    ),
    AssistantTable(
      'teacher_attendance',
      'حضور الأساتذة: وقت الدخول والخروج ودقائق التأخر.',
      module: PermissionModule.attendance,
    ),
    AssistantTable(
      'worker_attendance',
      'حضور العمال: يومهم ووقت الدخول والخروج وتعديل المدير لليوم.',
      module: PermissionModule.workers,
      notes: {'override_kind': 'off لا يعمل / half نصف يوم / full يوم كامل'},
    ),
    AssistantTable(
      'waiting_lists',
      'قوائم الانتظار لمادة ومستوى، وحدّ تنبيه المدير.',
      module: PermissionModule.waiting,
    ),
    AssistantTable(
      'waiting_entries',
      'من ينتظر في كل قائمة انتظار (waiting_list_id، student_id).',
      module: PermissionModule.waiting,
    ),
    AssistantTable(
      'session_requests',
      'طلبات الأساتذة لتغيير الحصص وقرار الإدارة.',
      module: PermissionModule.requests,
      notes: {
        'type':
            'reschedule تغيير موعد / add إضافة / advance تسبيق / cancel إلغاء',
        'status': 'pending قيد الانتظار / approved مقبول / rejected مرفوض',
      },
    ),
    AssistantTable(
      'payments',
      'الدفعات المسجَّلة مع رقم الوصل. مجموع الدفعات = amount.',
      module: PermissionModule.payments,
      notes: {
        'type': 'month شهر (دورة) / transport نقل / registration حقوق تسجيل',
        'receipt_number': 'رقم الوصل المرقّم',
        'cycle_number': 'رقم الدورة عند دفع شهر',
      },
    ),
    AssistantTable(
      'student_credits',
      'أرصدة التلاميذ التي تُخصم من دورة تالية.',
      module: PermissionModule.payments,
      notes: {
        'reason':
            'excused غياب برخصة / mid_join التحاق في المنتصف / manual يدوي',
        'target_cycle_number': 'الدورة التي يُخصم منها',
      },
    ),
    AssistantTable(
      'registration_fees',
      'حقوق التسجيل لكل تلميذ في كل فترة (سنة أو فصل) وهل دُفعت.',
      module: PermissionModule.payments,
    ),
    AssistantTable(
      'teacher_payouts',
      'خلاصات الأساتذة: نصيبهم من كل دورة وهل سُلِّم.',
      module: PermissionModule.payouts,
      notes: {
        'kind': 'cycle اكتمال دورة / release نصيب معلّق أُفرج عنه',
        'paid_at': 'NULL = لم يُسلَّم بعد',
      },
    ),
    AssistantTable(
      'staff_debts',
      'ديون الأساتذة والعمال على المدرسة وتسديدها (لصاحب المدرسة وحده).',
      ownerOnly: true,
      notes: {
        'kind': 'debt دين / payment تسديد',
        'staff_type': 'teacher أو worker',
      },
    ),
    AssistantTable(
      'expense_categories',
      'أنواع المصاريف (منها «أجور العمال»).',
      module: PermissionModule.expenses,
    ),
    AssistantTable(
      'expenses',
      'المصاريف: النوع والمبلغ والتاريخ والملاحظة.',
      module: PermissionModule.expenses,
    ),
    AssistantTable(
      'sms_queue',
      'طابور الرسائل القصيرة: هاتف المستلم والنص وحالة الإرسال.',
      module: PermissionModule.sms,
      notes: {
        'status': 'pending / sending / sent / failed / cancelled',
        'kind': 'مفتاح القالب الذي نشأت منه الرسالة',
      },
    ),
    AssistantTable(
      'sms_templates',
      'قوالب الرسائل القصيرة المعدَّلة.',
      module: PermissionModule.sms,
    ),
    AssistantTable(
      'grades',
      'نتائج التلاميذ في الاختبارات (الدرجة من الدرجة العظمى).',
      module: PermissionModule.students,
    ),
    AssistantTable(
      'group_files',
      'ملفات الأفواج (العنوان واسم الملف وحجمه).',
      module: PermissionModule.groups,
    ),
    AssistantTable(
      'settings',
      'إعدادات المدرسة: أزواج مفتاح/قيمة (اسم المدرسة وحقوق التسجيل والفصول ...).',
      module: PermissionModule.settings,
    ),
    AssistantTable(
      'audit_log',
      'سجل العمليات: من غيّر ماذا ومتى.',
      module: PermissionModule.audit,
    ),
  ];

  static final Map<String, AssistantTable> _byName = {
    for (final table in tables) table.name: table,
  };

  /// هل يملك [session] قراءة الجداول؟ صاحب المدرسة والعمال وحدهم، والعامل بصلاحية ما.
  static bool isStaff(AuthSession session) => switch (session.role) {
    UserRole.owner => true,
    UserRole.worker => PermissionModule.values.any(session.policy.canAnyOf),
    UserRole.teacher || UserRole.parent => false,
  };

  /// الجداول التي يحق لـ[session] قراءتها.
  static List<AssistantTable> visibleTo(AuthSession session) {
    if (!isStaff(session)) return const [];
    return [
      for (final table in tables)
        if (_allows(session, table)) table,
    ];
  }

  static bool _allows(AuthSession session, AssistantTable table) {
    if (table.ownerOnly) return session.role == UserRole.owner;
    final module = table.module;
    return module == null || session.can(module, PermissionAction.view);
  }

  /// الجدول باسمه، أو `null` إن لم يكن في الدليل.
  static AssistantTable? byName(String name) => _byName[name];

  /// أسماء كل جداول القاعدة (المسموح وغيره).
  static Set<String> knownTables(AppDatabase db) => {
    for (final table in db.allTables) table.actualTableName,
  };

  /// أعمدة جدول مع أنواعها وشرحها، دون الأعمدة المحجوبة.
  static List<Map<String, Object?>> columnsOf(AppDatabase db, String name) {
    final info = byName(name);
    final table = db.allTables.firstWhere(
      (t) => t.actualTableName == name,
      orElse: () => throw ArgumentError('جدول غير موجود: $name'),
    );
    return [
      for (final column in table.$columns)
        if (!hiddenColumns.contains(column.$name))
          {
            'name': column.$name,
            'type': _typeName(column.type),
            if (column.$nullable) 'nullable': true,
            if (info?.notes[column.$name] != null)
              'note': info!.notes[column.$name],
          },
    ];
  }

  static String _typeName(Object type) {
    if (type == DriftSqlType.int || type == DriftSqlType.bigInt) {
      return 'integer';
    }
    if (type == DriftSqlType.bool) return 'boolean (0/1)';
    if (type == DriftSqlType.double) return 'real';
    if (type == DriftSqlType.string) return 'text';
    if (type == DriftSqlType.dateTime) return 'datetime';
    return 'blob';
  }
}
