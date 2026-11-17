import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

/// أرقام عربية-هندية وفارسية: واجهة المشروع بأرقام لاتينية.
final RegExp _easternDigits = RegExp('[٠-٩۰-۹]');

void main() {
  group('كتالوج الدروس', () {
    for (final app in AppIdentity.values) {
      group(app.name, () {
        final lessons = TutorialCatalog.forApp(app);

        test('له دروس، أولها الجولة السريعة', () {
          expect(lessons, isNotEmpty);
          expect(lessons.first.id, TutorialCatalog.welcomeId);
        });

        test('معرّفاتها فريدة ولكل درس عنوان وملخص وخطوات', () {
          expect(
            lessons.map((l) => l.id).toSet(),
            hasLength(lessons.length),
            reason: 'معرّف مكرر',
          );
          for (final lesson in lessons) {
            expect(lesson.title.trim(), isNotEmpty, reason: lesson.id);
            expect(lesson.summary.trim(), isNotEmpty, reason: lesson.id);
            expect(lesson.steps, isNotEmpty, reason: lesson.id);
            for (final step in lesson.steps) {
              expect(step.title.trim(), isNotEmpty, reason: lesson.id);
              expect(
                step.body.trim().length,
                greaterThan(15),
                reason: lesson.id,
              );
            }
          }
        });

        test('أرقامها لاتينية ولا يظهر فيها بريد الدخول الداخلي', () {
          for (final lesson in lessons) {
            final all = [
              lesson.title,
              lesson.summary,
              for (final step in lesson.steps) ...[step.title, step.body],
            ].join('\n');
            expect(all, isNot(contains(_easternDigits)), reason: lesson.id);
            expect(all, isNot(contains('@school.local')), reason: lesson.id);
          }
        });

        test('العثور على درس بمعرّفه، والمجهول يعطي null', () {
          for (final lesson in lessons) {
            expect(TutorialCatalog.find(app, lesson.id), same(lesson));
          }
          expect(TutorialCatalog.find(app, 'لا-يوجد'), isNull);
        });
      });
    }
  });

  group('درس كل تبويب', () {
    test('الإدارة', () {
      TutorialLesson? lesson(String path) =>
          TutorialCatalog.forTab(AppIdentity.admin, path);
      expect(lesson('/students')?.id, 'students');
      expect(lesson('/groups')?.id, 'groups');
      expect(lesson('/payments')?.id, 'payments');
      expect(lesson('/dashboard')?.id, TutorialCatalog.welcomeId);
      expect(lesson('/more'), isNull, reason: 'يُفتح له الدليل كله');
    });

    test('الأستاذ', () {
      TutorialLesson? lesson(String path) =>
          TutorialCatalog.forTab(AppIdentity.teacher, path);
      expect(lesson('/home')?.id, 'attendance');
      expect(lesson('/groups')?.id, 'groups');
      expect(lesson('/requests')?.id, 'requests');
      expect(lesson('/payout')?.id, 'earnings');
      expect(lesson('/account')?.id, TutorialCatalog.welcomeId);
    });

    test('الوليّ', () {
      TutorialLesson? lesson(String path) =>
          TutorialCatalog.forTab(AppIdentity.student, path);
      expect(lesson('/attendance')?.id, 'attendance');
      expect(lesson('/schedule')?.id, 'schedule');
      expect(lesson('/payments')?.id, 'payments');
      expect(lesson('/home')?.id, TutorialCatalog.welcomeId);
    });

    test('مسار مجهول يعطي الجولة السريعة لا خطأ', () {
      for (final app in AppIdentity.values) {
        expect(
          TutorialCatalog.forTab(app, '/غير-معروف')?.id,
          anyOf(TutorialCatalog.welcomeId, isNull),
        );
      }
    });
  });
}
