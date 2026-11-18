-- إعادة تعيين المدرسة: تمسح كل البيانات وحسابات غير المالك وتُبقي المالك، وتبدّل دورة المدرسة، ولا يبلغها
-- مستخدم. تعتمد على بيانات 002_rls.sql (حسابات acc-*) والدوال المساعدة منه.

-- دورة المدرسة قبل أي إعادة: نص فارغ، يقرؤه كل مستخدم مسجَّل ولا يقرؤه مجهول.
select test.login('acc-t1');
do $$
begin
  if public.school_epoch() <> '' then
    raise exception 'دورة المدرسة قبل الإعادة ليست فارغة';
  end if;
end $$;
select test.logout();
select test.login('acc-owner');
select test.denied($$select public.reset_school_data('acc-owner', 'المدير')$$,
  'المالك نفسه لا يستدعي الدالة مباشرة');
select test.denied($$select * from app.school_state$$, 'حالة المدرسة مغلقة أمام المستخدمين');
select test.logout();
select test.login('acc-t1');
select test.denied($$select public.reset_school_data('acc-t1', 'أستاذ')$$,
  'الأستاذ لا يستدعي الدالة');
select test.logout();

-- بيانات مبذورة قبل الإعادة: وتسجيلات دفع لمالك وأستاذ.
insert into push_installations (installation_id, user_id, platform, updated_at)
values ('install-owner-0001', 'acc-owner', 'android', 1),
       ('install-teacher-01', 'acc-t1', 'android', 1);
insert into settings (key, value, updated_at) values ('levels_seeded', '1', 1)
on conflict (key) do nothing;

do $$
declare
  before_push bigint := (select count(*) from app.push_config);
  before_removed bigint := (select count(*) from user_accounts where role <> 'owner');
  before_seq bigint := (select last_value from public.sync_seq);
  result jsonb;
  first_epoch text;
  t record;
  n bigint;
begin
  if (select count(*) from groups) + (select count(*) from students) + (select count(*) from subjects) = 0 then
    raise exception 'لا بيانات قبل الإعادة لاختبارها';
  end if;

  result := public.reset_school_data('acc-owner', 'المدير');
  first_epoch := result ->> 'epoch';
  if length(first_epoch) < 30 then
    raise exception 'الدورة الجديدة غير صالحة: %', first_epoch;
  end if;
  if public.school_epoch() <> first_epoch then
    raise exception 'دورة المدرسة لم تُحفظ';
  end if;

  -- كل جدول عام فُرِّغ ما عدا الحسابات وتسجيلات الدفع وسجل العمليات.
  for t in
    select tablename from pg_tables
     where schemaname = 'public'
       and tablename not in ('user_accounts', 'push_installations', 'audit_log')
  loop
    execute format('select count(*) from public.%I', t.tablename) into n;
    if n <> 0 then
      raise exception 'الجدول % لم يُفرَّغ (% صفاً)', t.tablename, n;
    end if;
  end loop;

  -- الحسابات: المالك وحده.
  if (select count(*) from user_accounts where role <> 'owner') <> 0 then
    raise exception 'بقيت حسابات لغير المالك';
  end if;
  if (select count(*) from user_accounts where id = 'acc-owner' and deleted_at is null) <> 1 then
    raise exception 'حساب المالك لم يبقَ';
  end if;
  -- الحذف وُصف لمن حُذفوا: بريدهم لتُزال أرقامهم من خدمة الدخول والدليل.
  if jsonb_array_length(result -> 'removed') <> before_removed or before_removed < 6 then
    raise exception 'المحذوفون غير من كانوا (% قبل): %', before_removed, result -> 'removed';
  end if;
  if (select count(*) from jsonb_array_elements(result -> 'removed') e
       where e ->> 'id' = 'acc-w1' and e ->> 'role' = 'worker'
         and e ->> 'email' = 'w1@school.local') <> 1 then
    raise exception 'وصف المحذوفين ناقص: %', result -> 'removed';
  end if;

  -- تسجيلات الدفع: يبقى تسجيل المالك فقط (حُذف تسجيل الأستاذ مع حسابه).
  if (select count(*) from push_installations where installation_id = 'install-owner-0001') <> 1
     or (select count(*) from push_installations p
          where not exists (select 1 from user_accounts a where a.id = p.user_id and a.role = 'owner')) <> 0 then
    raise exception 'تسجيلات الدفع بعد الإعادة غير المتوقعة';
  end if;

  -- سجل العمليات: صفّ واحد يصف الإعادة.
  if (select count(*) from audit_log) <> 1
     or (select count(*) from audit_log
          where action = 'reset_school' and user_id = 'acc-owner' and user_name = 'المدير') <> 1 then
    raise exception 'سجل العمليات بعد الإعادة غير المتوقع';
  end if;

  -- إعداد الدفع (مخطط app) لا يُمسّ، ومؤشر المزامنة لا يعود إلى الصفر.
  if (select count(*) from app.push_config) <> before_push then
    raise exception 'إعداد الدفع مُسّ';
  end if;
  if (select last_value from public.sync_seq) < before_seq then
    raise exception 'مؤشر المزامنة رجع إلى الوراء';
  end if;
end $$;

-- المالك ما زال معروفاً بعدها فتعمل صلاحياته، والكتابة الجديدة تأخذ مؤشراً أحدث.
select test.login('acc-owner');
select test.sees($$select 1 from user_accounts where id = 'acc-owner'$$, 1, 'المالك يرى حسابه بعد الإعادة');
select test.allowed(
  $$insert into subjects (id, created_at, updated_at, name, monthly_price)
    values ('after-reset', 1, 1, 'فيزياء', 2500)$$,
  'المالك يكتب في المدرسة الجديدة');
select test.logout();
do $$
begin
  if (select synced_at from subjects where id = 'after-reset') <= 0 then
    raise exception 'الكتابة بعد الإعادة بلا مؤشر مزامنة';
  end if;
end $$;
select test.login('acc-w1');
select test.sees($$select 1 from subjects$$, 0, 'عامل محذوف لا يرى شيئاً');
select test.logout();

-- الإعادة الثانية آمنة (تُكمل ما فاتها) وتبدّل الدورة من جديد.
do $$
declare
  first_epoch text := public.school_epoch();
  second jsonb := public.reset_school_data('acc-owner', 'المدير');
begin
  if second ->> 'epoch' = first_epoch or public.school_epoch() <> second ->> 'epoch' then
    raise exception 'الإعادة الثانية لم تبدّل الدورة';
  end if;
  if jsonb_array_length(second -> 'removed') <> 0 then
    raise exception 'الإعادة الثانية حذفت حسابات';
  end if;
  if (select count(*) from subjects) <> 0 then
    raise exception 'الإعادة الثانية لم تفرّغ ما كُتب بعد الأولى';
  end if;
  if (select count(*) from audit_log) <> 1
     or (select count(*) from audit_log where action = 'reset_school') <> 1 then
    raise exception 'سجل العمليات بعد الإعادة الثانية يصف الأخيرة وحدها';
  end if;
end $$;
