-- بديل محلي لما يوفّره Supabase جاهزاً: الأدوار والدالة auth.uid().
-- يُطبَّق في الاختبارات المحلية وفي GitHub Actions فقط، وليس على Supabase.
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
end
$$;

create schema if not exists auth;

create or replace function auth.uid() returns text
language sql stable as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
$$;

grant usage on schema auth to authenticated, anon;
grant usage on schema public to authenticated, anon;
