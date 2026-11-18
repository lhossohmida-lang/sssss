import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/testing.dart';

import '../support/fake_remote.dart';
import '../support/fixtures.dart';

/// خادم وهمي يدعم دورة المدرسة (`null`: خادم لا يدعمها).
class EpochRemote extends FakeRemote implements SchoolEpochSource {
  String? epoch = '';

  @override
  Future<String?> fetchSchoolEpoch() async {
    calls.add('epoch');
    if (offline) {
      throw const RemoteException('لا يوجد اتصال', permanent: false);
    }
    return epoch;
  }
}

/// بوابة إعادة تعيين وهمية: تسجّل كلمة السر وتنفّذ [onReset] على الخادم الوهمي.
class FakeResetGateway implements SchoolResetGateway {
  FakeResetGateway({required this.onReset, this.failure});

  final void Function() onReset;
  SchoolResetException? failure;
  final List<String> passwords = [];
  SchoolResetResult result = const SchoolResetResult(
    epoch: 'epoch-1',
    removedAccounts: 3,
  );

  @override
  Future<SchoolResetResult> reset({required String password}) async {
    passwords.add(password);
    if (failure != null) throw failure!;
    onReset();
    return result;
  }
}

void main() {
  Future<int> count(AppDatabase db, String table) async =>
      (await db.customSelect('SELECT COUNT(*) AS c FROM "$table"').getSingle())
          .read<int>('c');

  Future<void> saveRoom(TestEnv env, String id, String name) => env.writer.save(
    env.db.rooms,
    RoomsCompanion.insert(id: id, createdAt: 0, updatedAt: 0, name: name),
    key: {'id': id},
  );

  Future<List<String>> roomIds(TestEnv env) async =>
      [for (final r in await env.db.select(env.db.rooms).get()) r.id]..sort();

  Future<void> seedDeviceRows(AppDatabase db) async {
    await db
        .into(db.deviceSession)
        .insert(
          DeviceSessionCompanion.insert(
            id: const Value(1),
            accountId: 'u-owner',
            email: 'owner@school.local',
            role: 'owner',
            savedAt: 1,
          ),
        );
    await db
        .into(db.localCredentials)
        .insert(
          LocalCredentialsCompanion.insert(
            accountId: 'u-owner',
            salt: 's',
            hash: 'h',
            iterations: 1,
            updatedAt: 1,
          ),
        );
    await db
        .into(db.deviceInfo)
        .insert(DeviceInfoCompanion.insert(key: 'device_id', value: 'dev-1'));
  }

  group('مسح بيانات المدرسة من قاعدة الجهاز', () {
    test(
      'يفرّغ جداول المدرسة وطابورها ويُبقي جلسة الدخول ومفاتيح الجهاز',
      () async {
        final env = TestEnv();
        addTearDown(env.close);
        await env.subject();
        await env.teacher();
        await env.group();
        await env.slot(id: 'sl1', weekday: 6);
        await saveRoom(env, 'r1', 'القاعة 1');
        await env.db
            .into(env.db.syncState)
            .insert(
              SyncStateCompanion.insert(
                targetTable: 'rooms',
                lastPulledAt: const Value(7),
              ),
            );
        await env.db
            .into(env.db.uploadQueue)
            .insert(
              UploadQueueCompanion.insert(
                id: 'q1',
                kind: 'photo',
                localPath: '/tmp/a.jpg',
                remotePath: 'a.jpg',
                dedupeKey: 'k1',
                createdAt: 1,
              ),
            );
        await seedDeviceRows(env.db);
        expect(await count(env.db, 'outbox'), greaterThan(0));

        await wipeSchoolData(env.db);

        for (final table in [
          'groups',
          'group_slots',
          'subjects',
          'teachers',
          'rooms',
          'outbox',
          'sync_state',
          'upload_queue',
        ]) {
          expect(await count(env.db, table), 0, reason: table);
        }
        for (final table in [
          'device_session',
          'local_credentials',
          'device_info',
        ]) {
          expect(await count(env.db, table), 1, reason: table);
        }
      },
    );

    test('يُعلِم من يراقب الجداول فتتحدث الواجهة', () async {
      final env = TestEnv();
      addTearDown(env.close);
      await saveRoom(env, 'r1', 'القاعة 1');
      final seen = <int>[];
      final subscription = env.db
          .select(env.db.rooms)
          .watch()
          .listen((rows) => seen.add(rows.length));
      addTearDown(subscription.cancel);
      await pumpEventQueue();
      expect(seen.last, 1);
      await wipeSchoolData(env.db);
      await pumpEventQueue();
      expect(seen.last, 0);
    });
  });

  group('دورة المدرسة في المزامنة', () {
    late EpochRemote remote;

    SyncEngine engineFor(TestEnv env, {void Function()? onReset}) => SyncEngine(
      env.db,
      remote,
      tables: SyncProfile.forRole(UserRole.owner),
      clock: () => env.time,
      onSchoolReset: onReset,
    );

    setUp(() => remote = EpochRemote());

    test('الجهاز القديم بعد إعادة المدرسة يمسح بياناته ولا يُعيد رفعها ثم يسحب الجديد', () async {
      final a = TestEnv(idPrefix: 'a');
      final b = TestEnv(idPrefix: 'b');
      final c = TestEnv(idPrefix: 'c');
      addTearDown(a.close);
      addTearDown(b.close);
      addTearDown(c.close);

      // قبل الإعادة: ب ترفع غرفة وأ تسحبها وتحتفظ بتعديل لم يُرسل.
      await saveRoom(b, 'room-b', 'غرفة ب');
      await engineFor(b).syncOnce();
      await engineFor(a).syncOnce();
      await saveRoom(a, 'room-a-pending', 'تعديل لم يُرسل');
      await seedDeviceRows(a.db);
      expect(await roomIds(a), ['room-a-pending', 'room-b']);

      // المدرسة أُعيدت: الخادم فارغ بدورة جديدة، وجهاز جديد ج يرفع ما بعدها.
      remote
        ..wipe()
        ..epoch = 'epoch-1';
      final cReset = <String>[];
      await engineFor(c, onReset: () => cReset.add('c')).syncOnce();
      await saveRoom(c, 'room-new', 'غرفة جديدة');
      await engineFor(c).syncOnce();
      expect(remote.rows('rooms').map((r) => r['id']), ['room-new']);

      var resets = 0;
      final report = await engineFor(a, onReset: () => resets++).syncOnce();
      expect(report.error, isNull);
      // مُسح ما كان على الجهاز (حتى التعديل المعلّق)، وسُحبت المدرسة الجديدة وحدها.
      expect(await roomIds(a), ['room-new']);
      expect(await count(a.db, 'outbox'), 0);
      expect(remote.rows('rooms').map((r) => r['id']), [
        'room-new',
      ], reason: 'لم يُرفع شيء من القديم فلا تعود بيانات محذوفة');
      expect(resets, 1);
      expect(
        await DevicePreferences(a.db).read(DevicePreferences.schoolEpochKey),
        'epoch-1',
      );
      // جلسة الدخول ومفاتيح الجهاز باقية.
      expect(await count(a.db, 'device_session'), 1);
      expect(await count(a.db, 'local_credentials'), 1);
      expect(
        await DevicePreferences(a.db).read('device_id'),
        'dev-1',
        reason: 'مفاتيح الجهاز لا تُمسح',
      );

      // بعدها: لا مسح ثانية، ويُرفع ما يُكتب.
      await saveRoom(a, 'room-a2', 'بعد الإعادة');
      await engineFor(a, onReset: () => resets++).syncOnce();
      expect(resets, 1);
      expect(
        (remote.rows('rooms').map((r) => r['id']! as String).toList()..sort()),
        ['room-a2', 'room-new'],
      );
    });

    test('مدرسة لم تُعَد قط: لا مسح ويُرسل الطابور', () async {
      final a = TestEnv();
      addTearDown(a.close);
      await saveRoom(a, 'r1', 'القاعة 1');
      var resets = 0;
      await engineFor(a, onReset: () => resets++).syncOnce();
      expect(resets, 0);
      expect(remote.rows('rooms'), hasLength(1));
      expect(
        await DevicePreferences(a.db).read(DevicePreferences.schoolEpochKey),
        isNull,
        reason: 'لا شيء يُسجَّل للدورة الفارغة',
      );
    });

    test('تعذّرت قراءة الدورة: خطأ مؤقت ولا دفع ولا مسح', () async {
      final a = TestEnv();
      addTearDown(a.close);
      await saveRoom(a, 'r1', 'القاعة 1');
      remote.offline = true;
      final report = await engineFor(a).syncOnce();
      expect(report.error, isNotNull);
      expect(report.pending, greaterThan(0));
      expect(remote.calls, [
        'epoch',
      ], reason: 'لا دفع ولا سحب قبل معرفة الدورة');
      expect(await roomIds(a), ['r1']);
      expect(await count(a.db, 'outbox'), greaterThan(0));
    });

    test('خادم لا يدعم الدورة (ترحيل قديم): تعمل المزامنة كما كانت', () async {
      final a = TestEnv();
      addTearDown(a.close);
      remote.epoch = null;
      await saveRoom(a, 'r1', 'القاعة 1');
      var resets = 0;
      await engineFor(a, onReset: () => resets++).syncOnce();
      expect(resets, 0);
      expect(remote.rows('rooms'), hasLength(1));
    });

    test('خادم وهمي بلا دعم للدورة لا يُفحص أصلاً', () async {
      final a = TestEnv();
      addTearDown(a.close);
      final plain = FakeRemote();
      await saveRoom(a, 'r1', 'القاعة 1');
      await SyncEngine(
        a.db,
        plain,
        tables: SyncProfile.forRole(UserRole.owner),
        clock: () => a.time,
      ).syncOnce();
      expect(plain.rows('rooms'), hasLength(1));
      expect(plain.calls, isNot(contains('epoch')));
    });
  });

  group('قراءة دورة المدرسة من PostgREST', () {
    late List<http.Request> requests;
    late http.Response Function(http.Request) respond;

    PostgrestRemoteStore store() => PostgrestRemoteStore(
      restUrl: 'https://x.supabase.co/rest/v1',
      apiKey: 'anon-key',
      accessToken: () async => 'jwt-token',
      primaryKeys: const {},
      client: MockClient((request) async {
        requests.add(request);
        return respond(request);
      }),
    );

    setUp(() {
      requests = [];
      respond = (_) => http.Response(jsonEncode(''), 200);
    });

    test(
      'طلب دالة school_epoch بصلاحية المستخدم، والدورة الفارغة نص فارغ',
      () async {
        expect(await store().fetchSchoolEpoch(), '');
        final request = requests.single;
        expect(request.method, 'POST');
        expect(
          request.url.toString(),
          'https://x.supabase.co/rest/v1/rpc/school_epoch',
        );
        expect(request.headers['apikey'], 'anon-key');
        expect(request.headers['Authorization'], 'Bearer jwt-token');
        expect(request.body, '{}');
      },
    );

    test('دورة بعد إعادة', () async {
      respond = (_) => http.Response(jsonEncode('abc-123'), 200);
      expect(await store().fetchSchoolEpoch(), 'abc-123');
    });

    test('الدالة غير موجودة (ترحيل لم يُطبَّق): null لا خطأ', () async {
      respond = (_) => http.Response('{"code":"PGRST202"}', 404);
      expect(await store().fetchSchoolEpoch(), isNull);
    });

    test('رمز منتهٍ أو عطل خادم: خطأ مؤقت', () async {
      for (final status in [401, 429, 500, 503]) {
        respond = (_) => http.Response('{"message":"x"}', status);
        await expectLater(
          store().fetchSchoolEpoch(),
          throwsA(
            isA<RemoteException>().having(
              (e) => e.permanent,
              'permanent',
              isFalse,
            ),
          ),
          reason: '$status',
        );
      }
    });

    test('رد غير مفهوم: خطأ مؤقت', () async {
      for (final body in ['not json', '{"epoch":"x"}', '5']) {
        respond = (_) => http.Response(body, 200);
        await expectLater(
          store().fetchSchoolEpoch(),
          throwsA(isA<RemoteException>()),
          reason: body,
        );
      }
    });
  });

  group('بوابة إعادة التعيين', () {
    test('رد ناجح بنتيجته وبقاياه', () {
      final result = SupabaseSchoolResetGateway.parse({
        'ok': true,
        'epoch': 'e-1',
        'removed_accounts': 4,
        'failures': {'auth': 1, 'directory': 2, 'storage': 3},
      });
      expect(result.epoch, 'e-1');
      expect(result.removedAccounts, 4);
      expect(
        [result.authFailures, result.directoryFailures, result.storageFailures],
        [1, 2, 3],
      );
      expect(result.leftovers, 6);
      expect(result.complete, isFalse);
    });

    test('رد بلا بقايا: مكتمل', () {
      final result = SupabaseSchoolResetGateway.parse({
        'ok': true,
        'epoch': 'e-2',
        'removed_accounts': 0,
        'failures': {'auth': 0, 'directory': 0, 'storage': 0},
      });
      expect(result.complete, isTrue);
      expect(
        SupabaseSchoolResetGateway.parse({'ok': true, 'epoch': 'e-3'}).complete,
        isTrue,
        reason: 'غياب الأعداد يعني لا بقايا',
      );
    });

    test('رد غير مفهوم يُرفض ولا يُعدّ نجاحاً', () {
      for (final data in [
        null,
        'ok',
        {'ok': false, 'epoch': 'e'},
        {'ok': true},
        {'ok': true, 'epoch': 5},
      ]) {
        expect(
          () => SupabaseSchoolResetGateway.parse(data),
          throwsA(isA<SchoolResetException>()),
          reason: '$data',
        );
      }
    });

    test('رفض الخادم يُترجم بحسب حالته ورمزه', () {
      SchoolResetFailure kind(int status, [Object? details]) =>
          SupabaseSchoolResetGateway.mapFailure(status, details).failure;
      expect(
        kind(403, {'error': 'wrong_password'}),
        SchoolResetFailure.wrongPassword,
      );
      expect(kind(403, {'error': 'forbidden'}), SchoolResetFailure.forbidden);
      expect(kind(403), SchoolResetFailure.forbidden);
      expect(kind(401), SchoolResetFailure.forbidden);
      expect(kind(400), SchoolResetFailure.notAvailable);
      expect(kind(404), SchoolResetFailure.notAvailable);
      expect(kind(503), SchoolResetFailure.notAvailable);
      expect(kind(502), SchoolResetFailure.network);
      expect(kind(500), SchoolResetFailure.network);
      expect(kind(418), SchoolResetFailure.notAvailable);
      expect(
        SupabaseSchoolResetGateway.mapFailure(403, {
          'error': 'wrong_password',
        }).message,
        'كلمة السر غير صحيحة',
      );
    });
  });

  group('AppRuntime.resetSchool', () {
    late Directory photos;
    late EpochRemote remote;
    late FakeResetGateway gateway;
    late TestEnv env;

    setUp(() {
      photos = Directory.systemTemp.createTempSync('school_reset_photos_');
      env = TestEnv();
      remote = EpochRemote();
      gateway = FakeResetGateway(
        onReset: () {
          remote
            ..wipe()
            ..epoch = 'epoch-1';
        },
      );
    });

    tearDown(() async {
      await env.close();
      if (photos.existsSync()) photos.deleteSync(recursive: true);
    });

    Future<AppRuntime> started(UserRole role) async {
      final runtime = await startTestRuntime(
        app: role == UserRole.owner ? AppIdentity.admin : AppIdentity.teacher,
        accounts: [
          TestAccount(
            id: 'u-owner',
            email: 'owner@school.local',
            password: 'owner-pass-1',
            role: role,
            entityId: role == UserRole.teacher ? 't1' : null,
          ),
        ],
        database: env.db,
        photosDirectory: photos,
        schoolReset: gateway,
        syncFactory: (session) => SyncCoordinator(
          env.db,
          SyncEngine(
            env.db,
            remote,
            tables: SyncProfile.forRole(session.role),
            clock: () => env.time,
          ),
          debounce: const Duration(milliseconds: 5),
          interval: const Duration(hours: 1),
        ),
      );
      addTearDown(runtime.dispose);
      await runtime.auth.signIn(
        email: 'owner@school.local',
        password: 'owner-pass-1',
      );
      return runtime;
    }

    Future<void> until(Future<bool> Function() condition) async {
      for (var i = 0; i < 300; i++) {
        if (await condition()) return;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(
        await condition(),
        isTrue,
        reason: 'لم يتحقق الشرط في الوقت المحدد',
      );
    }

    test('المالك: تُمسح بيانات الخادم والجهاز وصوره ويبقى مسجَّلاً وتُبذَر المستويات من جديد', () async {
      final runtime = await started(UserRole.owner);
      // بعد أول مزامنة تُبذَر المستويات الافتراضية.
      await until(() async => await count(env.db, 'levels') == 12);
      await runtime.writer.save(
        env.db.rooms,
        RoomsCompanion.insert(
          id: 'r1',
          createdAt: 0,
          updatedAt: 0,
          name: 'القاعة 1',
        ),
        key: {'id': 'r1'},
      );
      await Directory('${photos.path}/students').create();
      await File('${photos.path}/students/a.jpg').writeAsBytes([1, 2, 3]);
      await File('${photos.path}/b.jpg').writeAsBytes([4]);

      final result = await runtime.resetSchool(password: 'owner-pass-1');

      expect(gateway.passwords, ['owner-pass-1']);
      expect(result.epoch, 'epoch-1');
      expect(await roomIds(env), isEmpty, reason: 'مُحيت بيانات الجهاز');
      expect(photos.listSync(), isEmpty, reason: 'مُحيت الصور');
      expect(
        await DevicePreferences(env.db).read(DevicePreferences.schoolEpochKey),
        'epoch-1',
      );
      expect(
        runtime.auth.current?.accountId,
        'u-owner',
        reason: 'يبقى مسجَّلاً',
      );
      expect(await count(env.db, 'device_session'), 1);
      // المدرسة الجديدة تُبذَر مستوياتها الافتراضية من جديد.
      await until(() async => await count(env.db, 'levels') == 12);
      await until(() async => remote.rows('levels').length == 12);
      expect(remote.rows('rooms'), isEmpty);
    });

    test('رُفضت الإعادة: لا يُمسح شيء ويصل السبب', () async {
      final runtime = await started(UserRole.owner);
      await runtime.writer.save(
        env.db.rooms,
        RoomsCompanion.insert(
          id: 'r1',
          createdAt: 0,
          updatedAt: 0,
          name: 'القاعة 1',
        ),
        key: {'id': 'r1'},
      );
      gateway.failure = const SchoolResetException(
        SchoolResetFailure.wrongPassword,
        'كلمة السر غير صحيحة',
      );
      await expectLater(
        runtime.resetSchool(password: 'wrong'),
        throwsA(
          isA<SchoolResetException>().having(
            (e) => e.failure,
            'failure',
            SchoolResetFailure.wrongPassword,
          ),
        ),
      );
      expect(await roomIds(env), ['r1']);
      expect(
        await DevicePreferences(env.db).read(DevicePreferences.schoolEpochKey),
        isNull,
      );
    });

    test('غير المالك لا يعيد تعيين المدرسة ولا تُستدعى البوابة', () async {
      final runtime = await started(UserRole.teacher);
      await expectLater(
        runtime.resetSchool(password: 'owner-pass-1'),
        throwsA(isA<SchoolResetException>()),
      );
      expect(gateway.passwords, isEmpty);
    });

    test('الوضع المحلي بلا خادم: غير متاحة', () async {
      final runtime = await startTestRuntime(
        localMode: true,
        photosDirectory: photos,
      );
      addTearDown(runtime.dispose);
      expect(runtime.schoolReset, isNull);
      await expectLater(
        runtime.resetSchool(password: 'x'),
        throwsA(isA<SchoolResetException>()),
      );
    });
  });
}
