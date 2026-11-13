-- اختبارات الصلاحيات لكل دور. أي فشل يرمي استثناء ويوقف التنفيذ.

create schema if not exists test;
grant usage on schema test to authenticated, anon;

create or replace function test.login(uid text) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', uid, false);
  perform set_config('role', 'authenticated', false);
end
$$;

create or replace function test.logout() returns void
language plpgsql as $$
begin
  perform set_config('role', 'none', false);
  perform set_config('request.jwt.claim.sub', '', false);
end
$$;

-- عدد الصفوف التي يراها المستخدم الحالي.
create or replace function test.sees(query text, expected int, label text)
returns void language plpgsql as $$
declare n int;
begin
  execute format('select count(*) from (%s) q', query) into n;
  if n <> expected then
    raise exception '[%] رأى % صفاً والمتوقع %', label, n, expected;
  end if;
end
$$;

-- العملية يجب أن تنجح وتمسّ صفاً واحداً على الأقل.
create or replace function test.allowed(statement text, label text)
returns void language plpgsql as $$
declare n int;
begin
  execute statement;
  get diagnostics n = row_count;
  if n < 1 then
    raise exception '[%] لم تمسّ العملية أي صف', label;
  end if;
end
$$;

-- العملية يجب أن تُرفض (استثناء صلاحيات) أو ألا تمسّ أي صف.
create or replace function test.denied(statement text, label text)
returns void language plpgsql as $$
declare n int;
begin
  begin
    execute statement;
    get diagnostics n = row_count;
  exception when insufficient_privilege then
    return;
  end;
  if n > 0 then
    raise exception '[%] عملية ممنوعة نجحت ومسّت % صفاً', label, n;
  end if;
end
$$;

grant execute on all functions in schema test to authenticated, anon;

-- ---------------------------------------------------------------------------
-- بيانات الاختبار (تُدرج بصلاحيات المالك الكامل للقاعدة)
-- ---------------------------------------------------------------------------

insert into subjects (id, created_at, updated_at, name, monthly_price)
values ('sub', 1, 1, 'رياضيات', 2000);
insert into rooms (id, created_at, updated_at, name, capacity)
values ('r1', 1, 1, 'القاعة 1', 20);

insert into teachers (id, created_at, updated_at, name, phone, email,
                      rate_per_student, qr_code)
values ('t1', 1, 1, 'كريم', '0770000001', 't1@school.local', 1000, 'T-AAAAAAAAAA'),
       ('t2', 1, 1, 'ليلى', '0770000002', 't2@school.local', 1200, 'T-BBBBBBBBBB');

insert into workers (id, created_at, updated_at, name, phone, email, qr_code,
                     expected_start_minutes, expected_end_minutes,
                     full_day_wage, half_day_wage, weekly_schedule, permissions)
values ('w1', 1, 1, 'سمير', '0660000001', 'w1@school.local', 'W-AAAAAAAAAA',
        480, 1020, 2000, 1200, '{}',
        '{"students": ["view", "add"], "scanner": ["use"], "receive_money": ["use"]}'),
       ('w2', 1, 1, 'نادية', '0660000002', 'w2@school.local', 'W-BBBBBBBBBB',
        480, 1020, 2000, 1200, '{}', '{}');

insert into parents (id, created_at, updated_at, phone, email, name)
values ('p1', 1, 1, '0550000001', 'p1@school.local', 'وليّ 1'),
       ('p2', 1, 1, '0550000002', 'p2@school.local', 'وليّ 2');

insert into students (id, created_at, updated_at, first_name, last_name,
                      parent_phone, uses_transport, transport_price, qr_code,
                      parent_account_id)
values ('s1', 1, 1, 'أحمد', 'أ', '0550000001', false, 0, 'S-AAAAAAAAAA', 'p1'),
       ('s2', 1, 1, 'سارة', 'ب', '0550000002', false, 0, 'S-BBBBBBBBBB', 'p2');

insert into groups (id, created_at, updated_at, number, subject_id, teacher_id,
                    room_id, sessions_per_cycle, current_cycle_number,
                    rate_per_student)
values ('g1', 1, 1, 1, 'sub', 't1', 'r1', 8, 1, 1500),
       ('g2', 1, 1, 2, 'sub', 't2', 'r1', 8, 1, null);

-- 2026-11-14 يوم سبت (isodow = 6).
insert into group_slots (id, created_at, updated_at, group_id, weekday,
                         start_minutes, end_minutes)
values ('sl1', 1, 1, 'g1', 6, 600, 690);

insert into group_students (id, created_at, updated_at, group_id, student_id,
                            joined_at, joined_at_cycle_number,
                            joined_at_session_number, monthly_price,
                            discount_type, discount_value)
values ('gs1', 1, 1, 'g1', 's1', 1, 1, 1, 2000, 'none', 0),
       ('gs2', 1, 1, 'g2', 's2', 1, 1, 1, 2000, 'none', 0);

insert into sessions (id, created_at, updated_at, group_id, cycle_number,
                      session_number, date, start_minutes, end_minutes, status)
values ('se1', 1, 1, 'g1', 1, 1, '2026-11-14', 600, 690, 'normal'),
       ('se2', 1, 1, 'g2', 1, 1, '2026-11-14', 900, 990, 'normal');

insert into payments (id, created_at, updated_at, student_id, type, group_id,
                      cycle_number, amount, received_by, receipt_number, note)
values ('pay1', 1, 1, 's1', 'month', 'g1', 1, 2000, 'acc-owner', 'A-000001', ''),
       ('pay2', 1, 1, 's2', 'month', 'g2', 1, 2000, 'acc-owner', 'A-000002', '');

insert into teacher_payouts (id, created_at, updated_at, teacher_id, group_id,
                             cycle_number, kind, amount, details)
values ('po1', 1, 1, 't1', 'g1', 1, 'cycle', 1000, '[]'),
       ('po2', 1, 1, 't2', 'g2', 1, 'cycle', 1200, '[]');

insert into expense_categories (id, created_at, updated_at, name, is_wages)
values ('ec1', 1, 1, 'كهرباء', false);

insert into user_accounts (id, created_at, updated_at, email, role, entity_id,
                           display_name, must_change_password)
values ('acc-owner', 1, 1, 'owner@school.local', 'owner', null, 'المدير', false),
       ('acc-w1', 1, 1, 'w1@school.local', 'worker', 'w1', 'سمير', true),
       ('acc-w2', 1, 1, 'w2@school.local', 'worker', 'w2', 'نادية', true),
       ('acc-t1', 1, 1, 't1@school.local', 'teacher', 't1', 'كريم', true),
       ('acc-t2', 1, 1, 't2@school.local', 'teacher', 't2', 'ليلى', true),
       ('acc-p1', 1, 1, 'p1@school.local', 'parent', 'p1', 'وليّ 1', true),
       ('acc-p2', 1, 1, 'p2@school.local', 'parent', 'p2', 'وليّ 2', true);

insert into notifications (id, created_at, updated_at, user_id, sender_id,
                           title, body, kind)
values ('n1', 1, 1, 'acc-p1', 'acc-owner', 'عنوان', 'نص', 'info'),
       ('n2', 1, 1, 'acc-p2', 'acc-owner', 'عنوان', 'نص', 'info');

-- ---------------------------------------------------------------------------
-- غير المسجَّل لا يرى شيئاً
-- ---------------------------------------------------------------------------
select set_config('role', 'anon', false);
select test.denied('select 1 from students', 'anon يقرأ التلاميذ');
select test.logout();

select test.login('unknown-user');
select test.sees('select 1 from students', 0, 'مستخدم بلا حساب: التلاميذ');
select test.sees('select 1 from settings', 0, 'مستخدم بلا حساب: الإعدادات فارغة أصلاً');
select test.denied(
  $$insert into rooms (id, created_at, updated_at, name, capacity)
    values ('rx', 1, 1, 'x', 1)$$, 'مستخدم بلا حساب يضيف قاعة');
select test.logout();

-- ---------------------------------------------------------------------------
-- صاحب المدرسة: كل شيء
-- ---------------------------------------------------------------------------
select test.login('acc-owner');
select test.sees('select 1 from students', 2, 'المالك: التلاميذ');
select test.sees('select 1 from workers', 2, 'المالك: العمال');
select test.sees('select 1 from payments', 2, 'المالك: المدفوعات');
select test.sees('select 1 from user_accounts', 7, 'المالك: الحسابات');
select test.sees('select 1 from teacher_payouts', 2, 'المالك: الخلاص');
select test.allowed(
  $$insert into students (id, created_at, updated_at, first_name, last_name,
      parent_phone, uses_transport, transport_price, qr_code)
    values ('s3', 1, 1, 'ج', 'ج', '0550000003', false, 0, 'S-CCCCCCCCCC')$$,
  'المالك يضيف تلميذاً');
select test.allowed(
  $$update students set first_name = 'معدَّل', updated_at = 2 where id = 's3'$$,
  'المالك يعدّل تلميذاً');
select test.allowed(
  $$update students set deleted_at = 3, updated_at = 3 where id = 's3'$$,
  'المالك يحذف تلميذاً حذفاً ناعماً');
select test.allowed(
  $$update workers set permissions = '{"students": ["view"]}', updated_at = 2
     where id = 'w2'$$, 'المالك يحدد صلاحيات عامل');
select test.allowed(
  $$update workers set permissions = '{}', updated_at = 3 where id = 'w2'$$,
  'المالك يسحب صلاحيات عامل');
select test.denied('delete from students where id = ''s3''',
  'لا حذف فعلي حتى للمالك');
select test.logout();

-- ---------------------------------------------------------------------------
-- عامل بصلاحيات: عرض وإضافة التلاميذ، الماسح، استلام المال
-- ---------------------------------------------------------------------------
select test.login('acc-w1');
select test.sees('select 1 from students where deleted_at is null', 2,
  'العامل 1: التلاميذ');
select test.allowed(
  $$insert into students (id, created_at, updated_at, first_name, last_name,
      parent_phone, uses_transport, transport_price, qr_code)
    values ('s4', 1, 1, 'د', 'د', '0550000004', false, 0, 'S-DDDDDDDDDD')$$,
  'العامل 1 يضيف تلميذاً');
select test.denied(
  $$update students set first_name = 'x', updated_at = 5 where id = 's1'$$,
  'العامل 1 يعدّل دون صلاحية التعديل');
select test.denied(
  $$update students set deleted_at = 5, updated_at = 5 where id = 's1'$$,
  'العامل 1 يحذف دون صلاحية الحذف');
select test.sees('select 1 from workers', 1, 'العامل 1 يرى سجله فقط');
select test.denied(
  $$update workers set permissions = '{"workers": ["view", "edit"]}',
      full_day_wage = 99999, updated_at = 5 where id = 'w1'$$,
  'العامل يرفع صلاحياته وأجره');
select test.sees('select 1 from payments', 0, 'العامل 1: لا عرض للمدفوعات');
select test.allowed(
  $$insert into payments (id, created_at, updated_at, student_id, type,
      group_id, cycle_number, amount, received_by, receipt_number, note)
    values ('pay3', 1, 1, 's1', 'registration', null, null, 500, 'acc-w1',
            'B-000001', '')$$, 'العامل 1 يستلم مالاً باسمه');
select test.denied(
  $$insert into payments (id, created_at, updated_at, student_id, type,
      group_id, cycle_number, amount, received_by, receipt_number, note)
    values ('pay4', 1, 1, 's1', 'registration', null, null, 500, 'acc-owner',
            'B-000002', '')$$, 'العامل يسجّل استلاماً باسم غيره');
select test.allowed(
  $$insert into attendance (id, created_at, updated_at, session_id, student_id,
      status, scanned_at, method)
    values ('att1', 1, 1, 'se1', 's1', 'present', 1, 'qr')$$,
  'العامل 1 يسجّل الحضور بالماسح');
select test.sees('select 1 from expenses', 0, 'العامل 1: المصاريف');
select test.denied(
  $$insert into expenses (id, created_at, updated_at, category_id, amount,
      date, note, created_by)
    values ('e1', 1, 1, 'ec1', 100, '2026-11-14', '', 'acc-w1')$$,
  'العامل 1 يسجّل مصروفاً دون صلاحية');
select test.sees('select 1 from user_accounts', 7, 'العامل يرى الحسابات');
select test.allowed(
  $$insert into user_accounts (id, created_at, updated_at, email, role,
      entity_id, display_name, must_change_password)
    values ('acc-p9', 1, 1, 'p9@school.local', 'parent', 'p9', '', true)$$,
  'العامل 1 ينشئ حساب وليّ');
select test.denied(
  $$insert into user_accounts (id, created_at, updated_at, email, role,
      entity_id, display_name, must_change_password)
    values ('acc-o2', 1, 1, 'o2@school.local', 'owner', null, '', true)$$,
  'العامل ينشئ حساب مالك');
select test.denied(
  $$update user_accounts set role = 'owner', updated_at = 9 where id = 'acc-w1'$$,
  'العامل يجعل نفسه مالكاً');
select test.sees('select 1 from audit_log', 0, 'العامل 1: سجل العمليات');
select test.logout();

-- عامل بلا أي صلاحية.
select test.login('acc-w2');
select test.sees('select 1 from students', 0, 'العامل 2: التلاميذ');
select test.sees('select 1 from subjects', 1, 'العامل 2: المواد مراجع عامة');
select test.denied(
  $$insert into students (id, created_at, updated_at, first_name, last_name,
      parent_phone, uses_transport, transport_price, qr_code)
    values ('s5', 1, 1, 'ه', 'ه', '0550000005', false, 0, 'S-EEEEEEEEEE')$$,
  'العامل 2 يضيف تلميذاً');
select test.denied(
  $$insert into attendance (id, created_at, updated_at, session_id, student_id,
      status, scanned_at, method)
    values ('att9', 1, 1, 'se2', 's2', 'present', 1, 'qr')$$,
  'العامل 2 يسجّل حضوراً');
select test.allowed(
  $$insert into sms_queue (id, created_at, updated_at, phone, message, status,
      kind, attempts, created_by)
    values ('m1', 1, 1, '+213550000001', 'نص', 'pending', 'custom', 0,
            'acc-w2')$$,
  'أي جهاز إدارة يضيف إلى طابور الرسائل');
select test.sees('select 1 from sms_queue', 1, 'العامل يرى ما وضعه هو في الطابور');
select test.denied(
  $$insert into sms_queue (id, created_at, updated_at, phone, message, status,
      kind, attempts, created_by)
    values ('m2', 1, 1, '+213550000001', 'نص', 'pending', 'custom', 0,
            'acc-owner')$$,
  'العامل يضع رسالة باسم غيره');
select test.denied(
  $$update sms_queue set status = 'sent', updated_at = 2 where id = 'm1'$$,
  'العامل 2 يعلّم الرسالة مُرسلة');
select test.logout();

-- ---------------------------------------------------------------------------
-- الأستاذ: مجموعاته وتلاميذه فقط
-- ---------------------------------------------------------------------------
select test.login('acc-t1');
select test.sees('select 1 from students', 1, 'الأستاذ 1: تلاميذه');
select test.sees('select 1 from teachers', 1, 'الأستاذ 1: سجله فقط');
select test.sees('select 1 from groups', 1, 'الأستاذ 1: مجموعاته');
select test.sees('select 1 from group_students', 1, 'الأستاذ 1: انتسابات مجموعته');
select test.sees('select 1 from sessions', 1, 'الأستاذ 1: حصصه');
select test.sees('select 1 from parents', 1, 'الأستاذ 1: أولياء تلاميذه');
select test.sees('select 1 from teacher_payouts', 1, 'الأستاذ 1: خلاصه');
select test.sees('select 1 from payments', 0, 'الأستاذ 1: لا مدفوعات');
select test.sees('select 1 from workers', 0, 'الأستاذ 1: لا عمال');
select test.sees('select 1 from user_accounts', 1, 'الأستاذ 1: حسابه فقط');
select test.sees('select 1 from chat_user_accounts', 2,
  'الأستاذ 1: حسابه ووليّو مجموعته في عرض المحادثة');
select test.sees(
  $$select 1 from chat_user_accounts where id = 'acc-p1'
    and email = 'chat-contact+6163632d7031@invalid.local'
    and must_change_password = false$$, 1,
  'الأستاذ يرى اسم الوليّ دون بريده أو حالة كلمة سره');
select test.sees(
  $$select 1 from chat_user_accounts where id in ('acc-t2', 'acc-p2')$$, 0,
  'الأستاذ لا يرى حسابات مجموعة أخرى');
select test.sees('select 1 from sms_queue', 0, 'الأستاذ 1: لا طابور رسائل');

select test.allowed(
  $$update attendance set status = 'absent', method = 'manual', updated_at = 5
     where id = 'att1'$$, 'الأستاذ 1 يعدّل حضور مجموعته');
select test.denied(
  $$update attendance set status = 'excused', updated_at = 6 where id = 'att1'$$,
  'الأستاذ يمنح غياباً برخصة');
select test.denied(
  $$insert into attendance (id, created_at, updated_at, session_id, student_id,
      status, scanned_at, method)
    values ('att2', 1, 1, 'se2', 's2', 'present', 1, 'manual')$$,
  'الأستاذ 1 يسجّل حضور مجموعة غيره');

select test.allowed(
  $$update sessions set closed_at = 9, updated_at = 9 where id = 'se1'$$,
  'الأستاذ 1 يغلق حصته');
select test.denied(
  $$update sessions set date = '2026-11-20', updated_at = 10 where id = 'se1'$$,
  'الأستاذ يغيّر موعد حصة');
select test.denied(
  $$update sessions set status = 'cancelled', updated_at = 10 where id = 'se1'$$,
  'الأستاذ يلغي حصة');
select test.denied(
  $$update sessions set closed_at = 9, updated_at = 9 where id = 'se2'$$,
  'الأستاذ 1 يغلق حصة غيره');
select test.allowed(
  $$insert into sessions (id, created_at, updated_at, group_id, cycle_number,
      session_number, date, start_minutes, end_minutes, status)
    values ('se3', 1, 1, 'g1', 1, 2, '2026-11-21', 600, 690, 'normal')$$,
  'الأستاذ 1 ينشئ حصة مطابقة للجدول الأسبوعي');
select test.denied(
  $$insert into sessions (id, created_at, updated_at, group_id, cycle_number,
      session_number, date, start_minutes, end_minutes, status)
    values ('se4', 1, 1, 'g1', 1, 3, '2026-11-22', 600, 690, 'normal')$$,
  'الأستاذ ينشئ حصة خارج الجدول الأسبوعي');
select test.denied(
  $$insert into sessions (id, created_at, updated_at, group_id, cycle_number,
      session_number, date, start_minutes, end_minutes, status)
    values ('se5', 1, 1, 'g1', 1, 3, '2026-11-28', 600, 690, 'added')$$,
  'الأستاذ ينشئ حصة مضافة دون موافقة');

select test.allowed(
  $$insert into session_requests (id, created_at, updated_at, teacher_id,
      group_id, type, session_id, new_date, new_start_minutes,
      new_end_minutes, reason, status, admin_note)
    values ('rq1', 1, 1, 't1', 'g1', 'reschedule', 'se3', '2026-11-23', 600,
            690, 'ظرف', 'pending', '')$$, 'الأستاذ 1 يرسل طلباً');
select test.denied(
  $$insert into session_requests (id, created_at, updated_at, teacher_id,
      group_id, type, reason, status, admin_note)
    values ('rq2', 1, 1, 't1', 'g1', 'add', '', 'approved', '')$$,
  'الأستاذ يرسل طلباً مقبولاً مسبقاً');
select test.denied(
  $$insert into session_requests (id, created_at, updated_at, teacher_id,
      group_id, type, reason, status, admin_note)
    values ('rq3', 1, 1, 't1', 'g2', 'add', '', 'pending', '')$$,
  'الأستاذ 1 يرسل طلباً لمجموعة غيره');
select test.denied(
  $$update session_requests set status = 'approved', updated_at = 5
     where id = 'rq1'$$, 'الأستاذ يوافق على طلبه');

select test.allowed(
  $$insert into grades (id, created_at, updated_at, student_id, group_id,
      title, score, max_score, note, date)
    values ('gr1', 1, 1, 's1', 'g1', 'فرض 1', 15, 20, '', '2026-11-14')$$,
  'الأستاذ 1 يسجّل نتيجة لمجموعته');
select test.denied(
  $$insert into grades (id, created_at, updated_at, student_id, group_id,
      title, score, max_score, note, date)
    values ('gr2', 1, 1, 's2', 'g2', 'فرض 1', 15, 20, '', '2026-11-14')$$,
  'الأستاذ 1 يسجّل نتيجة لمجموعة غيره');
select test.denied(
  $$update groups set rate_per_student = 99999, updated_at = 5 where id = 'g1'$$,
  'الأستاذ يرفع مبلغه');
select test.denied(
  $$update teacher_payouts set amount = 99999, updated_at = 5 where id = 'po1'$$,
  'الأستاذ يعدّل خلاصه');
select test.allowed(
  $$update user_accounts set must_change_password = false, updated_at = 5
     where id = 'acc-t1'$$, 'الأستاذ يحدّث حسابه بعد تغيير كلمة السر');
select test.denied(
  $$update user_accounts set role = 'owner', updated_at = 6 where id = 'acc-t1'$$,
  'الأستاذ يجعل نفسه مالكاً');
select test.allowed(
  $$insert into audit_log (id, user_id, user_name, action, entity, entity_id,
      created_at, updated_at)
    values ('au1', 'acc-t1', 'كريم', 'create', 'grades', 'gr1', 1, 1)$$,
  'الأستاذ يكتب في سجل العمليات باسمه');
select test.denied(
  $$insert into audit_log (id, user_id, user_name, action, entity, entity_id,
      created_at, updated_at)
    values ('au2', 'acc-owner', 'المدير', 'create', 'grades', 'gr1', 1, 1)$$,
  'الأستاذ يكتب في السجل باسم المدير');
select test.allowed(
  $$insert into notifications (id, created_at, updated_at, user_id, sender_id,
      title, body, kind)
    values ('n3', 1, 1, 'acc-owner', 'acc-t1', 'طلب جديد', 'نص',
            'request_pending')$$,
  'الأستاذ يرسل إشعاراً للمدير');
select test.denied(
  $$insert into notifications (id, created_at, updated_at, user_id, sender_id,
      title, body, kind)
    values ('n4', 1, 1, 'acc-p1', 'acc-owner', 'انتحال', 'نص', 'info')$$,
  'الأستاذ يرسل إشعاراً باسم المدير');
select test.denied(
  $$update notifications set title = 'معدَّل', updated_at = 5 where id = 'n3'$$,
  'المرسل يعدّل إشعاراً بعد إرساله');
select test.logout();

-- المدير يراجع الطلب، وسجل العمليات لا يُعدَّل.
select test.login('acc-owner');
select test.sees('select 1 from session_requests', 1, 'المالك يرى الطلب');
select test.allowed(
  $$update session_requests set status = 'approved', reviewed_by = 'acc-owner',
      reviewed_at = 9, updated_at = 9 where id = 'rq1'$$,
  'المالك يوافق على الطلب');
select test.sees('select 1 from audit_log', 1, 'المالك يقرأ سجل العمليات');
select test.denied(
  $$update audit_log set action = 'x', updated_at = 9 where id = 'au1'$$,
  'سجل العمليات لا يُعدَّل حتى من المالك');
select test.sees('select 1 from notifications', 3, 'المالك: ما استلمه وما أرسله');
select test.logout();

-- ---------------------------------------------------------------------------
-- الوليّ: أبناؤه فقط
-- ---------------------------------------------------------------------------
select test.login('acc-p1');
select test.sees('select 1 from students', 1, 'الوليّ 1: أبناؤه');
select test.sees('select 1 from group_students', 1, 'الوليّ 1: انتسابات أبنائه');
select test.sees('select 1 from sessions', 2, 'الوليّ 1: حصص مجموعة ابنه');
select test.sees('select 1 from attendance', 1, 'الوليّ 1: حضور ابنه');
select test.sees('select 1 from payments', 2, 'الوليّ 1: مدفوعات ابنه');
select test.sees('select 1 from grades', 1, 'الوليّ 1: نتائج ابنه');
select test.sees('select 1 from notifications', 1, 'الوليّ 1: إشعاراته');
select test.sees('select 1 from teachers', 0, 'الوليّ لا يقرأ جدول الأساتذة');
select test.sees('select 1 from groups', 0, 'الوليّ لا يقرأ جدول المجموعات');
select test.sees(
  $$select 1 from teacher_cards
     where id = 't1' and email = '' and phone = '' and rate_per_student = 0
       and qr_code not like 'T-%'$$, 1,
  'الوليّ يرى بطاقة أستاذ ابنه دون البريد والرمز والمبلغ');
select test.sees('select 1 from teacher_cards', 1, 'الوليّ: أساتذة أبنائه فقط');
select test.sees(
  'select 1 from group_cards where rate_per_student is null', 1,
  'الوليّ يرى مجموعة ابنه دون مبلغ الأستاذ');
select test.sees('select 1 from teacher_payouts', 0, 'الوليّ: لا خلاص');
select test.sees('select 1 from workers', 0, 'الوليّ: لا عمال');
select test.sees('select 1 from sms_queue', 0, 'الوليّ: لا طابور رسائل');
select test.sees('select 1 from audit_log', 0, 'الوليّ: لا سجل عمليات');
select test.sees('select 1 from parents', 1, 'الوليّ: سجله فقط');
select test.sees('select 1 from user_accounts', 1, 'الوليّ: حسابه فقط');
select test.sees('select 1 from chat_user_accounts', 2,
  'الوليّ 1: حسابه وأستاذ ابنه في عرض المحادثة');
select test.sees(
  $$select 1 from chat_user_accounts where id = 'acc-t1'
    and email = 'chat-contact+6163632d7431@invalid.local'
    and must_change_password = false$$, 1,
  'الوليّ يرى اسم الأستاذ دون بريده أو حالة كلمة سره');
select test.sees(
  $$select 1 from chat_user_accounts where id in ('acc-t2', 'acc-p2')$$, 0,
  'الوليّ لا يرى حسابات مجموعة أخرى');
select test.denied(
  $$insert into attendance (id, created_at, updated_at, session_id, student_id,
      status, scanned_at, method)
    values ('att3', 1, 1, 'se3', 's1', 'present', 1, 'manual')$$,
  'الوليّ يسجّل حضور ابنه');
select test.denied(
  $$update attendance set status = 'present', updated_at = 20 where id = 'att1'$$,
  'الوليّ يعدّل حضور ابنه');
select test.denied(
  $$insert into payments (id, created_at, updated_at, student_id, type,
      amount, received_by, receipt_number, note)
    values ('pay9', 1, 1, 's1', 'registration', 500, 'acc-p1', 'Z-000001', '')$$,
  'الوليّ يسجّل دفعة لنفسه');
select test.denied(
  $$update students set parent_account_id = 'p1', updated_at = 20
     where id = 's2'$$, 'الوليّ يربط تلميذاً آخر بحسابه');
select test.allowed(
  $$update notifications set read_at = 5, updated_at = 5 where id = 'n1'$$,
  'الوليّ يعلّم إشعاره مقروءاً');
select test.denied(
  $$update notifications set read_at = 5, updated_at = 5 where id = 'n2'$$,
  'الوليّ يعدّل إشعار غيره');

-- المحادثات: الوليّ يفتح غرفة مع أستاذ ابنه.
select test.allowed(
  $$insert into chat_rooms (id, created_at, updated_at, type, group_id, title,
      created_by, is_closed)
    values ('room1', 1, 1, 'private', null, '', 'acc-p1', false)$$,
  'الوليّ 1 ينشئ غرفة');
select test.allowed(
  $$insert into chat_members (id, created_at, updated_at, room_id, user_id,
      user_role, last_read_at, muted)
    values ('cm1', 1, 1, 'room1', 'acc-p1', 'parent', 0, false),
           ('cm2', 1, 1, 'room1', 'acc-t1', 'teacher', 0, false)$$,
  'منشئ الغرفة يضيف أعضاءها');
select test.allowed(
  $$insert into chat_messages (id, created_at, updated_at, room_id, sender_id,
      sender_role, content)
    values ('msg1', 1, 1, 'room1', 'acc-p1', 'parent', 'السلام عليكم')$$,
  'العضو يرسل رسالة');
select test.denied(
  $$insert into chat_messages (id, created_at, updated_at, room_id, sender_id,
      sender_role, content)
    values ('msg-spoof-parent', 1, 1, 'room1', 'acc-p1', 'owner', 'انتحال الدور')$$,
  'العضو لا ينتحل دوراً آخر في الرسالة');
select test.denied(
  $$insert into chat_rooms (id, created_at, updated_at, type, group_id, title,
      created_by, is_closed)
    values ('room-parent-group', 1, 1, 'group', 'g1', 'غير مسموح',
      'acc-p1', false)$$,
  'الوليّ لا ينشئ غرفة مجموعة');
select test.allowed(
  $$insert into chat_rooms (id, created_at, updated_at, type, group_id, title,
      created_by, is_closed)
    values ('room-parent-private', 1, 1, 'private', null, '',
      'acc-p1', false)$$,
  'الوليّ ينشئ غرفة خاصة');
select test.denied(
  $$insert into chat_members (id, created_at, updated_at, room_id, user_id,
      user_role, last_read_at, muted)
    values ('cm-outsider', 1, 1, 'room-parent-private', 'acc-p2', 'parent', 0, false)$$,
  'الوليّ لا يضيف وليّاً من خارج مجموعته');
select test.logout();

select test.login('acc-t1');
select test.allowed(
  $$insert into chat_rooms (id, created_at, updated_at, type, group_id, title,
      created_by, is_closed)
    values ('room-teacher-group', 1, 1, 'group', 'g1', 'مجموعة الأستاذ',
      'acc-t1', false)$$,
  'أستاذ المجموعة ينشئ غرفتها');
select test.allowed(
  $$insert into chat_members (id, created_at, updated_at, room_id, user_id,
      user_role, last_read_at, muted)
    values ('tm-t1', 1, 1, 'room-teacher-group', 'acc-t1', 'teacher', 0, false),
           ('tm-p1', 1, 1, 'room-teacher-group', 'acc-p1', 'parent', 0, false)$$,
  'أستاذ المجموعة يضيف نفسه والوليّ النشط');
select test.denied(
  $$insert into chat_members (id, created_at, updated_at, room_id, user_id,
      user_role, last_read_at, muted)
    values ('tm-p2', 1, 1, 'room-teacher-group', 'acc-p2', 'parent', 0, false)$$,
  'أستاذ المجموعة لا يضيف وليّاً من مجموعة أخرى');
select test.denied(
  $$insert into chat_rooms (id, created_at, updated_at, type, group_id, title,
      created_by, is_closed)
    values ('room-teacher-other-group', 1, 1, 'group', 'g2', 'مجموعة أخرى',
      'acc-t1', false)$$,
  'الأستاذ لا ينشئ غرفة مجموعة أستاذ آخر');
select test.denied(
  $$insert into chat_messages (id, created_at, updated_at, room_id, sender_id,
      sender_role, content)
    values ('msg2', 1, 1, 'room1', 'acc-p1', 'parent', 'انتحال')$$,
  'الأستاذ لا يرسل رسالة باسم وليّ آخر');
select test.logout();

select test.login('acc-t1');
select test.sees('select 1 from chat_messages', 1, 'الأستاذ العضو يقرأ الرسائل');
select test.allowed(
  $$insert into chat_messages (id, created_at, updated_at, room_id, sender_id,
      sender_role, content)
    values ('msg3', 2, 2, 'room1', 'acc-t1', 'teacher', 'وعليكم السلام')$$,
  'الأستاذ العضو يرد');
select test.allowed(
  $$update chat_rooms set last_message_at = 2, updated_at = 2 where id = 'room1'$$,
  'العضو يحدّث وقت آخر رسالة');
select test.denied(
  $$update chat_rooms set is_closed = true, updated_at = 2 where id = 'room1'$$,
  'العضو لا يغلق الغرفة بنفسه');
select test.allowed(
  $$update chat_members set last_read_at = 5, muted = true, updated_at = 5
     where id = 'cm2'$$, 'العضو يحدّث «مقروء» والكتم');
select test.logout();

select test.login('acc-p2');
select test.sees('select 1 from chat_rooms', 0, 'غير العضو لا يرى الغرفة');
select test.sees('select 1 from chat_messages', 0, 'غير العضو لا يقرأ الرسائل');
select test.sees('select 1 from chat_members', 0, 'غير العضو لا يرى الأعضاء');
select test.denied(
  $$insert into chat_messages (id, created_at, updated_at, room_id, sender_id,
      sender_role, content)
    values ('msg4', 1, 1, 'room1', 'acc-p2', 'parent', 'دخيل')$$,
  'غير العضو يرسل رسالة');
select test.denied(
  $$insert into chat_members (id, created_at, updated_at, room_id, user_id,
      user_role, last_read_at, muted)
    values ('cm3', 1, 1, 'room1', 'acc-p2', 'parent', 0, false)$$,
  'غير العضو يضيف نفسه إلى غرفة');
select test.sees('select 1 from students', 1, 'الوليّ 2: ابنه فقط');
select test.sees('select 1 from payments', 1, 'الوليّ 2: مدفوعات ابنه فقط');
select test.logout();

-- المدير يراقب ويدير المحادثات.
select test.login('acc-owner');
select test.sees('select 1 from chat_messages', 2, 'المالك يرى كل الرسائل');
select test.allowed(
  $$insert into chat_messages (id, created_at, updated_at, room_id, sender_id,
      sender_role, content)
    values ('msg-owner', 3, 3, 'room1', 'acc-owner', 'owner', 'رسالة من الإدارة')$$,
  'المالك يكتب في غرفة يراقبها');
select test.logout();

select test.login('acc-owner');
select test.allowed(
  $$update workers set permissions = '{"chat":["edit"]}', updated_at = 4
     where id = 'w2'$$,
  'المالك يفعّل مراقبة المحادثات للعامل 2');
select test.logout();

select test.login('acc-w2');
select test.sees('select 1 where app.can(''chat'', ''edit'')', 1,
  'العامل يملك صلاحية تعديل المحادثات');
select test.sees('select 1 from chat_rooms where id = ''room1''', 1,
  'العامل المراقب يرى الغرفة');
select test.sees('select 1 from chat_messages where room_id = ''room1''', 3,
  'العامل المراقب يرى الرسائل السابقة');
select test.allowed(
  $$insert into chat_messages (id, created_at, updated_at, room_id, sender_id,
      sender_role, content)
    values ('msg-worker', 4, 4, 'room1', 'acc-w2', 'worker', 'رسالة من العامل')$$,
  'العامل المراقب يكتب وهو غير عضو');
select test.denied(
  $$insert into chat_messages (id, created_at, updated_at, room_id, sender_id,
      sender_role, content)
    values ('msg-spoof-role', 5, 5, 'room1', 'acc-w2', 'owner', 'انتحال الدور')$$,
  'العامل لا ينتحل دوراً آخر في الرسالة');
select test.logout();

select test.login('acc-owner');
select test.allowed(
  $$update chat_messages set deleted_at = 9, updated_at = 9 where id = 'msg3'$$,
  'المالك يحذف رسالة');
select test.allowed(
  $$update chat_members set deleted_at = 9, updated_at = 9 where id = 'cm1'$$,
  'المالك يزيل عضواً');
select test.allowed(
  $$update chat_rooms set is_closed = true, updated_at = 9 where id = 'room1'$$,
  'المالك يغلق الغرفة');
select test.logout();

select test.login('acc-t1');
select test.denied(
  $$insert into chat_messages (id, created_at, updated_at, room_id, sender_id,
      sender_role, content)
    values ('msg5', 3, 3, 'room1', 'acc-t1', 'teacher', 'بعد الإغلاق')$$,
  'لا رسائل في غرفة مغلقة');
select test.logout();

select test.login('acc-p1');
select test.sees('select 1 from chat_messages', 0,
  'العضو المُزال لا يقرأ الرسائل');
select test.logout();

-- وليّ غادر مجموعة لا يرى غرفتها حتى لو لم يصل تحديث عضويته في المحادثة بعد.
select test.login('acc-owner');
select test.allowed(
  $$insert into chat_rooms (id, created_at, updated_at, type, group_id, title,
      created_by, is_closed)
    values ('room-group', 10, 10, 'group', 'g1', 'المجموعة 1',
      'acc-owner', false)$$,
  'المالك ينشئ غرفة مجموعة');
select test.allowed(
  $$insert into chat_members (id, created_at, updated_at, room_id, user_id,
      user_role, last_read_at, muted)
    values ('gm-p1', 10, 10, 'room-group', 'acc-p1', 'parent', 0, false),
           ('gm-t1', 10, 10, 'room-group', 'acc-t1', 'teacher', 0, false)$$,
  'المالك يضيف أعضاء غرفة المجموعة');
select test.allowed(
  $$insert into chat_messages (id, created_at, updated_at, room_id, sender_id,
      sender_role, content)
    values ('gm-msg', 10, 10, 'room-group', 'acc-owner', 'owner', 'رسالة المجموعة')$$,
  'المالك يكتب في غرفة المجموعة');
select test.logout();

select test.login('acc-p1');
select test.allowed(
  $$insert into chat_messages (id, created_at, updated_at, room_id, sender_id,
      sender_role, content)
    values ('gm-p-msg', 11, 11, 'room-group', 'acc-p1', 'parent', 'ردّ الولي')$$,
  'الوليّ النشط يرد في غرفة المجموعة');
select test.logout();

select test.login('acc-t1');
select test.denied(
  $$update chat_members set deleted_at = 12, updated_at = 12 where id = 'gm-p1'$$,
  'أستاذ المجموعة لا يزيل وليّاً ما زال منتسباً');
select test.logout();

select test.login('acc-owner');
select test.allowed(
  $$update group_students set left_at = 12, updated_at = 12 where id = 'gs1'$$,
  'المالك يحدّث خروج التلميذ من المجموعة');
select test.logout();

select test.login('acc-t1');
select test.allowed(
  $$update chat_members set deleted_at = 13, updated_at = 13 where id = 'gm-p1'$$,
  'أستاذ المجموعة يزامن إزالة الوليّ بعد مغادرته');
select test.logout();

select test.login('acc-p1');
select test.sees('select 1 from chat_rooms where id = ''room-group''', 0,
  'وليّ غادر المجموعة لا يرى غرفتها');
select test.sees('select 1 from chat_messages where room_id = ''room-group''', 0,
  'وليّ غادر المجموعة لا يقرأ رسائلها');
select test.denied(
  $$insert into chat_messages (id, created_at, updated_at, room_id, sender_id,
      sender_role, content)
    values ('gm-msg-p1', 13, 13, 'room-group', 'acc-p1', 'parent', 'بعد المغادرة')$$,
  'وليّ غادر المجموعة لا يرسل إلى غرفتها');
select test.denied(
  $$update chat_messages set deleted_at = 14, updated_at = 14
     where id = 'gm-p-msg'$$,
  'وليّ غادر المجموعة لا يعدّل رسائله القديمة');
select test.denied(
  $$update chat_members set muted = true, updated_at = 15 where id = 'gm-p1'$$,
  'وليّ غادر المجموعة لا يحدّث كتم الغرفة');
select test.logout();

select test.login('acc-t1');
select test.sees('select 1 from chat_messages where room_id = ''room-group''', 2,
  'أستاذ المجموعة النشط يقرأ رسائل الغرفة قبل مغادرة الوليّ');
select test.logout();
