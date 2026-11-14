import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_desktop/google_sign_in_desktop.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:school_core/school_core.dart';

import 'package:school_ui/school_ui.dart';

const String _driveScope = 'https://www.googleapis.com/auth/drive.file';
const List<String> _driveScopes = [_driveScope];

/// هوية حساب Drive الذي صودق به على الجهاز.
class DriveAccount {
  const DriveAccount({
    required this.email,
    required this.isOwner,
    this.displayName,
  });

  final String email;
  final bool isOwner;
  final String? displayName;
}

/// العقد الذي تستعمله الشاشة، ويمكن استبداله في اختبارات الواجهة.
abstract interface class DriveController {
  bool get isConfigured;
  String get configurationMessage;
  Stream<DriveAccount?> get accountChanges;
  Stream<List<UploadQueueRow>> get queueChanges;
  Future<void> initialize();
  Future<void> signIn();
  Future<void> signOut();
  Future<int> addFiles(List<PlatformFile> files, DriveUploadKind kind);
  Future<int> uploadPending();
  Future<int> retryFailed();
  Future<void> dispose();
}

final Provider<DriveController> driveControllerProvider =
    Provider<DriveController>((ref) {
      final controller = GoogleDriveController(ref.watch(runtimeProvider));
      ref.onDispose(() => unawaited(controller.dispose()));
      return controller;
    });

final StreamProvider<DriveAccount?> driveAccountProvider =
    StreamProvider<DriveAccount?>((ref) {
      return ref.watch(driveControllerProvider).accountChanges;
    });

final StreamProvider<List<UploadQueueRow>> driveQueueProvider =
    StreamProvider<List<UploadQueueRow>>((ref) {
      return ref.watch(driveControllerProvider).queueChanges;
    });

/// ربط Google Sign-In على Android وتدفق PKCE ذي loopback على Windows.
/// رموز سطح المكتب تبقى في التخزين الآمن للنظام، ورمز Drive قصير العمر لا
/// يُكتب في قاعدة التطبيق أو في سجل العمليات.
class GoogleDriveController implements DriveController {
  GoogleDriveController(this.runtime)
    : _ownerEmail = const String.fromEnvironment('GOOGLE_DRIVE_OWNER_EMAIL'),
      _windowsClientId = const String.fromEnvironment(
        'GOOGLE_DRIVE_WINDOWS_CLIENT_ID',
      ),
      _windowsClientSecret = const String.fromEnvironment(
        'GOOGLE_DRIVE_WINDOWS_CLIENT_SECRET',
      ) {
    final staging = Directory(
      '${runtime.photosDirectory.parent.path}${Platform.pathSeparator}drive_uploads',
    );
    _queue = DriveQueueService(
      runtime.db,
      runtime.writer,
      stagingDirectory: staging,
    );
    _store = GoogleDriveFileStore(accessToken: _accessToken);
    _worker = UploadWorker(runtime.db, runtime.writer, _store);
  }

  final AppRuntime runtime;
  final String _ownerEmail;
  final String _windowsClientId;
  final String _windowsClientSecret;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final StreamController<DriveAccount?> _accountController =
      StreamController<DriveAccount?>.broadcast();
  late final DriveQueueService _queue;
  late final GoogleDriveFileStore _store;
  late final UploadWorker _worker;
  StreamSubscription<GoogleSignInAuthenticationEvent>? _authSubscription;
  Timer? _uploadTimer;
  GoogleSignInAccount? _googleAccount;
  DriveAccount? _account;
  Future<void>? _initializing;
  Future<int>? _uploading;
  bool _initialized = false;
  bool _closed = false;

  @override
  bool get isConfigured =>
      _ownerEmail.trim().isNotEmpty &&
      (Platform.isAndroid ||
          (Platform.isWindows &&
              _windowsClientId.trim().isNotEmpty &&
              _windowsClientSecret.trim().isNotEmpty));

  @override
  String get configurationMessage {
    if (_ownerEmail.trim().isEmpty) {
      return 'يُضبط بريد حساب Google المالك عند تجهيز مفاتيح المرحلة الأخيرة.';
    }
    if (Platform.isWindows &&
        (_windowsClientId.trim().isEmpty ||
            _windowsClientSecret.trim().isEmpty)) {
      return 'بيانات OAuth لنسخة Windows لم تُضبط بعد.';
    }
    if (!Platform.isWindows && !Platform.isAndroid) {
      return 'Google Drive متاح في تطبيق الإدارة على Android وWindows.';
    }
    return 'أضف إعداد OAuth الخاص بتطبيق Android إلى بناء الإدارة.';
  }

  @override
  Stream<DriveAccount?> get accountChanges async* {
    yield _account;
    yield* _accountController.stream;
  }

  @override
  Stream<List<UploadQueueRow>> get queueChanges => _queue.watchQueue();

  @override
  Future<void> initialize() {
    if (!isConfigured) return Future.value();
    return _initializing ??= _initialize();
  }

  Future<void> _initialize() async {
    if (_initialized) return;
    final google = GoogleSignIn.instance;
    if (Platform.isWindows) {
      final platform = GoogleSignInPlatform.instance;
      if (platform is! GoogleSignInDesktop) {
        throw StateError('مكوّن Google Sign-In لنسخة Windows غير مسجّل.');
      }
      platform
        ..clientSecret = _windowsClientSecret
        ..tokenDataStore = _SecureDriveTokenStore(_secureStorage);
    }
    await google.initialize(
      clientId: Platform.isWindows ? _windowsClientId : null,
    );
    _authSubscription = google.authenticationEvents.listen(
      (event) {
        if (event is GoogleSignInAuthenticationEventSignIn) {
          _setAccount(event.user);
        } else if (event is GoogleSignInAuthenticationEventSignOut) {
          _setAccount(null);
        }
      },
      onError: (Object error, StackTrace stack) {
        if (!_accountController.isClosed) {
          _accountController.addError(error, stack);
        }
      },
    );
    _initialized = true;
    final lightweight = google.attemptLightweightAuthentication();
    if (lightweight != null) {
      final account = await lightweight;
      if (account != null) _setAccount(account);
    }
  }

  @override
  Future<void> signIn() async {
    if (!isConfigured) throw StateError(configurationMessage);
    await initialize();
    if (_account case final current? when !current.isOwner) {
      await GoogleSignIn.instance.signOut();
    }
    final account = await GoogleSignIn.instance.authenticate();
    if (!_matchesOwner(account.email)) {
      await GoogleSignIn.instance.signOut();
      _setAccount(null);
      throw StateError('استخدم حساب Google المالك: $_ownerEmail');
    }
    await account.authorizationClient.authorizeScopes(_driveScopes);
    _setAccount(account);
    _startUploadTimer();
    await uploadPending();
  }

  @override
  Future<void> signOut() async {
    _uploadTimer?.cancel();
    _uploadTimer = null;
    if (_initialized) await GoogleSignIn.instance.signOut();
    _setAccount(null);
  }

  @override
  Future<int> addFiles(List<PlatformFile> files, DriveUploadKind kind) async {
    var added = 0;
    for (final file in files) {
      if (await _queue.enqueueStream(
        bytes: file.readAsByteStream(),
        fileName: file.name,
        kind: kind,
      )) {
        added++;
      }
    }
    if (_account?.isOwner == true) unawaited(uploadPending());
    return added;
  }

  @override
  Future<int> uploadPending() {
    if (_account?.isOwner != true) return Future.value(0);
    final running = _uploading;
    if (running != null) return running;
    final upload = _worker
        .processPending(buckets: const {DriveQueueService.bucket})
        .whenComplete(() => _uploading = null);
    _uploading = upload;
    return upload;
  }

  @override
  Future<int> retryFailed() async {
    final count = await _queue.retryFailed();
    if (_account?.isOwner == true) await uploadPending();
    return count;
  }

  Future<String?> _accessToken() async {
    final account = _googleAccount;
    if (account == null || !_matchesOwner(account.email)) return null;
    final authorization = await account.authorizationClient
        .authorizationForScopes(_driveScopes);
    return authorization?.accessToken;
  }

  bool _matchesOwner(String email) =>
      email.trim().toLowerCase() == _ownerEmail.trim().toLowerCase();

  void _setAccount(GoogleSignInAccount? account) {
    _googleAccount = account;
    final email = account?.email;
    _account = email == null
        ? null
        : DriveAccount(
            email: email,
            displayName: account?.displayName,
            isOwner: _matchesOwner(email),
          );
    if (_account?.isOwner == true) {
      _startUploadTimer();
    } else {
      _uploadTimer?.cancel();
      _uploadTimer = null;
    }
    if (!_accountController.isClosed) _accountController.add(_account);
  }

  void _startUploadTimer() {
    if (_uploadTimer != null || _account?.isOwner != true) return;
    _uploadTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(uploadPending()),
    );
    unawaited(uploadPending());
  }

  @override
  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    _uploadTimer?.cancel();
    await _authSubscription?.cancel();
    await _uploading;
    _store.dispose();
    await _accountController.close();
  }
}

class _SecureDriveTokenStore
    implements GoogleSignInDesktopStore<GoogleSignInDesktopTokenData> {
  _SecureDriveTokenStore(this.storage);

  final FlutterSecureStorage storage;
  static const String _key = 'google_drive_desktop_tokens';

  @override
  Future<GoogleSignInDesktopTokenData?> get() async {
    final encoded = await storage.read(key: _key);
    if (encoded == null || encoded.isEmpty) return null;
    final decoded = jsonDecode(encoded);
    if (decoded is! Map<String, dynamic>) return null;
    return GoogleSignInDesktopTokenData.fromJson(decoded);
  }

  @override
  Future<void> set(GoogleSignInDesktopTokenData? value) async {
    if (value == null) {
      await storage.delete(key: _key);
    } else {
      await storage.write(key: _key, value: jsonEncode(value.toJson()));
    }
  }
}

class DriveScreen extends ConsumerStatefulWidget {
  const DriveScreen({super.key});

  @override
  ConsumerState<DriveScreen> createState() => _DriveScreenState();
}

class _DriveScreenState extends ConsumerState<DriveScreen> {
  DriveUploadKind _kind = DriveUploadKind.file;
  bool _busy = false;
  String? _message;
  late final DriveController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(driveControllerProvider);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await _controller.initialize();
    } on Object catch (error) {
      if (mounted) {
        setState(() => _message = 'تعذّر تهيئة Google Drive: $error');
      }
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } on Object catch (error) {
      if (mounted) setState(() => _message = _userMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _userMessage(Object error) =>
      error is StateError ? error.message.toString() : 'تعذّرت العملية: $error';

  Future<void> _pickFiles() async {
    final files = await FilePicker.pickFiles();
    if (files.isEmpty) return;
    await _run(() async {
      final added = await _controller.addFiles(files, _kind);
      if (mounted) {
        setState(() {
          _message = added == 0
              ? 'الملفات موجودة في الطابور من قبل'
              : 'أُضيف $added ملف إلى طابور الرفع';
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(driveAccountProvider);
    final queue = ref.watch(driveQueueProvider);
    final current = account.value;
    final rows = queue.value ?? const <UploadQueueRow>[];
    final failed = rows
        .where((row) => row.status == UploadWorker.statusFailed)
        .length;
    final pending = rows
        .where((row) => row.status == UploadWorker.statusPending)
        .length;

    return Scaffold(
      appBar: AppBar(title: const Text('Google Drive')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      current == null
                          ? 'لم يُسجّل الدخول'
                          : current.isOwner
                          ? 'حساب المالك: ${current.email}'
                          : 'الحساب غير مخوّل: ${current.email}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (!_controller.isConfigured) ...[
                      const SizedBox(height: 8),
                      Text(_controller.configurationMessage),
                    ],
                    if (_message != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _message!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: _busy || !_controller.isConfigured
                              ? null
                              : () => _run(_controller.signIn),
                          icon: const Icon(Icons.login_rounded),
                          label: Text(
                            current?.isOwner == true
                                ? 'تحديث الاتصال'
                                : 'تسجيل الدخول',
                          ),
                        ),
                        if (current != null)
                          OutlinedButton.icon(
                            onPressed: _busy
                                ? null
                                : () => _run(_controller.signOut),
                            icon: const Icon(Icons.logout_rounded),
                            label: const Text('تسجيل الخروج'),
                          ),
                        OutlinedButton.icon(
                          onPressed: _busy || current?.isOwner != true
                              ? null
                              : () => _run(() async {
                                  await _controller.uploadPending();
                                }),
                          icon: const Icon(Icons.cloud_sync_rounded),
                          label: Text('رفع المنتظر ($pending)'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'إضافة ملفات إلى Drive',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<DriveUploadKind>(
                      initialValue: _kind,
                      decoration: const InputDecoration(labelText: 'المجلد'),
                      items: [
                        for (final kind in DriveUploadKind.values)
                          DropdownMenuItem(
                            value: kind,
                            child: Text(kind.folder),
                          ),
                      ],
                      onChanged: _busy
                          ? null
                          : (value) => setState(() => _kind = value ?? _kind),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: _busy ? null : _pickFiles,
                      icon: const Icon(Icons.attach_file_rounded),
                      label: const Text('اختيار ملفات'),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'تُحفظ الملفات محلياً أولاً، ثم تُرفع عند اتصال حساب المالك بالإنترنت.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'طابور الرفع (${rows.length})',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (failed > 0)
                  TextButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            await _controller.retryFailed();
                          }),
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text('إعادة المحاولة ($failed)'),
                  ),
              ],
            ),
            if (queue.isLoading && rows.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              ),
            if (rows.isEmpty && !queue.isLoading)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Text('لا توجد ملفات في طابور Google Drive.'),
                ),
              ),
            for (final row in rows)
              Card(
                child: ListTile(
                  leading: Icon(_statusIcon(row.status)),
                  title: Text(
                    row.remotePath,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(_statusLabel(row)),
                  trailing: row.status == UploadWorker.statusPending
                      ? const Icon(Icons.schedule_rounded)
                      : row.status == UploadWorker.statusDone
                      ? const Icon(Icons.cloud_done_rounded)
                      : const Icon(Icons.error_outline_rounded),
                ),
              ),
          ],
        ),
      ),
    );
  }

  IconData _statusIcon(String status) => switch (status) {
    UploadWorker.statusDone => Icons.cloud_done_outlined,
    UploadWorker.statusFailed => Icons.cloud_off_outlined,
    _ => Icons.cloud_upload_outlined,
  };

  String _statusLabel(UploadQueueRow row) => switch (row.status) {
    UploadWorker.statusDone => 'رُفع بنجاح',
    UploadWorker.statusFailed => row.lastError ?? 'فشل الرفع',
    _ =>
      row.attempts == 0
          ? 'بانتظار الاتصال'
          : 'إعادة المحاولة ${row.attempts} — ${row.lastError ?? ''}',
  };
}
