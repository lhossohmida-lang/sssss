import 'package:drift/drift.dart';

import '../data/local/app_database.dart';
import 'account_service.dart';
import 'catalog_service.dart';
import 'cycle_service.dart';
import 'date_key.dart';
import 'dues_service.dart';
import 'enrolment_service.dart';
import 'enums.dart';
import 'payment_service.dart';
import 'phone.dart';
import 'pricing.dart';
import 'registration_service.dart';
import 'school_settings.dart';

/// ما سُدِّد من الدورة الحالية عند إضافة تلميذ إلى الفوج.
enum CyclePaymentChoice {
  /// لم تُسدَّد بعد (تبقى في المستحقات).
  unpaid,

  /// سُدِّدت كلها.
  full,

  /// سُدِّد جزء منها ([GroupSetupStudent.partialAmount]).
  partial,
}

/// بيانات تلميذ يُضاف إلى فوج من صفحة إعداد الفوج.
class GroupSetupStudent {
  const GroupSetupStudent({
    required this.firstName,
    required this.lastName,
    required this.parentName,
    required this.parentPhone,
    this.levelId,
    this.payment = CyclePaymentChoice.unpaid,
    this.partialAmount = 0,
  });

  final String firstName;
  final String lastName;
  final String parentName;
  final String parentPhone;
  final String? levelId;
  final CyclePaymentChoice payment;

  /// المبلغ المسدَّد حين يكون [payment] جزئياً.
  final int partialAmount;
}

/// نتيجة إضافة تلميذ: ما تم له، وما سُدِّد، وسبب تعذّر التسديد إن تعذّر.
class GroupSetupResult {
  const GroupSetupResult({
    required this.registration,
    required this.paidNow,
    required this.remaining,
    this.payment,
    this.paymentError,
  });

  final RegistrationResult registration;

  /// ما سُدِّد الآن من الدورة الحالية بالدينار (صفر إن لم يُسدَّد شيء).
  final int paidNow;

  /// ما بقي على التلميذ من الدورة الحالية.
  final int remaining;

  /// الدفعة المسجَّلة (بوصلها) إن سُدِّد شيء.
  final PaymentRow? payment;

  /// سبب تعذّر تسجيل الدفعة مع أن التلميذ أُضيف؛ `null` إن لم يتعذّر.
  final String? paymentError;

  StudentRow get student => registration.student;
  ProvisionedAccount get parentAccount => registration.parentAccount;
}

/// نتيجة إضافة تلاميذ موجودين إلى الفوج: من أُضيف، ومن لم يُضَف وسبب ذلك.
class ExistingStudentsResult {
  const ExistingStudentsResult({required this.added, required this.skipped});

  /// معرّفات من أُضيفوا إلى الفوج.
  final List<String> added;

  /// معرّف من لم يُضَف ← السبب (منتسب أصلاً، غير موجود...).
  final Map<String, String> skipped;
}

/// تلميذ في الفوج ومعه وضع تسديد دورته الحالية (لصفحة الإعداد).
class GroupSetupRow {
  const GroupSetupRow({
    required this.studentId,
    required this.name,
    required this.parentPhone,
    required this.due,
    required this.paid,
  });

  final String studentId;
  final String name;
  final String parentPhone;

  /// المطلوب عن الدورة الحالية بعد التخفيض والأرصدة.
  final int due;
  final int paid;

  int get remaining => due - paid < 0 ? 0 : due - paid;
  bool get isSettled => remaining == 0;
}

/// إعداد فوج جديد أو قائم من صفحة واحدة: يضيف تلميذاً بحسابه وانتسابه (وتصله
/// بيانات دخول وليّه برسالة) ويسدّد ما شاء من دورته الحالية بوصل، ويعرض وضع
/// تسديد كل تلاميذ الفوج. الحضور السابق يُسجَّل بعدها من شاشته (انظر
/// `PastSessionsService`).
class GroupSetupService {
  /// [registration] يُطلب عند إضافة تلميذ فقط، فلا تحتاج قراءة قائمة التلاميذ
  /// إلى خدمة إنشاء الحسابات (وهي غير متاحة دون خادم مهيّأ).
  GroupSetupService(
    this.db,
    RegistrationService Function() registration,
    this.payments,
    this.dues,
    this.cycles, {
    this.enrolments,
    DateTime Function()? clock,
  }) : _registration = registration,
       _clock = clock ?? DateTime.now;

  final AppDatabase db;
  final RegistrationService Function() _registration;

  /// خدمة الانتساب، تُطلب عند إضافة تلاميذ موجودين فقط.
  final EnrolmentService Function()? enrolments;
  final PaymentService payments;
  final DuesService dues;
  final CycleService cycles;
  final DateTime Function() _clock;

  static const String fieldGroup = 'group';
  static const String fieldAmount = PaymentService.fieldAmount;

  /// الفوج الحي غير المؤرشف، أو يرمي [ValidationException].
  Future<GroupRow> _group(String groupId) async {
    final group = await (db.select(
      db.groups,
    )..where((g) => g.id.equals(groupId))).getSingleOrNull();
    if (group == null || group.deletedAt != null || group.archivedAt != null) {
      throw ValidationException.field(fieldGroup, 'الفوج غير متاح');
    }
    return group;
  }

  /// سعر شهر المادة الذي يُسجَّل به التلميذ في الفوج.
  Future<int> priceOf(GroupRow group) async {
    final subject = await (db.select(
      db.subjects,
    )..where((s) => s.id.equals(group.subjectId))).getSingle();
    return subject.monthlyPrice;
  }

  /// سعر دورة الفوج [groupId] للتلميذ.
  Future<int> priceOfGroup(String groupId) async =>
      priceOf(await _group(groupId));

  /// يضيف التلميذ إلى الفوج ويسدّد ما اختير من دورته الحالية.
  ///
  /// يرمي [ValidationException] إن كانت البيانات غير صالحة (فلا يُكتب شيء ولا
  /// يُنشأ حساب). وإن أُضيف التلميذ وتعذّر تسجيل الدفعة (مبلغ جزئي غير مقبول
  /// مثلاً) يبقى مضافاً ويُعاد السبب في [GroupSetupResult.paymentError].
  Future<GroupSetupResult> addStudent(
    String groupId,
    GroupSetupStudent input, {
    required SchoolSettings settings,
  }) async {
    final group = await _group(groupId);
    final price = await priceOf(group);
    final result = await _registration().register(
      RegistrationRequest(
        firstName: input.firstName,
        lastName: input.lastName,
        parentName: input.parentName,
        parentPhone: input.parentPhone,
        levelId: input.levelId,
        choices: [
          SubjectChoice(
            subjectId: group.subjectId,
            groupId: group.id,
            monthlyPrice: price,
          ),
        ],
        date: DateKey.of(_clock()),
      ),
      settings: settings,
    );
    return _pay(group, result, input);
  }

  /// ينسب تلاميذ موجودين من قبل إلى الفوج بسعر مادته، دون دفعة ولا رسالة (حساب وليّ كل
  /// منهم قائم). من التحق في منتصف الدورة يُنشأ له رصيد الحصص الفائتة كأي ملتحق. لا يتعطل
  /// الباقون بتلميذ تعذّرت إضافته: من لم يُضَف يأتي في [ExistingStudentsResult.skipped]
  /// بسببه (منتسب أصلاً، محذوف...). يرمي [ValidationException] إن لم يكن الفوج متاحاً.
  Future<ExistingStudentsResult> addExisting(
    String groupId,
    Iterable<String> studentIds,
  ) async {
    final enrol = enrolments?.call();
    if (enrol == null) {
      throw StateError('خدمة الانتساب غير مهيّأة');
    }
    final group = await _group(groupId);
    final price = await priceOf(group);
    final added = <String>[];
    final skipped = <String, String>{};
    for (final id in studentIds.toSet()) {
      final student = await (db.select(
        db.students,
      )..where((s) => s.id.equals(id))).getSingleOrNull();
      if (student == null || student.deletedAt != null) {
        skipped[id] = 'التلميذ غير موجود';
        continue;
      }
      try {
        await enrol.enrol(
          studentId: id,
          groupId: group.id,
          monthlyPrice: price,
        );
        added.add(id);
      } on ValidationException catch (e) {
        skipped[id] = e.toString();
      }
    }
    return ExistingStudentsResult(added: added, skipped: skipped);
  }

  Future<GroupSetupResult> _pay(
    GroupRow group,
    RegistrationResult registered,
    GroupSetupStudent input,
  ) async {
    final studentId = registered.student.id;
    final due = await _currentDue(group, studentId);
    var remaining = due?.remaining ?? 0;
    if (input.payment == CyclePaymentChoice.unpaid || due == null) {
      return GroupSetupResult(
        registration: registered,
        paidNow: 0,
        remaining: remaining,
      );
    }
    final amount = input.payment == CyclePaymentChoice.full
        ? remaining
        : input.partialAmount;
    if (amount <= 0) {
      return GroupSetupResult(
        registration: registered,
        paidNow: 0,
        remaining: remaining,
        paymentError: remaining == 0
            ? null
            : 'أدخل مبلغاً أكبر من صفر أو اختر «غير مسدّدة»',
      );
    }
    try {
      final payment = await payments.record(
        studentId: studentId,
        type: PaymentType.month,
        amount: amount,
        groupId: group.id,
        cycleNumber: group.currentCycleNumber,
      );
      remaining -= amount;
      return GroupSetupResult(
        registration: registered,
        paidNow: amount,
        remaining: remaining,
        payment: payment,
      );
    } on ValidationException catch (e) {
      return GroupSetupResult(
        registration: registered,
        paidNow: 0,
        remaining: remaining,
        paymentError: e.errors[fieldAmount] ?? e.errors.values.firstOrNull,
      );
    }
  }

  Future<CycleDue?> _currentDue(GroupRow group, String studentId) async {
    final dueList = await dues.cycleDues(
      studentId: studentId,
      groupId: group.id,
      cycleNumber: group.currentCycleNumber,
    );
    return dueList.firstOrNull;
  }

  /// يسدّد [amount] من الدورة الحالية لتلميذ في الفوج (للباقي بعد الإضافة).
  Future<PaymentRow> payCurrentCycle({
    required String groupId,
    required String studentId,
    required int amount,
  }) async {
    final group = await _group(groupId);
    return payments.record(
      studentId: studentId,
      type: PaymentType.month,
      amount: amount,
      groupId: group.id,
      cycleNumber: group.currentCycleNumber,
    );
  }

  /// تلاميذ الفوج الحاليون ومعهم تسديد الدورة الحالية، بترتيب الاسم.
  Future<List<GroupSetupRow>> students(String groupId) async {
    final group = await _group(groupId);
    final rows = await db
        .customSelect(
          'SELECT s.id, s.first_name, s.last_name, s.parent_phone '
          'FROM group_students gs JOIN students s ON s.id = gs.student_id '
          'WHERE gs.group_id = ? AND gs.deleted_at IS NULL '
          'AND gs.left_at IS NULL AND s.deleted_at IS NULL '
          'ORDER BY s.last_name, s.first_name, s.id',
          variables: [Variable<String>(groupId)],
          readsFrom: {db.groupStudents, db.students},
        )
        .get();
    final dueList = await dues.cycleDues(
      groupId: group.id,
      cycleNumber: group.currentCycleNumber,
    );
    final dueByStudent = {for (final due in dueList) due.studentId: due};
    return [
      for (final row in rows)
        GroupSetupRow(
          studentId: row.read<String>('id'),
          name:
              '${row.read<String>('first_name')} ${row.read<String>('last_name')}',
          parentPhone: PhoneNumbers.normalize(row.read<String>('parent_phone')),
          due: dueByStudent[row.read<String>('id')]?.due ?? 0,
          paid: dueByStudent[row.read<String>('id')]?.paid ?? 0,
        ),
    ];
  }

  /// عدد الحصص المغلقة (المنعقدة) في الدورة الحالية، أي ما سُجِّل منها.
  Future<int> heldSessions(String groupId) async {
    final group = await _group(groupId);
    return cycles.countedSessions(
      groupId,
      group.currentCycleNumber,
      closedOnly: true,
    );
  }
}
