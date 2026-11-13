-- ملف مولَّد من مخطط القاعدة المحلية. لا تعدّله يدوياً.
-- لإعادة توليده: UPDATE_SCHEMA=1 flutter test test/data/supabase_schema_test.dart

create sequence if not exists public.sync_seq;

-- «آخر تعديل يفوز»: تحديث أقدم من المخزَّن يُتجاهل.
-- `synced_at` رقم متزايد يسحب به كل جهاز ما تغيّر بعد آخر سحب.
create or replace function public.sync_stamp()
returns trigger language plpgsql as $$
begin
  if tg_op = 'UPDATE' and new.updated_at < old.updated_at then
    return null;
  end if;
  new.synced_at := nextval('public.sync_seq');
  return new;
end
$$;

create table if not exists public."attendance" (
  "id" text not null,
  "created_at" bigint not null,
  "updated_at" bigint not null,
  "deleted_at" bigint,
  "session_id" text not null,
  "student_id" text not null,
  "status" text not null,
  "scanned_at" bigint,
  "method" text not null,
  "synced_at" bigint not null default 0,
  primary key ("id")
);
create unique index if not exists "idx_attendance_pair" on public."attendance" (session_id, student_id);
create index if not exists "idx_attendance_student" on public."attendance" (student_id, status);
create index if not exists "idx_attendance_updated" on public."attendance" (updated_at);
create index if not exists "idx_attendance_synced" on public."attendance" (synced_at);
drop trigger if exists trg_sync_stamp on public."attendance";
create trigger trg_sync_stamp before insert or update on public."attendance"
  for each row execute function public.sync_stamp();

create table if not exists public."audit_log" (
  "id" text not null,
  "user_id" text not null,
  "user_name" text not null,
  "action" text not null,
  "entity" text not null,
  "entity_id" text not null,
  "before" text,
  "after" text,
  "created_at" bigint not null,
  "updated_at" bigint not null,
  "synced_at" bigint not null default 0,
  primary key ("id")
);
create index if not exists "idx_audit_log_created" on public."audit_log" (created_at);
create index if not exists "idx_audit_log_entity" on public."audit_log" (entity, entity_id);
create index if not exists "idx_audit_log_updated" on public."audit_log" (updated_at);
create index if not exists "idx_audit_log_user" on public."audit_log" (user_id, created_at);
create index if not exists "idx_audit_log_synced" on public."audit_log" (synced_at);
drop trigger if exists trg_sync_stamp on public."audit_log";
create trigger trg_sync_stamp before insert or update on public."audit_log"
  for each row execute function public.sync_stamp();

create table if not exists public."chat_members" (
  "id" text not null,
  "created_at" bigint not null,
  "updated_at" bigint not null,
  "deleted_at" bigint,
  "room_id" text not null,
  "user_id" text not null,
  "user_role" text not null,
  "last_read_at" bigint not null,
  "muted" boolean not null,
  "synced_at" bigint not null default 0,
  primary key ("id")
);
create unique index if not exists "idx_chat_members_pair" on public."chat_members" (room_id, user_id);
create index if not exists "idx_chat_members_updated" on public."chat_members" (updated_at);
create index if not exists "idx_chat_members_user" on public."chat_members" (user_id);
create index if not exists "idx_chat_members_synced" on public."chat_members" (synced_at);
drop trigger if exists trg_sync_stamp on public."chat_members";
create trigger trg_sync_stamp before insert or update on public."chat_members"
  for each row execute function public.sync_stamp();

create table if not exists public."chat_messages" (
  "id" text not null,
  "created_at" bigint not null,
  "updated_at" bigint not null,
  "deleted_at" bigint,
  "room_id" text not null,
  "sender_id" text not null,
  "sender_role" text not null,
  "content" text not null,
  "attachment_url" text,
  "attachment_name" text,
  "attachment_type" text,
  "attachment_local_path" text,
  "synced_at" bigint not null default 0,
  primary key ("id")
);
create index if not exists "idx_chat_messages_room" on public."chat_messages" (room_id, created_at);
create index if not exists "idx_chat_messages_updated" on public."chat_messages" (updated_at);
create index if not exists "idx_chat_messages_synced" on public."chat_messages" (synced_at);
drop trigger if exists trg_sync_stamp on public."chat_messages";
create trigger trg_sync_stamp before insert or update on public."chat_messages"
  for each row execute function public.sync_stamp();

create table if not exists public."chat_rooms" (
  "id" text not null,
  "created_at" bigint not null,
  "updated_at" bigint not null,
  "deleted_at" bigint,
  "type" text not null,
  "group_id" text,
  "title" text not null,
  "created_by" text not null,
  "is_closed" boolean not null,
  "last_message_at" bigint,
  "synced_at" bigint not null default 0,
  primary key ("id")
);
create index if not exists "idx_chat_rooms_group" on public."chat_rooms" (group_id);
create index if not exists "idx_chat_rooms_last" on public."chat_rooms" (last_message_at);
create index if not exists "idx_chat_rooms_updated" on public."chat_rooms" (updated_at);
create index if not exists "idx_chat_rooms_synced" on public."chat_rooms" (synced_at);
drop trigger if exists trg_sync_stamp on public."chat_rooms";
create trigger trg_sync_stamp before insert or update on public."chat_rooms"
  for each row execute function public.sync_stamp();

create table if not exists public."expense_categories" (
  "id" text not null,
  "created_at" bigint not null,
  "updated_at" bigint not null,
  "deleted_at" bigint,
  "name" text not null,
  "is_wages" boolean not null,
  "synced_at" bigint not null default 0,
  primary key ("id")
);
create index if not exists "idx_expense_categories_name" on public."expense_categories" (name);
create index if not exists "idx_expense_categories_updated" on public."expense_categories" (updated_at);
create index if not exists "idx_expense_categories_synced" on public."expense_categories" (synced_at);
drop trigger if exists trg_sync_stamp on public."expense_categories";
create trigger trg_sync_stamp before insert or update on public."expense_categories"
  for each row execute function public.sync_stamp();

create table if not exists public."expenses" (
  "id" text not null,
  "created_at" bigint not null,
  "updated_at" bigint not null,
  "deleted_at" bigint,
  "category_id" text not null,
  "amount" bigint not null,
  "date" text not null,
  "note" text not null,
  "invoice_photo_url" text,
  "invoice_photo_local_path" text,
  "worker_id" text,
  "created_by" text not null,
  "synced_at" bigint not null default 0,
  primary key ("id")
);
create index if not exists "idx_expenses_category_date" on public."expenses" (category_id, date);
create index if not exists "idx_expenses_date" on public."expenses" (date);
create index if not exists "idx_expenses_updated" on public."expenses" (updated_at);
create index if not exists "idx_expenses_synced" on public."expenses" (synced_at);
drop trigger if exists trg_sync_stamp on public."expenses";
create trigger trg_sync_stamp before insert or update on public."expenses"
  for each row execute function public.sync_stamp();

create table if not exists public."grades" (
  "id" text not null,
  "created_at" bigint not null,
  "updated_at" bigint not null,
  "deleted_at" bigint,
  "student_id" text not null,
  "group_id" text not null,
  "title" text not null,
  "score" double precision not null,
  "max_score" double precision not null,
  "note" text not null,
  "date" text not null,
  "synced_at" bigint not null default 0,
  primary key ("id")
);
create index if not exists "idx_grades_group" on public."grades" (group_id, date);
create index if not exists "idx_grades_student" on public."grades" (student_id, date);
create index if not exists "idx_grades_updated" on public."grades" (updated_at);
create index if not exists "idx_grades_synced" on public."grades" (synced_at);
drop trigger if exists trg_sync_stamp on public."grades";
create trigger trg_sync_stamp before insert or update on public."grades"
  for each row execute function public.sync_stamp();

create table if not exists public."group_files" (
  "id" text not null,
  "created_at" bigint not null,
  "updated_at" bigint not null,
  "deleted_at" bigint,
  "group_id" text not null,
  "title" text not null,
  "file_url" text,
  "file_name" text not null,
  "size_bytes" bigint not null,
  "local_path" text,
  "uploaded_by" text not null,
  "synced_at" bigint not null default 0,
  primary key ("id")
);
create index if not exists "idx_group_files_group" on public."group_files" (group_id, created_at);
create index if not exists "idx_group_files_updated" on public."group_files" (updated_at);
create index if not exists "idx_group_files_synced" on public."group_files" (synced_at);
drop trigger if exists trg_sync_stamp on public."group_files";
create trigger trg_sync_stamp before insert or update on public."group_files"
  for each row execute function public.sync_stamp();

create table if not exists public."group_slots" (
  "id" text not null,
  "created_at" bigint not null,
  "updated_at" bigint not null,
  "deleted_at" bigint,
  "group_id" text not null,
  "weekday" bigint not null,
  "start_minutes" bigint not null,
  "end_minutes" bigint not null,
  "room_id" text,
  "synced_at" bigint not null default 0,
  primary key ("id")
);
create index if not exists "idx_group_slots_day" on public."group_slots" (weekday, start_minutes);
create index if not exists "idx_group_slots_group" on public."group_slots" (group_id);
create index if not exists "idx_group_slots_room" on public."group_slots" (room_id, weekday);
create index if not exists "idx_group_slots_updated" on public."group_slots" (updated_at);
create index if not exists "idx_group_slots_synced" on public."group_slots" (synced_at);
drop trigger if exists trg_sync_stamp on public."group_slots";
create trigger trg_sync_stamp before insert or update on public."group_slots"
  for each row execute function public.sync_stamp();

create table if not exists public."group_students" (
  "id" text not null,
  "created_at" bigint not null,
  "updated_at" bigint not null,
  "deleted_at" bigint,
  "group_id" text not null,
  "student_id" text not null,
  "joined_at" bigint not null,
  "joined_at_cycle_number" bigint not null,
  "joined_at_session_number" bigint not null,
  "monthly_price" bigint not null,
  "discount_type" text not null,
  "discount_value" bigint not null,
  "left_at" bigint,
  "synced_at" bigint not null default 0,
  primary key ("id")
);
create unique index if not exists "idx_group_students_pair" on public."group_students" (group_id, student_id);
create index if not exists "idx_group_students_student" on public."group_students" (student_id);
create index if not exists "idx_group_students_updated" on public."group_students" (updated_at);
create index if not exists "idx_group_students_synced" on public."group_students" (synced_at);
drop trigger if exists trg_sync_stamp on public."group_students";
create trigger trg_sync_stamp before insert or update on public."group_students"
  for each row execute function public.sync_stamp();

create table if not exists public."groups" (
  "id" text not null,
  "created_at" bigint not null,
  "updated_at" bigint not null,
  "deleted_at" bigint,
  "number" bigint not null,
  "subject_id" text not null,
  "teacher_id" text not null,
  "room_id" text,
  "sessions_per_cycle" bigint not null,
  "current_cycle_number" bigint not null,
  "rate_per_student" bigint,
  "archived_at" bigint,
  "synced_at" bigint not null default 0,
  primary key ("id")
);
create index if not exists "idx_groups_number" on public."groups" (number);
create index if not exists "idx_groups_room" on public."groups" (room_id);
create index if not exists "idx_groups_subject" on public."groups" (subject_id);
create index if not exists "idx_groups_teacher" on public."groups" (teacher_id);
create index if not exists "idx_groups_updated" on public."groups" (updated_at);
create index if not exists "idx_groups_synced" on public."groups" (synced_at);
drop trigger if exists trg_sync_stamp on public."groups";
create trigger trg_sync_stamp before insert or update on public."groups"
  for each row execute function public.sync_stamp();

create table if not exists public."levels" (
  "id" text not null,
  "created_at" bigint not null,
  "updated_at" bigint not null,
  "deleted_at" bigint,
  "name" text not null,
  "stage" text not null,
  "sort_order" bigint not null,
  "synced_at" bigint not null default 0,
  primary key ("id")
);
create index if not exists "idx_levels_sort" on public."levels" (sort_order);
create index if not exists "idx_levels_updated" on public."levels" (updated_at);
create index if not exists "idx_levels_synced" on public."levels" (synced_at);
drop trigger if exists trg_sync_stamp on public."levels";
create trigger trg_sync_stamp before insert or update on public."levels"
  for each row execute function public.sync_stamp();

create table if not exists public."notifications" (
  "id" text not null,
  "created_at" bigint not null,
  "updated_at" bigint not null,
  "deleted_at" bigint,
  "user_id" text not null,
  "sender_id" text,
  "title" text not null,
  "body" text not null,
  "kind" text not null,
  "entity" text,
  "entity_id" text,
  "read_at" bigint,
  "synced_at" bigint not null default 0,
  primary key ("id")
);
create index if not exists "idx_notifications_unread" on public."notifications" (user_id, read_at);
create index if not exists "idx_notifications_updated" on public."notifications" (updated_at);
create index if not exists "idx_notifications_user" on public."notifications" (user_id, created_at);
create index if not exists "idx_notifications_synced" on public."notifications" (synced_at);
drop trigger if exists trg_sync_stamp on public."notifications";
create trigger trg_sync_stamp before insert or update on public."notifications"
  for each row execute function public.sync_stamp();

create table if not exists public."parents" (
  "id" text not null,
  "created_at" bigint not null,
  "updated_at" bigint not null,
  "deleted_at" bigint,
  "phone" text not null,
  "email" text not null,
  "name" text not null,
  "auth_user_id" text,
  "synced_at" bigint not null default 0,
  primary key ("id")
);
create index if not exists "idx_parents_email" on public."parents" (email);
create unique index if not exists "idx_parents_phone" on public."parents" (phone);
create index if not exists "idx_parents_updated" on public."parents" (updated_at);
create index if not exists "idx_parents_synced" on public."parents" (synced_at);
drop trigger if exists trg_sync_stamp on public."parents";
create trigger trg_sync_stamp before insert or update on public."parents"
  for each row execute function public.sync_stamp();

create table if not exists public."payments" (
  "id" text not null,
  "created_at" bigint not null,
  "updated_at" bigint not null,
  "deleted_at" bigint,
  "student_id" text not null,
  "type" text not null,
  "group_id" text,
  "cycle_number" bigint,
  "period_key" text,
  "amount" bigint not null,
  "received_by" text not null,
  "receipt_number" text not null,
  "note" text not null,
  "synced_at" bigint not null default 0,
  primary key ("id")
);
create index if not exists "idx_payments_created" on public."payments" (created_at);
create index if not exists "idx_payments_group_cycle" on public."payments" (group_id, cycle_number);
create unique index if not exists "idx_payments_receipt" on public."payments" (receipt_number);
create index if not exists "idx_payments_student" on public."payments" (student_id, type);
create index if not exists "idx_payments_updated" on public."payments" (updated_at);
create index if not exists "idx_payments_synced" on public."payments" (synced_at);
drop trigger if exists trg_sync_stamp on public."payments";
create trigger trg_sync_stamp before insert or update on public."payments"
  for each row execute function public.sync_stamp();

create table if not exists public."registration_fees" (
  "id" text not null,
  "created_at" bigint not null,
  "updated_at" bigint not null,
  "deleted_at" bigint,
  "student_id" text not null,
  "period_key" text not null,
  "amount" bigint not null,
  "paid" boolean not null,
  "synced_at" bigint not null default 0,
  primary key ("id")
);
create index if not exists "idx_registration_fees_paid" on public."registration_fees" (period_key, paid);
create unique index if not exists "idx_registration_fees_period" on public."registration_fees" (student_id, period_key);
create index if not exists "idx_registration_fees_updated" on public."registration_fees" (updated_at);
create index if not exists "idx_registration_fees_synced" on public."registration_fees" (synced_at);
drop trigger if exists trg_sync_stamp on public."registration_fees";
create trigger trg_sync_stamp before insert or update on public."registration_fees"
  for each row execute function public.sync_stamp();

create table if not exists public."rooms" (
  "id" text not null,
  "created_at" bigint not null,
  "updated_at" bigint not null,
  "deleted_at" bigint,
  "name" text not null,
  "capacity" bigint not null,
  "synced_at" bigint not null default 0,
  primary key ("id")
);
create index if not exists "idx_rooms_name" on public."rooms" (name);
create index if not exists "idx_rooms_updated" on public."rooms" (updated_at);
create index if not exists "idx_rooms_synced" on public."rooms" (synced_at);
drop trigger if exists trg_sync_stamp on public."rooms";
create trigger trg_sync_stamp before insert or update on public."rooms"
  for each row execute function public.sync_stamp();

create table if not exists public."session_requests" (
  "id" text not null,
  "created_at" bigint not null,
  "updated_at" bigint not null,
  "deleted_at" bigint,
  "teacher_id" text not null,
  "group_id" text not null,
  "type" text not null,
  "session_id" text,
  "new_date" text,
  "new_start_minutes" bigint,
  "new_end_minutes" bigint,
  "new_room_id" text,
  "reason" text not null,
  "status" text not null,
  "reviewed_by" text,
  "reviewed_at" bigint,
  "admin_note" text not null,
  "synced_at" bigint not null default 0,
  primary key ("id")
);
create index if not exists "idx_session_requests_group" on public."session_requests" (group_id);
create index if not exists "idx_session_requests_status" on public."session_requests" (status, created_at);
create index if not exists "idx_session_requests_teacher" on public."session_requests" (teacher_id);
create index if not exists "idx_session_requests_updated" on public."session_requests" (updated_at);
create index if not exists "idx_session_requests_synced" on public."session_requests" (synced_at);
drop trigger if exists trg_sync_stamp on public."session_requests";
create trigger trg_sync_stamp before insert or update on public."session_requests"
  for each row execute function public.sync_stamp();

create table if not exists public."sessions" (
  "id" text not null,
  "created_at" bigint not null,
  "updated_at" bigint not null,
  "deleted_at" bigint,
  "group_id" text not null,
  "cycle_number" bigint not null,
  "session_number" bigint,
  "date" text not null,
  "start_minutes" bigint not null,
  "end_minutes" bigint not null,
  "room_id" text,
  "status" text not null,
  "closed_at" bigint,
  "synced_at" bigint not null default 0,
  primary key ("id")
);
create index if not exists "idx_sessions_date" on public."sessions" (date, start_minutes);
create index if not exists "idx_sessions_group_cycle" on public."sessions" (group_id, cycle_number);
create unique index if not exists "idx_sessions_group_slot" on public."sessions" (group_id, date, start_minutes);
create index if not exists "idx_sessions_room_date" on public."sessions" (room_id, date);
create index if not exists "idx_sessions_updated" on public."sessions" (updated_at);
create index if not exists "idx_sessions_synced" on public."sessions" (synced_at);
drop trigger if exists trg_sync_stamp on public."sessions";
create trigger trg_sync_stamp before insert or update on public."sessions"
  for each row execute function public.sync_stamp();

create table if not exists public."settings" (
  "key" text not null,
  "value" text not null,
  "updated_at" bigint not null,
  "synced_at" bigint not null default 0,
  primary key ("key")
);
create index if not exists "idx_settings_updated" on public."settings" (updated_at);
create index if not exists "idx_settings_synced" on public."settings" (synced_at);
drop trigger if exists trg_sync_stamp on public."settings";
create trigger trg_sync_stamp before insert or update on public."settings"
  for each row execute function public.sync_stamp();

create table if not exists public."sms_queue" (
  "id" text not null,
  "created_at" bigint not null,
  "updated_at" bigint not null,
  "deleted_at" bigint,
  "phone" text not null,
  "message" text not null,
  "status" text not null,
  "kind" text not null,
  "attempts" bigint not null,
  "last_error" text,
  "not_before" bigint,
  "sent_at" bigint,
  "created_by" text,
  "event_key" text,
  "synced_at" bigint not null default 0,
  primary key ("id")
);
create unique index if not exists "idx_sms_queue_event_key" on public."sms_queue" (event_key);
create index if not exists "idx_sms_queue_sent" on public."sms_queue" (sent_at);
create index if not exists "idx_sms_queue_status" on public."sms_queue" (status, created_at);
create index if not exists "idx_sms_queue_updated" on public."sms_queue" (updated_at);
create index if not exists "idx_sms_queue_synced" on public."sms_queue" (synced_at);
drop trigger if exists trg_sync_stamp on public."sms_queue";
create trigger trg_sync_stamp before insert or update on public."sms_queue"
  for each row execute function public.sync_stamp();

create table if not exists public."sms_templates" (
  "key" text not null,
  "body" text not null,
  "updated_at" bigint not null,
  "synced_at" bigint not null default 0,
  primary key ("key")
);
create index if not exists "idx_sms_templates_updated" on public."sms_templates" (updated_at);
create index if not exists "idx_sms_templates_synced" on public."sms_templates" (synced_at);
drop trigger if exists trg_sync_stamp on public."sms_templates";
create trigger trg_sync_stamp before insert or update on public."sms_templates"
  for each row execute function public.sync_stamp();

create table if not exists public."student_credits" (
  "id" text not null,
  "created_at" bigint not null,
  "updated_at" bigint not null,
  "deleted_at" bigint,
  "student_id" text not null,
  "group_id" text not null,
  "amount" bigint not null,
  "reason" text not null,
  "source_cycle_number" bigint not null,
  "target_cycle_number" bigint not null,
  "session_id" text,
  "synced_at" bigint not null default 0,
  primary key ("id")
);
create index if not exists "idx_student_credits_source" on public."student_credits" (group_id, source_cycle_number);
create index if not exists "idx_student_credits_target" on public."student_credits" (student_id, group_id, target_cycle_number);
create index if not exists "idx_student_credits_updated" on public."student_credits" (updated_at);
create index if not exists "idx_student_credits_synced" on public."student_credits" (synced_at);
drop trigger if exists trg_sync_stamp on public."student_credits";
create trigger trg_sync_stamp before insert or update on public."student_credits"
  for each row execute function public.sync_stamp();

create table if not exists public."students" (
  "id" text not null,
  "created_at" bigint not null,
  "updated_at" bigint not null,
  "deleted_at" bigint,
  "first_name" text not null,
  "last_name" text not null,
  "parent_phone" text not null,
  "photo_url" text,
  "photo_local_path" text,
  "level_id" text,
  "uses_transport" boolean not null,
  "transport_price" bigint not null,
  "transport_line_id" text,
  "qr_code" text not null,
  "parent_account_id" text,
  "synced_at" bigint not null default 0,
  primary key ("id")
);
create index if not exists "idx_students_first_name" on public."students" (first_name);
create index if not exists "idx_students_level" on public."students" (level_id);
create index if not exists "idx_students_name" on public."students" (last_name, first_name);
create index if not exists "idx_students_parent_account" on public."students" (parent_account_id);
create index if not exists "idx_students_parent_phone" on public."students" (parent_phone);
create unique index if not exists "idx_students_qr" on public."students" (qr_code);
create index if not exists "idx_students_transport_line" on public."students" (transport_line_id);
create index if not exists "idx_students_updated" on public."students" (updated_at);
create index if not exists "idx_students_synced" on public."students" (synced_at);
drop trigger if exists trg_sync_stamp on public."students";
create trigger trg_sync_stamp before insert or update on public."students"
  for each row execute function public.sync_stamp();

create table if not exists public."subjects" (
  "id" text not null,
  "created_at" bigint not null,
  "updated_at" bigint not null,
  "deleted_at" bigint,
  "name" text not null,
  "level_id" text,
  "monthly_price" bigint not null,
  "synced_at" bigint not null default 0,
  primary key ("id")
);
create index if not exists "idx_subjects_level" on public."subjects" (level_id);
create index if not exists "idx_subjects_name" on public."subjects" (name);
create index if not exists "idx_subjects_updated" on public."subjects" (updated_at);
create index if not exists "idx_subjects_synced" on public."subjects" (synced_at);
drop trigger if exists trg_sync_stamp on public."subjects";
create trigger trg_sync_stamp before insert or update on public."subjects"
  for each row execute function public.sync_stamp();

create table if not exists public."teacher_attendance" (
  "id" text not null,
  "created_at" bigint not null,
  "updated_at" bigint not null,
  "deleted_at" bigint,
  "teacher_id" text not null,
  "session_id" text,
  "date" text not null,
  "check_in" bigint,
  "check_out" bigint,
  "late_minutes" bigint not null,
  "synced_at" bigint not null default 0,
  primary key ("id")
);
create index if not exists "idx_teacher_attendance_session" on public."teacher_attendance" (session_id);
create index if not exists "idx_teacher_attendance_teacher" on public."teacher_attendance" (teacher_id, date);
create index if not exists "idx_teacher_attendance_updated" on public."teacher_attendance" (updated_at);
create index if not exists "idx_teacher_attendance_synced" on public."teacher_attendance" (synced_at);
drop trigger if exists trg_sync_stamp on public."teacher_attendance";
create trigger trg_sync_stamp before insert or update on public."teacher_attendance"
  for each row execute function public.sync_stamp();

create table if not exists public."teacher_payouts" (
  "id" text not null,
  "created_at" bigint not null,
  "updated_at" bigint not null,
  "deleted_at" bigint,
  "teacher_id" text not null,
  "group_id" text not null,
  "cycle_number" bigint not null,
  "kind" text not null,
  "amount" bigint not null,
  "details" text not null,
  "paid_at" bigint,
  "paid_by" text,
  "synced_at" bigint not null default 0,
  primary key ("id")
);
create index if not exists "idx_teacher_payouts_group_cycle" on public."teacher_payouts" (group_id, cycle_number);
create index if not exists "idx_teacher_payouts_teacher" on public."teacher_payouts" (teacher_id, paid_at);
create index if not exists "idx_teacher_payouts_updated" on public."teacher_payouts" (updated_at);
create index if not exists "idx_teacher_payouts_synced" on public."teacher_payouts" (synced_at);
drop trigger if exists trg_sync_stamp on public."teacher_payouts";
create trigger trg_sync_stamp before insert or update on public."teacher_payouts"
  for each row execute function public.sync_stamp();

create table if not exists public."teacher_subjects" (
  "teacher_id" text not null,
  "subject_id" text not null,
  "updated_at" bigint not null,
  "deleted_at" bigint,
  "synced_at" bigint not null default 0,
  primary key ("teacher_id", "subject_id")
);
create index if not exists "idx_teacher_subjects_subject" on public."teacher_subjects" (subject_id);
create index if not exists "idx_teacher_subjects_updated" on public."teacher_subjects" (updated_at);
create index if not exists "idx_teacher_subjects_synced" on public."teacher_subjects" (synced_at);
drop trigger if exists trg_sync_stamp on public."teacher_subjects";
create trigger trg_sync_stamp before insert or update on public."teacher_subjects"
  for each row execute function public.sync_stamp();

create table if not exists public."teachers" (
  "id" text not null,
  "created_at" bigint not null,
  "updated_at" bigint not null,
  "deleted_at" bigint,
  "name" text not null,
  "phone" text not null,
  "email" text not null,
  "photo_url" text,
  "photo_local_path" text,
  "rate_per_student" bigint not null,
  "qr_code" text not null,
  "auth_user_id" text,
  "synced_at" bigint not null default 0,
  primary key ("id")
);
create index if not exists "idx_teachers_name" on public."teachers" (name);
create index if not exists "idx_teachers_phone" on public."teachers" (phone);
create unique index if not exists "idx_teachers_qr" on public."teachers" (qr_code);
create index if not exists "idx_teachers_updated" on public."teachers" (updated_at);
create index if not exists "idx_teachers_synced" on public."teachers" (synced_at);
drop trigger if exists trg_sync_stamp on public."teachers";
create trigger trg_sync_stamp before insert or update on public."teachers"
  for each row execute function public.sync_stamp();

create table if not exists public."transport_lines" (
  "id" text not null,
  "created_at" bigint not null,
  "updated_at" bigint not null,
  "deleted_at" bigint,
  "name" text not null,
  "driver_name" text not null,
  "driver_phone" text not null,
  "bus_number" text not null,
  "synced_at" bigint not null default 0,
  primary key ("id")
);
create index if not exists "idx_transport_lines_name" on public."transport_lines" (name);
create index if not exists "idx_transport_lines_updated" on public."transport_lines" (updated_at);
create index if not exists "idx_transport_lines_synced" on public."transport_lines" (synced_at);
drop trigger if exists trg_sync_stamp on public."transport_lines";
create trigger trg_sync_stamp before insert or update on public."transport_lines"
  for each row execute function public.sync_stamp();

create table if not exists public."user_accounts" (
  "id" text not null,
  "created_at" bigint not null,
  "updated_at" bigint not null,
  "deleted_at" bigint,
  "email" text not null,
  "role" text not null,
  "entity_id" text,
  "display_name" text not null,
  "must_change_password" boolean not null,
  "synced_at" bigint not null default 0,
  primary key ("id")
);
create unique index if not exists "idx_user_accounts_email" on public."user_accounts" (email);
create index if not exists "idx_user_accounts_entity" on public."user_accounts" (role, entity_id);
create index if not exists "idx_user_accounts_updated" on public."user_accounts" (updated_at);
create index if not exists "idx_user_accounts_synced" on public."user_accounts" (synced_at);
drop trigger if exists trg_sync_stamp on public."user_accounts";
create trigger trg_sync_stamp before insert or update on public."user_accounts"
  for each row execute function public.sync_stamp();

create table if not exists public."waiting_entries" (
  "id" text not null,
  "created_at" bigint not null,
  "updated_at" bigint not null,
  "deleted_at" bigint,
  "waiting_list_id" text not null,
  "student_id" text not null,
  "added_at" bigint not null,
  "synced_at" bigint not null default 0,
  primary key ("id")
);
create unique index if not exists "idx_waiting_entries_pair" on public."waiting_entries" (waiting_list_id, student_id);
create index if not exists "idx_waiting_entries_student" on public."waiting_entries" (student_id);
create index if not exists "idx_waiting_entries_updated" on public."waiting_entries" (updated_at);
create index if not exists "idx_waiting_entries_synced" on public."waiting_entries" (synced_at);
drop trigger if exists trg_sync_stamp on public."waiting_entries";
create trigger trg_sync_stamp before insert or update on public."waiting_entries"
  for each row execute function public.sync_stamp();

create table if not exists public."waiting_lists" (
  "id" text not null,
  "created_at" bigint not null,
  "updated_at" bigint not null,
  "deleted_at" bigint,
  "subject_id" text not null,
  "level_id" text,
  "preferred_teacher_id" text,
  "threshold" bigint not null,
  "threshold_notified_at" bigint,
  "synced_at" bigint not null default 0,
  primary key ("id")
);
create index if not exists "idx_waiting_lists_subject" on public."waiting_lists" (subject_id, level_id);
create index if not exists "idx_waiting_lists_updated" on public."waiting_lists" (updated_at);
create index if not exists "idx_waiting_lists_synced" on public."waiting_lists" (synced_at);
drop trigger if exists trg_sync_stamp on public."waiting_lists";
create trigger trg_sync_stamp before insert or update on public."waiting_lists"
  for each row execute function public.sync_stamp();

create table if not exists public."worker_attendance" (
  "id" text not null,
  "created_at" bigint not null,
  "updated_at" bigint not null,
  "deleted_at" bigint,
  "worker_id" text not null,
  "date" text not null,
  "check_in" bigint,
  "check_out" bigint,
  "late_minutes" bigint not null,
  "override_kind" text,
  "synced_at" bigint not null default 0,
  primary key ("id")
);
create index if not exists "idx_worker_attendance_date" on public."worker_attendance" (date);
create unique index if not exists "idx_worker_attendance_day" on public."worker_attendance" (worker_id, date);
create index if not exists "idx_worker_attendance_updated" on public."worker_attendance" (updated_at);
create index if not exists "idx_worker_attendance_synced" on public."worker_attendance" (synced_at);
drop trigger if exists trg_sync_stamp on public."worker_attendance";
create trigger trg_sync_stamp before insert or update on public."worker_attendance"
  for each row execute function public.sync_stamp();

create table if not exists public."workers" (
  "id" text not null,
  "created_at" bigint not null,
  "updated_at" bigint not null,
  "deleted_at" bigint,
  "name" text not null,
  "phone" text not null,
  "email" text not null,
  "qr_code" text not null,
  "expected_start_minutes" bigint not null,
  "expected_end_minutes" bigint not null,
  "full_day_wage" bigint not null,
  "half_day_wage" bigint not null,
  "weekly_schedule" text not null,
  "permissions" text not null,
  "auth_user_id" text,
  "synced_at" bigint not null default 0,
  primary key ("id")
);
create index if not exists "idx_workers_name" on public."workers" (name);
create unique index if not exists "idx_workers_qr" on public."workers" (qr_code);
create index if not exists "idx_workers_updated" on public."workers" (updated_at);
create index if not exists "idx_workers_synced" on public."workers" (synced_at);
drop trigger if exists trg_sync_stamp on public."workers";
create trigger trg_sync_stamp before insert or update on public."workers"
  for each row execute function public.sync_stamp();

-- البث اللحظي لكل الجداول المزامَنة.
do $$
declare t text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach t in array array[
      'attendance',
      'audit_log',
      'chat_members',
      'chat_messages',
      'chat_rooms',
      'expense_categories',
      'expenses',
      'grades',
      'group_files',
      'group_slots',
      'group_students',
      'groups',
      'levels',
      'notifications',
      'parents',
      'payments',
      'registration_fees',
      'rooms',
      'session_requests',
      'sessions',
      'settings',
      'sms_queue',
      'sms_templates',
      'student_credits',
      'students',
      'subjects',
      'teacher_attendance',
      'teacher_payouts',
      'teacher_subjects',
      'teachers',
      'transport_lines',
      'user_accounts',
      'waiting_entries',
      'waiting_lists',
      'worker_attendance',
      'workers'
    ] loop
      if not exists (select 1 from pg_publication_tables
        where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
        execute format('alter publication supabase_realtime add table public.%I', t);
      end if;
    end loop;
  end if;
end
$$;
