import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:school_core/school_core.dart';

void main() {
  late List<http.Request> requests;
  late http.Response Function(http.Request) respond;
  String? token = 'jwt-token';

  PostgrestRemoteStore store({Duration timeout = const Duration(seconds: 5)}) =>
      PostgrestRemoteStore(
        restUrl: 'https://x.supabase.co/rest/v1',
        apiKey: 'anon-key',
        accessToken: () async => token,
        primaryKeys: const {
          'rooms': ['id'],
          'teacher_subjects': ['teacher_id', 'subject_id'],
          'audit_log': ['id'],
        },
        client: MockClient((request) async {
          requests.add(request);
          return respond(request);
        }),
        timeout: timeout,
      );

  setUp(() {
    requests = [];
    token = 'jwt-token';
    respond = (_) => http.Response('', 201);
  });

  group('الدفع', () {
    test('طلب upsert بالصيغة الصحيحة', () async {
      await store().upsert('rooms', [
        {'id': 'r1', 'name': 'القاعة 1', 'capacity': 20, 'updated_at': 5},
      ]);
      final request = requests.single;
      expect(request.method, 'POST');
      expect(request.url.path, '/rest/v1/rooms');
      expect(request.url.queryParameters['on_conflict'], 'id');
      expect(request.headers['apikey'], 'anon-key');
      expect(request.headers['Authorization'], 'Bearer jwt-token');
      expect(
        request.headers['Prefer'],
        'resolution=merge-duplicates,return=minimal',
      );
      expect(request.headers['Content-Type'], startsWith('application/json'));
      final body = jsonDecode(utf8.decode(request.bodyBytes)) as List;
      expect((body.single as Map)['name'], 'القاعة 1');
    });

    test('المفتاح المركّب والجداول التي يُضاف إليها فقط', () async {
      await store().upsert('teacher_subjects', [
        {'teacher_id': 't1', 'subject_id': 's1', 'updated_at': 1},
      ]);
      expect(
        requests.last.url.queryParameters['on_conflict'],
        'teacher_id,subject_id',
      );
      await store().upsert('audit_log', [
        {'id': 'a1'},
      ], insertOnly: true);
      expect(
        requests.last.headers['Prefer'],
        'resolution=ignore-duplicates,return=minimal',
      );
    });

    test('قائمة فارغة لا ترسل طلباً، وجدول مجهول يُرفض نهائياً', () async {
      await store().upsert('rooms', const []);
      expect(requests, isEmpty);
      await expectLater(
        store().upsert('nope', [
          {'id': 'x'},
        ]),
        throwsA(
          isA<RemoteException>().having((e) => e.permanent, 'permanent', true),
        ),
      );
    });

    test('تصنيف الأخطاء: نهائية ومؤقتة', () async {
      Future<bool> permanentFor(int status) async {
        respond = (_) => http.Response(
          jsonEncode({'message': 'new row violates row-level security policy'}),
          status,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
        try {
          await store().upsert('rooms', [
            {'id': 'r1'},
          ]);
        } on RemoteException catch (e) {
          expect(e.message, contains('$status'));
          return e.permanent;
        }
        fail('لم يُرمَ استثناء للحالة $status');
      }

      for (final status in [400, 403, 404, 409, 422]) {
        expect(await permanentFor(status), isTrue, reason: '$status');
      }
      for (final status in [401, 408, 429, 500, 502, 503]) {
        expect(await permanentFor(status), isFalse, reason: '$status');
      }
    });

    test('رسالة الخادم تظهر في الخطأ', () async {
      respond = (_) => http.Response(
        jsonEncode({'message': 'رفض الصلاحيات'}),
        403,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
      await expectLater(
        store().upsert('rooms', [
          {'id': 'r1'},
        ]),
        throwsA(
          isA<RemoteException>().having(
            (e) => e.message,
            'message',
            contains('رفض الصلاحيات'),
          ),
        ),
      );
    });

    test('أعطال الشبكة والمهلة مؤقتة', () async {
      Future<RemoteException> failWith(Object error) async {
        respond = (_) => throw error;
        try {
          await store().upsert('rooms', [
            {'id': 'r1'},
          ]);
        } on RemoteException catch (e) {
          return e;
        }
        fail('لم يُرمَ استثناء');
      }

      expect(
        (await failWith(const SocketException('no route'))).permanent,
        isFalse,
      );
      expect(
        (await failWith(http.ClientException('reset'))).permanent,
        isFalse,
      );

      final slow = PostgrestRemoteStore(
        restUrl: 'https://x.supabase.co/rest/v1',
        apiKey: 'k',
        accessToken: () async => 't',
        primaryKeys: const {
          'rooms': ['id'],
        },
        client: MockClient(
          (_) => Future.delayed(
            const Duration(milliseconds: 200),
            () => http.Response('', 201),
          ),
        ),
        timeout: const Duration(milliseconds: 20),
      );
      await expectLater(
        slow.upsert('rooms', [
          {'id': 'r1'},
        ]),
        throwsA(
          isA<RemoteException>()
              .having((e) => e.permanent, 'permanent', false)
              .having((e) => e.message, 'message', 'انتهت مهلة الاتصال'),
        ),
      );
    });

    test('دون تسجيل دخول: خطأ مؤقت ولا يُرسل شيء', () async {
      token = null;
      await expectLater(
        store().upsert('rooms', [
          {'id': 'r1'},
        ]),
        throwsA(
          isA<RemoteException>().having((e) => e.permanent, 'permanent', false),
        ),
      );
      expect(requests, isEmpty);
    });
  });

  group('السحب', () {
    test('طلب السحب بالمؤشر والترتيب والحد', () async {
      respond = (_) => http.Response.bytes(
        utf8.encode(
          jsonEncode([
            {'id': 'r1', 'name': 'القاعة 1', 'synced_at': 11},
            {'id': 'r2', 'name': 'القاعة 2', 'synced_at': 12},
          ]),
        ),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
      final rows = await store().pull('rooms', afterSyncedAt: 10, limit: 500);
      final request = requests.single;
      expect(request.method, 'GET');
      expect(request.url.path, '/rest/v1/rooms');
      expect(request.url.queryParameters, {
        'select': '*',
        'synced_at': 'gt.10',
        'order': 'synced_at.asc',
        'limit': '500',
      });
      expect(rows.map((r) => r['name']), ['القاعة 1', 'القاعة 2']);
      expect(rows.last['synced_at'], 12);
    });

    test('رد غير مفهوم خطأ مؤقت', () async {
      respond = (_) => http.Response('<html>', 200);
      await expectLater(
        store().pull('rooms', afterSyncedAt: 0, limit: 10),
        throwsA(
          isA<RemoteException>().having((e) => e.permanent, 'permanent', false),
        ),
      );
      respond = (_) => http.Response('{"a": 1}', 200);
      await expectLater(
        store().pull('rooms', afterSyncedAt: 0, limit: 10),
        throwsA(isA<RemoteException>()),
      );
    });

    test('رفض السحب يُبلَّغ', () async {
      respond = (_) => http.Response('', 503);
      await expectLater(
        store().pull('rooms', afterSyncedAt: 0, limit: 10),
        throwsA(
          isA<RemoteException>().having((e) => e.permanent, 'permanent', false),
        ),
      );
    });
  });

  test('مفاتيح الجداول تُستخرج من القاعدة دون الجداول المحلية', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final keys = PostgrestRemoteStore.primaryKeysOf(db);
    expect(keys['students'], ['id']);
    expect(keys['settings'], ['key']);
    expect(keys['teacher_subjects'], ['teacher_id', 'subject_id']);
    expect(keys.containsKey('outbox'), isFalse);
    expect(keys.containsKey('upload_queue'), isFalse);
    expect(keys, hasLength(36));
  });

  test('المحرك يعمل فوق عميل REST: دفع ثم سحب', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final server = <String, Map<String, Object?>>{};
    var sequence = 0;
    final rest = PostgrestRemoteStore(
      restUrl: 'https://x.supabase.co/rest/v1',
      apiKey: 'k',
      accessToken: () async => 't',
      primaryKeys: PostgrestRemoteStore.primaryKeysOf(db),
      client: MockClient((request) async {
        final table = request.url.pathSegments.last;
        if (request.method == 'POST') {
          for (final row
              in jsonDecode(utf8.decode(request.bodyBytes)) as List) {
            final map = (row as Map).cast<String, Object?>();
            if (table == 'rooms') {
              server[map['id']! as String] = {...map, 'synced_at': ++sequence};
            }
          }
          return http.Response('', 201);
        }
        final after = int.parse(
          request.url.queryParameters['synced_at']!.substring(3),
        );
        final rows = table == 'rooms'
            ? server.values
                  .where((r) => (r['synced_at']! as int) > after)
                  .toList()
            : const <Map<String, Object?>>[];
        return http.Response.bytes(
          utf8.encode(jsonEncode(rows)),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final writer = SyncWriter(
      db,
      actor: () => const Actor(userId: 'u1', userName: 'المدير'),
    );
    await writer.save(
      db.rooms,
      RoomsCompanion.insert(id: 'r1', createdAt: 0, updatedAt: 0, name: 'ق'),
      key: const {'id': 'r1'},
    );
    final engine = SyncEngine(
      db,
      rest,
      tables: SyncProfile.forRole(UserRole.owner),
    );
    final report = await engine.syncOnce();
    expect(report.pushed, 2);
    expect(report.isClean, isTrue);
    expect(server['r1']?['name'], 'ق');
    expect(server['r1']?['deleted_at'], isNull);
  });
}
