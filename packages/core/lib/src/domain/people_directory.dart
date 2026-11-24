import 'package:drift/drift.dart';

import '../data/local/app_database.dart';
import 'enums.dart';

/// من يُحدَّد في قوائم العمليات الجماعية.
enum PersonKind {
  student,
  teacher,
  worker;

  /// الاسم بالعربية للجمع في العناوين.
  String get plural => switch (this) {
    PersonKind.student => 'التلاميذ',
    PersonKind.teacher => 'الأساتذة',
    PersonKind.worker => 'العمال',
  };
}

/// شخص في قائمة التحديد الجماعي (طباعة البطاقات وإرسال بيانات الدخول والرسائل).
class BulkPerson {
  const BulkPerson({
    required this.kind,
    required this.id,
    required this.name,
    required this.phone,
    required this.qrCode,
    this.subtitle,
    this.levelId,
    this.photoLocalPath,
    this.accountId,
  });

  final PersonKind kind;
  final String id;
  final String name;

  /// هاتف الوليّ للتلميذ، وهاتف الأستاذ أو العامل.
  final String phone;
  final String qrCode;

  /// السنة الدراسية للتلميذ، ومواد الأستاذ، و«عامل».
  final String? subtitle;

  /// سنة التلميذ للتصفية؛ `null` لغيره أو بلا سنة.
  final String? levelId;
  final String? photoLocalPath;

  /// حساب الدخول: حساب الوليّ للتلميذ (يشترك فيه الإخوة)، وحساب الأستاذ أو العامل.
  final String? accountId;
}

/// قوائم التلاميذ والأساتذة والعمال كاملة للتحديد الجماعي، مرتبة بالاسم، وتتحدث لحظياً.
class PeopleDirectory {
  PeopleDirectory(this.db);

  final AppDatabase db;

  Stream<List<BulkPerson>> watch(PersonKind kind) => switch (kind) {
    PersonKind.student => _students(),
    PersonKind.teacher => _teachers(),
    PersonKind.worker => _workers(),
  };

  Stream<List<BulkPerson>> _students() => db
      .customSelect(
        "SELECT s.id, s.first_name || ' ' || s.last_name AS name, "
        's.parent_phone AS phone, s.qr_code, s.level_id, l.name AS level_name, '
        's.photo_local_path, '
        '(SELECT a.id FROM parents p JOIN user_accounts a ON a.email = p.email '
        'AND a.deleted_at IS NULL WHERE p.id = s.parent_account_id LIMIT 1) '
        'AS account_id '
        'FROM students s LEFT JOIN levels l ON l.id = s.level_id '
        'WHERE s.deleted_at IS NULL AND s.single_use = 0 '
        'ORDER BY s.last_name, s.first_name, s.id',
        readsFrom: {db.students, db.levels, db.parents, db.userAccounts},
      )
      .watch()
      .map(
        (rows) => [
          for (final row in rows)
            BulkPerson(
              kind: PersonKind.student,
              id: row.read<String>('id'),
              name: row.read<String>('name').trim(),
              phone: row.read<String>('phone'),
              qrCode: row.read<String>('qr_code'),
              subtitle: row.read<String?>('level_name'),
              levelId: row.read<String?>('level_id'),
              photoLocalPath: row.read<String?>('photo_local_path'),
              accountId: row.read<String?>('account_id'),
            ),
        ],
      );

  Stream<List<BulkPerson>> _teachers() => db
      .customSelect(
        'SELECT t.id, t.name, t.phone, t.qr_code, t.photo_local_path, '
        '(SELECT group_concat(name, \'، \') FROM (SELECT sub.name FROM teacher_subjects ts '
        'JOIN subjects sub ON sub.id = ts.subject_id AND sub.deleted_at IS NULL '
        'WHERE ts.teacher_id = t.id ORDER BY sub.name)) AS subjects, '
        '(SELECT a.id FROM user_accounts a WHERE a.entity_id = t.id '
        'AND a.role = ? AND a.deleted_at IS NULL LIMIT 1) AS account_id '
        'FROM teachers t WHERE t.deleted_at IS NULL ORDER BY t.name, t.id',
        variables: [Variable<String>(UserRole.teacher.code)],
        readsFrom: {
          db.teachers,
          db.teacherSubjects,
          db.subjects,
          db.userAccounts,
        },
      )
      .watch()
      .map(
        (rows) => [
          for (final row in rows)
            BulkPerson(
              kind: PersonKind.teacher,
              id: row.read<String>('id'),
              name: row.read<String>('name'),
              phone: row.read<String>('phone'),
              qrCode: row.read<String>('qr_code'),
              subtitle: switch (row.read<String?>('subjects')) {
                final subjects? when subjects.isNotEmpty => 'أستاذ · $subjects',
                _ => 'أستاذ',
              },
              photoLocalPath: row.read<String?>('photo_local_path'),
              accountId: row.read<String?>('account_id'),
            ),
        ],
      );

  Stream<List<BulkPerson>> _workers() => db
      .customSelect(
        'SELECT w.id, w.name, w.phone, w.qr_code, '
        '(SELECT a.id FROM user_accounts a WHERE a.entity_id = w.id '
        'AND a.role = ? AND a.deleted_at IS NULL LIMIT 1) AS account_id '
        'FROM workers w WHERE w.deleted_at IS NULL ORDER BY w.name, w.id',
        variables: [Variable<String>(UserRole.worker.code)],
        readsFrom: {db.workers, db.userAccounts},
      )
      .watch()
      .map(
        (rows) => [
          for (final row in rows)
            BulkPerson(
              kind: PersonKind.worker,
              id: row.read<String>('id'),
              name: row.read<String>('name'),
              phone: row.read<String>('phone'),
              qrCode: row.read<String>('qr_code'),
              subtitle: 'عامل',
              accountId: row.read<String?>('account_id'),
            ),
        ],
      );
}
