-- إشعارات الدفع: المشغِّلان موجودان، والإعداد مغلق أمام المستخدمين، وإدراج الإشعار أو الرسالة
-- لا يتعطل دون إعداد أو دون pg_net. تعتمد على الدوال المساعدة من 002_rls.sql.

do $$
begin
  if (select count(*) from pg_trigger
       where tgname in ('trg_push_notifications', 'trg_push_chat_messages')
         and not tgisinternal) <> 2 then
    raise exception 'مشغّلا الدفع غير موجودين';
  end if;
end $$;

-- دون إعداد دفع: الإدراج ينجح.
select test.allowed(
  $$insert into notifications (id, created_at, updated_at, user_id, title, body, kind)
    values ('push-n1', 1, 1, 'acc-owner', 'عنوان', 'نص', 'info')$$,
  'إدراج إشعار دون إعداد دفع ينجح');
select test.allowed(
  $$insert into chat_messages (id, created_at, updated_at, room_id, sender_id, sender_role, content)
    values ('push-m1', 1, 1, 'room-x', 'acc-owner', 'owner', 'مرحباً')$$,
  'إدراج رسالة دون إعداد دفع ينجح');

-- الإعداد مغلق أمام المستخدمين.
select test.login('acc-owner');
select test.denied($$select * from app.push_config$$, 'المستخدم لا يقرأ إعداد الدفع');
select test.denied(
  $$select public.set_push_config('https://x.example.com/functions/v1/send-push', repeat('s', 40))$$,
  'المستخدم لا يضبط إعداد الدفع');
select test.logout();

-- الضبط يرفض ما ليس https أو سرّاً قصيراً (استثناء عادي لا استثناء صلاحيات).
do $$
declare
  failed boolean := false;
begin
  begin
    perform public.set_push_config('http://x.example.com/f', repeat('s', 40));
  exception when others then
    failed := true;
  end;
  if not failed then
    raise exception 'عنوان غير https لم يُرفض';
  end if;
  failed := false;
  begin
    perform public.set_push_config('https://x.example.com/f', 'short');
  exception when others then
    failed := true;
  end;
  if not failed then
    raise exception 'سرّ قصير لم يُرفض';
  end if;
end $$;

-- مع الإعداد: يُحفظ، وإعادة الضبط تستبدل، والإدراج ينجح حتى دون pg_net (الخطأ يُبتلع).
select test.allowed(
  $$select public.set_push_config('https://x.example.com/functions/v1/send-push', repeat('a', 40))$$,
  'الضبط الصحيح ينجح');
select test.allowed(
  $$select public.set_push_config('https://y.example.com/functions/v1/send-push', repeat('b', 40))$$,
  'إعادة الضبط تستبدل');
do $$
begin
  if (select count(*) from app.push_config) <> 2
     or (select value from app.push_config where key = 'url') <> 'https://y.example.com/functions/v1/send-push' then
    raise exception 'إعداد الدفع لم يُحفظ كما يجب';
  end if;
end $$;
select test.allowed(
  $$insert into notifications (id, created_at, updated_at, user_id, title, body, kind)
    values ('push-n2', 1, 1, 'acc-owner', 'عنوان', 'نص', 'info')$$,
  'الإدراج ينجح مع الإعداد حتى لو تعذّر الإرسال');
select test.sees($$select 1 from notifications where id = 'push-n2'$$, 1, 'الإشعار حُفظ');
