-- الصلاحيات على الخادم (Row Level Security) لكل دور:
-- صاحب المدرسة، العامل (حسب ما يفعّله المدير)، الأستاذ، الوليّ.
--
-- الأجهزة ترسل «إضافة أو تحديث»، والحذف ناعم (تحديث `deleted_at`)، فلا
-- توجد صلاحية حذف فعلي لأحد.

create schema if not exists app;
grant usage on schema app to authenticated;

-- ---------------------------------------------------------------------------
-- دوال المساعدة (تعمل بصلاحيات مالكها حتى لا تدور الصلاحيات على نفسها)
-- ---------------------------------------------------------------------------

create or replace function app.uid() returns text
language sql stable as $$ select auth.uid()::text $$;

create or replace function app.role() returns text
language sql stable security definer set search_path = public as $$
  select a.role from user_accounts a
   where a.id = app.uid() and a.deleted_at is null
$$;

create or replace function app.entity_id() returns text
language sql stable security definer set search_path = public as $$
  select a.entity_id from user_accounts a
   where a.id = app.uid() and a.deleted_at is null
$$;

create or replace function app.is_owner() returns boolean
language sql stable as $$ select coalesce(app.role() = 'owner', false) $$;

create or replace function app.is_staff() returns boolean
language sql stable as $$
  select coalesce(app.role() in ('owner', 'worker'), false)
$$;

-- هل يملك المستخدم الصلاحية [action] على الوحدة [module]؟
-- صاحب المدرسة يملك كل شيء؛ العامل حسب حقل `permissions` (JSON من اسم
-- الوحدة إلى قائمة الأفعال: view / add / edit / delete / use).
create or replace function app.can(module text, action text) returns boolean
language sql stable security definer set search_path = public as $$
  select case app.role()
    when 'owner' then true
    when 'worker' then coalesce(
      (select (w.permissions::jsonb -> module) ? action from workers w
        where w.id = app.entity_id() and w.deleted_at is null),
      false)
    else false
  end
$$;

create or replace function app.teaches_group(gid text) returns boolean
language sql stable security definer set search_path = public as $$
  select app.role() = 'teacher' and exists (
    select 1 from groups g
     where g.id = gid and g.teacher_id = app.entity_id())
$$;

create or replace function app.teaches_student(sid text) returns boolean
language sql stable security definer set search_path = public as $$
  select app.role() = 'teacher' and exists (
    select 1 from group_students gs join groups g on g.id = gs.group_id
     where gs.student_id = sid and gs.deleted_at is null
       and g.teacher_id = app.entity_id())
$$;

create or replace function app.parent_of(sid text) returns boolean
language sql stable security definer set search_path = public as $$
  select app.role() = 'parent' and exists (
    select 1 from students s
     where s.id = sid and s.parent_account_id = app.entity_id())
$$;

create or replace function app.parent_in_group(gid text) returns boolean
language sql stable security definer set search_path = public as $$
  select app.role() = 'parent' and exists (
    select 1 from group_students gs join students s on s.id = gs.student_id
     where gs.group_id = gid and gs.deleted_at is null
       and s.parent_account_id = app.entity_id())
$$;

create or replace function app.session_group(sid text) returns text
language sql stable security definer set search_path = public as $$
  select s.group_id from sessions s where s.id = sid
$$;

create or replace function app.active_chat_group(gid text) returns boolean
language sql stable security definer set search_path = public as $$
  select case app.role()
    when 'teacher' then exists (
      select 1 from groups g
       where g.id = gid and g.teacher_id = app.entity_id()
         and g.deleted_at is null and g.archived_at is null)
    when 'parent' then exists (
      select 1 from groups g
      join group_students gs on gs.group_id = g.id and gs.deleted_at is null
      join students s on s.id = gs.student_id and s.deleted_at is null
       where g.id = gid and g.deleted_at is null and g.archived_at is null
         and gs.left_at is null
         and s.parent_account_id = app.entity_id())
    else true
  end
$$;

create or replace function app.chat_room_group(rid text) returns text
language sql stable security definer set search_path = public as $$
  select r.group_id from chat_rooms r where r.id = rid and r.type = 'group'
$$;

create or replace function app.group_chat_participant(
  gid text, target_uid text, target_role text
) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from groups g join user_accounts target
      on target.id = target_uid and target.role = target_role
      and target.deleted_at is null
    where g.id = gid and g.deleted_at is null and g.archived_at is null
      and ((target.role = 'teacher' and target.entity_id = g.teacher_id)
        or (target.role = 'parent' and exists (
          select 1 from group_students gs
          join students s on s.id = gs.student_id and s.deleted_at is null
          where gs.group_id = g.id and gs.deleted_at is null
            and gs.left_at is null
            and s.parent_account_id = target.entity_id)))
  )
$$;

-- لا يبدأ الأستاذ والوليّ محادثة خاصة إلا مع مجموعة نشطة مشتركة.
create or replace function app.can_message_account(target_uid text) returns boolean
language sql stable security definer set search_path = public as $$
  select case
    when app.can('chat', 'add') or app.can('chat', 'edit') then true
    when app.role() not in ('teacher', 'parent') then false
    else exists (
      select 1 from user_accounts target
      join groups g on g.deleted_at is null and g.archived_at is null
      join group_students gs on gs.group_id = g.id
        and gs.deleted_at is null and gs.left_at is null
      join students s on s.id = gs.student_id and s.deleted_at is null
      where target.id = target_uid and target.deleted_at is null
        and ((app.role() = 'teacher' and target.role = 'parent'
              and g.teacher_id = app.entity_id()
              and s.parent_account_id = target.entity_id)
          or (app.role() = 'parent' and target.role = 'teacher'
              and g.teacher_id = target.entity_id
              and s.parent_account_id = app.entity_id()))
    )
  end
$$;

create or replace function app.can_create_chat_room(room_type text, gid text)
returns boolean language sql stable security definer set search_path = public as $$
  select case
    when room_type is null then false
    when room_type = 'private' and gid is not null then false
    when room_type = 'group' and gid is null then false
    when room_type not in ('private', 'group') then false
    when app.can('chat', 'add') or app.can('chat', 'edit') then true
    when room_type = 'private' then gid is null
      and app.role() in ('teacher', 'parent')
    when room_type = 'group' then app.active_chat_group(gid)
    else false
  end
$$;

create or replace function app.is_room_member(rid text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from chat_members m join chat_rooms r on r.id = m.room_id
       where m.room_id = rid and m.user_id = app.uid() and m.deleted_at is null
       and (r.type <> 'group' or app.active_chat_group(r.group_id)))
$$;

create or replace function app.created_room(rid text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from chat_rooms r
     where r.id = rid and r.created_by = app.uid()
       and (r.type <> 'group' or app.active_chat_group(r.group_id)))
$$;

create or replace function app.can_add_chat_member(
  rid text, target_uid text, target_role text
) returns boolean
language sql stable security definer set search_path = public as $$
  select case
    when app.can('chat', 'add') or app.can('chat', 'edit') then true
    when not app.created_room(rid) then false
    when target_uid = app.uid() then target_role = app.role()
    else exists (
      select 1 from chat_rooms r join user_accounts target
        on target.id = target_uid and target.role = target_role
        and target.deleted_at is null
      where r.id = rid and r.deleted_at is null and (
        (r.type = 'private' and app.can_message_account(target_uid))
        or (r.type = 'group' and app.active_chat_group(r.group_id)
          and app.group_chat_participant(r.group_id, target_uid, target.role))
      )
    )
  end
$$;

-- الغرفة المحدّثة من عضو عادي لا تغيّر حالة الإغلاق أو أعضاءها أو تعريفها.
-- يسمح للعضو بتحديث آخر رسالة، ولأستاذ المجموعة بتعديل عنوان مجموعته.
create or replace function app.guard_chat_room_update() returns trigger
language plpgsql set search_path = public as $$
declare
  allowed_columns text[] := array['updated_at', 'synced_at', 'last_message_at'];
begin
  if current_user <> 'authenticated' or app.can('chat', 'edit') then
    return new;
  end if;
  if old.type = 'group' and app.teaches_group(old.group_id) then
    allowed_columns := array_append(allowed_columns, 'title');
  end if;
  if not app.is_room_member(old.id)
     or (to_jsonb(new) - allowed_columns) <> (to_jsonb(old) - allowed_columns) then
    raise exception 'لا صلاحية لتعديل هذه الغرفة'
      using errcode = '42501';
  end if;
  return new;
end
$$;

create or replace function app.guard_chat_member_update() returns trigger
language plpgsql set search_path = public as $$
declare
  allowed_columns text[];
  gid text := app.chat_room_group(old.room_id);
begin
  if current_user <> 'authenticated' or app.can('chat', 'edit') then
    return new;
  end if;
  if old.user_id = app.uid() and old.user_role = app.role()
     and app.is_room_member(old.room_id) then
    allowed_columns := array['updated_at', 'synced_at', 'last_read_at', 'muted'];
  elsif app.teaches_group(gid) and app.active_chat_group(gid)
      and old.user_role in ('teacher', 'parent') then
    allowed_columns := array['updated_at', 'synced_at', 'deleted_at'];
    if old.deleted_at is null and new.deleted_at is not null
       and app.group_chat_participant(gid, old.user_id, old.user_role) then
      raise exception 'لا يمكن إزالة عضو نشط من الغرفة الجماعية'
        using errcode = '42501';
    end if;
    if new.deleted_at is null
       and not app.group_chat_participant(gid, new.user_id, new.user_role) then
      raise exception 'لا يمكن إضافة عضو غير نشط إلى الغرفة الجماعية'
        using errcode = '42501';
    end if;
  else
    raise exception 'لا صلاحية لتعديل عضو المحادثة'
      using errcode = '42501';
  end if;
  if (to_jsonb(new) - allowed_columns) <> (to_jsonb(old) - allowed_columns) then
    raise exception 'لا صلاحية لتغيير بيانات عضو المحادثة'
      using errcode = '42501';
  end if;
  return new;
end
$$;

drop trigger if exists trg_chat_member_update_guard on public.chat_members;
create trigger trg_chat_member_update_guard before update on public.chat_members
  for each row execute function app.guard_chat_member_update();

drop trigger if exists trg_chat_room_update_guard on public.chat_rooms;
create trigger trg_chat_room_update_guard before update on public.chat_rooms
  for each row execute function app.guard_chat_room_update();

create or replace function app.room_open(rid text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from chat_rooms r
     where r.id = rid and not r.is_closed and r.deleted_at is null)
$$;

-- ---------------------------------------------------------------------------
-- مولّد القواعد
-- ---------------------------------------------------------------------------

-- يضبط قواعد جدول: القراءة والإضافة والتحديث. `null` يعني ممنوع.
--
-- الأجهزة ترسل «إضافة أو تحديث» (upsert)، و PostgreSQL يفحص قاعدة الإضافة
-- على الصف المقترح حتى لو انتهى الأمر بتحديث. لذلك قاعدة الإضافة تقبل من
-- يحق له الإضافة **أو** التحديث، وحارس بعد الإضافة (لا يعمل إلا إذا أُنشئ
-- صف جديد فعلاً) يفرض صلاحية الإضافة الحقيقية.
create or replace function app.set_rules(
  tbl text, select_sql text, insert_sql text, update_sql text,
  update_check_sql text default null
) returns void language plpgsql as $$
declare
  upd_check text := coalesce(update_check_sql, update_sql);
begin
  execute format('alter table public.%I enable row level security', tbl);
  execute format('drop policy if exists p_select on public.%I', tbl);
  execute format('drop policy if exists p_insert on public.%I', tbl);
  execute format('drop policy if exists p_update on public.%I', tbl);
  execute format('drop trigger if exists trg_ins_guard on public.%I', tbl);
  if select_sql is not null then
    execute format(
      'create policy p_select on public.%I for select to authenticated using (%s)',
      tbl, select_sql);
  end if;
  if insert_sql is not null then
    execute format(
      'create policy p_insert on public.%I for insert to authenticated with check ((%s) or (%s))',
      tbl, insert_sql, coalesce(upd_check, 'false'));
    execute format($f$
      create or replace function app.%I() returns trigger
      language plpgsql as $g$
      declare ok boolean;
      begin
        if current_user <> 'authenticated' then
          return null;
        end if;
        select (%s) into ok from (select new.*) as %I;
        if not coalesce(ok, false) then
          raise exception 'لا صلاحية لإضافة سجل جديد في %s'
            using errcode = '42501';
        end if;
        return null;
      end
      $g$
    $f$, 'ins_guard_' || tbl, insert_sql, tbl, tbl);
    execute format(
      'create trigger trg_ins_guard after insert on public.%I '
      'for each row execute function app.%I()', tbl, 'ins_guard_' || tbl);
  end if;
  if update_sql is not null then
    execute format(
      'create policy p_update on public.%I for update to authenticated using (%s) with check (%s)',
      tbl, update_sql, upd_check);
  end if;
end
$$;

-- قواعد جدول تديره الإدارة حسب وحدة صلاحيات [module]:
-- القراءة: view (أو شرط إضافي). الإضافة: add. التحديث: edit، والحذف الناعم
-- (تحديث يضع deleted_at): delete.
create or replace function app.staff_rules(
  tbl text, module text,
  extra_select text default 'false',
  extra_insert text default 'false',
  extra_update text default 'false'
) returns void language plpgsql as $$
declare
  soft boolean;
  upd_check text;
begin
  select exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = tbl
       and column_name = 'deleted_at') into soft;
  if soft then
    upd_check := format(
      '(deleted_at is null and app.can(%L, ''edit'')) '
      'or (deleted_at is not null and app.can(%L, ''delete'')) or (%s)',
      module, module, extra_update);
  else
    upd_check := format('app.can(%L, ''edit'') or (%s)', module, extra_update);
  end if;
  perform app.set_rules(
    tbl,
    format('app.can(%L, ''view'') or (%s)', module, extra_select),
    format('app.can(%L, ''add'') or (%s)', module, extra_insert),
    format('app.can(%L, ''edit'') or app.can(%L, ''delete'') or (%s)',
           module, module, extra_update),
    upd_check);
end
$$;

-- ---------------------------------------------------------------------------
-- القواعد جدولاً جدولاً
-- ---------------------------------------------------------------------------

-- مراجع يقرؤها الجميع ويعدّلها من له صلاحية الوحدة.
select app.staff_rules('settings', 'settings', 'true');
select app.staff_rules('levels', 'settings', 'true');
select app.staff_rules('subjects', 'subjects', 'true');
select app.staff_rules('rooms', 'rooms', 'true');
select app.staff_rules('teacher_subjects', 'teachers', 'true');

select app.staff_rules('transport_lines', 'transport',
  $$app.role() = 'parent' and exists (
      select 1 from students s
       where s.transport_line_id = transport_lines.id
         and s.parent_account_id = app.entity_id())$$);

-- الأشخاص.
select app.staff_rules('students', 'students',
  'app.teaches_student(id) or app.parent_of(id)');

select app.staff_rules('parents', 'students',
  $$(app.role() = 'parent' and id = app.entity_id())
    or exists (select 1 from students s
                where s.parent_account_id = parents.id
                  and app.teaches_student(s.id))$$);

-- الأستاذ يرى سجله كاملاً. الوليّ لا يقرأ جدول الأساتذة (فيه رمز QR
-- والبريد والمبلغ)، بل العرض المحجوب `teacher_cards` أدناه.
select app.staff_rules('teachers', 'teachers',
  $$app.role() = 'teacher' and id = app.entity_id()$$);

-- العمال: القراءة لمن له الصلاحية وللعامل نفسه؛ التعديل لصاحب المدرسة فقط
-- (الأجور والصلاحيات).
select app.set_rules('workers',
  $$app.can('workers', 'view')
    or (app.role() = 'worker' and id = app.entity_id())$$,
  'app.is_owner()', 'app.is_owner()');

-- الحسابات: كلٌّ يرى حسابه، والإدارة ترى الكل. الإدارة تنشئ حسابات الأساتذة
-- والأولياء؛ حسابات العمال والمالك لصاحب المدرسة فقط. المستخدم يحدّث حسابه
-- (تغيير كلمة السر) دون أن يغيّر دوره أو صاحبه.
select app.set_rules('user_accounts',
  'id = app.uid() or app.is_staff()',
  $$app.is_owner()
    or (role = 'teacher' and app.can('teachers', 'add'))
    or (role = 'parent' and app.can('students', 'add'))$$,
  $$app.is_owner()
    or id = app.uid()
    or (role = 'teacher' and app.can('teachers', 'edit'))
    or (role = 'parent' and app.can('students', 'edit'))$$,
  $$app.is_owner()
    or (id = app.uid() and role = app.role()
        and entity_id is not distinct from app.entity_id())
    or (role = 'teacher' and app.can('teachers', 'edit'))
    or (role = 'parent' and app.can('students', 'edit'))$$);

-- المجموعات والجدول. الوليّ يقرأ المجموعات عبر العرض `group_cards`.
select app.staff_rules('groups', 'groups', 'app.teaches_group(id)');
select app.staff_rules('group_slots', 'groups',
  'app.teaches_group(group_id) or app.parent_in_group(group_id)');
select app.staff_rules('group_students', 'groups',
  'app.teaches_group(group_id) or app.parent_of(student_id)');
select app.staff_rules('waiting_lists', 'waiting');
select app.staff_rules('waiting_entries', 'waiting',
  'app.parent_of(student_id)');

-- الحصص: الإدارة (الحضور أو الماسح أو المجموعات)، والأستاذ لمجموعاته
-- (مع حارس يمنعه من تغيير المواعيد، انظر أسفل الملف).
select app.set_rules('sessions',
  $$app.can('groups', 'view') or app.can('attendance', 'view')
    or app.teaches_group(group_id) or app.parent_in_group(group_id)$$,
  $$app.can('groups', 'add') or app.can('attendance', 'add')
    or app.can('scanner', 'use') or app.teaches_group(group_id)$$,
  $$app.can('groups', 'edit') or app.can('attendance', 'edit')
    or app.can('scanner', 'use') or app.teaches_group(group_id)$$);

-- الحضور: الأستاذ يسجّل لمجموعاته، لكن «غائب برخصة» للإدارة فقط.
select app.set_rules('attendance',
  $$app.can('attendance', 'view')
    or app.teaches_group(app.session_group(session_id))
    or app.parent_of(student_id)$$,
  $$app.can('attendance', 'add') or app.can('scanner', 'use')
    or (app.teaches_group(app.session_group(session_id))
        and status <> 'excused')$$,
  $$app.can('attendance', 'edit') or app.can('scanner', 'use')
    or app.teaches_group(app.session_group(session_id))$$,
  $$app.can('attendance', 'edit') or app.can('scanner', 'use')
    or (app.teaches_group(app.session_group(session_id))
        and status <> 'excused')$$);

select app.set_rules('teacher_attendance',
  $$app.can('teachers', 'view')
    or (app.role() = 'teacher' and teacher_id = app.entity_id())$$,
  $$app.can('scanner', 'use') or app.can('attendance', 'add')$$,
  $$app.can('scanner', 'use') or app.can('attendance', 'edit')$$);

select app.set_rules('worker_attendance',
  $$app.can('workers', 'view')
    or (app.role() = 'worker' and worker_id = app.entity_id())$$,
  $$app.can('scanner', 'use') or app.can('workers', 'edit')$$,
  $$app.can('scanner', 'use') or app.can('workers', 'edit')$$);

-- طلبات الأستاذ: يرسلها الأستاذ معلّقة، ويراجعها من له الصلاحية فقط.
select app.set_rules('session_requests',
  $$app.can('requests', 'view')
    or (app.role() = 'teacher' and teacher_id = app.entity_id())$$,
  $$app.role() = 'teacher' and teacher_id = app.entity_id()
    and app.teaches_group(group_id)
    and status = 'pending' and reviewed_by is null$$,
  $$app.can('requests', 'edit')$$);

-- المالية.
select app.set_rules('payments',
  $$app.can('payments', 'view') or app.parent_of(student_id)$$,
  $$app.can('receive_money', 'use') and received_by = app.uid()$$,
  $$app.can('payments', 'edit') or app.can('payments', 'delete')$$,
  $$(deleted_at is null and app.can('payments', 'edit'))
    or (deleted_at is not null and app.can('payments', 'delete'))$$);

select app.set_rules('student_credits',
  $$app.can('payments', 'view') or app.parent_of(student_id)$$,
  $$app.can('attendance', 'edit') or app.can('students', 'add')
    or app.can('payments', 'add') or app.can('scanner', 'use')$$,
  $$app.can('attendance', 'edit') or app.can('payments', 'edit')
    or app.can('scanner', 'use')$$);

select app.set_rules('registration_fees',
  $$app.can('payments', 'view') or app.parent_of(student_id)$$,
  $$app.can('students', 'add') or app.can('receive_money', 'use')$$,
  $$app.can('students', 'edit') or app.can('receive_money', 'use')$$);

select app.staff_rules('teacher_payouts', 'payouts',
  $$app.role() = 'teacher' and teacher_id = app.entity_id()$$);
select app.staff_rules('expense_categories', 'expenses');
select app.staff_rules('expenses', 'expenses');

-- الرسائل القصيرة: أي جهاز إدارة يضيف إلى الطابور؛ الإرسال وتحديث الحالة
-- لمن له صلاحية الإرسال (هاتف المدير).
select app.set_rules('sms_queue',
  $$app.can('sms', 'view') or created_by = app.uid()$$,
  'app.is_staff() and created_by = app.uid()',
  $$app.can('sms', 'use') or app.can('sms', 'edit')$$);
select app.staff_rules('sms_templates', 'sms', 'app.is_staff()');

-- المحادثات: الأعضاء فقط، وصاحب المدرسة (أو من له صلاحية المراقبة) يرى
-- الكل ويكتب ويدير الغرف، مع تحقق العلاقة النشطة لمجموعات الأستاذ والوليّ.
select app.set_rules('chat_rooms',
  $$app.can('chat', 'view') or app.can('chat', 'edit')
    or app.is_room_member(id) or created_by = app.uid()$$,
  $$created_by = app.uid() and app.can_create_chat_room(type, group_id)$$,
  $$app.can('chat', 'edit') or app.is_room_member(id)$$,
  $$
    (deleted_at is null and
      (app.can('chat', 'edit') or app.is_room_member(id)))
    or (deleted_at is not null and app.can('chat', 'edit'))
  $$);

select app.set_rules('chat_members',
  $$app.can('chat', 'view') or app.can('chat', 'edit')
    or app.is_room_member(room_id)$$,
  $$app.can('chat', 'add') or app.can('chat', 'edit')
    or app.can_add_chat_member(room_id, user_id, user_role)$$,
  $$app.can('chat', 'edit')
    or (user_id = app.uid() and app.is_room_member(room_id))
    or (app.teaches_group(app.chat_room_group(room_id))
      and app.active_chat_group(app.chat_room_group(room_id)))$$,
  $$app.can('chat', 'edit')
    or (user_id = app.uid() and user_role = app.role()
      and app.is_room_member(room_id))
    or (app.teaches_group(app.chat_room_group(room_id))
      and app.active_chat_group(app.chat_room_group(room_id))
      and (deleted_at is not null or app.group_chat_participant(
        app.chat_room_group(room_id), user_id, user_role)))$$);

select app.set_rules('chat_messages',
  $$app.can('chat', 'view') or app.can('chat', 'edit')
    or app.is_room_member(room_id)$$,
  $$sender_id = app.uid() and sender_role = app.role()
    and (app.is_room_member(room_id)
    or app.can('chat', 'edit'))
    and app.room_open(room_id)$$,
  $$app.can('chat', 'edit') or app.can('chat', 'delete') or
    (sender_id = app.uid() and app.is_room_member(room_id))$$);

-- النتائج والملفات: يكتبها أستاذ المجموعة، ويقرؤها الوليّ.
select app.set_rules('grades',
  $$app.can('students', 'view') or app.teaches_group(group_id)
    or app.parent_of(student_id)$$,
  $$app.teaches_group(group_id) or app.is_owner()$$,
  $$app.teaches_group(group_id) or app.is_owner()$$);

select app.set_rules('group_files',
  $$app.can('groups', 'view') or app.teaches_group(group_id)
    or app.parent_in_group(group_id)$$,
  $$app.teaches_group(group_id) or app.is_owner()$$,
  $$app.teaches_group(group_id) or app.is_owner()$$);

-- الإشعارات: كلٌّ يقرأ إشعاراته ويعلّمها مقروءة؛ أي مستخدم يرسل إشعاراً
-- باسمه، ويرى ما أرسله (الخادم يشترط قراءة الصف المرسَل عند المزامنة).
select app.set_rules('notifications',
  'user_id = app.uid() or sender_id = app.uid()',
  'app.role() is not null and sender_id = app.uid()',
  'user_id = app.uid()');

-- سجل العمليات: يُضاف فقط ولا يُعدَّل. يقرؤه من له الصلاحية، وكلٌّ يرى
-- ما كتبه هو. كل عملية تُنسب إلى الحساب الذي قام بها فعلاً.
select app.set_rules('audit_log',
  $$app.can('audit', 'view') or user_id = app.uid()$$,
  $$app.role() is not null and user_id = app.uid()$$,
  null);

-- ---------------------------------------------------------------------------
-- عروض محجوبة للوليّ: اسم الأستاذ وصورته ومجموعات أبنائه، دون رمز QR
-- ولا البريد ولا مبلغ الأستاذ. الأعمدة مطابقة للجدول الأصلي ليُخزَّن محلياً.
-- ---------------------------------------------------------------------------

create or replace view public.teacher_cards as
  select t.id, t.created_at, t.updated_at, t.deleted_at, t.name,
         ''::text as phone, ''::text as email, t.photo_url,
         null::text as photo_local_path, 0::bigint as rate_per_student,
         ('X-' || t.id)::text as qr_code, null::text as auth_user_id,
         t.synced_at
    from public.teachers t
   where app.role() = 'parent' and exists (
     select 1 from public.groups g
      where g.teacher_id = t.id and app.parent_in_group(g.id));

create or replace view public.group_cards as
  select g.id, g.created_at, g.updated_at, g.deleted_at, g.number,
         g.subject_id, g.teacher_id, g.room_id, g.sessions_per_cycle,
         g.current_cycle_number, null::bigint as rate_per_student,
         g.archived_at, g.synced_at
    from public.groups g
   where app.parent_in_group(g.id);

-- ---------------------------------------------------------------------------
-- حارس الحصص: لا يتغير موعد دون موافقة الإدارة. الأستاذ ينشئ حصة فقط إن
-- طابقت خانة من الجدول الأسبوعي لمجموعته، ولا يغيّر موعداً ولا قاعة ولا
-- حالة ولا دورة.
-- ---------------------------------------------------------------------------

create or replace function app.guard_teacher_session() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if app.role() is distinct from 'teacher' then
    return new;
  end if;
  if tg_op = 'INSERT' then
    if new.status <> 'normal' or not exists (
      select 1 from group_slots gs
       where gs.group_id = new.group_id and gs.deleted_at is null
         and gs.start_minutes = new.start_minutes
         and gs.weekday = extract(isodow from new.date::date)) then
      raise exception 'الأستاذ لا ينشئ حصة خارج الجدول الأسبوعي'
        using errcode = '42501';
    end if;
  elsif new.date is distinct from old.date
     or new.start_minutes is distinct from old.start_minutes
     or new.end_minutes is distinct from old.end_minutes
     or new.room_id is distinct from old.room_id
     or new.status is distinct from old.status
     or new.group_id is distinct from old.group_id
     or new.cycle_number is distinct from old.cycle_number
     or new.deleted_at is distinct from old.deleted_at then
    raise exception 'لا يتغير موعد الحصة دون موافقة الإدارة'
      using errcode = '42501';
  end if;
  return new;
end
$$;

drop trigger if exists trg_guard_teacher_session on public.sessions;
create trigger trg_guard_teacher_session before insert or update
  on public.sessions
  for each row execute function app.guard_teacher_session();

-- ---------------------------------------------------------------------------
-- الامتيازات
-- ---------------------------------------------------------------------------

revoke all on all tables in schema public from anon;
grant select, insert, update on all tables in schema public to authenticated;
grant usage, select on sequence public.sync_seq to authenticated;
grant execute on all functions in schema app to authenticated;
