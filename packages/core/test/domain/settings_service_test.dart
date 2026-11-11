import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

import '../support/fixtures.dart';

void main() {
  group('SchoolSettings', () {
    test('القيم الافتراضية هي الاقتراحات المعتمدة', () {
      const s = SchoolSettings();
      expect(s.scanMarginMinutes, 30);
      expect(s.graceMinutes, 5);
      expect(s.duesSessionThreshold, 2);
      expect(s.registrationFeePeriod, FeePeriod.year);
      expect(s.registrationFee, 0);
      expect(s.semesters, isEmpty);
      expect(s.validate(), isEmpty);
    });

    test('الذهاب والعودة عبر أزواج الجدول', () {
      const original = SchoolSettings(
        schoolName: 'مدرسة النجاح',
        schoolAddress: 'حي 1 ماي، الجزائر',
        schoolPhone: '0550123456',
        registrationFee: 1500,
        registrationFeePeriod: FeePeriod.semester,
        semesters: [
          Semester(name: 'الفصل الأول', start: '2026-09-15', end: '2026-12-20'),
          Semester(
            name: 'الفصل الثاني',
            start: '2027-01-05',
            end: '2027-03-31',
          ),
        ],
        scanMarginMinutes: 45,
        graceMinutes: 10,
        duesSessionThreshold: 3,
      );
      expect(SchoolSettings.fromMap(original.toMap()), original);
    });

    test('مفاتيح غائبة أو تالفة تأخذ الافتراضي ولا ترمي', () {
      final s = SchoolSettings.fromMap({
        SettingKeys.registrationFee: 'abc',
        SettingKeys.registrationFeePeriod: 'decade',
        SettingKeys.semesters: '{not json',
        SettingKeys.scanMarginMinutes: '',
        SettingKeys.graceMinutes: ' 7 ',
      });
      expect(s.registrationFee, 0);
      expect(s.registrationFeePeriod, FeePeriod.year);
      expect(s.semesters, isEmpty);
      expect(s.scanMarginMinutes, 30);
      expect(s.graceMinutes, 7);
    });

    test('فصول تالفة تُتجاهل والسليمة تبقى', () {
      final s = SchoolSettings.fromMap({
        SettingKeys.semesters:
            '[{"name":"أ","start":"2026-09-01","end":"2026-12-31"},'
            '{"name":"ب","start":"bad","end":"2027-03-01"},'
            '{"name":1},"x"]',
      });
      expect(s.semesters.map((e) => e.name), ['أ']);
    });

    test('التحقق من الهاتف والمبلغ والحدود', () {
      expect(
        const SchoolSettings(schoolPhone: '0150123456')
            .validate()
            .containsKey(SettingKeys.schoolPhone),
        isTrue,
      );
      expect(
        const SchoolSettings(schoolPhone: '+213 550 12 34 56').validate(),
        isEmpty,
      );
      expect(
        const SchoolSettings(registrationFee: -10).validate().keys,
        contains(SettingKeys.registrationFee),
      );
      expect(
        const SchoolSettings(registrationFee: 1505).validate().keys,
        contains(SettingKeys.registrationFee),
      );
      expect(
        const SchoolSettings(scanMarginMinutes: 181).validate().keys,
        contains(SettingKeys.scanMarginMinutes),
      );
      expect(
        const SchoolSettings(graceMinutes: -1).validate().keys,
        contains(SettingKeys.graceMinutes),
      );
      expect(
        const SchoolSettings(duesSessionThreshold: 13).validate().keys,
        contains(SettingKeys.duesSessionThreshold),
      );
      expect(
        const SchoolSettings(
          scanMarginMinutes: 0,
          graceMinutes: 0,
          duesSessionThreshold: 0,
        ).validate(),
        isEmpty,
      );
    });

    test('الفصول: اسم مطلوب، بداية قبل النهاية، دون تداخل', () {
      String? error(List<Semester> semesters) =>
          SchoolSettings(semesters: semesters)
              .validate()[SettingKeys.semesters];
      expect(
        error(const [
          Semester(name: ' ', start: '2026-09-01', end: '2026-12-01'),
        ]),
        contains('أدخل الاسم'),
      );
      expect(
        error(const [
          Semester(name: 'أ', start: '2026-12-01', end: '2026-09-01'),
        ]),
        contains('بعد نهايته'),
      );
      expect(
        error(const [
          Semester(name: 'أ', start: '2026-09-01', end: '2026-12-01'),
          Semester(name: 'ب', start: '2026-12-01', end: '2027-03-01'),
        ]),
        contains('متداخلان'),
      );
      expect(
        error(const [
          Semester(name: 'ب', start: '2027-01-01', end: '2027-03-01'),
          Semester(name: 'أ', start: '2026-09-01', end: '2026-12-31'),
        ]),
        isNull,
      );
      expect(error(const []), isNull);
    });

    test('الفصل الذي يضم تاريخاً', () {
      const s = SchoolSettings(
        semesters: [
          Semester(name: 'الأول', start: '2026-09-15', end: '2026-12-20'),
          Semester(name: 'الثاني', start: '2027-01-05', end: '2027-03-31'),
        ],
      );
      expect(s.semesterOn('2026-09-15')?.name, 'الأول');
      expect(s.semesterOn('2026-12-20')?.name, 'الأول');
      expect(s.semesterOn('2026-12-25'), isNull);
      expect(s.semesterOn('2027-02-01')?.name, 'الثاني');
    });
  });

  group('SettingsService', () {
    late TestEnv env;
    late SettingsService service;

    setUp(() {
      env = TestEnv();
      service = SettingsService(env.db, env.writer);
    });
    tearDown(() => env.close());

    test('قاعدة فارغة: القيم الافتراضية', () async {
      expect(await service.load(), const SchoolSettings());
    });

    test('الحفظ ثم القراءة', () async {
      const wanted = SchoolSettings(
        schoolName: 'مدرسة النجاح',
        schoolPhone: '0550123456',
        registrationFee: 2000,
        registrationFeePeriod: FeePeriod.semester,
        semesters: [
          Semester(name: 'الأول', start: '2026-09-15', end: '2026-12-20'),
        ],
        scanMarginMinutes: 20,
      );
      await service.save(wanted);
      expect(await service.load(), wanted);
    });

    test(
      'الكتابة عبر SyncWriter: سجل عمليات وطابور مزامنة لكل مفتاح تغيّر',
      () async {
        await service.save(const SchoolSettings(schoolName: 'مدرسة'));
        final outbox = await env.db.select(env.db.outbox).get();
        final settingsRows = outbox.where((o) => o.targetTable == 'settings');
        expect(
          settingsRows.map((o) => o.rowId),
          contains(SettingKeys.schoolName),
        );
        final audit = await env.db.select(env.db.auditLog).get();
        expect(audit.where((a) => a.entity == 'settings'), isNotEmpty);
      },
    );

    test('حفظ نفس القيم لا يكتب شيئاً ثانية', () async {
      const s = SchoolSettings(schoolName: 'مدرسة');
      await service.save(s);
      final before = (await env.db.select(env.db.auditLog).get()).length;
      await service.save(s);
      expect((await env.db.select(env.db.auditLog).get()).length, before);
    });

    test('تغيير مفتاح واحد يكتب ذلك المفتاح فقط', () async {
      await service.save(const SchoolSettings(schoolName: 'مدرسة'));
      final before = (await env.db.select(env.db.auditLog).get()).length;
      env.time += 10;
      await service.save(
        const SchoolSettings(schoolName: 'مدرسة', graceMinutes: 9),
      );
      expect((await env.db.select(env.db.auditLog).get()).length, before + 1);
      expect((await service.load()).graceMinutes, 9);
    });

    test('قيم غير صالحة: استثناء بالأخطاء ولا يُكتب شيء', () async {
      await expectLater(
        service.save(
          const SchoolSettings(
            schoolName: 'م',
            schoolPhone: '123',
            graceMinutes: 99,
          ),
        ),
        throwsA(
          isA<SettingsValidationException>().having(
            (e) => e.errors.keys,
            'keys',
            containsAll([SettingKeys.schoolPhone, SettingKeys.graceMinutes]),
          ),
        ),
      );
      expect(await env.db.select(env.db.settings).get(), isEmpty);
    });

    test('watch يُبلغ بالتغيير', () async {
      final seen = <String>[];
      final sub = service.watch().listen((s) => seen.add(s.schoolName));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await service.save(const SchoolSettings(schoolName: 'أ'));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await service.save(const SchoolSettings(schoolName: 'ب'));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await sub.cancel();
      expect(seen.first, '');
      expect(seen.last, 'ب');
      expect(seen, contains('أ'));
    });
  });

  group('LevelService', () {
    late TestEnv env;
    late LevelService levels;

    setUp(() {
      env = TestEnv();
      levels = LevelService(env.db, env.writer);
    });
    tearDown(() => env.close());

    Future<List<LevelRow>> all() => levels.watchAll().first;

    test('المستويات الافتراضية: ابتدائي 5 ومتوسط 4 وثانوي 3 مرتبة', () async {
      await levels.ensureDefaults();
      final rows = await all();
      expect(rows, hasLength(12));
      expect(rows.where((r) => r.stage == 'primary'), hasLength(5));
      expect(rows.where((r) => r.stage == 'middle'), hasLength(4));
      expect(rows.where((r) => r.stage == 'secondary'), hasLength(3));
      expect(rows.first.name, '1 ابتدائي');
      expect(rows.last.name, '3 ثانوي');
      final order = rows.map((r) => r.sortOrder).toList();
      expect(order, [...order]..sort());
    });

    test('مرة واحدة: إعادة الاستدعاء لا تكرر ولا تعيد المحذوف', () async {
      await levels.ensureDefaults();
      final first = (await all()).first;
      await levels.remove(first.id);
      await levels.ensureDefaults();
      final rows = await all();
      expect(rows, hasLength(11));
      expect(rows.any((r) => r.id == first.id), isFalse);
    });

    test('جهازان يبدآن دون إنترنت ينتجان نفس المعرّفات', () async {
      final other = TestEnv(idPrefix: 'b');
      addTearDown(other.close);
      await levels.ensureDefaults();
      await LevelService(other.db, other.writer).ensureDefaults();
      final a = (await all()).map((r) => r.id).toSet();
      final b = (await LevelService(
        other.db,
        other.writer,
      ).watchAll().first).map((r) => r.id).toSet();
      expect(a, b);
    });

    test('جدول فيه مستويات قبل البذر: لا إضافة فوقها', () async {
      await levels.add(name: 'مستوى خاص', stage: EducationStage.middle);
      await levels.ensureDefaults();
      expect(await all(), hasLength(1));
    });

    test('الإضافة في آخر طورها', () async {
      await levels.ensureDefaults();
      final added = await levels.add(
        name: '5 متوسط',
        stage: EducationStage.middle,
      );
      final rows = await all();
      final middle = rows.where((r) => r.stage == 'middle').toList();
      expect(middle.last.id, added.id);
      expect(added.sortOrder, greaterThan(middle.first.sortOrder));
      // وبعد الابتدائي وقبل الثانوي.
      expect(
        rows.indexOf(rows.firstWhere((r) => r.id == added.id)),
        lessThan(rows.indexWhere((r) => r.stage == 'secondary')),
      );
    });

    test('اسم فارغ أو مكرر مرفوض', () async {
      await levels.ensureDefaults();
      await expectLater(
        levels.add(name: '  ', stage: EducationStage.primary),
        throwsArgumentError,
      );
      await expectLater(
        levels.add(name: '1 ابتدائي', stage: EducationStage.primary),
        throwsArgumentError,
      );
    });

    test('إعادة التسمية والحذف الناعم', () async {
      await levels.ensureDefaults();
      final row = (await all()).first;
      expect(await levels.rename(row.id, 'السنة الأولى ابتدائي'), isTrue);
      expect((await all()).first.name, 'السنة الأولى ابتدائي');
      await expectLater(
        levels.rename(row.id, '2 ابتدائي'),
        throwsArgumentError,
      );
      // الاسم نفسه لصاحبه مسموح.
      expect(await levels.rename(row.id, 'السنة الأولى ابتدائي'), isTrue);
      expect(await levels.rename('missing', 'اسم'), isFalse);

      expect(await levels.remove(row.id), isTrue);
      expect(await levels.remove(row.id), isFalse);
      final stored = await (env.db.select(
        env.db.levels,
      )..where((t) => t.id.equals(row.id))).getSingle();
      expect(stored.deletedAt, isNotNull);
      expect((await all()).any((r) => r.id == row.id), isFalse);
    });

    test('الكتابة عبر SyncWriter', () async {
      await levels.ensureDefaults();
      final outbox = await env.db.select(env.db.outbox).get();
      expect(outbox.where((o) => o.targetTable == 'levels'), hasLength(12));
    });
  });
}
