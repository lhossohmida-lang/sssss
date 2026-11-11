import 'package:drift/drift.dart';

import '../data/local/app_database.dart';
import '../data/local/sync_writer.dart';
import 'account_service.dart';
import 'catalog_service.dart';
import 'dues_service.dart';
import 'enrolment_service.dart';
import 'enums.dart';
import 'phone.dart';
import 'qr_code.dart';
import 'school_settings.dart';

/// اختيار مادة في استمارة التسجيل: مجموعة، أو قائمة الانتظار إن كان
/// [groupId] فارغاً.
class SubjectChoice {
  const SubjectChoice({
    required this.subjectId,
    this.groupId,
    this.preferredTeacherId,
    this.monthlyPrice = 0,
    this.discountType = DiscountType.none,
    this.discountValue = 0,
  });

  final String subjectId;

  /// المجموعة المختارة؛ `null` يعني قائمة الانتظار.
  final String? groupId;

  /// الأستاذ المفضّل في قائمة الانتظار (اختياري).
  final String? preferredTeacherId;

  /// سعر الشهر قبل التخفيض (للمجموعة فقط).
  final int monthlyPrice;
  final DiscountType discountType;
  final int discountValue;

  bool get isWaiting => groupId == null;
}

/// بيانات استمارة تسجيل تلميذ جديد.
class RegistrationRequest {
  const RegistrationRequest({
    required this.firstName,
    required this.lastName,
    required this.parentName,
    required this.parentPhone,
    required this.choices,
    required this.date,
    this.levelId,
    this.usesTransport = false,
    this.transportPrice = 0,
    this.transportLineId,
  });

  final String firstName;
  final String lastName;
  final String parentName;
  final String parentPhone;
  final String? levelId;
  final List<SubjectChoice> choices;

  /// تاريخ التسجيل `YYYY-MM-DD` (يحدد فترة حقوق التسجيل).
  final String date;
  final bool usesTransport;

  /// سعر النقل الشهري بالدينار.
  final int transportPrice;
  final String? transportLineId;
}

/// نتيجة التسجيل: التلميذ، حساب وليّه، وما تم في المواد.
class RegistrationResult {
  const RegistrationResult({
    required this.student,
    required this.parentAccount,
    required this.enrolledGroupIds,
    required this.waitingListIds,
    required this.registrationFee,
  });

  final StudentRow student;

  /// حساب الوليّ: جديد (ببيانات دخوله) أو موجود رُبط به.
  final ProvisionedAccount parentAccount;
  final List<String> enrolledGroupIds;
  final List<String> waitingListIds;

  /// حقوق التسجيل المستحقة؛ `null` إن كانت صفراً في الإعدادات.
  final RegistrationFeeRow? registrationFee;
}

/// تسجيل تلميذ جديد: بياناته، رمز QR، حساب وليّه (جديد أو قائم بنفس الهاتف)،
/// انتسابه إلى المجموعات أو قوائم الانتظار، النقل، وحقوق التسجيل.
class RegistrationService {
  RegistrationService(
    this.db,
    this.writer, {
    required this.accounts,
    required this.enrolments,
    required this.dues,
  });

  final AppDatabase db;
  final SyncWriter writer;
  final AccountService accounts;
  final EnrolmentService enrolments;
  final DuesService dues;

  static const String fieldFirstName = 'first_name';
  static const String fieldLastName = 'last_name';
  static const String fieldParentName = 'parent_name';
  static const String fieldPhone = AccountService.fieldPhone;
  static const String fieldSubjects = 'subjects';
  static const String fieldTransport = 'transport';

  /// حقل خطأ المادة رقم [index] (من صفر): `choice:0:price` مثلاً.
  static String choiceField(int index, String field) => 'choice:$index:$field';

  /// أخطاء الاستمارة قبل أي كتابة. فارغة إن كانت سليمة.
  Future<Map<String, String>> validate(RegistrationRequest r) async {
    final errors = <String, String>{};
    if (r.firstName.trim().isEmpty) errors[fieldFirstName] = 'أدخل الاسم';
    if (r.lastName.trim().isEmpty) errors[fieldLastName] = 'أدخل اللقب';
    if (r.parentName.trim().isEmpty) {
      errors[fieldParentName] = 'أدخل اسم الوليّ';
    }
    if (!PhoneNumbers.isValid(r.parentPhone)) {
      errors[fieldPhone] = 'رقم الهاتف يبدأ بـ 05 أو 06 أو 07 ويتبعه 8 أرقام';
    }
    if (r.choices.isEmpty) {
      errors[fieldSubjects] = 'اختر مادة واحدة على الأقل';
    }
    final seen = <String>{};
    for (var i = 0; i < r.choices.length; i++) {
      final choice = r.choices[i];
      if (!seen.add(choice.subjectId)) {
        errors[fieldSubjects] = 'المادة مكررة في الاستمارة';
      }
      if (choice.isWaiting) continue;
      EnrolmentService.priceErrors(
        price: choice.monthlyPrice,
        discountType: choice.discountType,
        discountValue: choice.discountValue,
      ).forEach((field, message) => errors[choiceField(i, field)] = message);
    }
    if (r.usesTransport) {
      if (r.transportPrice <= 0) {
        errors[fieldTransport] = 'أدخل سعر النقل الشهري';
      } else if (r.transportPrice % 10 != 0) {
        errors[fieldTransport] = 'السعر من مضاعفات 10 دج';
      }
    }
    if (errors.isEmpty) {
      final phone = PhoneNumbers.normalize(r.parentPhone);
      final twin =
          await (db.select(db.students)..where(
                (s) =>
                    s.firstName.equals(r.firstName.trim()) &
                    s.lastName.equals(r.lastName.trim()) &
                    s.parentPhone.equals(phone) &
                    s.deletedAt.isNull(),
              ))
              .get();
      if (twin.isNotEmpty) {
        errors[fieldFirstName] = 'هذا التلميذ مسجَّل من قبل لنفس الوليّ';
      }
      // هاتف مستعمل لحساب أستاذ أو عامل لا يصلح لحساب وليّ.
      final account = await accounts.findByEmail(
        AccountService.emailFor(phone),
      );
      if (account != null && account.role != UserRole.parent.code) {
        errors[fieldPhone] = 'رقم الهاتف مستعمل في حساب ${_roleLabel(account)}';
      }
    }
    return errors;
  }

  /// يسجّل التلميذ. يرمي [ValidationException] إن كانت الاستمارة غير صالحة،
  /// فلا يُكتب شيء ولا يُنشأ حساب.
  ///
  /// حساب الوليّ يُنشأ أولاً (اتصال خارجي في وضع الخادم) ثم تُكتب بقية
  /// البيانات في معاملة واحدة؛ إن فشلت أُعيدت المحاولة فيُربط بالحساب القائم.
  Future<RegistrationResult> register(
    RegistrationRequest r, {
    required SchoolSettings settings,
  }) async {
    final errors = await validate(r);
    if (errors.isNotEmpty) throw ValidationException(errors);

    final phone = PhoneNumbers.normalize(r.parentPhone);
    final parentName = r.parentName.trim();
    final existingParent = await (db.select(
      db.parents,
    )..where((p) => p.phone.equals(phone))).getSingleOrNull();
    final parentId = existingParent?.id ?? writer.newId();
    final account = await accounts.create(
      role: UserRole.parent,
      entityId: parentId,
      displayName: parentName,
      phone: phone,
      reuseExisting: true,
    );
    final qr = await _uniqueQr();
    final studentId = writer.newId();

    return db.transaction(() async {
      if (existingParent == null || existingParent.deletedAt != null) {
        await writer.save(
          db.parents,
          ParentsCompanion.insert(
            id: parentId,
            createdAt: 0,
            updatedAt: 0,
            phone: phone,
            email: account.email,
            name: Value(parentName),
            authUserId: Value(account.accountId),
            deletedAt: const Value(null),
          ),
          key: {'id': parentId},
        );
      }
      await writer.save(
        db.students,
        StudentsCompanion.insert(
          id: studentId,
          createdAt: 0,
          updatedAt: 0,
          firstName: r.firstName.trim(),
          lastName: r.lastName.trim(),
          parentPhone: phone,
          levelId: Value(r.levelId),
          usesTransport: Value(r.usesTransport),
          transportPrice: Value(r.usesTransport ? r.transportPrice : 0),
          transportLineId: Value(r.usesTransport ? r.transportLineId : null),
          qrCode: qr,
          parentAccountId: Value(parentId),
        ),
        key: {'id': studentId},
      );

      final groups = <String>[];
      final waiting = <String>[];
      for (final choice in r.choices) {
        final groupId = choice.groupId;
        if (groupId == null) {
          waiting.add(
            await enrolments.addToWaiting(
              studentId: studentId,
              subjectId: choice.subjectId,
              levelId: r.levelId,
              preferredTeacherId: choice.preferredTeacherId,
            ),
          );
        } else {
          await enrolments.enrol(
            studentId: studentId,
            groupId: groupId,
            monthlyPrice: choice.monthlyPrice,
            discountType: choice.discountType,
            discountValue: choice.discountValue,
          );
          groups.add(groupId);
        }
      }

      final fee = settings.registrationFee > 0
          ? await dues.ensureRegistrationFee(
              studentId: studentId,
              periodKey: settings.feePeriodKey(r.date),
              amount: settings.registrationFee,
            )
          : null;
      final student = await (db.select(
        db.students,
      )..where((s) => s.id.equals(studentId))).getSingle();
      return RegistrationResult(
        student: student,
        parentAccount: account,
        enrolledGroupIds: groups,
        waitingListIds: waiting,
        registrationFee: fee,
      );
    });
  }

  String _roleLabel(UserAccountRow account) {
    try {
      return UserRole.fromCode(account.role).label;
    } on ArgumentError {
      return 'آخر';
    }
  }

  /// رمز QR غير مستعمل للتلميذ.
  Future<String> _uniqueQr() async {
    for (var i = 0; i < 10; i++) {
      final code = QrCodes.generate(QrOwnerKind.student);
      final clash = await (db.select(
        db.students,
      )..where((s) => s.qrCode.equals(code))).get();
      if (clash.isEmpty) return code;
    }
    throw StateError('تعذّر توليد رمز QR فريد');
  }
}
