-- إعادة تعيين المدرسة بالكامل: تُمسح كل بياناتها (التلاميذ والأفواج والحضور والمدفوعات والإعدادات
-- والرسائل والسجلات...) وحسابات كل من عدا صاحب المدرسة، ويبقى صاحبها بحسابه، وكأنها مدرسة جديدة.
-- لا يستدعيها أي مستخدم: تستدعيها دالة reset-school بالمفتاح السرّي بعد تحقق من كلمة سرّ المالك.
--
-- «دورة» المدرسة (epoch) نص يتغير عند كل إعادة تعيين. الأجهزة تقرؤه قبل أن ترسل شيئاً، فمن كانت
-- بياناته المحلية من دورة سابقة يمسحها بدل أن يعيد رفعها فتعود بيانات محذوفة إلى المدرسة.
--
-- كله آمن عند التكرار (يُطبَّق مرتين في الاختبارات).
create schema if not exists app;

create table if not exists app.school_state (
  id int primary key check (id = 1),
  epoch text not null,
  reset_at bigint,
  reset_by text
);
alter table app.school_state enable row level security;
revoke all on app.school_state from public, anon, authenticated;
insert into app.school_state (id, epoch) values (1, '') on conflict (id) do nothing;

-- دورة المدرسة الحالية: نص فارغ ما لم تُعَد المدرسة من قبل. يقرؤها كل مستخدم مسجَّل.
create or replace function public.school_epoch() returns text
language sql stable security definer set search_path = '' as $$
  select coalesce((select epoch from app.school_state where id = 1), '')
$$;
revoke all on function public.school_epoch() from public, anon;
grant execute on function public.school_epoch() to authenticated;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant execute on function public.school_epoch() to service_role;
  end if;
end $$;

-- يمسح بيانات المدرسة ويبدّل دورتها في معاملة واحدة، ويعيد:
--   epoch   الدورة الجديدة،
--   removed حسابات من حُذفوا (id وemail وrole) لتُحذف من خدمة الدخول ومن دليل المدارس،
--   objects ملفات التخزين (bucket وname) لتُحذف بواجهة التخزين (لا تُحذف من هنا لئلا تبقى كتلها).
-- تبقى صفوف user_accounts لأصحاب المدرسة، وتسجيلات إشعارات الدفع لحساباتهم؛ وكل جدول عام آخر يُفرَّغ
-- (يُعدَّد من النظام فلا ينجو جدول أُضيف بعد هذا الملف). وصف المدرسة في سجل العمليات صفّ واحد.
create or replace function public.reset_school_data(p_actor_id text, p_actor_name text)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_epoch text := gen_random_uuid()::text;
  v_now bigint := (extract(epoch from clock_timestamp()) * 1000)::bigint;
  v_tables text;
  v_removed jsonb;
  v_objects jsonb := '[]'::jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'email', email, 'role', role)), '[]'::jsonb)
    into v_removed
    from public.user_accounts
   where role <> 'owner';

  if to_regclass('storage.objects') is not null then
    execute $q$
      select coalesce(jsonb_agg(jsonb_build_object('bucket', bucket_id, 'name', name)), '[]'::jsonb)
        from storage.objects where bucket_id in ('photos', 'files')
    $q$ into v_objects;
  end if;

  select string_agg(format('%I.%I', schemaname, tablename), ', ')
    into v_tables
    from pg_tables
   where schemaname = 'public'
     and tablename not in ('user_accounts', 'push_installations');
  if v_tables is not null then
    execute 'truncate table ' || v_tables;
  end if;

  -- حذف حسابات غير المالك؛ تسجيلات الدفع لهم تُحذف معهم (مفتاح أجنبي بحذف متسلسل).
  delete from public.user_accounts where role <> 'owner';

  insert into app.school_state (id, epoch, reset_at, reset_by)
  values (1, v_epoch, v_now, p_actor_id)
  on conflict (id) do update
    set epoch = excluded.epoch, reset_at = excluded.reset_at, reset_by = excluded.reset_by;

  insert into public.audit_log (id, user_id, user_name, action, entity, entity_id,
                                "before", "after", created_at, updated_at)
  values (gen_random_uuid()::text, coalesce(p_actor_id, ''), coalesce(p_actor_name, ''),
          'reset_school', 'school', 'school', null, null, v_now, v_now);

  return jsonb_build_object('epoch', v_epoch, 'removed', v_removed, 'objects', v_objects);
end $$;
revoke all on function public.reset_school_data(text, text) from public, anon, authenticated;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant execute on function public.reset_school_data(text, text) to service_role;
  end if;
end $$;
