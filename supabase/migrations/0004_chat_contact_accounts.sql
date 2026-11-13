-- حسابات مختصرة لجهات المحادثة؛ تبقي البريد وحالة كلمة السر سرّية.
-- يسحب الأستاذ والوليّ هذا العرض المحلي بدلاً من قراءة صفوف الحسابات كاملة.
create or replace view public.chat_user_accounts
with (security_barrier = true) as
select
  a.id,
  a.created_at,
  a.updated_at,
  a.deleted_at,
  a.synced_at,
  case
    when a.id = app.uid() then a.email
    else 'chat-contact+' || encode(convert_to(a.id, 'UTF8'), 'hex')
      || '@invalid.local'
  end as email,
  a.role,
  a.entity_id,
  a.display_name,
  case when a.id = app.uid() then a.must_change_password else false end
    as must_change_password
from public.user_accounts a
where a.id = app.uid() or app.can_message_account(a.id);

grant select on public.chat_user_accounts to authenticated;
