import 'package:flutter_test/flutter_test.dart';
import 'package:school_assistant/school_assistant.dart';

ReadOnlySql guard() => ReadOnlySql(
  allowedTables: {'students', 'groups', 'payments'},
  knownTables: {
    'students',
    'groups',
    'payments',
    'user_accounts',
    'outbox',
    'local_credentials',
  },
  hiddenColumns: AssistantSchema.hiddenColumns,
);

Matcher rejects([String? containing]) => throwsA(
  isA<ArgumentError>().having(
    (e) => '${e.message}',
    'message',
    containing == null ? isNotEmpty : contains(containing),
  ),
);

void main() {
  group('استعلامات مقبولة', () {
    test('SELECT بسيط يُغلَّف بسقف للصفوف', () {
      final sql = guard().prepare(
        'SELECT COUNT(*) AS n FROM students WHERE deleted_at IS NULL',
      );
      expect(
        sql,
        'SELECT * FROM (SELECT COUNT(*) AS n FROM students WHERE deleted_at IS NULL) '
        'LIMIT ${ReadOnlySql.maxRows + 1}',
      );
    });

    test('فاصلة منقوطة أخيرة وحيدة، وCTE، وربط بين جدولين مسموحين', () {
      expect(guard().prepare('select 1;'), contains('select 1'));
      expect(
        guard().prepare(
          'WITH x AS (SELECT group_id FROM payments) '
          'SELECT g.number FROM groups g JOIN x ON x.group_id = g.id',
        ),
        startsWith('SELECT * FROM (WITH x AS'),
      );
    });

    test('أسماء أعمدة تشبه كلمات ممنوعة ليست ممنوعة: created_at وdeleted_at وupdated_at', () {
      expect(
        guard().prepare(
          'SELECT created_at, updated_at, deleted_at FROM students',
        ),
        isNotEmpty,
      );
    });

    test('ما داخل النصوص لا يُفحص، ودالة replace مسموحة', () {
      expect(
        guard().prepare(
          "SELECT replace(first_name, 'a', 'b'), 'drop table x; --' AS note "
          'FROM students',
        ),
        isNotEmpty,
      );
    });

    test('اقتباس اسم جدول مسموح', () {
      expect(guard().prepare('SELECT * FROM "students"'), isNotEmpty);
      expect(guard().prepare('SELECT * FROM [groups]'), isNotEmpty);
    });
  });

  group('استعلامات مرفوضة', () {
    test('فارغ أو طويل جداً', () {
      expect(() => guard().prepare('   '), rejects('SELECT'));
      expect(
        () => guard().prepare('SELECT ${'a' * ReadOnlySql.maxLength}'),
        rejects('أطول'),
      );
    });

    test('كل ما ليس SELECT أو WITH', () {
      for (final sql in [
        'DELETE FROM students',
        'UPDATE students SET first_name = 1',
        'INSERT INTO students VALUES (1)',
        'DROP TABLE students',
        'CREATE TABLE x (a)',
        'ALTER TABLE students ADD b',
        'PRAGMA table_info(students)',
        'ATTACH DATABASE x AS y',
        'VACUUM',
        'REPLACE INTO students VALUES (1)',
      ]) {
        expect(() => guard().prepare(sql), rejects(), reason: sql);
      }
    });

    test('DML مخبّأ داخل WITH أو بعد SELECT', () {
      expect(
        () => guard().prepare(
          'WITH x AS (SELECT 1) UPDATE students SET first_name = 2',
        ),
        rejects('update'),
      );
      expect(
        () => guard().prepare('WITH x AS (SELECT 1) DELETE FROM students'),
        rejects('delete'),
      );
      expect(
        () => guard().prepare('SELECT 1 UNION SELECT 2 RETURNING a'),
        rejects('returning'),
      );
    });

    test('استعلامات متعددة وتعليقات', () {
      expect(
        () => guard().prepare('SELECT 1; DELETE FROM students'),
        rejects('استعلام واحد'),
      );
      expect(() => guard().prepare('SELECT 1 -- x'), rejects('تعليقات'));
      expect(() => guard().prepare('SELECT 1 /* x */'), rejects('تعليقات'));
    });

    test('جداول غير مسموحة بكل صيغ الإشارة إليها', () {
      for (final sql in [
        'SELECT * FROM user_accounts',
        'SELECT * FROM students s JOIN outbox o ON 1 = 1',
        'SELECT * FROM (SELECT * FROM local_credentials)',
        'SELECT * FROM "user_accounts"',
        'SELECT * FROM [user_accounts]',
        'SELECT * FROM `outbox`',
        'WITH u AS (SELECT * FROM user_accounts) SELECT * FROM u',
        'SELECT (SELECT COUNT(*) FROM outbox) AS n',
        'SELECT * FROM students, user_accounts',
      ]) {
        expect(() => guard().prepare(sql), rejects('غير متاح'), reason: sql);
      }
    });

    test('جدول معروف غير مسموح لحساب هذا العامل', () {
      final limited = ReadOnlySql(
        allowedTables: {'students'},
        knownTables: {'students', 'payments'},
      );
      expect(
        () => limited.prepare('SELECT SUM(amount) FROM payments'),
        rejects('«payments»'),
      );
    });

    test('أعمدة محجوبة', () {
      expect(
        () => guard().prepare('SELECT qr_code FROM students'),
        rejects('محجوب'),
      );
      expect(
        () => guard().prepare('SELECT photo_url, auth_user_id FROM students'),
        rejects('محجوب'),
      );
    });

    test('جداول النظام ودوال الموارد والتكرار', () {
      for (final sql in [
        'SELECT * FROM sqlite_master',
        'SELECT * FROM pragma_table_info(1)',
        'SELECT zeroblob(1000000000)',
        'SELECT randomblob(10)',
        'WITH RECURSIVE r(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM r) SELECT * FROM r',
        'SELECT load_extension(1)',
      ]) {
        expect(() => guard().prepare(sql), rejects(), reason: sql);
      }
    });

    test('اقتباس غير مغلق', () {
      expect(() => guard().prepare("SELECT 'abc"), rejects('اقتباس'));
      expect(() => guard().prepare('SELECT "abc'), rejects('اقتباس'));
    });
  });
}
