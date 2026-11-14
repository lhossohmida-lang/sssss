import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

import '../support/fake_remote.dart';
import '../support/fixtures.dart';

class FakeRealtime implements RealtimeSource {
  final StreamController<RemoteChange> controller =
      StreamController<RemoteChange>.broadcast();

  @override
  Stream<RemoteChange> changes() => controller.stream;

  Future<void> close() => controller.close();
}

class _CountingFileStore implements FileStore {
  int uploads = 0;

  @override
  Future<String> upload({
    required String bucket,
    required String remotePath,
    required String localPath,
  }) async {
    uploads++;
    return remotePath;
  }

  @override
  Future<Uint8List> download({
    required String bucket,
    required String remotePath,
  }) async => Uint8List(0);
}

void main() {
  late TestEnv env;
  late FakeRemote remote;
  late FakeRealtime realtime;
  late SyncCoordinator coordinator;
  late List<SyncStatus> statuses;

  Future<void> saveRoom(String id, String name) => env.writer.save(
    env.db.rooms,
    RoomsCompanion.insert(id: id, createdAt: 0, updatedAt: 0, name: name),
    key: {'id': id},
  );

  /// ينتظر حتى يتحقق الشرط (المزامنة تجري في الخلفية).
  Future<void> until(bool Function() condition) async {
    for (var i = 0; i < 200 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(condition(), isTrue, reason: 'لم يتحقق الشرط في الوقت المحدد');
  }

  SyncCoordinator build({int debounceMs = 20}) => SyncCoordinator(
    env.db,
    SyncEngine(
      env.db,
      remote,
      tables: SyncProfile.forRole(UserRole.owner),
      clock: () => env.time,
    ),
    realtime: realtime,
    debounce: Duration(milliseconds: debounceMs),
    interval: const Duration(hours: 1),
    clock: () => env.time,
  );

  setUp(() {
    env = TestEnv();
    remote = FakeRemote();
    realtime = FakeRealtime();
    coordinator = build();
    statuses = [];
    coordinator.statusStream.listen(statuses.add);
  });

  tearDown(() async {
    await coordinator.stop();
    await realtime.close();
    await env.close();
  });

  test('كل كتابة محلية تُدفع تلقائياً في الخلفية', () async {
    coordinator.start();
    await saveRoom('r1', 'القاعة 1');
    await until(() => remote.rows('rooms').isNotEmpty);
    expect(remote.row('rooms', 'r1')?['name'], 'القاعة 1');
    await until(() => coordinator.status.phase == SyncPhase.idle);
    expect(coordinator.status.pending, 0);
    expect(coordinator.status.lastSuccessAt, isNotNull);
  });

  test('كتابات متتالية تُجمَّع في جولة واحدة', () async {
    // مهلة تجميع أطول من زمن الكتابات الخمس حتى لا يعتمد الاختبار على
    // سرعة الجهاز.
    await coordinator.stop();
    coordinator = build(debounceMs: 400);
    coordinator.start();
    await until(() => coordinator.status.lastSuccessAt != null);
    remote.calls.clear();
    for (var i = 0; i < 5; i++) {
      await saveRoom('r$i', 'ق$i');
    }
    await until(() => remote.rows('rooms').length == 5);
    await until(() => coordinator.status.phase == SyncPhase.idle);
    // كل جولة تسحب الجداول مرة واحدة، فعدد سحبات جدول واحد = عدد الجولات.
    expect(
      remote.calls.where((c) => c == 'pull:settings'),
      hasLength(lessThanOrEqualTo(2)),
      reason: 'خمس كتابات متتالية لا تُنتج خمس جولات',
    );
  });

  test('البث اللحظي يطبّق تغييرات الأجهزة الأخرى فوراً', () async {
    coordinator.start();
    realtime.controller.add(
      const RemoteChange(
        table: 'rooms',
        row: {
          'id': 'r9',
          'created_at': 1,
          'updated_at': 5,
          'deleted_at': null,
          'name': 'من جهاز آخر',
          'capacity': 10,
          'synced_at': 3,
        },
      ),
    );
    RoomRow? room;
    for (var i = 0; i < 100 && room == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      room = await (env.db.select(
        env.db.rooms,
      )..where((r) => r.id.equals('r9'))).getSingleOrNull();
    }
    expect(room?.name, 'من جهاز آخر');
    await until(() => coordinator.status.phase == SyncPhase.idle);
    expect(remote.rows('rooms'), isEmpty, reason: 'ما وصل بالبث لا يُعاد دفعه');
  });

  test('إشعار الخادم يظهر في قائمة المستخدم وعدّاده فوراً', () async {
    final inboxEvents = <List<NotificationRow>>[];
    final unreadEvents = <int>[];
    final inboxSubscription = env.db
        .watchNotifications('acc-push')
        .listen(inboxEvents.add);
    final unreadSubscription = env.db
        .watchUnreadNotificationCount('acc-push')
        .listen(unreadEvents.add);
    coordinator.start();
    realtime.controller.add(
      const RemoteChange(
        table: 'notifications',
        row: {
          'id': 'notification-live',
          'created_at': 1,
          'updated_at': 3,
          'deleted_at': null,
          'user_id': 'acc-push',
          'sender_id': 'acc-owner',
          'title': 'طلب جديد',
          'body': 'وصل طلبك إلى الإدارة',
          'kind': 'request_pending',
          'entity': 'request',
          'entity_id': 'request-1',
          'read_at': null,
          'synced_at': 2,
        },
      ),
    );

    await until(
      () => inboxEvents.any(
        (rows) => rows.any((row) => row.id == 'notification-live'),
      ),
    );
    await until(() => unreadEvents.contains(1));
    expect(inboxEvents.last.single.title, 'طلب جديد');
    expect(unreadEvents.last, 1);

    await inboxSubscription.cancel();
    await unreadSubscription.cancel();
  });

  test(
    'دون إنترنت: الحالة «غير متصل» والعمل المحلي مستمر، ثم يتعافى',
    () async {
      remote.offline = true;
      coordinator.start();
      await saveRoom('r1', 'القاعة 1');
      await until(() => coordinator.status.phase == SyncPhase.offline);
      expect(coordinator.status.message, 'لا يوجد اتصال');
      expect(coordinator.status.pending, greaterThan(0));
      expect(
        await env.db.select(env.db.rooms).get(),
        hasLength(1),
        reason: 'البيانات محفوظة محلياً',
      );

      remote.offline = false;
      env.time += 60000;
      await coordinator.syncNow();
      expect(coordinator.status.phase, SyncPhase.idle);
      expect(coordinator.status.pending, 0);
      expect(remote.rows('rooms'), hasLength(1));
    },
  );

  test('الصفوف المرفوضة تظهر في الحالة', () async {
    remote.reject = (table, row) => table == 'rooms' ? 'ممنوع' : null;
    coordinator.start();
    await saveRoom('r1', 'القاعة 1');
    await until(() => coordinator.status.rejected == 1);
    expect(coordinator.status.phase, SyncPhase.idle);
  });

  test('لا تتداخل جولتان، والطلب أثناء جولة يعيد جولة بعدها', () async {
    coordinator.start();
    await until(() => coordinator.status.lastSuccessAt != null);
    await saveRoom('r1', 'القاعة 1');
    final first = coordinator.syncNow();
    final second = coordinator.syncNow();
    expect(identical(first, second), isTrue);
    await first;
    expect(remote.rows('rooms'), hasLength(1));
    expect(coordinator.status.phase, SyncPhase.idle);
  });

  test('حالات الواجهة: جارٍ ثم خامل', () async {
    coordinator.start();
    await until(
      () =>
          statuses.any((s) => s.phase == SyncPhase.syncing) &&
          statuses.last.phase == SyncPhase.idle,
    );
  });

  test('بعد الإيقاف لا تُطلب جولات جديدة', () async {
    coordinator.start();
    await until(() => coordinator.status.lastSuccessAt != null);
    await coordinator.stop();
    remote.calls.clear();
    coordinator.requestSync();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(remote.calls, isEmpty);
    // إعادة إنشاء منسّق جديد حتى لا يُغلق المنسّق مرتين في tearDown.
    coordinator = SyncCoordinator(
      env.db,
      SyncEngine(env.db, remote, tables: SyncProfile.forRole(UserRole.owner)),
    );
  });

  test('منسّق Supabase يترك عناصر Google Drive لطابورها المستقل', () async {
    await coordinator.stop();
    final directory = await Directory.systemTemp.createTemp('sync_drive_test');
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/report.xlsx')
      ..writeAsBytesSync([1, 2, 3]);
    final queue = DriveQueueService(
      env.db,
      env.writer,
      stagingDirectory: Directory('${directory.path}/queue'),
      clock: () => env.time,
    );
    await queue.enqueueFile(
      sourcePath: source.path,
      fileName: 'report.xlsx',
      kind: DriveUploadKind.attendanceExcel,
    );
    final files = _CountingFileStore();
    coordinator = SyncCoordinator(
      env.db,
      SyncEngine(env.db, remote, tables: SyncProfile.forRole(UserRole.owner)),
      uploads: UploadWorker(env.db, env.writer, files, clock: () => env.time),
    );

    await coordinator.syncNow();

    expect(files.uploads, 0);
    expect(
      (await env.db.select(env.db.uploadQueue).getSingle()).status,
      UploadWorker.statusPending,
    );
  });
}
