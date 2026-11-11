-- مخازن الملفات وصلاحياتها. مخطط `storage` موجود في Supabase فقط، فهذا
-- الملف لا يفعل شيئاً على PostgreSQL المحلي، ويُختبر عند الربط بالمشروع
-- الحقيقي (المرحلة 8).
--
-- photos: صور التلاميذ والأساتذة وفواتير المصاريف. تكتبها الإدارة.
-- files:  ملفات المجموعات ومرفقات المحادثات. يكتبها أي مستخدم مسجَّل.
-- المخزنان خاصان: القراءة للمستخدمين المسجَّلين فقط.
do $$
begin
  if not exists (select 1 from pg_namespace where nspname = 'storage') then
    return;
  end if;

  insert into storage.buckets (id, name, public, file_size_limit)
  values ('photos', 'photos', false, 2097152),
         ('files', 'files', false, 10485760)
  on conflict (id) do update set file_size_limit = excluded.file_size_limit;

  drop policy if exists school_read on storage.objects;
  create policy school_read on storage.objects for select to authenticated
    using (bucket_id in ('photos', 'files') and app.role() is not null);

  drop policy if exists school_photos_write on storage.objects;
  create policy school_photos_write on storage.objects for insert
    to authenticated
    with check (bucket_id = 'photos' and app.is_staff());

  drop policy if exists school_photos_update on storage.objects;
  create policy school_photos_update on storage.objects for update
    to authenticated
    using (bucket_id = 'photos' and app.is_staff())
    with check (bucket_id = 'photos' and app.is_staff());

  drop policy if exists school_files_write on storage.objects;
  create policy school_files_write on storage.objects for insert
    to authenticated
    with check (bucket_id = 'files' and app.role() is not null
                and owner = auth.uid());
end
$$;
