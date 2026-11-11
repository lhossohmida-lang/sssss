# نظام إدارة مدرسة دروس خصوصية

ثلاثة تطبيقات Flutter في مستودع واحد (monorepo)، بواجهة عربية كاملة.

| المسار | المحتوى |
| --- | --- |
| `apps/admin` | تطبيق الإدارة (Android + Windows) |
| `apps/teacher` | تطبيق الأستاذ (Android) |
| `apps/student` | تطبيق التلميذ والولي (Android) |
| `packages/core` | النماذج، القاعدة المحلية، المزامنة، قواعد الحساب |
| `packages/ui` | نظام التصميم claymorphism |
| `packages/chat` | المحادثات |
| `packages/sms` | الرسائل القصيرة |
| `packages/assistant` | المساعد الذكي |

## التشغيل للمطوّر

```bash
source tool/setup_env.sh                          # يثبّت Flutter ويجلب الحزم
flutter analyze --fatal-infos --fatal-warnings    # التحليل
dart run melos run test --no-select               # كل الاختبارات
```

## البناء والنشر

- `check`: يحلّل ويختبر عند كل push.
- `build`: يبني ثلاثة ملفات APK ونسخة Windows وينشرها في GitHub Releases. يُشغَّل بتغيير محتوى الملف `RELEASE_VERSION` (المحتوى هو اسم النسخة).

## ملفات المتابعة

`PLAN.md` الخطة، `PROGRESS.md` التقدم، `ANSWERS.md` المواصفات المعتمدة، `DECISIONS.md` القرارات.
