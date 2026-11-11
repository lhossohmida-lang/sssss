-- اختبارات مخطط الخادم. أي فشل يرمي استثناء ويوقف التنفيذ.

do $$
declare
  n int;
  r record;
begin
  -- كل الجداول المزامَنة موجودة.
  select count(*) into n from information_schema.tables
   where table_schema = 'public' and table_type = 'BASE TABLE';
  if n <> 36 then
    raise exception 'عدد الجداول % وليس 36', n;
  end if;

  -- لكل جدول عمود المزامنة ومشغّله.
  for r in
    select table_name from information_schema.tables
     where table_schema = 'public' and table_type = 'BASE TABLE'
  loop
    if not exists (
      select 1 from information_schema.columns
       where table_schema = 'public' and table_name = r.table_name
         and column_name = 'synced_at') then
      raise exception 'الجدول % بلا synced_at', r.table_name;
    end if;
    if not exists (
      select 1 from pg_trigger t join pg_class c on c.oid = t.tgrelid
       where c.relname = r.table_name and t.tgname = 'trg_sync_stamp') then
      raise exception 'الجدول % بلا مشغّل المزامنة', r.table_name;
    end if;
  end loop;
end
$$;

-- «آخر تعديل يفوز» ورقم المزامنة المتزايد.
do $$
declare
  first_seq bigint;
  second_seq bigint;
  current_name text;
begin
  insert into public.rooms (id, created_at, updated_at, name, capacity)
  values ('test-room', 1, 100, 'الأصل', 5);
  select synced_at into first_seq from public.rooms where id = 'test-room';
  if first_seq <= 0 then
    raise exception 'synced_at لم يُختم عند الإضافة';
  end if;

  -- تحديث أقدم يُتجاهل.
  update public.rooms set name = 'قديم', updated_at = 50 where id = 'test-room';
  select name into current_name from public.rooms where id = 'test-room';
  if current_name <> 'الأصل' then
    raise exception 'تحديث أقدم غلب الأحدث';
  end if;

  -- تحديث أحدث يُقبل ويرفع رقم المزامنة.
  update public.rooms set name = 'جديد', updated_at = 200 where id = 'test-room';
  select name, synced_at into current_name, second_seq
    from public.rooms where id = 'test-room';
  if current_name <> 'جديد' or second_seq <= first_seq then
    raise exception 'تحديث أحدث لم يُطبَّق كما يجب';
  end if;

  -- الإدراج مع التعارض (كما ترسله الأجهزة) يحترم نفس القاعدة.
  insert into public.rooms (id, created_at, updated_at, name, capacity)
  values ('test-room', 1, 150, 'من جهاز متأخر', 5)
  on conflict (id) do update set
    name = excluded.name, updated_at = excluded.updated_at;
  select name into current_name from public.rooms where id = 'test-room';
  if current_name <> 'جديد' then
    raise exception 'upsert أقدم غلب الأحدث';
  end if;

  delete from public.rooms where id = 'test-room';
end
$$;

-- الفهارس الفريدة تمنع التكرار على الخادم أيضاً.
do $$
begin
  insert into public.attendance
    (id, created_at, updated_at, session_id, student_id, status, method)
  values ('a1', 1, 1, 'se', 'st', 'present', 'qr');
  begin
    insert into public.attendance
      (id, created_at, updated_at, session_id, student_id, status, method)
    values ('a2', 1, 1, 'se', 'st', 'present', 'qr');
    raise exception 'حضور مكرر قُبل';
  exception when unique_violation then
    null;
  end;
  delete from public.attendance where id = 'a1';
end
$$;
