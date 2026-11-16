-- ديون صاحب المدرسة لأساتذته وعماله (السائق عامل) وتسديدها.
--
-- المخطط نفسه مولَّد في 0001_schema.sql للخوادم الجديدة؛ هذا الملف للخوادم
-- المنشورة قبل هذا الجدول (يُطبَّق مرة واحدة هناك). كله آمن عند التكرار.
create table if not exists public."staff_debts" (
  "id" text not null,
  "created_at" bigint not null,
  "updated_at" bigint not null,
  "deleted_at" bigint,
  "staff_type" text not null,
  "staff_id" text not null,
  "kind" text not null,
  "amount" bigint not null,
  "date" text not null,
  "note" text not null,
  "created_by" text not null,
  "expense_id" text,
  "synced_at" bigint not null default 0,
  primary key ("id")
);
create index if not exists "idx_staff_debts_date" on public."staff_debts" (date);
create index if not exists "idx_staff_debts_staff" on public."staff_debts" (staff_type, staff_id);
create index if not exists "idx_staff_debts_updated" on public."staff_debts" (updated_at);
create index if not exists "idx_staff_debts_synced" on public."staff_debts" (synced_at);
drop trigger if exists trg_sync_stamp on public."staff_debts";
create trigger trg_sync_stamp before insert or update on public."staff_debts"
  for each row execute function public.sync_stamp();

-- دفتر مالي لصاحب المدرسة وحده: لا يراه العمال ولا الأساتذة ولا الأولياء.
select app.set_rules(
  'staff_debts',
  'app.is_owner()',
  'app.is_owner()',
  'app.is_owner()'
);

revoke all on public."staff_debts" from anon;
grant select, insert, update on public."staff_debts" to authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
        where pubname = 'supabase_realtime' and schemaname = 'public'
          and tablename = 'staff_debts') then
    alter publication supabase_realtime add table public."staff_debts";
  end if;
end
$$;
