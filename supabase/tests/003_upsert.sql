-- الأجهزة ترسل «إضافة أو تحديث» (INSERT ... ON CONFLICT DO UPDATE).
-- هذه الاختبارات تثبت أن الصلاحيات تعمل مع هذه الصيغة كما تعمل مع
-- الإضافة والتحديث الصريحين. تعتمد على بيانات 002_rls.sql.

-- عامل يملك «تعديل التلاميذ» دون «الإضافة».
select test.login('acc-owner');
select test.allowed(
  $$update workers
       set permissions = '{"students": ["view", "edit"], "attendance": ["view", "edit"]}',
           updated_at = 50
     where id = 'w2'$$, 'المالك يمنح العامل 2 التعديل دون الإضافة');
select test.logout();

select test.login('acc-w2');
select test.allowed(
  $$insert into students (id, created_at, updated_at, first_name, last_name,
      parent_phone, uses_transport, transport_price, qr_code, parent_account_id)
    values ('s1', 1, 60, 'أحمد المعدَّل', 'أ', '0550000001', false, 0,
            'S-AAAAAAAAAA', 'p1')
    on conflict (id) do update set
      first_name = excluded.first_name, updated_at = excluded.updated_at$$,
  'صاحب «التعديل» يحدّث سجلاً موجوداً عبر upsert');
select test.sees(
  $$select 1 from students where id = 's1' and first_name = 'أحمد المعدَّل'$$,
  1, 'التحديث عبر upsert طُبّق');
select test.denied(
  $$insert into students (id, created_at, updated_at, first_name, last_name,
      parent_phone, uses_transport, transport_price, qr_code)
    values ('s77', 1, 1, 'جديد', 'ج', '0550000077', false, 0, 'S-GGGGGGGGGG')
    on conflict (id) do update set
      first_name = excluded.first_name, updated_at = excluded.updated_at$$,
  'صاحب «التعديل» دون «الإضافة» ينشئ سجلاً جديداً عبر upsert');
select test.sees($$select 1 from students where id = 's77'$$, 0,
  'السجل الممنوع لم يُنشأ');
select test.denied(
  $$insert into students (id, created_at, updated_at, first_name, last_name,
      parent_phone, uses_transport, transport_price, qr_code, parent_account_id,
      deleted_at)
    values ('s1', 1, 70, 'أحمد', 'أ', '0550000001', false, 0, 'S-AAAAAAAAAA',
            'p1', 70)
    on conflict (id) do update set
      deleted_at = excluded.deleted_at, updated_at = excluded.updated_at$$,
  'صاحب «التعديل» دون «الحذف» يحذف حذفاً ناعماً عبر upsert');
select test.allowed(
  $$insert into attendance (id, created_at, updated_at, session_id, student_id,
      status, scanned_at, method)
    values ('att1', 1, 80, 'se1', 's1', 'excused', null, 'manual')
    on conflict (id) do update set
      status = excluded.status, method = excluded.method,
      updated_at = excluded.updated_at$$,
  'العامل المخوَّل يمنح غياباً برخصة عبر upsert');
select test.logout();

-- upsert أقدم من المخزَّن يُتجاهل دون خطأ (آخر تعديل يفوز).
select test.login('acc-owner');
select test.denied(
  $$insert into students (id, created_at, updated_at, first_name, last_name,
      parent_phone, uses_transport, transport_price, qr_code, parent_account_id)
    values ('s1', 1, 10, 'نسخة قديمة', 'أ', '0550000001', false, 0,
            'S-AAAAAAAAAA', 'p1')
    on conflict (id) do update set
      first_name = excluded.first_name, updated_at = excluded.updated_at$$,
  'upsert أقدم لا يمسّ الصف');
select test.sees(
  $$select 1 from students where id = 's1' and first_name = 'أحمد المعدَّل'$$,
  1, 'النسخة الأحدث بقيت');
select test.logout();

-- الأستاذ: يحدّث حضور مجموعته عبر upsert، ولا يمنح رخصة.
select test.login('acc-t1');
select test.allowed(
  $$insert into attendance (id, created_at, updated_at, session_id, student_id,
      status, scanned_at, method)
    values ('att1', 1, 90, 'se1', 's1', 'present', 90, 'manual')
    on conflict (id) do update set
      status = excluded.status, updated_at = excluded.updated_at$$,
  'الأستاذ يحدّث حضور مجموعته عبر upsert');
select test.denied(
  $$insert into attendance (id, created_at, updated_at, session_id, student_id,
      status, scanned_at, method)
    values ('att1', 1, 95, 'se1', 's1', 'excused', null, 'manual')
    on conflict (id) do update set
      status = excluded.status, updated_at = excluded.updated_at$$,
  'الأستاذ يمنح رخصة عبر upsert');
select test.denied(
  $$insert into session_requests (id, created_at, updated_at, teacher_id,
      group_id, type, reason, status, admin_note)
    values ('rq1', 1, 99, 't1', 'g1', 'reschedule', '', 'pending', '')
    on conflict (id) do update set
      status = excluded.status, reviewed_by = null, updated_at = excluded.updated_at$$,
  'الأستاذ يعيد طلبه المراجَع إلى الانتظار عبر upsert');

-- إشعار لمستخدم آخر: المرسل يراه (لأنه مرسله) فيُقبل بصيغة upsert.
select test.allowed(
  $$insert into notifications (id, created_at, updated_at, user_id, sender_id,
      title, body, kind)
    values ('n9', 1, 1, 'acc-owner', 'acc-t1', 'طلب', 'نص', 'request_pending')
    on conflict (id) do update set
      title = excluded.title, updated_at = excluded.updated_at$$,
  'إرسال إشعار لمستخدم آخر عبر upsert');
select test.denied(
  $$insert into notifications (id, created_at, updated_at, user_id, sender_id,
      title, body, kind)
    values ('n9', 1, 5, 'acc-owner', 'acc-t1', 'معدَّل', 'نص', 'request_pending')
    on conflict (id) do update set
      title = excluded.title, updated_at = excluded.updated_at$$,
  'المرسل يعدّل إشعاره بعد إرساله عبر upsert');

-- سجل العمليات: إضافة مع تجاهل المكرر (إعادة إرسال بعد انقطاع).
select test.allowed(
  $$insert into audit_log (id, user_id, user_name, action, entity, entity_id,
      created_at, updated_at)
    values ('au7', 'acc-t1', 'كريم', 'update', 'attendance', 'att1', 5, 5)
    on conflict (id) do nothing$$, 'سجل عمليات جديد');
insert into audit_log (id, user_id, user_name, action, entity, entity_id,
                       created_at, updated_at)
values ('au7', 'acc-t1', 'كريم', 'مزوَّر', 'attendance', 'att1', 9, 9)
on conflict (id) do nothing;
select test.logout();

select test.login('acc-owner');
select test.sees(
  $$select 1 from audit_log where id = 'au7' and action = 'update'$$, 1,
  'إعادة إرسال السجل لا تغيّره');
select test.sees($$select 1 from notifications where id = 'n9'$$, 1,
  'الإشعار وصل صاحبه');
select test.allowed(
  $$insert into notifications (id, created_at, updated_at, user_id, sender_id,
      title, body, kind, read_at)
    values ('n9', 1, 5, 'acc-owner', 'acc-t1', 'طلب', 'نص', 'request_pending', 5)
    on conflict (id) do update set
      read_at = excluded.read_at, updated_at = excluded.updated_at$$,
  'صاحب الإشعار يعلّمه مقروءاً عبر upsert');
select test.logout();

-- عامل دون صلاحية عرض الرسائل يضيف إلى الطابور عبر upsert.
select test.login('acc-w2');
select test.allowed(
  $$insert into sms_queue (id, created_at, updated_at, phone, message, status,
      kind, attempts, created_by)
    values ('m7', 1, 1, '+213550000001', 'نص', 'pending', 'custom', 0,
            'acc-w2')
    on conflict (id) do update set
      status = excluded.status, updated_at = excluded.updated_at$$,
  'إضافة رسالة إلى الطابور عبر upsert');
select test.denied(
  $$insert into sms_queue (id, created_at, updated_at, phone, message, status,
      kind, attempts, created_by)
    values ('m7', 1, 5, '+213550000001', 'نص', 'sent', 'custom', 0, 'acc-w2')
    on conflict (id) do update set
      status = excluded.status, updated_at = excluded.updated_at$$,
  'العامل دون صلاحية الإرسال يعلّم رسالته مُرسلة');
select test.logout();

select test.login('acc-owner');
select test.allowed(
  $$insert into sms_queue (id, created_at, updated_at, phone, message, status,
      kind, attempts, sent_at, created_by)
    values ('m7', 1, 9, '+213550000001', 'نص', 'sent', 'custom', 1, 9, 'acc-w2')
    on conflict (id) do update set
      status = excluded.status, attempts = excluded.attempts,
      sent_at = excluded.sent_at, updated_at = excluded.updated_at$$,
  'هاتف المدير يحدّث حالة الرسالة عبر upsert');
select test.logout();

-- الوليّ لا يكتب شيئاً عبر upsert أيضاً.
select test.login('acc-p1');
select test.denied(
  $$insert into attendance (id, created_at, updated_at, session_id, student_id,
      status, scanned_at, method)
    values ('att1', 1, 200, 'se1', 's1', 'present', 1, 'manual')
    on conflict (id) do update set
      status = excluded.status, updated_at = excluded.updated_at$$,
  'الوليّ يعدّل حضور ابنه عبر upsert');
select test.denied(
  $$insert into payments (id, created_at, updated_at, student_id, type,
      group_id, cycle_number, amount, received_by, receipt_number, note)
    values ('pay1', 1, 200, 's1', 'month', 'g1', 1, 1, 'acc-owner',
            'A-000001', '')
    on conflict (id) do update set
      amount = excluded.amount, updated_at = excluded.updated_at$$,
  'الوليّ يغيّر مبلغ دفعة عبر upsert');
select test.logout();
