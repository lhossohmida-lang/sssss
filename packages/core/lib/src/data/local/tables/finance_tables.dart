import 'package:drift/drift.dart';

import 'people_tables.dart';
import 'sync_columns.dart';
import 'teaching_tables.dart';

/// مدفوعات التلاميذ. كل دفعة لها وصل برقم تسلسلي.
@DataClassName('PaymentRow')
@TableIndex(name: 'idx_payments_student', columns: {#studentId, #type})
@TableIndex(name: 'idx_payments_group_cycle', columns: {#groupId, #cycleNumber})
@TableIndex(name: 'idx_payments_created', columns: {#createdAt})
@TableIndex(
  name: 'idx_payments_receipt',
  columns: {#receiptNumber},
  unique: true,
)
@TableIndex(name: 'idx_payments_updated', columns: {#updatedAt})
class Payments extends Table with SyncColumns {
  TextColumn get studentId => text().references(Students, #id)();

  /// `month` / `transport` / `registration`.
  TextColumn get type => text()();

  /// المجموعة عند دفع «شهر»؛ فارغ لغيره.
  TextColumn get groupId => text().nullable().references(Groups, #id)();

  /// رقم الدورة عند دفع «شهر».
  IntColumn get cycleNumber => integer().nullable()();

  /// مفتاح الفترة لغير «شهر»: `YYYY-MM` للنقل، ومفتاح السنة أو الفصل
  /// لحقوق التسجيل.
  TextColumn get periodKey => text().nullable()();

  /// المبلغ بالدينار.
  IntColumn get amount => integer()();

  /// معرّف من استلم المال.
  TextColumn get receivedBy => text()();

  /// رقم الوصل: بادئة الجهاز ثم رقم تسلسلي، مثل `A-000123`.
  TextColumn get receiptNumber => text()();

  TextColumn get note => text().withDefault(const Constant(''))();
}

/// أرصدة التلاميذ: مبلغ يُخصم من دورة قادمة (غياب برخصة أو التحاق في المنتصف).
@DataClassName('StudentCreditRow')
@TableIndex(
  name: 'idx_student_credits_target',
  columns: {#studentId, #groupId, #targetCycleNumber},
)
@TableIndex(
  name: 'idx_student_credits_source',
  columns: {#groupId, #sourceCycleNumber},
)
@TableIndex(name: 'idx_student_credits_updated', columns: {#updatedAt})
class StudentCredits extends Table with SyncColumns {
  TextColumn get studentId => text().references(Students, #id)();

  TextColumn get groupId => text().references(Groups, #id)();

  /// المبلغ بالدينار (موجب).
  IntColumn get amount => integer()();

  /// `excused` غياب برخصة / `mid_join` التحاق في المنتصف / `manual` يدوي.
  TextColumn get reason => text()();

  /// الدورة التي نشأ فيها الرصيد.
  IntColumn get sourceCycleNumber => integer()();

  /// الدورة التي يُخصم منها الرصيد.
  IntColumn get targetCycleNumber => integer()();

  /// الحصة المعنية عند الغياب برخصة (لمنع احتساب الرصيد مرتين).
  TextColumn get sessionId => text().nullable().references(Sessions, #id)();
}

/// حقوق التسجيل: مرة واحدة لكل تلميذ في الفترة (سنة أو فصل).
@DataClassName('RegistrationFeeRow')
@TableIndex(
  name: 'idx_registration_fees_period',
  columns: {#studentId, #periodKey},
  unique: true,
)
@TableIndex(name: 'idx_registration_fees_paid', columns: {#periodKey, #paid})
@TableIndex(name: 'idx_registration_fees_updated', columns: {#updatedAt})
class RegistrationFees extends Table with SyncColumns {
  TextColumn get studentId => text().references(Students, #id)();

  /// مفتاح الفترة، مثل `2026-2027` أو `2026-2027/1`.
  TextColumn get periodKey => text()();

  IntColumn get amount => integer()();

  BoolColumn get paid => boolean().withDefault(const Constant(false))();
}

/// خلاص الأساتذة لكل (مجموعة + دورة)، مع التفصيل لكل تلميذ.
@DataClassName('TeacherPayoutRow')
@TableIndex(name: 'idx_teacher_payouts_teacher', columns: {#teacherId, #paidAt})
@TableIndex(
  name: 'idx_teacher_payouts_group_cycle',
  columns: {#groupId, #cycleNumber},
)
@TableIndex(name: 'idx_teacher_payouts_updated', columns: {#updatedAt})
class TeacherPayouts extends Table with SyncColumns {
  TextColumn get teacherId => text().references(Teachers, #id)();

  TextColumn get groupId => text().references(Groups, #id)();

  IntColumn get cycleNumber => integer()();

  /// `cycle` خلاص اكتمال الدورة / `release` نصيب معلّق أُفرج عنه بعد تسديد.
  TextColumn get kind => text().withDefault(const Constant('cycle'))();

  IntColumn get amount => integer()();

  /// التفصيل لكل تلميذ بصيغة JSON.
  TextColumn get details => text().withDefault(const Constant('[]'))();

  /// وقت تسليم المال للأستاذ؛ `null` يعني لم يُسلَّم بعد.
  IntColumn get paidAt => integer().nullable()();

  TextColumn get paidBy => text().nullable()();
}

/// أنواع المصاريف.
@DataClassName('ExpenseCategoryRow')
@TableIndex(name: 'idx_expense_categories_name', columns: {#name})
@TableIndex(name: 'idx_expense_categories_updated', columns: {#updatedAt})
class ExpenseCategories extends Table with SyncColumns {
  TextColumn get name => text()();

  /// هل هذا النوع هو «أجور العمال»؟
  BoolColumn get isWages => boolean().withDefault(const Constant(false))();
}

/// المصاريف.
@DataClassName('ExpenseRow')
@TableIndex(name: 'idx_expenses_category_date', columns: {#categoryId, #date})
@TableIndex(name: 'idx_expenses_date', columns: {#date})
@TableIndex(name: 'idx_expenses_updated', columns: {#updatedAt})
class Expenses extends Table with SyncColumns {
  TextColumn get categoryId => text().references(ExpenseCategories, #id)();

  IntColumn get amount => integer()();

  /// التاريخ بصيغة `YYYY-MM-DD`.
  TextColumn get date => text()();

  TextColumn get note => text().withDefault(const Constant(''))();

  TextColumn get invoicePhotoUrl => text().nullable()();

  TextColumn get invoicePhotoLocalPath => text().nullable()();

  /// العامل المعني عند تسجيل أجر.
  TextColumn get workerId => text().nullable().references(Workers, #id)();

  TextColumn get createdBy => text()();
}
