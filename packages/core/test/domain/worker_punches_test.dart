import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

void main() {
  group('WorkPunches', () {
    test('سجل قديم بلا عمود الدخولات: زوج واحد من الدخول إلى الخروج', () {
      expect(WorkPunches.parse(null, 1000, 5000), [
        const WorkPunch(1000, 5000),
      ]);
      expect(WorkPunches.parse(null, 1000, null), [const WorkPunch(1000)]);
      expect(WorkPunches.parse(null, null, null), isEmpty);
    });

    test('ترميز ثم قراءة يعيد الدخولات نفسها', () {
      const punches = [WorkPunch(1000, 2000), WorkPunch(3000)];
      final json = WorkPunches.encode(punches);
      expect(json, '[[1000,2000],[3000,null]]');
      expect(WorkPunches.parse(json, 1000, 2000), punches);
    });

    test('خروج أحدث مسحه جهاز قديم يغلق آخر دخول مفتوح', () {
      expect(WorkPunches.parse('[[1000,2000],[3000,null]]', 1000, 9000), [
        const WorkPunch(1000, 2000),
        const WorkPunch(3000, 9000),
      ]);
    });

    test('نص تالف يرجع إلى الدخول والخروج', () {
      expect(WorkPunches.parse('not json', 1000, 5000), [
        const WorkPunch(1000, 5000),
      ]);
    });

    test('مجموع الدقائق للدخولات المغلقة فقط', () {
      const minute = Duration.millisecondsPerMinute;
      expect(
        WorkPunches.workedMinutes(const [
          WorkPunch(0, 60 * minute),
          WorkPunch(120 * minute, 150 * minute),
          WorkPunch(200 * minute),
        ]),
        90,
      );
      expect(WorkPunches.workedMinutes(const [WorkPunch(0)]), isNull);
    });
  });

  group('WorkerDay.statusOn', () {
    WorkerDay day({
      String date = '2026-11-10',
      bool present = true,
      WorkDayKind paid = WorkDayKind.off,
      bool overridden = false,
      List<WorkPunch> punches = const [WorkPunch(0, 60000)],
    }) => WorkerDay(
      date: date,
      present: present,
      paidKind: paid,
      wage: 0,
      lateMinutes: 0,
      overridden: overridden,
      checkIn: present ? 0 : null,
      checkOut: present ? 60000 : null,
      punches: present ? punches : const [],
    );

    test('غائب أحمر، ونصف يوم أو يوم كامل أخضر، وأقل من النصف برتقالي', () {
      const today = '2026-11-20';
      expect(day(present: false).statusOn(today), WorkDayStatus.absent);
      expect(
        day(paid: WorkDayKind.half).statusOn(today),
        WorkDayStatus.complete,
      );
      expect(
        day(paid: WorkDayKind.full).statusOn(today),
        WorkDayStatus.complete,
      );
      expect(day().statusOn(today), WorkDayStatus.short);
      expect(
        day(punches: const [WorkPunch(0)]).statusOn(today),
        WorkDayStatus.short,
      );
    });

    test('يوم مقبل، واليوم قبل الدخول، وفي العمل الآن', () {
      const today = '2026-11-10';
      expect(day(date: '2026-11-11').statusOn(today), WorkDayStatus.future);
      expect(day(present: false).statusOn(today), WorkDayStatus.future);
      expect(
        day(punches: const [WorkPunch(0)]).statusOn(today),
        WorkDayStatus.working,
      );
    });

    test('تعديل المدير: غائب أحمر وكامل أخضر', () {
      const today = '2026-11-20';
      expect(day(overridden: true).statusOn(today), WorkDayStatus.absent);
      expect(
        day(overridden: true, paid: WorkDayKind.full).statusOn(today),
        WorkDayStatus.complete,
      );
    });
  });
}
