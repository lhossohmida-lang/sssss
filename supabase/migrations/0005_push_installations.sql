-- Firebase Installation IDs are private to one signed-in account and are not
-- included in the replicated local tables.
create table if not exists public.push_installations (
  installation_id text primary key
    check (length(installation_id) between 10 and 256),
  user_id text not null references public.user_accounts(id) on delete cascade,
  platform text not null check (platform = 'android'),
  updated_at bigint not null
);

select app.set_rules(
  'push_installations',
  'user_id = app.uid()',
  'user_id = app.uid()',
  'user_id = app.uid()'
);

drop policy if exists p_delete on public.push_installations;
create policy p_delete on public.push_installations
  for delete to authenticated using (user_id = app.uid());

revoke all on public.push_installations from anon;
grant select, insert, update, delete on public.push_installations to authenticated;
