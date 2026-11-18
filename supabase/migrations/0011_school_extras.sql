-- الأفواج المنتظِرة وحصص المراجعة، وما يأخذه الأستاذ عن كل تلميذ، والتلاميذ لمرة واحدة وضيوف الحصص،
-- ودليل الهواتف.
--
-- المخطط نفسه مولَّد في 0001_schema.sql للخوادم الجديدة؛ هذا الملف للخوادم المنشورة قبل هذه الأعمدة
-- والجداول (يُطبَّق مرة واحدة هناك). كله آمن عند التكرار. انشر الخادم بهذا الترحيل **قبل** وصول التطبيقات
-- التي ترسل الأعمدة الجديدة إلى أجهزتها.

-- فوج منتظِر: عدد التلاميذ المطلوب لبدئه، ووقت تنبيه المدير باكتماله؛ وحصة المراجعة (فوج من حصة واحدة).
alter table public."groups" add column if not exists "waiting_target" bigint;
alter table public."groups" add column if not exists "start_alerted_at" bigint;
alter table public."groups" add column if not exists "is_review" boolean not null default false;
-- القيمة الافتراضية تبقى (ولو في خادم جديد أنشأه 0001 بلا قيمة): تطبيق أقدم لا يرسل العمود فلا يفشل إنشاء فوج منه.
alter table public."groups" alter column "is_review" set default false;

-- ما يأخذه الأستاذ عن هذا التلميذ في الدورة؛ فارغ يعني نصيب الفوج كاملاً (التخفيض على حساب المدرسة).
alter table public."group_students" add column if not exists "teacher_amount" bigint;

-- تلميذ لمرة واحدة: حضر حصة واحدة فدفع ثمنها فقط (يُخفى من قائمة التلاميذ العادية).
alter table public."students" add column if not exists "single_use" boolean not null default false;
alter table public."students" alter column "single_use" set default false;

-- دليل الهواتف: أرقام يسجلها المدير منفصلة عن التلاميذ.
create table if not exists public."contacts" (
  "id" text not null,
  "created_at" bigint not null,
  "updated_at" bigint not null,
  "deleted_at" bigint,
  "name" text not null,
  "phone" text not null,
  "note" text not null,
  "follow_up_date" text,
  "source" text not null,
  "synced_at" bigint not null default 0,
  primary key ("id")
);
create index if not exists "idx_contacts_name" on public."contacts" (name);
create index if not exists "idx_contacts_phone" on public."contacts" (phone);
create index if not exists "idx_contacts_updated" on public."contacts" (updated_at);
create index if not exists "idx_contacts_synced" on public."contacts" (synced_at);
drop trigger if exists trg_sync_stamp on public."contacts";
create trigger trg_sync_stamp before insert or update on public."contacts"
  for each row execute function public.sync_stamp();

-- ضيوف الحصص: تلميذ يحضر حصة واحدة ويدفع ثمنها وحدها، وتذكرته لمرة واحدة.
create table if not exists public."session_guests" (
  "id" text not null,
  "created_at" bigint not null,
  "updated_at" bigint not null,
  "deleted_at" bigint,
  "session_id" text not null,
  "student_id" text not null,
  "price" bigint not null,
  "teacher_amount" bigint not null,
  "ticket_code" text,
  "used_at" bigint,
  "synced_at" bigint not null default 0,
  primary key ("id")
);
create unique index if not exists "idx_session_guests_pair" on public."session_guests" (session_id, student_id);
create index if not exists "idx_session_guests_student" on public."session_guests" (student_id);
create unique index if not exists "idx_session_guests_ticket" on public."session_guests" (ticket_code);
create index if not exists "idx_session_guests_updated" on public."session_guests" (updated_at);
create index if not exists "idx_session_guests_synced" on public."session_guests" (synced_at);
drop trigger if exists trg_sync_stamp on public."session_guests";
create trigger trg_sync_stamp before insert or update on public."session_guests"
  for each row execute function public.sync_stamp();

-- دليل الهواتف للإدارة وحدها (صلاحية التلاميذ): لا يراه الأستاذ ولا الوليّ.
select app.staff_rules('contacts', 'students');

-- ضيف الحصة: تقرؤه الإدارة (الحضور أو المجموعات)، وأستاذ مجموعة الحصة، ووليّ التلميذ. تضيفه الإدارة، ويمسح
-- المدخل تذكرته (الماسح) فيكتب وقت استعمالها.
select app.set_rules('session_guests',
  $$app.can('attendance', 'view') or app.can('groups', 'view')
    or app.teaches_group(app.session_group(session_id))
    or app.parent_of(student_id)$$,
  $$app.can('attendance', 'add') or app.can('scanner', 'use')$$,
  $$app.can('attendance', 'edit') or app.can('scanner', 'use')$$);

revoke all on public."contacts" from anon;
grant select, insert, update on public."contacts" to authenticated;
revoke all on public."session_guests" from anon;
grant select, insert, update on public."session_guests" to authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1 from pg_publication_tables
       where pubname = 'supabase_realtime' and schemaname = 'public'
         and tablename = 'contacts') then
      alter publication supabase_realtime add table public."contacts";
    end if;
    if not exists (
      select 1 from pg_publication_tables
       where pubname = 'supabase_realtime' and schemaname = 'public'
         and tablename = 'session_guests') then
      alter publication supabase_realtime add table public."session_guests";
    end if;
  end if;
end
$$;
