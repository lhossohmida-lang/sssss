-- سعر الشهر لكل فوج (الترحيل 0010): العمود وقيمته الافتراضية، وملء الفوج القائم من سعر مادته ومبلغ أستاذه.
-- تُشغَّل بعد 005_reset.sql (قاعدة بلا بيانات)، وتنظّف ما تكتبه.

do $$
begin
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'groups' and column_name = 'monthly_price'
       and is_nullable = 'NO' and column_default = '0') then
    raise exception 'groups.monthly_price غير موجود، أو ليس إلزامياً بقيمة افتراضية صفر';
  end if;
end
$$;

-- فوج أنشأه تطبيق أقدم: بلا سعر ولا مبلغ أستاذ.
insert into subjects (id, created_at, updated_at, name, monthly_price)
values ('gp-sub', 1, 1, 'مادة اختبار سعر الفوج', 2750),
       ('gp-free', 1, 1, 'مادة بلا سعر', 0);
insert into teachers (id, created_at, updated_at, name, phone, email, rate_per_student, qr_code)
values ('gp-t', 1, 1, 'أستاذ سعر الفوج', '0550000999', 'gp-t@school.local', 1230, 'T-GP-T');
insert into groups (id, created_at, updated_at, number, subject_id, teacher_id,
                    sessions_per_cycle, current_cycle_number, rate_per_student)
values ('gp-old', 1, 1, 91, 'gp-sub', 'gp-t', 8, 1, null),
       ('gp-set', 1, 1, 92, 'gp-sub', 'gp-t', 8, 1, 900),
       ('gp-nop', 1, 1, 93, 'gp-free', 'gp-t', 8, 1, null);
-- فوج خاص له سعره من إنشائه: لا يمسّه الترحيل.
update groups set monthly_price = 3400 where id = 'gp-set';

do $$
declare
  p bigint;
begin
  select monthly_price into p from groups where id = 'gp-old';
  if p <> 0 then raise exception 'السعر الافتراضي % وليس 0', p; end if;
end
$$;

-- رقم المزامنة قبل الملء: يجب أن يزيد بعده فتسحب الأجهزة ما تغيّر.
create temp table gp_before as
  select id, synced_at from groups where id in ('gp-old', 'gp-nop');

-- إعادة تطبيق الترحيل (آمن عند التكرار) تملأ القديم من مادته وأستاذه.
\ir ../migrations/0010_group_price.sql

do $$
declare
  old_g record;
  set_g record;
  nop_g record;
begin
  select monthly_price, rate_per_student into old_g from groups where id = 'gp-old';
  if old_g.monthly_price <> 2750 or old_g.rate_per_student <> 1230 then
    raise exception 'الفوج القديم أخذ % و% وليس 2750 و1230', old_g.monthly_price, old_g.rate_per_student;
  end if;
  select monthly_price, rate_per_student into set_g from groups where id = 'gp-set';
  if set_g.monthly_price <> 3400 or set_g.rate_per_student <> 900 then
    raise exception 'فوج له سعره تغيّر: % و%', set_g.monthly_price, set_g.rate_per_student;
  end if;
  -- مادة بلا سعر: يبقى الصفر (يأخذ التطبيق سعر مادته وقتها)، ومبلغ الأستاذ يُملأ.
  select monthly_price, rate_per_student into nop_g from groups where id = 'gp-nop';
  if nop_g.monthly_price <> 0 or nop_g.rate_per_student <> 1230 then
    raise exception 'فوج مادته بلا سعر أخذ % و%', nop_g.monthly_price, nop_g.rate_per_student;
  end if;
  -- التحديث مرّ بمشغّل المزامنة فتسحبه الأجهزة (synced_at زاد).
  if exists (
    select 1 from groups g join gp_before b on b.id = g.id where g.synced_at <= b.synced_at) then
    raise exception 'ملء الفوج القديم لم يمرّ بمشغّل المزامنة';
  end if;
end
$$;

drop table gp_before;
delete from groups where id in ('gp-old', 'gp-set', 'gp-nop');
delete from teachers where id = 'gp-t';
delete from subjects where id in ('gp-sub', 'gp-free');
