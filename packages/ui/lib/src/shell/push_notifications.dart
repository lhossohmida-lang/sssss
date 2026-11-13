import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:school_core/school_core.dart';

/// Enable only after Firebase's per-app Android configuration is supplied.
const bool firebasePushEnabled = bool.fromEnvironment(
  'FIREBASE_PUSH_ENABLED',
  defaultValue: false,
);

@pragma('vm:entry-point')
Future<void> firebasePushBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) await Firebase.initializeApp();
}

abstract interface class PushMessagingClient {
  Future<bool> requestPermission();

  Future<void> register();

  Future<void> unregister();

  Stream<String> get registrations;

  Stream<String> get unregistrations;

  Stream<Map<String, String>> get messageOpens;

  Future<Map<String, String>?> get initialMessage;
}

class FirebasePushMessagingClient implements PushMessagingClient {
  FirebasePushMessagingClient(this.messaging);

  final FirebaseMessaging messaging;

  @override
  Future<bool> requestPermission() async {
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  @override
  Future<void> register() => messaging.register();

  @override
  Future<void> unregister() => messaging.unregister();

  @override
  Stream<String> get registrations => messaging.onRegistered;

  @override
  Stream<String> get unregistrations => messaging.onUnregistered;

  @override
  Stream<Map<String, String>> get messageOpens =>
      FirebaseMessaging.onMessageOpenedApp.map(_stringData);

  @override
  Future<Map<String, String>?> get initialMessage async {
    final message = await messaging.getInitialMessage();
    return message == null ? null : _stringData(message);
  }

  static Map<String, String> _stringData(RemoteMessage message) => {
    for (final entry in message.data.entries) entry.key: entry.value.toString(),
  };
}

/// Registers only the signed-in account's Android Firebase installation ID.
///
/// FCM is opt-in at build time so local development continues to work before
/// Firebase secrets and `google-services.json` are supplied in stage 8.
class PushNotificationCoordinator {
  PushNotificationCoordinator({
    required this.installationStore,
    required this.isLocalMode,
    required this.signOutAction,
    required this.navigate,
    this.messaging,
    this.enabled = firebasePushEnabled,
    int Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch) {
    _messaging = messaging;
  }

  final PushInstallationStore? installationStore;
  final bool isLocalMode;
  final Future<void> Function() signOutAction;
  final void Function(String path) navigate;
  final PushMessagingClient? messaging;
  final bool enabled;
  final int Function() _clock;

  PushMessagingClient? _messaging;
  StreamSubscription<String>? _registrationSubscription;
  StreamSubscription<String>? _unregistrationSubscription;
  StreamSubscription<Map<String, String>>? _openSubscription;
  Future<void> _transition = Future<void>.value();
  String? _requestedAccountId;
  String? _activeAccountId;
  String? _registeredInstallationId;
  int _generation = 0;
  bool _disposed = false;

  Future<void> updateSession(AuthSession? session) {
    if (_disposed) return Future<void>.value();
    final accountId = session?.accountId;
    if (accountId == _requestedAccountId) return _transition;
    _requestedAccountId = accountId;
    final generation = ++_generation;
    _transition = _transition
        .catchError((Object _) {})
        .then((_) => _applySession(accountId, generation));
    return _transition;
  }

  /// Removes the Firebase Installation ID before the Supabase session ends.
  Future<void> signOut() async {
    await updateSession(null);
    await signOutAction();
  }

  Future<void> _applySession(String? accountId, int generation) async {
    await _cancelListeners();
    final oldAccountId = _activeAccountId;
    final oldInstallationId = _registeredInstallationId;
    _activeAccountId = null;
    _registeredInstallationId = null;

    if (oldAccountId != null && oldInstallationId != null) {
      await _bestEffortUnregister(oldAccountId, oldInstallationId);
    }
    if (oldAccountId != null && oldAccountId != accountId) {
      await _bestEffortUnregisterFirebase();
    }
    if (generation != _generation || _disposed) return;

    _activeAccountId = accountId;
    if (accountId == null ||
        !enabled ||
        isLocalMode ||
        installationStore == null) {
      return;
    }

    final client = await _client();
    if (client == null || generation != _generation || _disposed) return;

    try {
      if (!await client.requestPermission()) return;
      _registrationSubscription = client.registrations.listen(
        (id) => unawaited(_saveInstallation(accountId, id, generation)),
      );
      _unregistrationSubscription = client.unregistrations.listen(
        (id) => unawaited(_removeInstallation(accountId, id, generation)),
      );
      _openSubscription = client.messageOpens.listen(
        (data) => _openMessage(data, accountId, generation),
      );
      await client.register();
      if (generation != _generation || _disposed) return;
      final initial = await client.initialMessage;
      if (initial != null) _openMessage(initial, accountId, generation);
    } on Exception {
      // Push remains unavailable on this device until Firebase is configured
      // or the user retries a sign-in after a network failure.
    }
  }

  Future<PushMessagingClient?> _client() async {
    final current = _messaging;
    if (current != null) return current;
    if (!enabled || defaultTargetPlatform != TargetPlatform.android) {
      return null;
    }
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(firebasePushBackgroundHandler);
      return _messaging = FirebasePushMessagingClient(
        FirebaseMessaging.instance,
      );
    } on Exception {
      return null;
    }
  }

  Future<void> _saveInstallation(
    String accountId,
    String installationId,
    int generation,
  ) async {
    if (installationId.length < 10 || installationId.length > 256) return;
    if (generation != _generation || accountId != _activeAccountId) return;
    final previous = _registeredInstallationId;
    if (previous == installationId) return;
    if (previous != null) {
      await _bestEffortUnregister(accountId, previous);
    }
    if (generation != _generation || accountId != _activeAccountId) return;

    _registeredInstallationId = installationId;
    try {
      await installationStore!.register(
        accountId: accountId,
        installationId: installationId,
        platform: 'android',
        updatedAt: _clock(),
      );
    } on Exception {
      if (_registeredInstallationId == installationId) {
        _registeredInstallationId = null;
      }
      await _bestEffortUnregister(accountId, installationId);
    }
  }

  Future<void> _removeInstallation(
    String accountId,
    String installationId,
    int generation,
  ) async {
    if (generation != _generation || accountId != _activeAccountId) return;
    if (_registeredInstallationId == installationId) {
      _registeredInstallationId = null;
    }
    await _bestEffortUnregister(accountId, installationId);
  }

  void _openMessage(
    Map<String, String> data,
    String accountId,
    int generation,
  ) {
    if (generation != _generation || accountId != _activeAccountId) return;
    final path = notificationDestination(data);
    if (path != null) navigate(path);
  }

  Future<void> _bestEffortUnregister(
    String accountId,
    String installationId,
  ) async {
    try {
      await installationStore?.unregister(
        accountId: accountId,
        installationId: installationId,
      );
    } on Exception {
      // Logout must still work if the server is temporarily unreachable.
    }
  }

  Future<void> _bestEffortUnregisterFirebase() async {
    try {
      await _messaging?.unregister();
    } on Exception {
      // A later Firebase registration refreshes the server-side FID.
    }
  }

  Future<void> _cancelListeners() async {
    await _registrationSubscription?.cancel();
    await _unregistrationSubscription?.cancel();
    await _openSubscription?.cancel();
    _registrationSubscription = null;
    _unregistrationSubscription = null;
    _openSubscription = null;
  }

  /// App shutdown keeps the installation registered so background pushes arrive.
  Future<void> dispose() async {
    _disposed = true;
    _generation++;
    await _transition;
    await _cancelListeners();
  }
}

/// Accept only known in-app destinations; never route to an arbitrary payload.
String? notificationDestination(Map<String, String> data) {
  if (data['type'] == 'chat') {
    final roomId = data['room_id']?.trim();
    if (roomId == null || roomId.isEmpty) return null;
    return '/chat/${Uri.encodeComponent(roomId)}';
  }
  if (data['type'] == 'notification' ||
      (data['notification_id']?.isNotEmpty ?? false)) {
    return '/notifications';
  }
  return null;
}
