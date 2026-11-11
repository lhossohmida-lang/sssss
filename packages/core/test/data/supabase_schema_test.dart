import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/src/data/remote/synced_tables.dart';

import '../support/supabase_schema.dart';

void main() {
  late AppDatabase db;
  final file = File('../../supabase/migrations/0001_schema.sql');

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('مخطط الخادم مطابق لمخطط القاعدة المحلية', () async {
    final generated = await generateSupabaseSchema(db);
    if (Platform.environment['UPDATE_SCHEMA'] == '1') {
      file.writeAsStringSync(generated);
    }
    expect(
      file.readAsStringSync(),
      generated,
      reason:
          'تغيّر المخطط المحلي. أعد التوليد: '
          'UPDATE_SCHEMA=1 flutter test test/data/supabase_schema_test.dart',
    );
  });

  test('كل الجداول المزامَنة موجودة في مخطط الخادم دون الجداول المحلية', () {
    final sql = file.readAsStringSync();
    for (final table in db.allTables) {
      final name = table.actualTableName;
      final present = sql.contains('create table if not exists public."$name"');
      expect(present, !localOnlyTables.contains(name), reason: name);
    }
  });

  test('لكل جدول: عمود المزامنة وفهرسه ومشغّل «آخر تعديل يفوز»', () {
    final sql = file.readAsStringSync();
    final tables = RegExp(r'create table if not exists public\."(\w+)"')
        .allMatches(sql)
        .map((m) => m.group(1)!)
        .toList();
    expect(tables, hasLength(db.allTables.length - localOnlyTables.length));
    for (final name in tables) {
      expect(sql, contains('"idx_${name}_synced" on public."$name"'));
      expect(
        sql,
        contains(
          'create trigger trg_sync_stamp before insert or update '
          'on public."$name"',
        ),
      );
    }
    expect(
      RegExp('"synced_at" bigint not null default 0').allMatches(sql),
      hasLength(tables.length),
    );
  });

  test('الفهارس الفريدة محفوظة على الخادم', () {
    final sql = file.readAsStringSync();
    expect(
      sql,
      contains(
        'create unique index if not exists "idx_students_qr" '
        'on public."students" (qr_code);',
      ),
    );
    expect(
      sql,
      contains(
        'create unique index if not exists "idx_attendance_pair" '
        'on public."attendance" (session_id, student_id);',
      ),
    );
  });
}
