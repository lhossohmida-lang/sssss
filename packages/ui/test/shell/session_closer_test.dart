import 'dart:async';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/testing.dart';
import 'package:school_ui/school_ui.dart';

class _FailingService extends AttendanceService {
  _FailingService(super.db, super.writer, super.cycles, super.dues);

  @override
  Future<int> closeDueSessions(DateTime now) =>
      Future<int>.error(StateError('فشل مقصود'));
}

class _RecordingService extends AttendanceService {
  _RecordingService(super.db, super.writer, super.cycles, super.dues);

  final calls = <DateTime>[];
  final firstCallStarted = Completer<void>();
  final releaseFirstCall = Completer<void>();
  final secondCallStarted = Completer<void>();

  @override
  Future<int> closeDueSessions(DateTime now) async {
    calls.add(now);
    if (calls.length == 1) {
      firstCallStarted.complete();
      await releaseFirstCall.future;
    } else if (calls.length == 2) {
      secondCallStarted.complete();
    }
    return 0;
  }
}

void main() {
  late AppRuntime runtime;
  late AttendanceService service;

  setUp(() async {
    runtime = await startTestRuntime(
      app: AppIdentity.admin,
      accounts: const [
        TestAccount(
          id: 'u-owner',
          email: 'owner@school.local',
          password: 'owner-pass-1',
          role: UserRole.owner,
          displayName: 'المدير',
        ),
      ],
    );
    await runtime.auth.signIn(
      email: 'owner@school.local',
      password: 'owner-pass-1',
    );
    final db = runtime.db;
    service = AttendanceService(
      db,
      runtime.writer,
      CycleService(db, runtime.writer),
      DuesService(db, runtime.writer),
    );
    await db
        .into(db.subjects)
        .insert(
          SubjectsCompanion.insert(
            id: 'math',
            createdAt: 1,
            updatedAt: 1,
            name: 'رياضيات',
            monthlyPrice: const Value(2000),
          ),
        );
    await db
        .into(db.teachers)
        .insert(
          TeachersCompanion.insert(
            id: 't1',
            createdAt: 1,
            updatedAt: 1,
            name: 'كمال',
            phone: '0660000001',
            email: 't1@school.local',
            qrCode: 'T-t1',
          ),
        );
    await db
        .into(db.groups)
        .insert(
          GroupsCompanion.insert(
            id: 'g1',
            createdAt: 1,
            updatedAt: 1,
            number: 1,
            subjectId: 'math',
            teacherId: 't1',
          ),
        );
    await db
        .into(db.sessions)
        .insert(
          SessionsCompanion.insert(
            id: 'se1',
            createdAt: 1,
            updatedAt: 1,
            groupId: 'g1',
            cycleNumber: 1,
            date: '2026-11-07',
            startMinutes: 600,
            endMinutes: 690,
            sessionNumber: const Value(1),
          ),
        );
  });

  tearDown(() async {
    await runtime.auth.dispose();
    await runtime.db.close();
  });

  test('runOnce يغلق الحصة المنتهية مرة واحدة فقط', () async {
    final closer = SessionCloser(
      service,
      clock: () => DateTime(2026, 11, 7, 12),
    );
    expect(await closer.runOnce(), 1);
    expect(await closer.runOnce(), 0);
    expect(closer.lastError, isNull);
    closer.dispose();
  });

  test('قبل نهاية الحصة لا يُغلق شيء', () async {
    final closer = SessionCloser(
      service,
      clock: () => DateTime(2026, 11, 7, 10, 30),
    );
    expect(await closer.runOnce(), 0);
    closer.dispose();
  });

  test('start يشغّل فوراً ثم دورياً حتى dispose', () async {
    var now = DateTime(2026, 11, 7, 10, 30);
    final db = runtime.db;
    final recording = _RecordingService(
      db,
      runtime.writer,
      CycleService(db, runtime.writer),
      DuesService(db, runtime.writer),
    );
    final closer = SessionCloser(
      recording,
      period: const Duration(milliseconds: 20),
      clock: () => now,
    );
    closer.start();
    await recording.firstCallStarted.future;
    expect(recording.calls, [DateTime(2026, 11, 7, 10, 30)]);
    recording.releaseFirstCall.complete();

    now = DateTime(2026, 11, 7, 12);
    await recording.secondCallStarted.future.timeout(
      const Duration(seconds: 5),
    );
    expect(recording.calls[1], DateTime(2026, 11, 7, 12));

    closer.dispose();
    final callCountAfterDispose = recording.calls.length;
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(recording.calls, hasLength(callCountAfterDispose));
    expect(await closer.runOnce(), 0, reason: 'بعد dispose لا عمل');
  });

  test('خطأ طارئ لا يوقف المهمة ويُحفظ للتشخيص', () async {
    final db = runtime.db;
    final failing = _FailingService(
      db,
      runtime.writer,
      CycleService(db, runtime.writer),
      DuesService(db, runtime.writer),
    );
    final closer = SessionCloser(failing);
    expect(await closer.runOnce(), 0);
    expect(closer.lastError, isA<StateError>());
    closer.dispose();
  });

  group('المزوّد', () {
    Future<bool> closedAfterStart(
      ProviderContainer container,
      AppRuntime runtime,
    ) async {
      final sub = container.listen(sessionCloserProvider, (_, _) {});
      await Future<void>.delayed(const Duration(milliseconds: 200));
      sub.close();
      final session =
          (await runtime.db.select(runtime.db.sessions).get()).single;
      return session.closedAt != null;
    }

    test('يعمل في الإدارة لمن يملك صلاحية الحضور', () async {
      final container = ProviderContainer(
        overrides: [runtimeProvider.overrideWithValue(runtime)],
      );
      addTearDown(container.dispose);
      expect(await closedAfterStart(container, runtime), isTrue);
    });

    test('لا يعمل إن عُطّل', () async {
      final container = ProviderContainer(
        overrides: [
          runtimeProvider.overrideWithValue(runtime),
          sessionCloserEnabledProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);
      expect(await closedAfterStart(container, runtime), isFalse);
    });
  });
}
