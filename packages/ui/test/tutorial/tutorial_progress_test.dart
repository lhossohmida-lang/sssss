import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/testing.dart';
import 'package:school_ui/school_ui.dart';

const _owner = TestAccount(
  id: 'u-owner',
  email: 'owner@school.local',
  password: 'owner-pass-1',
  role: UserRole.owner,
  displayName: 'المدير',
);

void main() {
  late AppRuntime runtime;
  late DevicePreferences preferences;

  setUp(() async {
    runtime = await startTestRuntime(
      app: AppIdentity.admin,
      accounts: [_owner],
    );
    preferences = DevicePreferences(runtime.db);
  });

  tearDown(() async {
    await runtime.auth.dispose();
    await runtime.db.close();
  });

  test('حساب جديد: لا شيء منتهٍ ولم تُعرض عليه الجولة', () async {
    final state = await TutorialProgress(preferences, 'a').load();
    expect(state.prompted, isFalse);
    expect(state.isDone('students'), isFalse);
    expect(state.doneCount(TutorialCatalog.admin), 0);
  });

  test('تسجيل الإنجاز والعرض، وتكراره لا يضر', () async {
    final progress = TutorialProgress(preferences, 'a');
    await progress.markDone('students');
    await progress.markDone('students');
    await progress.markPrompted();
    await progress.markDone('groups');

    final state = await progress.load();
    expect(state.isDone('students'), isTrue);
    expect(state.isDone('groups'), isTrue);
    expect(state.isDone('payments'), isFalse);
    expect(state.prompted, isTrue);
    expect(state.doneCount(TutorialCatalog.admin), 2);
    expect(
      await preferences.read('tutorial_a'),
      '_prompted,groups,students',
      reason: 'قائمة مفصولة بفواصل مرتّبة',
    );
  });

  test('التقدّم لكل حساب على حدة', () async {
    await TutorialProgress(preferences, 'a').markDone('students');
    final other = await TutorialProgress(preferences, 'b').load();
    expect(other.isDone('students'), isFalse);
    expect(other.prompted, isFalse);
  });

  test('المراقبة تُصدر كل تغيير', () async {
    final progress = TutorialProgress(preferences, 'a');
    final seen = <bool>[];
    final subscription = progress.watch().listen(
      (state) => seen.add(state.isDone('students')),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await progress.markDone('students');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await subscription.cancel();
    expect(seen.first, isFalse);
    expect(seen.last, isTrue);
  });

  test('قيمة تالفة محفوظة لا تُسقط القراءة', () async {
    await preferences.write('tutorial_a', ',, students ,,');
    final state = await TutorialProgress(preferences, 'a').load();
    expect(state.isDone('students'), isTrue);
    expect(state.prompted, isFalse);
  });
}
