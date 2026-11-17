-- دليل المدارس: مشروع Supabase واحد للمطوّر لا يحمل بيانات أي مدرسة. تعرف منه التطبيقات العامة
-- أي خادم تتصل به:
--  * الأستاذ والتلميذ: قائمة المدارس المُعلنة (list_schools) فيختار المستخدم مدرسته.
--  * الإدارة: من رقم هاتف المالك أو العامل (resolve_school) فلا يلصق أحد رمز ربط.
-- لا يُكشف أي جدول للمستخدمين: الوصول عبر الدوال أدناه فقط. كله آمن عند التكرار.
create schema if not exists app;

-- المدارس. المفتاح العام مصمَّم ليُضمَّن في التطبيقات (لا سرّية فيه)؛ ويُرفض السرّي (sb_secret_).
create table if not exists public.schools (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique check (slug ~ '^[a-z0-9][a-z0-9-]{0,38}[a-z0-9]$'),
  name text not null check (char_length(btrim(name)) between 2 and 80),
  url text not null unique check (url ~ '^https://[a-z0-9]{20}\.supabase\.co$'),
  publishable_key text not null check (
    char_length(publishable_key) between 20 and 600
    and publishable_key !~ '^sb_secret_'
    and publishable_key !~ '\s'
  ),
  -- هل تظهر في قائمة المدارس لتطبيقي الأستاذ والتلميذ؟
  listed boolean not null default true,
  -- بصمة مفتاح التسجيل الخاص بالمدرسة (المفتاح نفسه سرّ في دوال خادمها فقط).
  register_key_hash text,
  created_at timestamptz not null default now()
);

-- أرقام هواتف طاقم المدرسة (المالك والعمال) مبصومة بملح سرّي: لا يُخزَّن رقم صريح.
create table if not exists public.staff_phones (
  phone_hash text not null,
  school_id uuid not null references public.schools (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (phone_hash, school_id)
);
create index if not exists staff_phones_school_idx on public.staff_phones (school_id);

-- الملح السرّي للبصمات (صف واحد، يُولَّد مرة عند أول تطبيق ولا يخرج من القاعدة).
create table if not exists app.directory_pepper (
  id boolean primary key default true check (id),
  pepper text not null
);
insert into app.directory_pepper (id, pepper)
select true, replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '')
where not exists (select 1 from app.directory_pepper);

-- عدّاد محاولات البحث لكل عنوان IP في نافذة 10 دقائق (لمنع تعداد الأرقام).
create table if not exists app.lookup_attempts (
  who text not null,
  bucket bigint not null,
  attempts int not null default 0,
  primary key (who, bucket)
);

alter table public.schools enable row level security;
alter table public.staff_phones enable row level security;
alter table app.directory_pepper enable row level security;
alter table app.lookup_attempts enable row level security;
revoke all on public.schools from public, anon, authenticated;
revoke all on public.staff_phones from public, anon, authenticated;
revoke all on app.directory_pepper from public, anon, authenticated;
revoke all on app.lookup_attempts from public, anon, authenticated;

-- بصمة رقم هاتف جزائري (05/06/07 + 8 أرقام، بصيغة محلية أو دولية)، أو null إن لم يصلح.
create or replace function app.phone_key(p_phone text) returns text
language plpgsql stable security definer set search_path = '' as $$
declare
  digits text;
  salt text;
begin
  digits := regexp_replace(coalesce(p_phone, ''), '[\s\-.()]', '', 'g');
  if digits like '+213%' then
    digits := '0' || substr(digits, 5);
  elsif digits like '00213%' then
    digits := '0' || substr(digits, 6);
  end if;
  if digits !~ '^0[567][0-9]{8}$' then
    return null;
  end if;
  select d.pepper into salt from app.directory_pepper d where d.id;
  return encode(sha256(convert_to(salt || ':' || digits, 'UTF8')), 'hex');
end $$;

-- عنوان العميل كما يمرّره PostgREST (دون PostgREST، كما في الاختبارات، يكون null).
create or replace function app.client_key() returns text
language plpgsql stable as $$
declare
  headers jsonb;
  addr text;
begin
  begin
    headers := nullif(current_setting('request.headers', true), '')::jsonb;
  exception when others then
    headers := null;
  end;
  addr := coalesce(
    headers ->> 'cf-connecting-ip',
    split_part(coalesce(headers ->> 'x-forwarded-for', ''), ',', 1)
  );
  return nullif(btrim(coalesce(addr, '')), '');
end $$;

-- يرفض الطلب بعد [p_limit] محاولة لنفس العنوان في نافذة 10 دقائق.
create or replace function app.throttle(p_limit int) returns void
language plpgsql security definer set search_path = '' as $$
declare
  client text := app.client_key();
  slot bigint := floor(extract(epoch from now()) / 600);
  used int;
begin
  if client is null then
    return;
  end if;
  delete from app.lookup_attempts t where t.bucket < slot - 1;
  insert into app.lookup_attempts as a (who, bucket, attempts)
  values (client, slot, 1)
  on conflict (who, bucket) do update set attempts = a.attempts + 1
  returning a.attempts into used;
  if used > p_limit then
    raise exception 'rate_limited';
  end if;
end $$;

-- قائمة المدارس المُعلنة (تطبيقا الأستاذ والتلميذ).
create or replace function public.list_schools()
returns table (id uuid, name text, url text, publishable_key text)
language sql stable security definer set search_path = '' as $$
  select s.id, s.name, s.url, s.publishable_key
  from public.schools s
  where s.listed
  order by s.name
$$;

-- المدارس التي لطاقمها هذا الرقم (حتى خمس)، لتطبيق الإدارة.
create or replace function public.resolve_school(p_phone text)
returns table (id uuid, name text, url text, publishable_key text)
language plpgsql security definer set search_path = '' as $$
declare
  hashed text := app.phone_key(p_phone);
begin
  perform app.throttle(60);
  if hashed is null then
    return;
  end if;
  return query
    select s.id, s.name, s.url, s.publishable_key
    from public.staff_phones p
    join public.schools s on s.id = p.school_id
    where p.phone_hash = hashed
    order by s.name
    limit 5;
end $$;

-- تسجيل مدرسة (أو تحديثها) مع رقم مالكها: يستدعيها مسار النشر بالمفتاح السرّي وحده.
create or replace function public.register_school(
  p_slug text,
  p_name text,
  p_url text,
  p_key text,
  p_listed boolean,
  p_register_key text,
  p_owner_phone text
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  school uuid;
  hashed text := app.phone_key(p_owner_phone);
begin
  if length(coalesce(p_register_key, '')) < 32 then
    raise exception 'مفتاح التسجيل قصير';
  end if;
  insert into public.schools as s (slug, name, url, publishable_key, listed, register_key_hash)
  values (
    p_slug,
    btrim(p_name),
    p_url,
    p_key,
    coalesce(p_listed, true),
    encode(sha256(convert_to(p_register_key, 'UTF8')), 'hex')
  )
  on conflict (slug) do update set
    name = excluded.name,
    url = excluded.url,
    publishable_key = excluded.publishable_key,
    listed = excluded.listed,
    register_key_hash = excluded.register_key_hash
  returning s.id into school;
  if hashed is not null then
    insert into public.staff_phones (phone_hash, school_id)
    values (hashed, school)
    on conflict do nothing;
  end if;
  return school;
end $$;

-- تسجيل رقم عامل جديد: تستدعيها دالة provision-account في خادم المدرسة بمفتاح تسجيلها.
create or replace function public.school_register_phone(
  p_slug text,
  p_register_key text,
  p_phone text
) returns boolean
language plpgsql security definer set search_path = '' as $$
declare
  school uuid;
  hashed text := app.phone_key(p_phone);
begin
  perform app.throttle(120);
  if hashed is null then
    return false;
  end if;
  select s.id into school
  from public.schools s
  where s.slug = p_slug
    and s.register_key_hash =
      encode(sha256(convert_to(coalesce(p_register_key, ''), 'UTF8')), 'hex');
  if school is null then
    return false;
  end if;
  insert into public.staff_phones (phone_hash, school_id)
  values (hashed, school)
  on conflict do nothing;
  return true;
end $$;

-- إزالة رقم (عند حذف حساب عامل أو تغيير رقمه).
create or replace function public.school_unregister_phone(
  p_slug text,
  p_register_key text,
  p_phone text
) returns boolean
language plpgsql security definer set search_path = '' as $$
declare
  school uuid;
  hashed text := app.phone_key(p_phone);
begin
  perform app.throttle(120);
  if hashed is null then
    return false;
  end if;
  select s.id into school
  from public.schools s
  where s.slug = p_slug
    and s.register_key_hash =
      encode(sha256(convert_to(coalesce(p_register_key, ''), 'UTF8')), 'hex');
  if school is null then
    return false;
  end if;
  delete from public.staff_phones where phone_hash = hashed and school_id = school;
  return true;
end $$;

-- الصلاحيات: القراءة والتسجيل بمفتاح المدرسة لكل من يملك المفتاح العام؛ تسجيل المدرسة نفسها لمفتاح الخادم.
revoke all on function app.phone_key(text) from public, anon, authenticated;
revoke all on function app.client_key() from public, anon, authenticated;
revoke all on function app.throttle(int) from public, anon, authenticated;
revoke all on function public.list_schools() from public, anon, authenticated;
revoke all on function public.resolve_school(text) from public, anon, authenticated;
revoke all on function public.register_school(text, text, text, text, boolean, text, text)
  from public, anon, authenticated;
revoke all on function public.school_register_phone(text, text, text) from public, anon, authenticated;
revoke all on function public.school_unregister_phone(text, text, text) from public, anon, authenticated;
grant execute on function public.list_schools() to anon, authenticated;
grant execute on function public.resolve_school(text) to anon, authenticated;
grant execute on function public.school_register_phone(text, text, text) to anon, authenticated;
grant execute on function public.school_unregister_phone(text, text, text) to anon, authenticated;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant execute on function public.register_school(text, text, text, text, boolean, text, text)
      to service_role;
    grant usage on schema app to service_role;
  end if;
end
$$;
