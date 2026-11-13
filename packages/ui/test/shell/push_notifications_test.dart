import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

class _FakePushMessaging implements PushMessagingClient {
  final StreamController<String> registeredInstallations =
      StreamController<String>.broadcast();
  final StreamController<String> unregisteredInstallations =
      StreamController<String>.broadcast();
  final StreamController<Map<String, String>> openedMessages =
      StreamController<Map<String, String>>.broadcast();

  bool permissionGranted = true;
  String installationId = 'fid-initial-1234567890123456';
  Map<String, String>? initial;
  int permissionRequests = 0;
  int registrationRequests = 0;
  int unregistrationRequests = 0;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return permissionGranted;
  }

  @override
  Future<void> register() async {
    registrationRequests++;
    registeredInstallations.add(installationId);
  }

  @override
  Future<void> unregister() async {
    unregistrationRequests++;
    unregisteredInstallations.add(installationId);
  }

  @override
  Stream<String> get registrations => registeredInstallations.stream;

  @override
  Stream<String> get unregistrations => unregisteredInstallations.stream;

  @override
  Stream<Map<String, String>> get messageOpens => openedMessages.stream;

  @override
  Future<Map<String, String>?> get initialMessage async => initial;

  Future<void> close() async {
    await registeredInstallations.close();
    await unregisteredInstallations.close();
    await openedMessages.close();
  }
}

class _FakePushInstallationStore implements PushInstallationStore {
  final registered =
      <
        ({
          String accountId,
          String installationId,
          String platform,
          int updatedAt,
        })
      >[];
  final unregistered = <({String accountId, String installationId})>[];

  @override
  Future<void> register({
    required String accountId,
    required String installationId,
    required String platform,
    required int updatedAt,
  }) async {
    registered.add((
      accountId: accountId,
      installationId: installationId,
      platform: platform,
      updatedAt: updatedAt,
    ));
  }

  @override
  Future<void> unregister({
    required String accountId,
    required String installationId,
  }) async {
    unregistered.add((accountId: accountId, installationId: installationId));
  }
}

AuthSession _session(String id) => AuthSession(
  AccountRecord(id: id, email: '$id@school.local', role: UserRole.parent),
);

Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 100 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(condition(), isTrue, reason: 'لم يتحقق الشرط في الوقت المحدد');
}

void main() {
  test('Firebase push stays disabled until a build opts in', () {
    expect(firebasePushEnabled, isFalse);
  });

  test(
    'registers and rotates an installation, then removes it before sign out',
    () async {
      final messaging = _FakePushMessaging();
      final store = _FakePushInstallationStore();
      var signedOut = false;
      final coordinator = PushNotificationCoordinator(
        installationStore: store,
        isLocalMode: false,
        signOutAction: () async {
          signedOut = true;
        },
        navigate: (_) {},
        messaging: messaging,
        enabled: true,
        clock: () => 1234,
      );

      await coordinator.updateSession(_session('acc-1'));
      await _until(() => store.registered.length == 1);
      expect(messaging.permissionRequests, 1);
      expect(store.registered, [
        (
          accountId: 'acc-1',
          installationId: 'fid-initial-1234567890123456',
          platform: 'android',
          updatedAt: 1234,
        ),
      ]);

      const refreshed = 'fid-refreshed-1234567890123456';
      messaging.registeredInstallations.add(refreshed);
      await _until(() => store.registered.length == 2);
      expect(store.unregistered, [
        (accountId: 'acc-1', installationId: 'fid-initial-1234567890123456'),
      ]);

      await coordinator.signOut();
      expect(store.unregistered.last, (
        accountId: 'acc-1',
        installationId: refreshed,
      ));
      expect(messaging.unregistrationRequests, 1);
      expect(signedOut, isTrue);

      await coordinator.dispose();
      await messaging.close();
    },
  );

  test('opens only a known chat or notification destination', () async {
    final messaging = _FakePushMessaging()..initial = {'type': 'notification'};
    final routes = <String>[];
    final coordinator = PushNotificationCoordinator(
      installationStore: _FakePushInstallationStore(),
      isLocalMode: false,
      signOutAction: () async {},
      navigate: routes.add,
      messaging: messaging,
      enabled: true,
    );

    await coordinator.updateSession(_session('acc-2'));
    expect(routes, ['/notifications']);

    messaging.openedMessages.add({'type': 'chat', 'room_id': 'room-1'});
    await _until(() => routes.length == 2);
    expect(routes.last, '/chat/room-1');
    messaging.openedMessages.add({'type': 'chat', 'room_id': '../settings'});
    messaging.openedMessages.add({'route': '/settings'});
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(routes, ['/notifications', '/chat/room-1', '/chat/..%2Fsettings']);

    await coordinator.dispose();
    await messaging.close();
  });

  test('does not register when disabled, local, or denied', () async {
    final messaging = _FakePushMessaging();
    final store = _FakePushInstallationStore();

    final disabled = PushNotificationCoordinator(
      installationStore: store,
      isLocalMode: false,
      signOutAction: () async {},
      navigate: (_) {},
      messaging: messaging,
      enabled: false,
    );
    await disabled.updateSession(_session('acc-disabled'));
    expect(messaging.permissionRequests, 0);
    await disabled.dispose();

    final local = PushNotificationCoordinator(
      installationStore: store,
      isLocalMode: true,
      signOutAction: () async {},
      navigate: (_) {},
      messaging: messaging,
      enabled: true,
    );
    await local.updateSession(_session('acc-local'));
    expect(messaging.permissionRequests, 0);
    await local.dispose();

    messaging.permissionGranted = false;
    final denied = PushNotificationCoordinator(
      installationStore: store,
      isLocalMode: false,
      signOutAction: () async {},
      navigate: (_) {},
      messaging: messaging,
      enabled: true,
    );
    await denied.updateSession(_session('acc-denied'));
    expect(messaging.permissionRequests, 1);
    expect(messaging.registrationRequests, 0);
    expect(store.registered, isEmpty);

    await denied.dispose();
    await messaging.close();
  });
}
