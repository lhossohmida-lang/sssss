import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

const _url = 'https://abcdefghijklmnopqrst.supabase.co';
const _key = 'sb_publishable_abcdefghijklmnopqrstuvwxyz012345';

String _b64(Object value) =>
    base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');

String _code(Map<String, Object?> map) => 'SCH1.${_b64(map)}';

PairingFailure _failure(String code) {
  try {
    SchoolPairing.parse(code);
  } on PairingException catch (e) {
    return e.failure;
  }
  fail('كان يجب أن يُرفض الرمز');
}

/// مفتاح قديم بصيغة JWT بدور معيّن (الرأس والتوقيع شكليان).
String _jwt(String role) =>
    'eyJhbGciOiJIUzI1NiJ9.${_b64({'role': role, 'iss': 'supabase'})}.c2ln';

void main() {
  group('SchoolPairing', () {
    test('الرمز يُرمَّز ويُقرأ كما هو (مع الاسم العربي)', () {
      const pairing = SchoolPairing(
        url: _url,
        key: _key,
        name: 'مدرسة النور الخاصة',
      );
      final back = SchoolPairing.parse(pairing.code);
      expect(back, pairing);
      expect(back.name, 'مدرسة النور الخاصة');
    });

    test('الرمز يطابق متجه الاختبار المشترك مع tool/pairing_code.py', () {
      // المتجهان نفسهما في tool/pairing_code_test.py: انحراف الصيغة يكسر الاثنين.
      const withName =
          'SCH1.eyJ2IjoxLCJ1IjoiaHR0cHM6Ly9hYmNkZWZnaGlqa2xtbm9wcXJzdC5zdXBhYmFzZS5jbyIsImsiOiJzYl9w'
          'dWJsaXNoYWJsZV9hYmNkZWZnaGlqa2xtbm9wcXJzdHV2d3h5ejAxMjM0NSIsIm4iOiLZhdiv2LHYs9ipINin2YTZhtmI'
          '2LEifQ';
      const withoutName =
          'SCH1.eyJ2IjoxLCJ1IjoiaHR0cHM6Ly9hYmNkZWZnaGlqa2xtbm9wcXJzdC5zdXBhYmFzZS5jbyIsImsiOiJzYl9w'
          'dWJsaXNoYWJsZV9hYmNkZWZnaGlqa2xtbm9wcXJzdHV2d3h5ejAxMjM0NSJ9';
      const named = SchoolPairing(url: _url, key: _key, name: 'مدرسة النور');
      expect(named.code, withName);
      expect(const SchoolPairing(url: _url, key: _key).code, withoutName);
      expect(SchoolPairing.parse(withName), named);
      expect(SchoolPairing.parse(withoutName).name, '');
    });

    test('الرمز نصّ واحد بلا فراغات ولا علامة = ويبدأ بـ SCH1.', () {
      final code = const SchoolPairing(url: _url, key: _key).code;
      expect(code, startsWith('SCH1.'));
      expect(code, isNot(contains(RegExp(r'[\s=]'))));
    });

    test(
      'يقبل الرمز وقد كُسرت سطوره أو أحيط بفراغات أو غُيّرت حالة بدايته',
      () {
        final code = const SchoolPairing(url: _url, key: _key).code;
        final broken =
            '  ${code.substring(0, 30)}\n${code.substring(30, 60)}\r\n'
            '${code.substring(60)}  ';
        expect(SchoolPairing.parse(broken).url, _url);
        expect(
          SchoolPairing.parse(code.replaceFirst('SCH1.', 'sch1.')).url,
          _url,
        );
      },
    );

    test('يوحّد العنوان: حروف صغيرة ودون شرطة أخيرة', () {
      final pairing = SchoolPairing.parse(
        _code({
          'v': 1,
          'u': 'https://ABCDefghijklmnopqrst.Supabase.co/',
          'k': _key,
        }),
      );
      expect(pairing.url, _url);
    });

    test('رفض: نصّ فارغ أو ليس رمزاً أو ترميز تالف أو JSON ليس كائناً', () {
      expect(_failure('   '), PairingFailure.empty);
      expect(_failure('https://x.supabase.co'), PairingFailure.malformed);
      expect(_failure('SCH1.!!!'), PairingFailure.malformed);
      expect(_failure('SCH1.${_b64([1, 2])}'), PairingFailure.malformed);
      expect(_failure(_code({'u': _url, 'k': _key})), PairingFailure.malformed);
    });

    test('رفض إصدار لا يعرفه التطبيق برسالة تطلب التحديث', () {
      final failure = _failure(_code({'v': 2, 'u': _url, 'k': _key}));
      expect(failure, PairingFailure.unsupportedVersion);
      expect(failure.message, contains('حدّث'));
    });

    test('رفض العنوان: غير https أو بمسار أو بيانات دخول أو فارغ', () {
      for (final url in [
        'http://abcdefghijklmnopqrst.supabase.co',
        'https://abcdefghijklmnopqrst.supabase.co/rest/v1',
        'https://user:pw@abcdefghijklmnopqrst.supabase.co',
        'https://abcdefghijklmnopqrst.supabase.co?x=1',
        'abcdefghijklmnopqrst.supabase.co',
        '',
      ]) {
        expect(
          _failure(_code({'v': 1, 'u': url, 'k': _key})),
          PairingFailure.badUrl,
          reason: url,
        );
      }
      expect(
        _failure(_code({'v': 1, 'k': _key})),
        PairingFailure.badUrl,
        reason: 'بلا عنوان',
      );
    });

    test('رفض مفتاح ناقص أو بفراغات', () {
      for (final key in ['', 'short', 'has space inside the key value 1234']) {
        expect(
          _failure(_code({'v': 1, 'u': _url, 'k': key})),
          PairingFailure.badKey,
          reason: key,
        );
      }
    });

    test('لا يقبل مفتاحاً سرياً أبداً: sb_secret_ أو service_role', () {
      expect(
        _failure(
          _code({'v': 1, 'u': _url, 'k': 'sb_secret_abcdefghijklmnopqrstuv'}),
        ),
        PairingFailure.secretKey,
      );
      expect(
        _failure(_code({'v': 1, 'u': _url, 'k': _jwt('service_role')})),
        PairingFailure.secretKey,
      );
    });

    test('يقبل مفتاح anon القديم بدور anon', () {
      final pairing = SchoolPairing.parse(
        _code({'v': 1, 'u': _url, 'k': _jwt('anon')}),
      );
      expect(pairing.key, _jwt('anon'));
    });

    test('اسم المدرسة اختياري ويُقصّ، وأطول من 80 حرفاً مرفوض', () {
      expect(
        SchoolPairing.parse(
          _code({'v': 1, 'u': _url, 'k': _key, 'n': '  مدرسة  '}),
        ).name,
        'مدرسة',
      );
      expect(
        SchoolPairing.parse(_code({'v': 1, 'u': _url, 'k': _key})).name,
        '',
      );
      expect(
        _failure(_code({'v': 1, 'u': _url, 'k': _key, 'n': 'ب' * 81})),
        PairingFailure.malformed,
      );
    });

    test('toConfig يعطي إعدادات مهيّأة بمفتاح مدرسة من عنوان الخادم', () {
      final config = const SchoolPairing(
        url: _url,
        key: _key,
        name: 'النور',
      ).toConfig();
      expect(config.isConfigured, isTrue);
      expect(config.schoolName, 'النور');
      expect(config.schoolKey, 'abcdefghijklmnopqrst_supabase_co');
    });

    test('toString لا يكشف المفتاح', () {
      expect(
        const SchoolPairing(url: _url, key: _key).toString(),
        isNot(contains(_key)),
      );
    });
  });

  group('AppConfig.schoolKey', () {
    test('مدرستان بخادمين مختلفين لهما مفتاحان مختلفان، ودون خادم فارغ', () {
      const a = AppConfig(
        supabaseUrl: 'https://aaaa.supabase.co',
        supabaseAnonKey: 'k',
      );
      const b = AppConfig(
        supabaseUrl: 'https://bbbb.supabase.co',
        supabaseAnonKey: 'k',
      );
      expect(a.schoolKey, isNot(b.schoolKey));
      expect(const AppConfig().schoolKey, isEmpty);
    });

    test('أحرف المفتاح تصلح اسم ملف، ومنفذ غير القياسي يدخل فيه', () {
      expect(
        AppConfig.schoolKeyOf('https://My-School.example.com:8443'),
        'my_school_example_com_8443',
      );
      expect(
        AppConfig.schoolKeyOf('https://x.example.com'),
        isNot(contains(RegExp(r'[^a-z0-9_]'))),
      );
    });
  });

  group('FilePairingStore', () {
    late Directory dir;
    late FilePairingStore store;
    const pairing = SchoolPairing(url: _url, key: _key, name: 'النور');

    setUp(() {
      dir = Directory.systemTemp.createTempSync('school_pairing_');
      store = FilePairingStore(File('${dir.path}/nested/pairing_admin.json'));
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('لا ربط قبل الحفظ، ثم يُحفظ ويُقرأ، ثم يُفكّ', () async {
      expect(await store.load(), isNull);
      await store.save(pairing);
      expect(await store.load(), pairing);
      await store.clear();
      expect(await store.load(), isNull);
      await store.clear(); // لا يخطئ إن لم يكن موجوداً
    });

    test('الحفظ يستبدل ربطاً سابقاً ولا يترك ملفاً مؤقتاً', () async {
      await store.save(pairing);
      const other = SchoolPairing(
        url: 'https://zzzzzzzzzzzzzzzzzzzz.supabase.co',
        key: _key,
      );
      await store.save(other);
      expect(await store.load(), other);
      expect(File('${store.file.path}.tmp').existsSync(), isFalse);
    });

    test(
      'المعاينة المحلية: تُحفظ، وربط مدرسة يلغيها، وفكّ الربط يمحوها',
      () async {
        expect(await store.isLocalPreview(), isFalse);
        await store.chooseLocalPreview();
        expect(await store.isLocalPreview(), isTrue);
        expect(await store.load(), isNull, reason: 'لا مدرسة في المعاينة');
        await store.save(pairing);
        expect(await store.isLocalPreview(), isFalse);
        expect(await store.load(), pairing);
        await store.chooseLocalPreview();
        expect(await store.load(), isNull, reason: 'المعاينة تفك الربط');
        await store.clear();
        expect(await store.isLocalPreview(), isFalse);
      },
    );

    test('ملف تالف أو بمفتاح سري يُعدّ غير مربوط ولا يرمي', () async {
      await store.file.parent.create(recursive: true);
      await store.file.writeAsString('{not json');
      expect(await store.load(), isNull);
      await store.file.writeAsString(jsonEncode([1, 2]));
      expect(await store.load(), isNull);
      await store.file.writeAsString(
        jsonEncode({
          'v': 1,
          'u': _url,
          'k': 'sb_secret_abcdefghijklmnopqrstuv',
        }),
      );
      expect(await store.load(), isNull);
      expect(await store.isLocalPreview(), isFalse);
    });
  });

  group('resolveSchoolConfig', () {
    late Directory dir;
    late FilePairingStore store;
    const baked = AppConfig(
      supabaseUrl: 'https://baked.supabase.co',
      supabaseAnonKey: 'baked-key-value',
    );

    setUp(() {
      dir = Directory.systemTemp.createTempSync('school_resolve_');
      store = FilePairingStore(File('${dir.path}/pairing.json'));
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('المضمَّن وقت البناء يغلب الربط المحفوظ', () async {
      await store.save(const SchoolPairing(url: _url, key: _key));
      final config = await resolveSchoolConfig(store, baked: baked);
      expect(config?.supabaseUrl, 'https://baked.supabase.co');
    });

    test('دون مضمَّن يُستعمل الربط المحفوظ', () async {
      await store.save(
        const SchoolPairing(url: _url, key: _key, name: 'النور'),
      );
      final config = await resolveSchoolConfig(store, baked: const AppConfig());
      expect(config?.supabaseUrl, _url);
      expect(config?.schoolName, 'النور');
    });

    test('دون الاثنين: null (جهاز لم يُربط)', () async {
      expect(
        await resolveSchoolConfig(store, baked: const AppConfig()),
        isNull,
      );
    });
  });
}
