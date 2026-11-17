-- دليل المدارس: القراءة المُعلنة، والبحث برقم الهاتف، وتسجيل أرقام الطاقم بمفتاح المدرسة،
-- والحدّ من المحاولات، وإغلاق الجداول والدوال الخاصة أمام مفتاح التطبيق العام (دور anon).
create schema if not exists test;

create or replace function test.expect(ok boolean, msg text) returns void
language plpgsql as $$
begin
  if not coalesce(ok, false) then
    raise exception 'FAILED: %', msg;
  end if;
end $$;

-- ينفّذ [sql] بدور anon ويعيد true إن رُفض لنقص الصلاحية.
create or replace function test.anon_denied(sql text) returns boolean
language plpgsql as $$
begin
  set local role anon;
  execute sql;
  reset role;
  return false;
exception when insufficient_privilege then
  return true;
end $$;

-- مدرستان: معلنة وغير معلنة. الرقم الثاني بصيغة دولية بمسافات ليُوحَّد.
select public.register_school(
  'alnour', 'مدرسة النور', 'https://aaaaaaaaaaaaaaaaaaaa.supabase.co',
  'sb_publishable_' || repeat('a', 30), true, repeat('k', 40), '0550123456');
select public.register_school(
  'khafia', 'مدرسة خفية', 'https://bbbbbbbbbbbbbbbbbbbb.supabase.co',
  'sb_publishable_' || repeat('b', 30), false, repeat('h', 40), '+213 661 23 45 67');

do $$
declare
  schools int;
  hashed int;
  raw int;
begin
  select count(*) into schools from public.schools;
  select count(*) into hashed from public.staff_phones where length(phone_hash) = 64;
  select count(*) into raw from public.staff_phones where phone_hash like '%0550123456%';
  perform test.expect(schools = 2, 'مدرستان مسجّلتان');
  perform test.expect(hashed = 2, 'أرقام المالكين مخزَّنة مبصومة');
  perform test.expect(raw = 0, 'لا يُخزَّن رقم صريح');
end $$;

-- القراءة المُعلنة: غير المعلنة لا تظهر في القائمة.
do $$
declare
  n int;
  first_name text;
begin
  set local role anon;
  select count(*), min(name) into n, first_name from public.list_schools();
  reset role;
  perform test.expect(n = 1, 'list_schools تعيد المدرسة المعلنة وحدها');
  perform test.expect(first_name = 'مدرسة النور', 'اسم المدرسة المعلنة');
end $$;

-- البحث برقم الهاتف بكل الصيغ، ومدرسة غير معلنة تُعرف برقم طاقمها.
do $$
declare
  local_form int;
  international int;
  double_zero int;
  unlisted int;
  unknown int;
  invalid int;
  empty int;
begin
  set local role anon;
  select count(*) into local_form from public.resolve_school('0550123456');
  select count(*) into international from public.resolve_school('+213 550 12 34 56');
  select count(*) into double_zero from public.resolve_school('00213550123456');
  select count(*) into unlisted from public.resolve_school('0661234567');
  select count(*) into unknown from public.resolve_school('0771111111');
  select count(*) into invalid from public.resolve_school('abc');
  select count(*) into empty from public.resolve_school(null);
  reset role;
  perform test.expect(local_form = 1, 'الصيغة المحلية');
  perform test.expect(international = 1, 'الصيغة الدولية');
  perform test.expect(double_zero = 1, 'الصيغة 00213');
  perform test.expect(unlisted = 1, 'المدرسة غير المعلنة تُعرف برقم طاقمها');
  perform test.expect(unknown = 0, 'رقم غير مسجّل');
  perform test.expect(invalid = 0, 'رقم غير صالح لا يرمي ولا يعيد شيئاً');
  perform test.expect(empty = 0, 'null لا يرمي');
end $$;

-- تسجيل رقم عامل: مفتاح خاطئ أو مدرسة مجهولة تُرفض، والصحيح يسجّل ثم يمكن إزالته.
do $$
declare
  wrong boolean;
  unknown_school boolean;
  bad_phone boolean;
  good boolean;
  found_after int;
  removed boolean;
  found_removed int;
begin
  set local role anon;
  wrong := public.school_register_phone('alnour', repeat('x', 40), '0771111111');
  unknown_school := public.school_register_phone('nope', repeat('k', 40), '0771111111');
  bad_phone := public.school_register_phone('alnour', repeat('k', 40), 'abc');
  good := public.school_register_phone('alnour', repeat('k', 40), '0771111111');
  select count(*) into found_after from public.resolve_school('0771111111');
  removed := public.school_unregister_phone('alnour', repeat('k', 40), '0771111111');
  select count(*) into found_removed from public.resolve_school('0771111111');
  reset role;
  perform test.expect(wrong = false, 'مفتاح خاطئ يُرفض');
  perform test.expect(unknown_school = false, 'مدرسة مجهولة تُرفض');
  perform test.expect(bad_phone = false, 'رقم غير صالح يُرفض');
  perform test.expect(good = true, 'مفتاح المدرسة يسجّل الرقم');
  perform test.expect(found_after = 1, 'الرقم المسجّل يُعرف');
  perform test.expect(removed = true, 'الإزالة بمفتاح المدرسة');
  perform test.expect(found_removed = 0, 'الرقم المُزال لا يُعرف');
end $$;

-- رقم واحد في مدرستين: يعيد المدرستين (مالك مدرستين أو عامل في اثنتين).
do $$
declare
  added boolean;
  n int;
begin
  set local role anon;
  added := public.school_register_phone('khafia', repeat('h', 40), '0550123456');
  select count(*) into n from public.resolve_school('0550123456');
  reset role;
  perform test.expect(added, 'تسجيل الرقم في المدرسة الثانية');
  perform test.expect(n = 2, 'الرقم يعيد المدرستين');
end $$;

-- إعادة تسجيل المدرسة نفسها تحدّث بياناتها وتُبطل مفتاح التسجيل القديم.
select public.register_school(
  'alnour', 'مدرسة النور الجديدة', 'https://aaaaaaaaaaaaaaaaaaaa.supabase.co',
  'sb_publishable_' || repeat('a', 30), true, repeat('z', 40), '0550123456');
do $$
declare
  schools int;
  renamed text;
  old_key boolean;
  new_key boolean;
begin
  select count(*) into schools from public.schools;
  select name into renamed from public.schools where slug = 'alnour';
  set local role anon;
  old_key := public.school_register_phone('alnour', repeat('k', 40), '0772222222');
  new_key := public.school_register_phone('alnour', repeat('z', 40), '0772222222');
  reset role;
  perform test.expect(schools = 2, 'إعادة التسجيل لا تكرّر المدرسة');
  perform test.expect(renamed = 'مدرسة النور الجديدة', 'الاسم يتحدّث');
  perform test.expect(old_key = false, 'مفتاح التسجيل القديم يبطل');
  perform test.expect(new_key = true, 'المفتاح الجديد يعمل');
end $$;

-- الجداول والدوال الخاصة مغلقة أمام دور anon.
select test.expect(test.anon_denied('select * from public.schools'), 'anon لا يقرأ المدارس');
select test.expect(test.anon_denied('select * from public.staff_phones'), 'anon لا يقرأ الأرقام');
select test.expect(test.anon_denied('select * from app.directory_pepper'), 'anon لا يقرأ الملح');
select test.expect(test.anon_denied('select * from app.lookup_attempts'), 'anon لا يقرأ العدّادات');
select test.expect(
  test.anon_denied($$select app.phone_key('0550123456')$$), 'anon لا يستدعي دوال app');
select test.expect(
  test.anon_denied(
    $$select public.register_school('x1', 'xx', 'https://cccccccccccccccccccc.supabase.co',
      'sb_publishable_cccccccccccccccccccccccc', true, repeat('c', 40), null)$$),
  'anon لا يسجّل مدرسة');

-- قيود البيانات: المفتاح السرّي والعنوان غير https ومفتاح التسجيل القصير تُرفض.
do $$
declare
  secret_refused boolean := false;
  url_refused boolean := false;
  short_refused boolean := false;
begin
  begin
    perform public.register_school(
      'sec', 'مدرسة سرية', 'https://dddddddddddddddddddd.supabase.co',
      'sb_secret_' || repeat('d', 30), true, repeat('s', 40), null);
  exception when check_violation then
    secret_refused := true;
  end;
  begin
    perform public.register_school(
      'plain', 'مدرسة عادية', 'http://eeeeeeeeeeeeeeeeeeee.supabase.co',
      'sb_publishable_' || repeat('e', 30), true, repeat('p', 40), null);
  exception when check_violation then
    url_refused := true;
  end;
  begin
    perform public.register_school(
      'short', 'مدرسة قصيرة', 'https://ffffffffffffffffffff.supabase.co',
      'sb_publishable_' || repeat('f', 30), true, 'tiny', null);
  exception when others then
    short_refused := true;
  end;
  perform test.expect(secret_refused, 'المفتاح السرّي يُرفض');
  perform test.expect(url_refused, 'عنوان غير https يُرفض');
  perform test.expect(short_refused, 'مفتاح تسجيل قصير يُرفض');
  perform test.expect((select count(*) from public.schools) = 2, 'لم تُضف مدرسة مرفوضة');
end $$;

-- الحدّ من المحاولات: ستون بحثاً لكل عنوان في نافذة عشر دقائق، والحادي والستون يُرفض.
do $$
declare
  i int;
  ok_calls int := 0;
  blocked boolean := false;
  other_ok boolean := false;
begin
  perform set_config('request.headers', '{"x-forwarded-for": "203.0.113.7, 10.0.0.1"}', true);
  set local role anon;
  for i in 1..60 loop
    perform * from public.resolve_school('0771111111');
    ok_calls := ok_calls + 1;
  end loop;
  begin
    perform * from public.resolve_school('0771111111');
  exception when others then
    blocked := true;
  end;
  perform set_config('request.headers', '{"x-forwarded-for": "203.0.113.8"}', true);
  begin
    perform * from public.resolve_school('0771111111');
    other_ok := true;
  exception when others then
    other_ok := false;
  end;
  reset role;
  perform test.expect(ok_calls = 60, 'الستون الأولى تنجح');
  perform test.expect(blocked, 'الحادية والستون تُرفض');
  perform test.expect(other_ok, 'عنوان آخر لا يتأثر');
end $$;
