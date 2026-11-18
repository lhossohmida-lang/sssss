-- الأفواج المنتظِرة وحصص المراجعة وضيوف الحصص ودليل الهواتف (الترحيل 0011): الأعمدة وقيمها الافتراضية،
-- وصلاحيات الجدولين الجديدين. تُشغَّل بعد 006_group_price.sql (دوال test.* من 002_rls.sql)، وتنظّف ما تكتبه.

do $$
begin
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'groups' and column_name = 'is_review'
       and is_nullable = 'NO' and column_default = 'false') then
    raise exception 'groups.is_review غير موجود، أو ليس إلزامياً بقيمة افتراضية false';
  end if;
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'students' and column_name = 'single_use'
       and is_nullable = 'NO' and column_default = 'false') then
    raise exception 'students.single_use غير موجود، أو ليس إلزامياً بقيمة افتراضية false';
  end if;
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'group_students'
       and column_name = 'teacher_amount' and is_nullable = 'YES') then
    raise exception 'group_students.teacher_amount غير موجود أو إلزامي';
  end if;
end
$$;

-- بيانات الاختبار (بصلاحيات المالك الكامل للقاعدة).
insert into subjects (id, created_at, updated_at, name, monthly_price)
values ('x-sub', 1, 1, 'مادة اختبار الإضافات', 2000);
insert into teachers (id, created_at, updated_at, name, phone, email, rate_per_student, qr_code)
values ('x-t1', 1, 1, 'أستاذ إ1', '0550001001', 'x-t1@school.local', 1000, 'T-XT1XT1XT1X'),
       ('x-t2', 1, 1, 'أستاذ إ2', '0550001002', 'x-t2@school.local', 1000, 'T-XT2XT2XT2X');
insert into workers (id, created_at, updated_at, name, phone, email, qr_code,
                     expected_start_minutes, expected_end_minutes,
                     full_day_wage, half_day_wage, weekly_schedule, permissions)
values ('x-w1', 1, 1, 'عامل إ1', '0660001001', 'x-w1@school.local', 'W-XW1XW1XW1X',
        480, 1020, 2000, 1200, '{}', '{"students": ["view", "add"], "attendance": ["view"]}'),
       ('x-w2', 1, 1, 'عامل إ2', '0660001002', 'x-w2@school.local', 'W-XW2XW2XW2X',
        480, 1020, 2000, 1200, '{}', '{}');
insert into parents (id, created_at, updated_at, phone, email, name)
values ('x-p1', 1, 1, '0550001011', 'x-p1@school.local', 'وليّ إ1'),
       ('x-p2', 1, 1, '0550001012', 'x-p2@school.local', 'وليّ إ2');

-- فوج عادي كتبه تطبيق أقدم: بلا الأعمدة الجديدة، فتأخذ قيمها الافتراضية.
insert into groups (id, created_at, updated_at, number, subject_id, teacher_id,
                    sessions_per_cycle, current_cycle_number, monthly_price, rate_per_student)
values ('x-g1', 1, 1, 1, 'x-sub', 'x-t1', 8, 1, 2000, 1000);
insert into students (id, created_at, updated_at, first_name, last_name, parent_phone,
                      uses_transport, transport_price, qr_code, parent_account_id)
values ('x-s1', 1, 1, 'طالب', 'عادي', '0550001011', false, 0, 'S-XS1XS1XS1X', 'x-p1'),
       ('x-s2', 1, 1, 'طالب', 'آخر', '0550001012', false, 0, 'S-XS2XS2XS2X', 'x-p2');

do $$
declare
  g record;
  s record;
begin
  select is_review, waiting_target, start_alerted_at into g from groups where id = 'x-g1';
  if g.is_review is not false or g.waiting_target is not null or g.start_alerted_at is not null then
    raise exception 'فوج قديم لم يأخذ القيم الافتراضية للأعمدة الجديدة';
  end if;
  select single_use into s from students where id = 'x-s1';
  if s.single_use is not false then
    raise exception 'تلميذ قديم لم يأخذ single_use = false';
  end if;
end
$$;

-- فوج منتظِر وحصة مراجعة، وتلميذ لمرة واحدة.
insert into groups (id, created_at, updated_at, number, subject_id, teacher_id,
                    sessions_per_cycle, current_cycle_number, monthly_price, rate_per_student,
                    waiting_target, is_review)
values ('x-g2', 1, 1, 2, 'x-sub', 'x-t1', 8, 1, 2000, 1000, 12, false),
       ('x-g3', 1, 1, 3, 'x-sub', 'x-t2', 1, 1, 500, 300, null, true);
insert into students (id, created_at, updated_at, first_name, last_name, parent_phone,
                      uses_transport, transport_price, qr_code, single_use)
values ('x-s3', 1, 1, 'ضيف', 'لمرة', '', false, 0, 'S-XS3XS3XS3X', true);
insert into sessions (id, created_at, updated_at, group_id, cycle_number, session_number,
                      date, start_minutes, end_minutes, status)
values ('x-se1', 1, 1, 'x-g1', 1, 1, '2026-11-14', 600, 690, 'normal'),
       ('x-se3', 1, 1, 'x-g3', 1, 1, '2026-11-15', 600, 780, 'normal');
insert into group_students (id, created_at, updated_at, group_id, student_id, joined_at,
                            joined_at_cycle_number, joined_at_session_number, monthly_price,
                            discount_type, discount_value, teacher_amount)
values ('x-gs1', 1, 1, 'x-g1', 'x-s1', 1, 1, 1, 2000, 'exempt', 0, 0),
       ('x-gs2', 1, 1, 'x-g2', 'x-s2', 1, 1, 1, 2000, 'none', 0, null);

insert into session_guests (id, created_at, updated_at, session_id, student_id, price,
                            teacher_amount, ticket_code)
values ('x-sg1', 1, 1, 'x-se3', 'x-s3', 500, 300, 'G-XXXXXXXXXX'),
       ('x-sg2', 1, 1, 'x-se3', 'x-s1', 0, 300, null);
insert into contacts (id, created_at, updated_at, name, phone, note, source)
values ('x-c1', 1, 1, 'مهتم', '0550009999', 'اتصل بعد شهر', 'manual');

insert into user_accounts (id, created_at, updated_at, email, role, entity_id,
                           display_name, must_change_password)
values ('x-acc-owner', 1, 1, 'x-owner@school.local', 'owner', null, 'مدير إ', false),
       ('x-acc-w1', 1, 1, 'x-w1@school.local', 'worker', 'x-w1', 'عامل إ1', true),
       ('x-acc-w2', 1, 1, 'x-w2@school.local', 'worker', 'x-w2', 'عامل إ2', true),
       ('x-acc-t1', 1, 1, 'x-t1@school.local', 'teacher', 'x-t1', 'أستاذ إ1', true),
       ('x-acc-t2', 1, 1, 'x-t2@school.local', 'teacher', 'x-t2', 'أستاذ إ2', true),
       ('x-acc-p1', 1, 1, 'x-p1@school.local', 'parent', 'x-p1', 'وليّ إ1', true),
       ('x-acc-p2', 1, 1, 'x-p2@school.local', 'parent', 'x-p2', 'وليّ إ2', true);

-- التذكرة فريدة: لا تذكرتان بالرمز نفسه.
do $$
begin
  begin
    insert into session_guests (id, created_at, updated_at, session_id, student_id, price,
                                teacher_amount, ticket_code)
    values ('x-sg-dup', 1, 1, 'x-se3', 'x-s2', 500, 300, 'G-XXXXXXXXXX');
    raise exception 'قُبلت تذكرتان بالرمز نفسه';
  exception when unique_violation then
    null;
  end;
  -- ولا ضيف مرتين في الحصة نفسها.
  begin
    insert into session_guests (id, created_at, updated_at, session_id, student_id, price,
                                teacher_amount)
    values ('x-sg-dup2', 1, 1, 'x-se3', 'x-s1', 500, 300);
    raise exception 'قُبل ضيف مرتين في الحصة نفسها';
  exception when unique_violation then
    null;
  end;
end
$$;

-- المالك: كل شيء.
select test.login('x-acc-owner');
select test.sees('select 1 from contacts where id = ''x-c1''', 1, 'المالك: دليل الهواتف');
select test.sees('select 1 from session_guests where id like ''x-sg%''', 2, 'المالك: ضيوف الحصص');
select test.allowed(
  $$insert into contacts (id, created_at, updated_at, name, phone, note, source)
    values ('x-c2', 1, 1, 'آخر', '0660000123', '', 'manual')$$,
  'المالك يسجّل رقماً');
select test.allowed(
  $$update contacts set deleted_at = 3, updated_at = 3 where id = 'x-c2'$$,
  'المالك يحذف رقماً حذفاً ناعماً');
select test.allowed(
  $$insert into session_guests (id, created_at, updated_at, session_id, student_id, price,
      teacher_amount, ticket_code)
    values ('x-sg3', 1, 1, 'x-se1', 'x-s2', 100, 50, null)$$,
  'المالك يضيف ضيفاً');
select test.logout();

-- عامل بصلاحية التلاميذ والحضور (عرض): يرى الدليل والضيوف، ولا يضيف ضيفاً.
select test.login('x-acc-w1');
select test.sees('select 1 from contacts where id = ''x-c1''', 1, 'عامل بصلاحية التلاميذ: الدليل');
select test.allowed(
  $$insert into contacts (id, created_at, updated_at, name, phone, note, source)
    values ('x-c3', 1, 1, 'من العامل', '0660000124', '', 'manual')$$,
  'عامل بصلاحية إضافة التلاميذ يسجّل رقماً');
select test.sees('select 1 from session_guests where id like ''x-sg%''', 3, 'عامل بصلاحية الحضور: الضيوف');
select test.denied(
  $$insert into session_guests (id, created_at, updated_at, session_id, student_id, price,
      teacher_amount, ticket_code)
    values ('x-sg4', 1, 1, 'x-se1', 'x-s2', 100, 50, null)$$,
  'عامل بلا صلاحية إضافة حضور لا يضيف ضيفاً');
select test.logout();

-- عامل بلا صلاحيات: لا يرى شيئاً.
select test.login('x-acc-w2');
select test.sees('select 1 from contacts', 0, 'عامل بلا صلاحيات: الدليل');
select test.sees('select 1 from session_guests', 0, 'عامل بلا صلاحيات: الضيوف');
select test.denied(
  $$insert into contacts (id, created_at, updated_at, name, phone, note, source)
    values ('x-c4', 1, 1, 'ممنوع', '0660000125', '', 'manual')$$,
  'عامل بلا صلاحيات يسجّل رقماً');
select test.logout();

-- الأستاذ: لا يرى الدليل، ويرى ضيوف حصص مجموعاته فقط.
select test.login('x-acc-t2');
select test.sees('select 1 from contacts', 0, 'الأستاذ: الدليل');
select test.sees('select 1 from session_guests', 2, 'أستاذ حصة المراجعة يرى ضيوفها');
select test.denied(
  $$insert into session_guests (id, created_at, updated_at, session_id, student_id, price,
      teacher_amount, ticket_code)
    values ('x-sg5', 1, 1, 'x-se3', 'x-s2', 100, 50, null)$$,
  'الأستاذ لا يضيف ضيفاً');
select test.logout();

select test.login('x-acc-t1');
select test.sees('select 1 from session_guests where session_id = ''x-se3''', 0,
  'أستاذ فوج آخر لا يرى ضيوف حصة المراجعة');
select test.sees('select 1 from session_guests where session_id = ''x-se1''', 1,
  'أستاذ الفوج يرى ضيوف حصة فوجه');
select test.logout();

-- الوليّ: لا يرى الدليل، ويرى ضيافة ابنه فقط.
select test.login('x-acc-p1');
select test.sees('select 1 from contacts', 0, 'الوليّ: الدليل');
select test.sees('select 1 from session_guests', 1, 'الوليّ يرى ضيافة ابنه فقط');
select test.denied(
  $$update session_guests set price = 0, updated_at = 9 where id = 'x-sg2'$$,
  'الوليّ لا يعدّل ضيافة');
select test.logout();

select test.login('x-acc-p2');
select test.sees('select 1 from session_guests where student_id = ''x-s1''', 0,
  'وليّ آخر لا يرى ضيافة ابن غيره');
select test.logout();

-- تنظيف.
delete from session_guests where id like 'x-sg%';
delete from contacts where id like 'x-c%';
delete from group_students where id like 'x-gs%';
delete from sessions where id in ('x-se1', 'x-se3');
delete from groups where id in ('x-g1', 'x-g2', 'x-g3');
delete from students where id in ('x-s1', 'x-s2', 'x-s3');
delete from user_accounts where id like 'x-acc-%';
delete from parents where id in ('x-p1', 'x-p2');
delete from workers where id in ('x-w1', 'x-w2');
delete from teachers where id in ('x-t1', 'x-t2');
delete from subjects where id = 'x-sub';
