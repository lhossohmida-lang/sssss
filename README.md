# نظام إدارة مدرسة دروس خصوصية

ثلاثة تطبيقات Flutter في مستودع واحد (monorepo)، بواجهة عربية كاملة من اليمين إلى
اليسار والعملة دج، تعمل **محلياً أولاً**: كل كتابة تُحفظ على الجهاز ثم تُزامَن مع
خادم Supabase حين يتوفر الاتصال.

| المسار | المحتوى |
| --- | --- |
| `apps/admin` | تطبيق الإدارة (Android + Windows): التلاميذ والمجموعات والحضور والمدفوعات والأساتذة والعمال والرسائل والتقارير والمساعد |
| `apps/teacher` | تطبيق الأستاذ (Android): حصصه وحضورها والطلبات والخلاص والنتائج والملفات |
| `apps/student` | تطبيق الوليّ والتلميذ (Android): الأبناء وحضورهم وجدولهم ومدفوعاتهم ونتائجهم ورمز الدخول |
| `packages/core` | القاعدة المحلية (drift)، الخدمات وقواعد الحساب، المزامنة، المصادقة |
| `packages/ui` | نظام التصميم claymorphism والهيكل المشترك والشاشات المشتركة |
| `packages/chat` | المحادثات |
| `packages/sms` | طابور الرسائل القصيرة وعامل الإرسال |
| `packages/assistant` | المساعد الذكي (عميل النموذج والأدوات المقيَّدة بالدور) |
| `supabase/` | مخطط الخادم وقواعد الصلاحيات والتخزين ودالة المساعد واختبارات SQL |

## 1. المتطلبات

- **Flutter 3.47.9** (القناة المستقرة؛ هذا هو الإصدار المثبَّت في مسارات البناء).
- **Android**: Android SDK وJDK 17 لبناء ملفات APK.
- **Windows** (نسخة الإدارة): Visual Studio مع حِمل «Desktop development with C++».
- على Linux أو macOS يثبّت `source tool/setup_env.sh` Flutter ويجلب الحزم؛ على Windows ثبّت
  Flutter يدوياً ثم نفّذ `flutter pub get` من جذر المشروع.

## 2. التشغيل للمطوّر

```bash
flutter pub get
dart format .                                      # التنسيق
flutter analyze --fatal-infos --fatal-warnings     # التحليل: صفر ملاحظات
dart run melos run test --no-select                # كل اختبارات الحزم
```

على حاسوب بطيء قد يُفسد التوازي زمن الاختبارات؛ شغّل الحزم بالتتابع:

```bash
dart run melos exec --concurrency=1 --dir-exists=test -- "flutter test"
```

تشغيل تطبيق: `cd apps/admin && flutter run -d windows` (أو `-d <جهاز Android>`)، وكذلك
`apps/teacher` و`apps/student`.

## 3. الوضع المحلي والاتصال بالخادم

الاتصال بالخادم يُمرَّر وقت البناء بـ`--dart-define`، ولا يُحفظ شيء منه في المستودع
(وهو عام):

```bash
flutter build apk --release \
  --dart-define=SUPABASE_URL=https://<مشروعك>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<المفتاح العام anon/publishable>
```

المفتاح العام مصمَّم ليُضمَّن في التطبيقات؛ صلاحيات البيانات يحميها RLS على الخادم لا
سرّيته. **دون هذين المتغيرين يعمل التطبيق في الوضع المحلي**: لا خادم ولا مزامنة، وتُنشأ
القاعدة على الجهاز ويُنشأ حساب صاحب المدرسة عند أول تشغيل.
لا تضع مفتاح `service_role` ولا أي مفتاح سرّي في التطبيق أو المستودع.

## 4. إعداد Supabase

ملفات الخادم في `supabase/migrations` وتُطبَّق **بهذا الترتيب** على مشروع جديد (من
محرر SQL في لوحة Supabase أو `supabase db push`):

| الملف | المحتوى |
| --- | --- |
| `0001_schema.sql` | الجداول والفهارس ومحفِّزات ختم المزامنة (مولَّد من مخطط drift) |
| `0002_rls.sql` | صلاحيات الصفوف لكل دور (صاحب المدرسة، العامل بصلاحياته، الأستاذ، الوليّ) والعروض المحجوبة `teacher_cards` و`group_cards` |
| `0003_storage.sql` | مخزنا الملفات `photos` (يكتبها الموظفون) و`files` (ملفات المجموعات والمرفقات) |
| `0004_chat_contact_accounts.sql` | حسابات جهات الاتصال للمحادثات |
| `0005_push_installations.sql` | تثبيتات إشعارات الدفع |
| `0006_photo_upload_limit.sql` | حد حجم الصور |

بعد تغيير جداول drift: `dart run build_runner build` داخل `packages/core`، ثم أعد توليد
مخطط الخادم: `UPDATE_SCHEMA=1 flutter test test/data/supabase_schema_test.dart`
(في PowerShell: `$env:UPDATE_SCHEMA=1` قبل الأمر) وأضف الملفات المولَّدة.

اختبارات الخادم تعمل على PostgreSQL 16 معزول:

```bash
tool/pg_test.sh        # يحتاج PostgreSQL 16 وbash؛ مهمة server-sql في Actions تشغّلها عند كل push
```

> **حالة التهيئة الآلية:** تطبيق المخطط على مشروع Supabase الحقيقي وإنشاء حساب المدير
> الأول، واختبار المزامنة وRealtime وStorage عليه، هي المهمتان 8.1 و8.2 من `PLAN.md`
> وتحتاجان بيانات المشروع (انظر `QUESTIONS.md`).

## 5. المساعد الذكي (دالة الخادم)

المساعد يمرّ عبر دالة Supabase Edge في `supabase/functions/assistant`: التطبيق يرسل
الطلب بجلسة المستخدم، والدالة تتحقق من دوره وتتصل بنموذج لغوي عبر واجهة **متوافقة مع
OpenAI** (OpenRouter افتراضياً). **مفتاح النموذج لا يُضمَّن في أي تطبيق** بل يُحفظ سرّاً
على الخادم، ولكل مدرسة مفتاحها (ويفضَّل أن يكون بحد إنفاق):

| الإعداد | الاستعمال |
| --- | --- |
| `LLM_API_KEY` | مفتاح المزوّد (سرّ) |
| `LLM_MODEL` | اسم النموذج؛ الافتراضي `openrouter/free` |
| `LLM_BASE_URL` | رابط الواجهة؛ الافتراضي `https://openrouter.ai/api/v1` (https فقط) |

للتجربة: نموذج مجاني على OpenRouter (اسمه ينتهي بـ`:free` ويدعم الأدوات) **ببيانات
وهمية فقط**، فمزوّدو المجاني قد يسجّلون الطلبات. وللعميل الحقيقي نموذج مدفوع: يُبدَّل
بتغيير `LLM_MODEL` ثم تشغيل مسار `supabase-deploy`، دون إعادة بناء أي تطبيق. حدود
المجاني 20 طلباً في الدقيقة و50 يومياً (1000 بعد شراء رصيد 10)، وكل استدعاء أداة
يستهلك طلباً.

مسار `supabase-deploy` يضبط هذه الأسرار من Environment المدرسة ويرفع الدوال؛ ويدوياً:

```bash
supabase secrets set LLM_API_KEY=<مفتاح المزوّد> LLM_MODEL=<اسم النموذج>
supabase functions deploy assistant
```

`SUPABASE_URL` ومفاتيح المشروع (`SUPABASE_PUBLISHABLE_KEYS` و`SUPABASE_SECRET_KEYS`)
توفّرها منصة Supabase للدالة. أدوات المساعد مقيَّدة بالدور والجلسة، وأي تغيير يطلبه يظهر
معاينةً وينتظر تأكيداً صريحاً من المستخدم. دون اتصال أو دون إعداد الدالة تعرض الشاشة
أن المساعد غير متاح. اختبارات الدالة: `deno test --allow-env supabase/functions/assistant/index_test.ts`.

على Android يملأ الإملاء الصوتي مسودة قابلة للتعديل ولا يُرسل الكلام حتى يضغط المستخدم
«إرسال»، وتقرأ الإجابة صوتياً بمحرك Android؛ Windows نصي فقط.

## 6. النسخ الاحتياطي والتصدير على Google Drive

تطبيق الإدارة يرفع إلى Drive حساب صاحب المدرسة وحده (نطاق `drive.file` فقط): نسخة
احتياطية يومية من القاعدة (يحتفظ Drive بآخر 30 منها) وملفات التصدير (مثل كشف الحضور
بصيغة Excel) في مسارات مرتَّبة بالفئة. تنشأ نسخة اليوم عند بدء الإدارة وتُراجَع كل ساعة أثناء فتح التطبيق.

متغيرات البناء (انظر `.github/workflows/build.yml`):

| المتغير | الاستعمال |
| --- | --- |
| `GOOGLE_DRIVE_OWNER_EMAIL` | بريد صاحب المدرسة المسموح له بالربط |
| `GOOGLE_DRIVE_WINDOWS_CLIENT_ID` و`GOOGLE_DRIVE_WINDOWS_CLIENT_SECRET` | عميل OAuth لنسخة Windows (تدفق desktop PKCE) |

يحتاج Android عميل OAuth من نوع Android في Google Cloud بصمةُ SHA-1 لمفتاح توقيع
التطبيق (المهمة 8.4). في CI تُحفظ الأسرار في **Settings ← Secrets and variables ←
Actions**: `GOOGLE_DESKTOP_CLIENT_SECRET` سرّ، و`GOOGLE_DRIVE_OWNER_EMAIL` و
`GOOGLE_DRIVE_WINDOWS_CLIENT_ID` متغيّران.

## 7. إشعارات الدفع (Firebase)

الإشعارات اللحظية داخل التطبيق تعمل عبر Realtime. إشعارات الدفع تُفعَّل بـ
`--dart-define=FIREBASE_PUSH_ENABLED=true` مع ملف `google-services.json` لكل تطبيق في
`apps/<التطبيق>/android/app/`، وهو مشروع Firebase يُنشأ بحساب صاحب المدرسة (المهمة 8.3).
دون ذلك تبقى الإشعارات داخل التطبيق فقط.

## 8. الرسائل القصيرة وصلاحياتها (Android)

الرسائل تُرسل **من هاتف الإدارة نفسه** بشريحته (لا خدمة وسيطة): تطبيق الإدارة على
Android يفرغ طابور `sms_queue` برسالة كل 3 ثوانٍ. الإرسال الفعلي من Android وحده (منصة
الإرسال تستعمل `SmsManager`)؛ ما يُضاف إلى الطابور من أي جهاز يُرسَل حين يفرغه هاتف الإدارة.

- الصلاحيات في `AndroidManifest.xml`: `SEND_SMS` و`READ_PHONE_STATE` (تعرّف الشرائح)
  و`FOREGROUND_SERVICE` و`FOREGROUND_SERVICE_SPECIAL_USE` و`POST_NOTIFICATIONS`. تُطلب
  `SEND_SMS` و`READ_PHONE_STATE` وقت التشغيل من شاشة الرسائل عند أول إرسال.
- **الهاتف بشريحتين** لا يرسل حتى تُختار الشريحة من إعدادات الرسائل (تُحفظ خانتها لا
  معرّف اشتراكها المؤقت). شريحة واحدة تُختار تلقائياً.
- ساعات الهدوء: الرسائل بين 21:00 و07:00 تُؤجَّل إلى 07:00. وللحد الشهري خيار في
  الإعدادات (صفر بلا حد).
- الفشل المؤقت يُعاد بمهل متزايدة (دقيقة ثم 5 ثم 15 ثم 60) ثم يُعلَّم فاشلاً بعد 5
  محاولات؛ ويمكن إعادة محاولة الفاشل يدوياً. رسائل إنشاء الحسابات وكلمات السر تُمسح
  كلمة السر منها بعد الإرسال.
- المرسل يعمل بخدمة مرئية في المقدمة أثناء التفريغ، فيظهر إشعار حتى ينتهي.
- قوالب الرسائل تُعدَّل من شاشة الرسائل بمتغيرات مثل `{name}` و`{school}`.

## 9. بناء كل تطبيق

```bash
# Android: apk لكل تطبيق
cd apps/admin   && flutter build apk --release    # + --dart-define لـ SUPABASE_* و GOOGLE_DRIVE_OWNER_EMAIL
cd apps/teacher && flutter build apk --release
cd apps/student && flutter build apk --release

# Windows (نسخة الإدارة)
cd apps/admin && flutter build windows --release
```

التوقيع: يقرأ Gradle المفتاح من متغيرات البيئة `SCHOOL_KEYSTORE_PATH` و
`SCHOOL_KEYSTORE_PASSWORD` و`SCHOOL_KEY_ALIAS` و`SCHOOL_KEY_PASSWORD`؛ فإن لم توجد وُقّع
الإصدار بمفتاح النسخ التجريبية `tool/signing/preview.jks` (غير سرّي، للنسخ التجريبية فقط).
**مفتاح التوقيع النهائي سرّ** يُحفظ في أسرار GitHub (`SCHOOL_KEYSTORE_BASE64` وكلمتا
السر والاسم المستعار) ولا يدخل المستودع.

تثبيت الـAPK من الهاتف: نزّله من صفحة **Releases** في GitHub ثم افتحه، وفعّل «تثبيت
تطبيقات من مصادر غير معروفة» لمتصفح التنزيل إن طُلب.

### مسارات GitHub Actions

| المسار | متى يعمل | ماذا يفعل |
| --- | --- | --- |
| `check` | كل push وطلب دمج | التنسيق والتحليل الصارم ودالة المساعد وكل الاختبارات، ومهمة `server-sql` لاختبارات الخادم |
| `build` | تغيّر محتوى `RELEASE_VERSION` أو يدوياً | يبني ثلاثة APK ونسخة Windows وينشرها في GitHub Releases باسم النسخة |
| `perf` | يدوياً أو عند تغيير اختبار القياس | قياس زمن الإطارات على محاكي Android (انظر `PERFORMANCE.md`) |

إصدار نسخة: غيّر محتوى `RELEASE_VERSION` (مثل `preview-5`) وادفع، وتحقق من نجاح `build`.

## 10. الجودة والأداء

- المنطق الحسابي كله في `packages/core` مرة واحدة ولا يتكرر في التطبيقات.
- كل كتابة في جدول مزامَن تمر عبر `SyncWriter` (حفظ + سجل عمليات + طابور مزامنة في
  معاملة واحدة)، والسجلات ذات المفتاح الطبيعي تأخذ معرّفها من `StableId`.
- اختبارات التكامل: `packages/core/test/integration` (تسجيل ← مسح ← دفع ← اكتمال دورة ←
  خلاص) و`packages/sms/test/integration` (طلب أستاذ ← موافقة ← SMS).
- مولّد بيانات الأداء (2000 تلميذ و100 مجموعة وسنة حضور و50 ألف رسالة):
  `PerfDataGenerator` في `package:school_core/testing.dart`.
- قياسات الاستعلامات والماسح وزمن الإطارات وميزانياتها وما أُصلح بها: **`PERFORMANCE.md`**
  (تمييز صريح بين أرقام حاسوب التطوير والمحاكي وهاتف حقيقي).

## 11. ملفات المتابعة

`PLAN.md` الخطة، `PROGRESS.md` حالة كل مهمة، `ANSWERS.md` المواصفات المعتمدة،
`DECISIONS.md` كل قرار وسببه، `QUESTIONS.md` الأسئلة والبيانات المؤجَّلة،
`PERFORMANCE.md` الأداء، `HANDOFF.md` و`LOCAL_PROMPT.md` للتناوب بين أدوات العمل.
