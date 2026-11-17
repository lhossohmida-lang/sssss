import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/testing.dart';

const _key = 'sb_publishable_directory-public-key';
const _config = DirectoryConfig(
  url: 'https://aaaaaaaaaaaaaaaaaaaa.supabase.co',
  key: _key,
);

Map<String, Object?> _row(
  String id,
  String name, {
  String url = 'https://bbbbbbbbbbbbbbbbbbbb.supabase.co',
  String key = 'sb_publishable_school-public-key',
}) => {'id': id, 'name': name, 'url': url, 'publishable_key': key};

http.Response _json(Object? body, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  group('DirectoryConfig', () {
    test('تُعدّ مهيّأة بعنوان https ومفتاح عام فقط', () {
      expect(_config.isConfigured, isTrue);
      expect(const DirectoryConfig().isConfigured, isFalse);
      expect(
        const DirectoryConfig(
          url: 'http://x.example.com',
          key: _key,
        ).isConfigured,
        isFalse,
      );
      expect(
        const DirectoryConfig(
          url: 'https://x.supabase.co',
          key: 'sb_secret_abcdefghijklmnopqrstuvwx',
        ).isConfigured,
        isFalse,
      );
      expect(
        const DirectoryConfig(url: 'https://x.supabase.co').isConfigured,
        isFalse,
      );
    });
  });

  group('DirectorySchool.tryParse', () {
    test('صف سليم يصير مدرسة بربطها', () {
      final school = DirectorySchool.tryParse(_row('1', ' مدرسة النور '))!;
      expect(school.id, '1');
      expect(school.name, 'مدرسة النور');
      expect(school.url, 'https://bbbbbbbbbbbbbbbbbbbb.supabase.co');
      expect(
        school.toPairing(),
        const SchoolPairing(
          url: 'https://bbbbbbbbbbbbbbbbbbbb.supabase.co',
          key: 'sb_publishable_school-public-key',
          name: 'مدرسة النور',
        ),
      );
    });

    test('الصفوف التالفة أو المشبوهة تُتجاهل', () {
      for (final bad in <Object?>[
        null,
        'نص',
        {'id': '1'},
        _row('1', 'س', url: 'http://plain.example.com'),
        _row('1', 'س', url: 'https://x.supabase.co/path'),
        _row('1', 'س', key: 'sb_secret_abcdefghijklmnopqrstuvwx'),
        _row('1', 'س', key: 'short'),
        {..._row('1', 'س'), 'id': 5},
      ]) {
        expect(DirectorySchool.tryParse(bad), isNull, reason: '$bad');
      }
    });

    test('اسم فارغ يُعرض بعنوان الخادم', () {
      expect(
        DirectorySchool.tryParse(_row('1', '  '))!.name,
        startsWith('https://'),
      );
    });
  });

  group('HttpSchoolDirectory', () {
    test(
      'list_schools: يطلب بالمفتاح العام ويقرأ الصفوف ويتجاهل التالف',
      () async {
        late http.Request seen;
        final directory = HttpSchoolDirectory(
          _config,
          client: MockClient((request) async {
            seen = request;
            return _json([
              _row('1', 'مدرسة النور'),
              _row('2', 'خادم مشبوه', url: 'http://evil.example.com'),
              _row(
                '3',
                'مدرسة الأمل',
                url: 'https://cccccccccccccccccccc.supabase.co',
              ),
            ]);
          }),
        );

        final schools = await directory.listSchools();

        expect(schools.map((s) => s.name), ['مدرسة النور', 'مدرسة الأمل']);
        expect(
          seen.url.toString(),
          'https://aaaaaaaaaaaaaaaaaaaa.supabase.co/rest/v1/rpc/list_schools',
        );
        expect(seen.method, 'POST');
        expect(seen.headers['apikey'], _key);
        expect(seen.headers.containsKey('Authorization'), isFalse);
        expect(jsonDecode(seen.body), <String, Object?>{});
      },
    );

    test('مفتاح JWT قديم يُرسل في الرأسين', () async {
      late http.Request seen;
      final directory = HttpSchoolDirectory(
        const DirectoryConfig(
          url: 'https://aaaaaaaaaaaaaaaaaaaa.supabase.co/',
          key: 'eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoiYW5vbiJ9.sig',
        ),
        client: MockClient((request) async {
          seen = request;
          return _json([]);
        }),
      );
      await directory.listSchools();
      expect(seen.headers['Authorization'], startsWith('Bearer eyJ'));
      expect(
        seen.url.toString(),
        'https://aaaaaaaaaaaaaaaaaaaa.supabase.co/rest/v1/rpc/list_schools',
      );
    });

    test('resolve_school: يوحّد الرقم ولا يطلب لرقم غير صالح', () async {
      final bodies = <Object?>[];
      final directory = HttpSchoolDirectory(
        _config,
        client: MockClient((request) async {
          bodies.add(jsonDecode(request.body));
          expect(request.url.path, endsWith('/rpc/resolve_school'));
          return _json([_row('1', 'مدرسة النور')]);
        }),
      );

      final found = await directory.resolveByPhone('+213 550 12 34 56');
      expect(found.single.name, 'مدرسة النور');
      expect(bodies, [
        {'p_phone': '0550123456'},
      ]);

      expect(await directory.resolveByPhone('abc'), isEmpty);
      expect(await directory.resolveByPhone(''), isEmpty);
      expect(bodies, hasLength(1), reason: 'الرقم الخاطئ لا يصل الخادم');
    });

    test('انقطاع الاتصال والمهلة: تعذّر الاتصال', () async {
      for (final failure in <Object>[
        const SocketException('offline'),
        http.ClientException('offline'),
        TimeoutException('slow'),
      ]) {
        final directory = HttpSchoolDirectory(
          _config,
          client: MockClient((_) async => throw failure),
        );
        await expectLater(
          directory.listSchools(),
          throwsA(
            isA<DirectoryException>().having(
              (e) => e.failure,
              'failure',
              DirectoryFailure.offline,
            ),
          ),
          reason: '$failure',
        );
      }
    });

    test('أخطاء الخادم: كثرة المحاولات وعدم التوفر ورد غير متوقع', () async {
      Future<DirectoryFailure> failureOf(http.Response response) async {
        final directory = HttpSchoolDirectory(
          _config,
          client: MockClient((_) async => response),
        );
        try {
          await directory.resolveByPhone('0550123456');
        } on DirectoryException catch (e) {
          return e.failure;
        }
        fail('لم يُرمَ');
      }

      expect(
        await failureOf(_json({'message': 'rate_limited'}, 400)),
        DirectoryFailure.rateLimited,
      );
      expect(await failureOf(_json({}, 429)), DirectoryFailure.rateLimited);
      expect(await failureOf(_json({}, 500)), DirectoryFailure.unavailable);
      expect(await failureOf(_json({}, 404)), DirectoryFailure.unavailable);
      expect(
        await failureOf(_json({'not': 'a list'})),
        DirectoryFailure.unavailable,
      );
      expect(
        await failureOf(http.Response.bytes(utf8.encode('ليس JSON'), 200)),
        DirectoryFailure.unavailable,
      );
    });

    test('الرسائل بالعربية', () {
      for (final failure in DirectoryFailure.values) {
        expect(failure.message, isNotEmpty);
        expect(DirectoryException(failure).message, failure.message);
      }
    });
  });

  group('FakeSchoolDirectory', () {
    test('يعيد المدارس وطاقم الرقم بعد توحيده، ويرمي العطل', () async {
      final school = DirectorySchool.tryParse(_row('1', 'مدرسة النور'))!;
      final directory = FakeSchoolDirectory(
        schools: [school],
        staff: {
          '0550123456': [school],
        },
      );
      expect(await directory.listSchools(), [school]);
      expect(await directory.resolveByPhone('+213550123456'), [school]);
      expect(await directory.resolveByPhone('0661234567'), isEmpty);
      directory.failure = DirectoryFailure.offline;
      await expectLater(
        directory.listSchools(),
        throwsA(isA<DirectoryException>()),
      );
      expect(directory.listCalls, 2);
      expect(directory.resolved, ['+213550123456', '0661234567']);
    });
  });
}
