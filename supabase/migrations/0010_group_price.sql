-- سعر الشهر لكل فوج: يُعيَّن عند إنشاء الفوج فقط (سعر فوج المتوسط غير سعر فوج الابتدائي)، وبه يُنسب التلاميذ إليه.
--
-- المخطط نفسه مولَّد في 0001_schema.sql للخوادم الجديدة؛ هذا الملف للخوادم المنشورة قبل هذا العمود (يُطبَّق مرة واحدة
-- هناك). كله آمن عند التكرار. انشر الخادم بهذا الترحيل **قبل** وصول التطبيقات التي ترسل العمود إلى أجهزتها.
alter table public."groups" add column if not exists "monthly_price" bigint not null default 0;

-- القيمة الافتراضية صفر تبقى (ولو في خادم جديد أنشأه 0001 بلا قيمة): تطبيق أقدم لا يرسل العمود فلا يفشل إنشاء فوج منه.
alter table public."groups" alter column "monthly_price" set default 0;

-- الفوج القائم يأخذ سعر مادته ومبلغ أستاذه الحاليين: لكل فوج قيمتاه، وهو ما تفعله القاعدة المحلية في ترقيتها نفسه.
-- التحديث يمرّ بمشغّل المزامنة فتسحبه الأجهزة (ولا يغيّر وقت التعديل فلا يتغلب على تعديل أحدث منه).
update public."groups" g
   set "monthly_price" = s."monthly_price"
  from public."subjects" s
 where s."id" = g."subject_id" and g."monthly_price" = 0 and s."monthly_price" > 0;

update public."groups" g
   set "rate_per_student" = t."rate_per_student"
  from public."teachers" t
 where t."id" = g."teacher_id" and g."rate_per_student" is null;
