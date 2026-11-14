-- صور الفواتير تحتاج دقة أعلى من صور الوجوه، لكن تبقى محدودة بحجم الملف
-- الأقصى المقبول في PhotoProcessor (10 MiB).
do $$
begin
  if not exists (select 1 from pg_namespace where nspname = 'storage') then
    return;
  end if;

  update storage.buckets
  set file_size_limit = 10485760
  where id = 'photos';
end
$$;
