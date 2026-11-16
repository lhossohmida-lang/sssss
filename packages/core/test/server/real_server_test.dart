import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// اختبارات على خادم Supabase الحقيقي (مدرسة demo): دفع الصفوف وسحبها و«آخر تعديل
/// يفوز» والحذف الناعم، والبث اللحظي، ورفع الملفات وتنزيلها بمكوّنات التطبيق نفسها
/// (`SupabaseBackend`). تمرَّر بيانات الخادم بـ`--dart-define` من مسار `server-test`؛
/// ودونها تُتخطّى فلا تفشل اختبارات المطوّر المحلية ولا مسار `check`.
const _url = String.fromEnvironment('SUPABASE_URL');
const _anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

/// مالك مؤقت ينشئه المسار قبل الاختبارات ويحذفه بعدها، فلا تتأثر بكلمة سر مالك
/// المدرسة الحقيقي (يغيّرها عند أول دخول).
const _email = String.fromEnvironment('SERVER_TEST_EMAIL');
const _password = String.fromEnvironment('SERVER_TEST_PASSWORD');

bool get _enabled =>
    _url.isNotEmpty &&
    _anonKey.isNotEmpty &&
    _email.isNotEmpty &&
    _password.isNotEmpty;

Map<String, Object?> _room(
  String id,
  int at, {
  String name = 'فحص التكامل',
  int? deletedAt,
}) => {
  'id': id,
  'created_at': at,
  'updated_at': at,
  'deleted_at': deletedAt,
  'name': name,
  'capacity': 2,
};

void main() {
  group(
    'الخادم الحقيقي',
    skip: _enabled ? false : 'لا بيانات خادم (SUPABASE_URL وغيرها)',
    () {
      late SupabaseClient client;
      late AppDatabase db;
      late SupabaseBackend backend;

      setUpAll(() async {
        // flutter_test يستبدل HttpClient بنسخة ترفض الشبكة إن هُيّئت الحاضنة.
        HttpOverrides.global = null;
        client = SupabaseClient(_url, _anonKey);
        final signedIn = await client.auth.signInWithPassword(
          email: _email,
          password: _password,
        );
        expect(signedIn.session, isNotNull, reason: 'دخول المالك');
        db = AppDatabase(NativeDatabase.memory());
        backend = SupabaseBackend(client, db: db, apiKey: _anonKey);
      });

      tearDownAll(() async {
        await client.auth.signOut();
        await client.dispose();
        await db.close();
      });

      /// أحدث `synced_at` في [table] الآن (مؤشر السحب قبل الكتابة).
      Future<int> latestStamp(String table) async {
        final rows = await client
            .from(table)
            .select('synced_at')
            .order('synced_at', ascending: false)
            .limit(1);
        return rows.isEmpty ? 0 : rows.first['synced_at']! as int;
      }

      Future<Map<String, Object?>?> pulled(
        String id, {
        required int after,
      }) async {
        final rows = await backend.remote.pull(
          'rooms',
          afterSyncedAt: after,
          limit: 500,
        );
        for (final row in rows) {
          if (row['id'] == id) return row;
        }
        return null;
      }

      test('الدفع والسحب و«آخر تعديل يفوز» والحذف الناعم', () async {
        final id = 'srv-it-${DateTime.now().microsecondsSinceEpoch}';
        final now = DateTime.now().millisecondsSinceEpoch;
        final before = await latestStamp('rooms');

        await backend.remote.upsert('rooms', [_room(id, now)]);
        final first = await pulled(id, after: before);
        expect(first, isNotNull, reason: 'الصف المدفوع لم يُسحب');
        expect(first!['name'], 'فحص التكامل');
        final firstStamp = first['synced_at']! as int;
        expect(firstStamp, greaterThan(before));

        // تحديث أقدم يُتجاهل فلا يتغير الصف ولا يتقدم ختمه.
        await backend.remote.upsert('rooms', [
          _room(id, now - 1000, name: 'قديم'),
        ]);
        final stale = await pulled(id, after: before);
        expect(stale!['name'], 'فحص التكامل');
        expect(stale['synced_at'], firstStamp);

        await backend.remote.upsert('rooms', [
          _room(id, now + 1000, name: 'جديد'),
        ]);
        final newer = await pulled(id, after: firstStamp);
        expect(newer!['name'], 'جديد');
        final newerStamp = newer['synced_at']! as int;
        expect(newerStamp, greaterThan(firstStamp));

        await backend.remote.upsert('rooms', [
          _room(id, now + 2000, name: 'جديد', deletedAt: now + 2000),
        ]);
        final deleted = await pulled(id, after: newerStamp);
        expect(deleted!['deleted_at'], now + 2000);
      });

      test('«إضافة فقط» تتجاهل الصف الموجود', () async {
        final id = 'srv-io-${DateTime.now().microsecondsSinceEpoch}';
        final now = DateTime.now().millisecondsSinceEpoch;
        final before = await latestStamp('rooms');
        await backend.remote.upsert('rooms', [
          _room(id, now),
        ], insertOnly: true);
        await backend.remote.upsert('rooms', [
          _room(id, now + 5000, name: 'يجب ألا يظهر'),
        ], insertOnly: true);
        final row = await pulled(id, after: before);
        expect(row!['name'], 'فحص التكامل');
      });

      test('البث اللحظي يوصل صفاً كتبه المالك', () async {
        final id = 'srv-rt-${DateTime.now().microsecondsSinceEpoch}';
        final now = DateTime.now().millisecondsSinceEpoch;
        final seen = Completer<RemoteChange>();
        final subscription = backend.realtime.changes().listen(
          (change) {
            if (change.table == 'rooms' &&
                change.row['id'] == id &&
                !seen.isCompleted) {
              seen.complete(change);
            }
          },
          onError: (Object error) {
            if (!seen.isCompleted) seen.completeError(error);
          },
        );
        addTearDown(subscription.cancel);

        // الاشتراك يستغرق لحظة: تُكرَّر الكتابة بتحديث أحدث كل بضع ثوانٍ حتى يصل حدث.
        final deadline = DateTime.now().add(const Duration(seconds: 45));
        var attempt = 0;
        while (!seen.isCompleted && DateTime.now().isBefore(deadline)) {
          attempt++;
          await backend.remote.upsert('rooms', [
            _room(id, now + attempt * 10, name: 'بث $attempt'),
          ]);
          await Future.any<void>([
            seen.future.then((_) {}),
            Future<void>.delayed(const Duration(seconds: 4)),
          ]);
        }
        final change = await seen.future.timeout(
          const Duration(seconds: 1),
          onTimeout: () =>
              throw TestFailure('لم يصل أي حدث بث لحظي خلال 45 ثانية'),
        );
        expect(change.row['name'], startsWith('بث'));
      });

      test('رفع الملفات وتنزيلها ورفض الصورة الأكبر من الحد', () async {
        final dir = await Directory.systemTemp.createTemp('srv-it');
        addTearDown(() => dir.delete(recursive: true));
        final stamp = DateTime.now().microsecondsSinceEpoch;
        final content = utf8.encode('فحص الملفات $stamp');
        final file = File('${dir.path}/a.bin')..writeAsBytesSync(content);

        final filePath = 'integration/$stamp.txt';
        expect(
          await backend.files.upload(
            bucket: 'files',
            remotePath: filePath,
            localPath: file.path,
          ),
          'files/$filePath',
        );
        expect(
          await backend.files.download(bucket: 'files', remotePath: filePath),
          content,
        );

        // الصور تقبل استبدال الملف نفسه (upsert) لموظفي الإدارة.
        final photoPath = 'integration/$stamp.bin';
        for (var i = 0; i < 2; i++) {
          await backend.files.upload(
            bucket: 'photos',
            remotePath: photoPath,
            localPath: file.path,
          );
        }

        final big = File('${dir.path}/big.bin')
          ..writeAsBytesSync(List<int>.filled(10 * 1024 * 1024 + 4096, 0));
        await expectLater(
          backend.files.upload(
            bucket: 'photos',
            remotePath: 'integration/big-$stamp.bin',
            localPath: big.path,
          ),
          throwsA(
            isA<RemoteException>().having(
              (e) => e.permanent,
              'permanent',
              true,
            ),
          ),
        );
      });
    },
  );
}
