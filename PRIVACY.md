# Privacy Policy / سياسة الخصوصية

Last updated: 2026-11-16 — آخر تحديث: 2026-11-16

> This is the privacy policy of the **School Management** apps (admin, teacher, student/parent)
> published from this repository. It is a template: the project owner should review it and adapt
> it to the school's legal situation. — هذه سياسة خصوصية تطبيقات **إدارة المدرسة** (الإدارة والأستاذ
> والتلميذ/الوليّ). هي نموذج يراجعه مالك المشروع ويكيّفه مع الوضع القانوني للمدرسة.

## English

**What the apps do.** They help a private tutoring school manage students, groups, attendance,
payments, messages and notifications. Each school has its own private server (a separate Supabase
project); data of two schools is never mixed.

**Data processed.** Data entered by the school: names and phone numbers of students, parents and
teachers, levels, groups, attendance, payments, grades, chat messages, files shared with groups and
optional photos. It is stored on the user's device and on the school's own server.

**Who sees it.** Only the people the school gives an account to, according to their role (owner,
staff, teacher, parent). The service operator sets up and maintains each school's server and uses
school data only to run and support the service; it is not sold, shared with advertisers or used for
tracking. The apps contain no advertising and no analytics.

**Google Drive (admin app only).** If the school owner chooses to link Google Drive, the app asks
for the narrowest scope, `https://www.googleapis.com/auth/drive.file`: it can only create and
access files that the app itself creates (the daily database backup and exported files such as
attendance sheets) in the owner's own Drive. It cannot see or change any other file. The sign-in
token stays on the owner's device (secure storage); it is not sent to the operator or any third
party. The owner can disconnect at any time in the app and revoke access at
https://myaccount.google.com/permissions, and can delete the backups from Drive.

The app's use and transfer of information received from Google APIs adheres to the
[Google API Services User Data Policy](https://developers.google.com/terms/api-services-user-data-policy),
including the Limited Use requirements.

**Push notifications.** Firebase Cloud Messaging delivers notifications. The app registers a
Firebase installation ID with the school's server so that notifications reach the right device.

**AI assistant (optional).** When a school enables it, a request typed or dictated by a user, and
the school data needed to answer it, are sent from the school's server to the configured AI
provider to produce the answer. Any change the assistant proposes is only applied after the user
explicitly confirms it. Schools that do not configure it do not use it.

**SMS.** Messages to parents are sent from the admin phone with its own SIM card; no third-party
SMS service is involved.

**Security.** Data travels over HTTPS and access is restricted on the server by role.

**Children.** Data about minors is entered by the school, which decides how it is used. Parents or
guardians who want to see, correct or delete a child's data should contact the school.

**Deleting data.** The school can delete records in the app, and can delete its whole server.

**Contact.** Open an issue on this project's GitHub repository.

## العربية

**ماذا تفعل التطبيقات.** تساعد مدرسة دروس خصوصية على إدارة التلاميذ والأفواج والحضور والدفعات
والرسائل والإشعارات. لكل مدرسة خادمها الخاص (مشروع Supabase مستقل)، فلا تختلط بيانات مدرستين.

**البيانات المعالَجة.** ما تدخله المدرسة: أسماء التلاميذ والأولياء والأساتذة وأرقام هواتفهم، والمستويات
والأفواج والحضور والدفعات والنتائج ورسائل المحادثة وملفات الأفواج وصور اختيارية. تُحفظ على جهاز المستخدم
وعلى خادم المدرسة نفسها.

**من يراها.** من تمنحهم المدرسة حساباً فقط، بحسب دورهم (صاحب المدرسة، موظف، أستاذ، وليّ). مشغّل الخدمة يهيّئ
خادم كل مدرسة ويصونه، ولا يستعمل بياناتها إلا لتشغيل الخدمة ودعمها؛ ولا تُباع ولا تُشارك مع معلنين ولا تُستعمل
للتتبع. لا إعلانات في التطبيقات ولا أدوات تحليل.

**Google Drive (تطبيق الإدارة فقط).** إن اختار صاحب المدرسة ربط Drive يطلب التطبيق أضيق نطاق ممكن
`https://www.googleapis.com/auth/drive.file`: لا يصل إلا إلى الملفات التي ينشئها التطبيق نفسه (نسخة قاعدة البيانات
اليومية وملفات التصدير مثل كشوف الحضور) داخل Drive صاحب المدرسة، ولا يرى ولا يعدّل أي ملف آخر. يبقى رمز الدخول على
جهاز المالك (تخزين آمن) ولا يُرسَل إلى المشغّل ولا إلى طرف ثالث. يمكن للمالك فصل الربط في أي وقت من التطبيق، وسحب
الإذن من https://myaccount.google.com/permissions، وحذف النسخ من Drive.

استعمال التطبيق للمعلومات الواردة من واجهات Google ونقلها يلتزم بـ
[سياسة بيانات مستخدمي خدمات Google API](https://developers.google.com/terms/api-services-user-data-policy)
بما فيها شروط «الاستعمال المحدود».

**إشعارات الدفع.** تصل عبر Firebase Cloud Messaging، ويسجّل التطبيق معرّف تثبيت Firebase لدى خادم المدرسة ليصل
الإشعار إلى الجهاز الصحيح.

**المساعد الذكي (اختياري).** إن فعّلته المدرسة يُرسَل طلب المستخدم (مكتوباً أو إملاءً) وما يلزم من بيانات المدرسة
للإجابة من خادمها إلى مزوّد الذكاء الاصطناعي المضبوط لتوليد الإجابة. ولا يُطبَّق أي تغيير يقترحه المساعد إلا بعد
تأكيد المستخدم الصريح. المدرسة التي لا تضبطه لا تستعمله.

**الرسائل القصيرة.** تُرسل رسائل الأولياء من هاتف الإدارة بشريحته نفسها دون خدمة وسيطة.

**الأمان.** تنتقل البيانات عبر HTTPS ويقيّد الخادم الوصول بحسب الدور.

**الأطفال.** بيانات القاصرين تُدخلها المدرسة وهي التي تقرّر استعمالها. على الولي الذي يريد الاطلاع على بيانات ابنه
أو تصحيحها أو حذفها أن يراجع المدرسة.

**حذف البيانات.** للمدرسة حذف السجلات من التطبيق، وحذف خادمها كاملاً.

**التواصل.** افتح «Issue» في مستودع المشروع على GitHub.
