import 'package:drift/drift.dart';

import '../data/local/app_database.dart';
import '../data/local/sync_writer.dart';
import 'catalog_service.dart';
import 'date_key.dart';
import 'phone.dart';

/// رقم تلميذ مسجَّل، للعرض في دليل الهواتف (للقراءة فقط: يُعدَّل من ملف التلميذ).
class StudentPhone {
  const StudentPhone({
    required this.studentId,
    required this.name,
    required this.phone,
  });

  final String studentId;
  final String name;
  final String phone;
}

/// دليل الهواتف: خانة منفصلة تماماً عن التلاميذ، تسجَّل فيها أرقام هواتف من لا يوجدون عندنا (تلاميذ
/// لحصة واحدة، أو أسماء تركوا أرقامهم ليُتَّصل بهم بعد مدة)، بملاحظة وتاريخ تواصل اختياريين.
class ContactService {
  ContactService(this.db, this.writer);

  final AppDatabase db;
  final SyncWriter writer;

  static const String fieldName = 'name';
  static const String fieldPhone = 'phone';
  static const String fieldFollowUp = 'follow_up';

  /// أصل السجل.
  static const String sourceManual = 'manual';
  static const String sourceOneTime = 'one_time';

  static final RegExp _digits = RegExp(r'^\+?\d{8,15}$');

  /// الأرقام المسجَّلة الحية، مرتبة بالاسم ثم الرقم، وتتحدث لحظياً. [query] يطابق الاسم أو الرقم
  /// أو الملاحظة.
  Stream<List<ContactRow>> watchAll({String query = ''}) {
    final text = query.trim();
    final select = db.select(db.contacts)
      ..where((c) {
        final alive = c.deletedAt.isNull();
        if (text.isEmpty) return alive;
        final like = '%$text%';
        return alive &
            (c.name.like(like) | c.phone.like(like) | c.note.like(like));
      })
      ..orderBy([
        (c) => OrderingTerm.asc(c.name),
        (c) => OrderingTerm.asc(c.id),
      ]);
    return select.watch();
  }

  /// أرقام التلاميذ المسجَّلين (أولياؤهم) مطابقة للبحث، مرتبة بالاسم، وتتحدث لحظياً. تُستثنى أرقام
  /// تلاميذ لمرة واحدة (لهم دليل الأرقام) وما لا رقم له.
  Stream<List<StudentPhone>> watchStudentPhones({
    String query = '',
    int limit = 200,
  }) {
    final text = query.trim();
    return db
        .customSelect(
          "SELECT s.id, s.first_name || ' ' || s.last_name AS name, "
          's.parent_phone AS phone FROM students s '
          "WHERE s.deleted_at IS NULL AND s.single_use = 0 AND s.parent_phone <> '' "
          "${text.isEmpty ? '' : "AND (s.first_name || ' ' || s.last_name LIKE ? OR s.parent_phone LIKE ?) "}"
          'ORDER BY s.last_name, s.first_name, s.id LIMIT ?',
          variables: [
            if (text.isNotEmpty) ...[
              Variable<String>('%$text%'),
              Variable<String>('%$text%'),
            ],
            Variable<int>(limit),
          ],
          readsFrom: {db.students},
        )
        .watch()
        .map(
          (rows) => [
            for (final row in rows)
              StudentPhone(
                studentId: row.read<String>('id'),
                name: row.read<String>('name').trim(),
                phone: row.read<String>('phone'),
              ),
          ],
        );
  }

  /// أخطاء الرقم والتاريخ: اسم الحقل ← الرسالة. فارغة إن كانت سليمة.
  static Map<String, String> validate({
    required String phone,
    String? followUpDate,
  }) {
    final errors = <String, String>{};
    final text = phone.trim();
    if (text.isEmpty) {
      errors[fieldPhone] = 'أدخل رقم الهاتف';
    } else if (!PhoneNumbers.isValid(text) &&
        !_digits.hasMatch(text.replaceAll(RegExp(r'[\s().-]'), ''))) {
      errors[fieldPhone] = 'رقم الهاتف غير صحيح (أرقام فقط، من 8 إلى 15 رقماً)';
    }
    if (followUpDate != null && followUpDate.isNotEmpty) {
      try {
        // «2026-13-45» يُقرأ تاريخاً منزاحاً؛ الصالح ما عاد بصيغته نفسها.
        if (DateKey.of(DateKey.parse(followUpDate)) != followUpDate) {
          throw const FormatException('تاريخ منزاح');
        }
      } on FormatException {
        errors[fieldFollowUp] = 'تاريخ التواصل غير صالح';
      }
    }
    return errors;
  }

  /// يوحّد الرقم: الجوال الجزائري بصيغته المحلية، وغيره أرقاماً بلا فواصل.
  static String normalizePhone(String phone) {
    final text = phone.trim();
    if (PhoneNumbers.isValid(text)) return PhoneNumbers.normalize(text);
    return text.replaceAll(RegExp(r'[\s().-]'), '');
  }

  /// يسجّل رقماً. يرمي [ValidationException] إن كان الرقم أو التاريخ غير صالح.
  Future<ContactRow> add({
    String name = '',
    required String phone,
    String note = '',
    String? followUpDate,
    String source = sourceManual,
  }) async {
    final errors = validate(phone: phone, followUpDate: followUpDate);
    if (errors.isNotEmpty) throw ValidationException(errors);
    final id = writer.newId();
    await writer.save(
      db.contacts,
      ContactsCompanion.insert(
        id: id,
        createdAt: 0,
        updatedAt: 0,
        name: Value(name.trim()),
        phone: normalizePhone(phone),
        note: Value(note.trim()),
        followUpDate: Value(
          followUpDate == null || followUpDate.isEmpty ? null : followUpDate,
        ),
        source: Value(source),
      ),
      key: {'id': id},
    );
    return (db.select(db.contacts)..where((c) => c.id.equals(id))).getSingle();
  }

  /// يسجّل الرقم إن لم يكن مسجَّلاً بالاسم نفسه (لتلميذ لمرة واحدة ترك رقمه). يعيد `null` إن وُجد.
  Future<ContactRow?> addIfMissing({
    required String name,
    required String phone,
    String note = '',
    String source = sourceOneTime,
  }) async {
    final normalized = normalizePhone(phone);
    final existing =
        await (db.select(db.contacts)..where(
              (c) =>
                  c.phone.equals(normalized) &
                  c.name.equals(name.trim()) &
                  c.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    if (existing != null) return null;
    return add(name: name, phone: phone, note: note, source: source);
  }

  /// يعدّل سجلاً. يعيد `false` إن لم يوجد.
  Future<bool> update(
    String id, {
    String name = '',
    required String phone,
    String note = '',
    String? followUpDate,
  }) async {
    final errors = validate(phone: phone, followUpDate: followUpDate);
    if (errors.isNotEmpty) throw ValidationException(errors);
    return writer.patch(
      db.contacts,
      key: {'id': id},
      values: {
        'name': name.trim(),
        'phone': normalizePhone(phone),
        'note': note.trim(),
        'follow_up_date': followUpDate == null || followUpDate.isEmpty
            ? null
            : followUpDate,
      },
    );
  }

  /// حذف ناعم.
  Future<bool> remove(String id) =>
      writer.softDelete(db.contacts, key: {'id': id});
}
