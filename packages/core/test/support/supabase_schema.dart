import 'package:drift/drift.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/src/data/remote/synced_tables.dart';

/// يولّد مخطط PostgreSQL (Supabase) من مخطط القاعدة المحلية، حتى يبقى
/// الخادم مطابقاً للجداول المحلية دائماً.
Future<String> generateSupabaseSchema(AppDatabase db) async {
  final out = StringBuffer()
    ..writeln('-- ملف مولَّد من مخطط القاعدة المحلية. لا تعدّله يدوياً.')
    ..writeln(
      '-- لإعادة توليده: UPDATE_SCHEMA=1 flutter test '
      'test/data/supabase_schema_test.dart',
    )
    ..writeln()
    ..writeln('create sequence if not exists public.sync_seq;')
    ..writeln()
    ..writeln('-- «آخر تعديل يفوز»: تحديث أقدم من المخزَّن يُتجاهل.')
    ..writeln('-- `synced_at` رقم متزايد يسحب به كل جهاز ما تغيّر بعد آخر سحب.')
    ..writeln('create or replace function public.sync_stamp()')
    ..writeln('returns trigger language plpgsql as \$\$')
    ..writeln('begin')
    ..writeln("  if tg_op = 'UPDATE' and new.updated_at < old.updated_at then")
    ..writeln('    return null;')
    ..writeln('  end if;')
    ..writeln("  new.synced_at := nextval('public.sync_seq');")
    ..writeln('  return new;')
    ..writeln('end')
    ..writeln('\$\$;');

  final tables =
      db.allTables
          .where((t) => !localOnlyTables.contains(t.actualTableName))
          .toList()
        ..sort((a, b) => a.actualTableName.compareTo(b.actualTableName));

  for (final table in tables) {
    final name = table.actualTableName;
    if (!table.columnsByName.containsKey('updated_at')) {
      throw StateError('الجدول $name بلا updated_at ولا يمكن مزامنته');
    }
    out
      ..writeln()
      ..writeln('create table if not exists public."$name" (');
    for (final column in table.$columns) {
      final type = switch (column.type) {
        DriftSqlType.int || DriftSqlType.bigInt => 'bigint',
        DriftSqlType.string => 'text',
        DriftSqlType.bool => 'boolean',
        DriftSqlType.double => 'double precision',
        _ => throw StateError('نوع غير مدعوم في $name.${column.name}'),
      };
      final nullable = column.$nullable ? '' : ' not null';
      out.writeln('  "${column.name}" $type$nullable,');
    }
    final key = table.$primaryKey.map((c) => '"${c.name}"').join(', ');
    out
      ..writeln('  "synced_at" bigint not null default 0,')
      ..writeln('  primary key ($key)')
      ..writeln(');');

    final indexes = await db
        .customSelect(
          "SELECT name, sql FROM sqlite_master WHERE type = 'index' "
          'AND tbl_name = ? AND sql IS NOT NULL ORDER BY name',
          variables: [Variable<String>(name)],
        )
        .get();
    for (final index in indexes) {
      final sql = index.read<String>('sql');
      final unique = sql.toUpperCase().startsWith('CREATE UNIQUE')
          ? 'unique '
          : '';
      final columns = sql.substring(sql.lastIndexOf('(')).replaceAll('"', '');
      out.writeln(
        'create ${unique}index if not exists "${index.read<String>('name')}" '
        'on public."$name" $columns;',
      );
    }
    out
      ..writeln(
        'create index if not exists "idx_${name}_synced" '
        'on public."$name" (synced_at);',
      )
      ..writeln('drop trigger if exists trg_sync_stamp on public."$name";')
      ..writeln(
        'create trigger trg_sync_stamp before insert or update '
        'on public."$name"',
      )
      ..writeln('  for each row execute function public.sync_stamp();');
  }

  out
    ..writeln()
    ..writeln('-- البث اللحظي لكل الجداول المزامَنة.')
    ..writeln('do \$\$')
    ..writeln('declare t text;')
    ..writeln('begin')
    ..writeln(
      '  if exists (select 1 from pg_publication where pubname = '
      "'supabase_realtime') then",
    )
    ..writeln('    foreach t in array array[');
  out.writeln(tables.map((t) => "      '${t.actualTableName}'").join(',\n'));
  out
    ..writeln('    ] loop')
    ..writeln('      if not exists (select 1 from pg_publication_tables')
    ..writeln(
      "        where pubname = 'supabase_realtime' "
      "and schemaname = 'public' and tablename = t) then",
    )
    ..writeln(
      "        execute format('alter publication supabase_realtime "
      "add table public.%I', t);",
    )
    ..writeln('      end if;')
    ..writeln('    end loop;')
    ..writeln('  end if;')
    ..writeln('end')
    ..writeln('\$\$;');
  return out.toString();
}
