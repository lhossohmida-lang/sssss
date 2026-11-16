-- إرسال إشعارات الدفع من الخادم: مشغِّلان على الإشعارات ورسائل المحادثة يستدعيان دالة
-- send-push عبر pg_net بسرّ مشترك يُضبط بعد النشر (rpc set_push_config). دون إعداد أو دون
-- pg_net لا يحدث شيء ولا يتعطل أي إدراج: الدفع تحسين لا شرط لحفظ الإشعار أو الرسالة.
do $$
begin
  create extension if not exists pg_net;
exception when others then
  raise notice 'pg_net غير متاح: لا إشعارات دفع من هذا الخادم';
end $$;

create schema if not exists app;

-- عنوان الدالة والسرّ المشترك (مغلق أمام كل مستخدم، يصله مالك الجدول ومفتاح الخادم السرّي فقط).
create table if not exists app.push_config (
  key text primary key check (key in ('url', 'secret')),
  value text not null
);
alter table app.push_config enable row level security;
revoke all on app.push_config from public, anon, authenticated;

create or replace function app.push_notify() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  endpoint text;
  shared text;
begin
  select value into endpoint from app.push_config where key = 'url';
  select value into shared from app.push_config where key = 'secret';
  if endpoint is null or shared is null then
    return new;
  end if;
  begin
    perform net.http_post(
      url := endpoint,
      headers := jsonb_build_object('Content-Type', 'application/json', 'x-push-secret', shared),
      body := jsonb_build_object('table', tg_table_name, 'id', new.id),
      timeout_milliseconds := 3000
    );
  exception when others then
    null; -- لا يُفشل الدفع إدراج الإشعار أو الرسالة
  end;
  return new;
end $$;

-- يضبطه مسار النشر بمفتاح الخادم السرّي (لا أحد غيره).
create or replace function public.set_push_config(p_url text, p_secret text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if p_url !~ '^https://[^/]+/' or length(p_secret) < 32 then
    raise exception 'إعداد الدفع غير صالح';
  end if;
  insert into app.push_config (key, value)
  values ('url', p_url), ('secret', p_secret)
  on conflict (key) do update set value = excluded.value;
end $$;
revoke all on function public.set_push_config(text, text) from public, anon, authenticated;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant execute on function public.set_push_config(text, text) to service_role;
  end if;
end $$;

drop trigger if exists trg_push_notifications on public.notifications;
create trigger trg_push_notifications after insert on public.notifications
  for each row execute function app.push_notify();

drop trigger if exists trg_push_chat_messages on public.chat_messages;
create trigger trg_push_chat_messages after insert on public.chat_messages
  for each row execute function app.push_notify();
