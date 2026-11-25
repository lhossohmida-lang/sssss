import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_desktop/google_sign_in_desktop.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:school_core/school_core.dart';

import 'package:school_ui/school_ui.dart';

const String _driveScope = 'https://www.googleapis.com/auth/drive.file';
const List<String> _driveScopes = [_driveScope];

/// بريد المالك الافتراضي من وقت البناء (بناء خاص بمدرسة). الإصدار العام يتركه فارغاً فيضبطه المالك
/// على جهازه، فلا يُضمَّن بريد شخصي في ملف APK علني.
const String _buildOwnerEmail = String.fromEnvironment(
  'GOOGLE_DRIVE_OWNER_EMAIL',
);

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
  bool get canCreateBackup;
  String get configurationMessage;

  /// بريد حساب Google المالك المعتمد لربط Drive على هذا الجهاز (فارغ إن لم يُضبط).
  String get ownerEmail;

  /// يحفظ بريد المالك لهذا الجهاز (لا يُزامَن)؛ يرمي [FormatException] إن لم يكن صالحاً.
  Future<void> setOwnerEmail(String email);
  Stream<DriveAccount?> get accountChanges;
  Stream<List<UploadQueueRow>> get queueChanges;
  Stream<String?> get backupStatusChanges;
  Future<void> initialize();
  Future<void> signIn();
  Future<void> signOut();
  Future<int> addFiles(List<PlatformFile> files, DriveUploadKind kind);
  Future<int> uploadPending();
  Future<int> retryFailed();
  Future<bool> createBackup();
  Future<List<DriveFileInfo>> listBackups();
  Future<void> restoreBackup(DriveFileInfo backup);
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

final StreamProvider<String?> driveBackupStatusProvider =
    StreamProvider<String?>((ref) {
      return ref.watch(driveControllerProvider).backupStatusChanges;
    });

/// يهيّئ النسخ اليومية مرة عند بدء تطبيق الإدارة، حتى إن لم تُفتح شاشة Drive.
class DriveBackupLifecycle extends ConsumerStatefulWidget {
  const DriveBackupLifecycle({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<DriveBackupLifecycle> createState() =>
      _DriveBackupLifecycleState();
}

class _DriveBackupLifecycleState extends ConsumerState<DriveBackupLifecycle> {
  @override
  void initState() {
    super.initState();
    unawaited(
      ref.read(driveControllerProvider).initialize().catchError((Object _) {}),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// ربط Google Sign-In على Android وiPhone وتدفق PKCE ذي loopback على Windows.
/// رموز سطح المكتب تبقى في التخزين الآمن للنظام، ورمز Drive قصير العمر لا
/// يُكتب في قاعدة التطبيق أو في سجل العمليات.
class GoogleDriveController implements DriveController {
  GoogleDriveController(this.runtime)
    : _windowsClientId = const String.fromEnvironment(
        'GOOGLE_DRIVE_WINDOWS_CLIENT_ID',
      ),
      _windowsClientSecret = const String.fromEnvironment(
        'GOOGLE_DRIVE_WINDOWS_CLIENT_SECRET',
      ),
      _serverClientId = const String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID'),
      _iosClientId = const String.fromEnvironment(
        'GOOGLE_DRIVE_IOS_CLIENT_ID',
      ) {
    _preferences = DevicePreferences(runtime.db);
    final staging = Directory(
      '${runtime.photosDirectory.parent.path}${platformPathSeparator}drive_uploads',
    );
    _queue = DriveQueueService(
      runtime.db,
      runtime.writer,
      stagingDirectory: staging,
    );
    _store = GoogleDriveFileStore(accessToken: _accessToken);
    _worker = UploadWorker(runtime.db, runtime.writer, _store);
    final databaseFile = runtime.databaseFile;
    _backup = databaseFile == null
        ? null
        : DatabaseBackupService(
            databaseFile: databaseFile,
            schemaVersion: runtime.db.schemaVersion,
          );
  }

  final AppRuntime runtime;

  /// بريد المالك المعتمد: ما ضبطه المالك على هذا الجهاز، وإلا الافتراضي من وقت البناء.
  String _ownerEmail = _buildOwnerEmail;
  late final DevicePreferences _preferences;
  final String _windowsClientId;
  final String _windowsClientSecret;

  /// معرّف عميل Web في Google Cloud: يلزم تسجيل الدخول على Android (Credential
  /// Manager) إن لم يضمّنه ملف google-services.json.
  final String _serverClientId;

  /// معرّف عميل iOS في Google Cloud (نوع iOS، معرّف الحزمة dz.school.admin): يلزم Drive على iPhone، ويضيف
  /// مسار ios في CI مخطّطه المعكوس إلى Info.plist.
  final String _iosClientId;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final StreamController<DriveAccount?> _accountController =
      StreamController<DriveAccount?>.broadcast();
  late final DriveQueueService _queue;
  late final GoogleDriveFileStore _store;
  late final UploadWorker _worker;
  final StreamController<String?> _backupStatusController =
      StreamController<String?>.broadcast();
  late final DatabaseBackupService? _backup;
  StreamSubscription<GoogleSignInAuthenticationEvent>? _authSubscription;
  Timer? _uploadTimer;
  Timer? _dailyBackupTimer;
  GoogleSignInAccount? _googleAccount;
  DriveAccount? _account;
  Future<void>? _initializing;
  Future<int>? _uploading;
  Future<void>? _googleInit;
  bool _initialized = false;
  bool _googleReady = false;
  bool _closed = false;
  bool _creatingBackup = false;
  String? _backupStatus;

  @override
  bool get isConfigured =>
      _ownerEmail.trim().isNotEmpty &&
      (_isAndroid ||
          (_isIOS && _iosClientId.trim().isNotEmpty) ||
          (_isWindows &&
              _windowsClientId.trim().isNotEmpty &&
              _windowsClientSecret.trim().isNotEmpty));

  @override
  bool get canCreateBackup => _backup != null;

  @override
  String get configurationMessage {
    if (_ownerEmail.trim().isEmpty) {
      return 'أدخل بريد حساب Google المالك (زر «ضبط البريد») لتفعيل الربط.';
    }
    if (_isWindows &&
        (_windowsClientId.trim().isEmpty ||
            _windowsClientSecret.trim().isEmpty)) {
      return 'بيانات OAuth لنسخة Windows لم تُضبط بعد.';
    }
    if (_isIOS && _iosClientId.trim().isEmpty) {
      return 'معرّف عميل iOS لـGoogle (GOOGLE_DRIVE_IOS_CLIENT_ID) لم يُضبط في هذا البناء.';
    }
    if (!_isWindows && !_isAndroid && !_isIOS) {
      return 'Google Drive متاح في تطبيق الإدارة المثبّت على Android وiPhone '
          'وWindows، لا في نسخة المتصفح.';
    }
    return 'أضف إعداد OAuth الخاص بتطبيق Android إلى بناء الإدارة.';
  }

  @override
  String get ownerEmail => _ownerEmail;

  @override
  Future<void> setOwnerEmail(String email) async {
    final saved = await _preferences.saveDriveOwnerEmail(email);
    _ownerEmail = saved ?? _buildOwnerEmail;
    // أهلية الحساب المتصل تتبع البريد الجديد، ثم يُهيَّأ الربط إن صار ممكناً.
    if (_googleAccount != null) _setAccount(_googleAccount);
    await _ensureGoogle();
  }

  @override
  Stream<DriveAccount?> get accountChanges async* {
    yield _account;
    yield* _accountController.stream;
  }

  @override
  Stream<List<UploadQueueRow>> get queueChanges => _queue.watchQueue();

  @override
  Stream<String?> get backupStatusChanges async* {
    yield _backupStatus;
    yield* _backupStatusController.stream;
  }

  @override
  Future<void> initialize() {
    return _initializing ??= _initialize();
  }

  Future<void> _initialize() async {
    if (_initialized) return;
    _ownerEmail = await _preferences.driveOwnerEmail() ?? _buildOwnerEmail;
    await _maybeCreateDailyBackup();
    _dailyBackupTimer ??= Timer.periodic(
      const Duration(hours: 1),
      (_) => unawaited(_maybeCreateDailyBackup()),
    );
    _initialized = true;
    await _ensureGoogle();
  }

  /// يهيّئ Google Sign-In مرة واحدة حين يصير الربط ممكناً (بعد ضبط بريد المالك على الأقل).
  Future<void> _ensureGoogle() async {
    if (_googleReady || !isConfigured) return;
    try {
      await (_googleInit ??= _initializeGoogle());
    } on Object {
      _googleInit = null;
      rethrow;
    }
  }

  Future<void> _initializeGoogle() async {
    final google = GoogleSignIn.instance;
    if (_isWindows) {
      final platform = GoogleSignInPlatform.instance;
      if (platform is! GoogleSignInDesktop) {
        throw StateError('مكوّن Google Sign-In لنسخة Windows غير مسجّل.');
      }
      platform
        ..clientSecret = _windowsClientSecret
        ..tokenDataStore = _SecureDriveTokenStore(
          _secureStorage,
          runtime.config.schoolKey,
        );
    }
    await google.initialize(
      clientId: _isWindows
          ? _windowsClientId
          : _isIOS
          ? _iosClientId
          : null,
      serverClientId: _isAndroid && _serverClientId.isNotEmpty
          ? _serverClientId
          : null,
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
    _googleReady = true;
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
    await _ensureGoogle();
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
    if (_googleReady) await GoogleSignIn.instance.signOut();
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
    final upload = _uploadAndRetain().whenComplete(() => _uploading = null);
    _uploading = upload;
    return upload;
  }

  @override
  Future<int> retryFailed() async {
    final count = await _queue.retryFailed();
    if (_account?.isOwner == true) await uploadPending();
    return count;
  }

  @override
  Future<bool> createBackup() async {
    if (_backup == null) {
      throw StateError('لا يتوفر ملف قاعدة بيانات محلي لإنشاء نسخة.');
    }
    final created = await _enqueueDailyBackup();
    _setBackupStatus(
      created
          ? 'أُضيفت نسخة اليوم إلى طابور Drive.'
          : 'نسخة اليوم موجودة مسبقاً.',
    );
    if (_account?.isOwner == true) unawaited(uploadPending());
    return created;
  }

  @override
  Future<List<DriveFileInfo>> listBackups() async {
    _requireOwner();
    final files = await _store.listDirectory(DriveUploadKind.backup.folder);
    return files.where(_isDatedBackup).toList()
      ..sort((a, b) => b.name.compareTo(a.name));
  }

  @override
  Future<void> restoreBackup(DriveFileInfo backup) async {
    _requireOwner();
    final service = _backup;
    if (service == null) {
      throw StateError('لا يتوفر ملف قاعدة بيانات محلي للاستعادة إليه.');
    }
    if (!_isDatedBackup(backup)) {
      throw StateError('ملف النسخة الاحتياطية غير معتمد.');
    }
    final available = await listBackups();
    if (!available.any((file) => file.id == backup.id)) {
      throw StateError('النسخة لم تعد موجودة في مجلد النسخ الاحتياطية.');
    }
    final temporary = File(
      '${_queue.stagingDirectory.path}$platformPathSeparator'
      'restore-${runtime.writer.newId()}.sqlite',
    );
    try {
      await _store.downloadFileTo(fileId: backup.id, destination: temporary);
      await service.restoreFrom(temporary);
      _setBackupStatus('تمت الاستعادة؛ أغلق التطبيق وأعد فتحه للمتابعة.');
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<bool> _enqueueDailyBackup() async {
    final backup = _backup;
    if (backup == null || _creatingBackup) return false;
    _creatingBackup = true;
    File? temporary;
    try {
      final now = DateTime.now();
      final date =
          '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';
      final fileName = 'school_admin_$date.sqlite';
      final remotePath = '${DriveUploadKind.backup.folder}/$fileName';
      if (await _queue.hasQueuedRemotePath(remotePath)) return false;

      temporary = File(
        '${_queue.stagingDirectory.path}$platformPathSeparator'
        'snapshot-${runtime.writer.newId()}.sqlite',
      );
      await backup.createSnapshot(temporary);
      return await _queue.enqueueFile(
        sourcePath: temporary.path,
        fileName: fileName,
        kind: DriveUploadKind.backup,
      );
    } finally {
      _creatingBackup = false;
      if (temporary != null && await temporary.exists()) {
        await temporary.delete();
      }
    }
  }

  Future<void> _maybeCreateDailyBackup() async {
    if (_backup == null || _closed) return;
    try {
      final created = await _enqueueDailyBackup();
      if (created) {
        _setBackupStatus('أُنشئت نسخة اليوم وتنتظر الرفع إلى Drive.');
      }
    } on Object catch (error) {
      _setBackupStatus('تعذّر إنشاء النسخة اليومية: $error');
    }
  }

  Future<int> _uploadAndRetain() async {
    final uploaded = await _worker.processPending(
      buckets: const {DriveQueueService.bucket},
    );
    if (_account?.isOwner == true) {
      try {
        await _queue.cleanupUploadedBackupFiles();
        if (uploaded > 0) await _pruneBackups();
      } on Object catch (error) {
        _setBackupStatus('رُفعت الملفات، وتعذّر تطبيق الاحتفاظ: $error');
      }
    }
    return uploaded;
  }

  Future<void> _pruneBackups() async {
    final backups = (await _store.listDirectory(
      DriveUploadKind.backup.folder,
    )).where(_isDatedBackup).toList()..sort((a, b) => b.name.compareTo(a.name));
    for (final old in backups.skip(30)) {
      await _store.deleteFile(old.id);
      await _queue.discardUploadedBackup(
        '${DriveUploadKind.backup.folder}/${old.name}',
      );
    }
  }

  bool _isDatedBackup(DriveFileInfo file) {
    final match = RegExp(r'^school_admin_(\d{4}-\d{2}-\d{2})\.sqlite$')
        .firstMatch(file.name);
    return match != null && DateTime.tryParse(match.group(1)!) != null;
  }

  void _requireOwner() {
    if (_account?.isOwner != true) {
      throw StateError('سجّل الدخول إلى حساب Google المالك أولاً.');
    }
  }

  void _setBackupStatus(String? value) {
    _backupStatus = value;
    if (!_backupStatusController.isClosed) _backupStatusController.add(value);
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
    _dailyBackupTimer?.cancel();
    await _authSubscription?.cancel();
    await _uploading;
    _store.dispose();
    await _accountController.close();
    await _backupStatusController.close();
  }
}

class _SecureDriveTokenStore
    implements GoogleSignInDesktopStore<GoogleSignInDesktopTokenData> {
  _SecureDriveTokenStore(this.storage, String school)
    : _key = school.isEmpty ? _baseKey : '${_baseKey}_$school';

  final FlutterSecureStorage storage;
  static const String _baseKey = 'google_drive_desktop_tokens';

  /// رموز كل مدرسة بمفتاح خاص بها، فلا يستعمل جهازٌ بُدّل ربطُه رموزَ مدرسة سابقة.
  final String _key;

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
  List<DriveFileInfo> _backups = const [];
  bool _loadedBackups = false;
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

  String _userMessage(Object error) => switch (error) {
    StateError() => error.message.toString(),
    FormatException() => error.message,
    _ => 'تعذّرت العملية: $error',
  };

  Future<void> _editOwnerEmail() async {
    final entered = await showDialog<String>(
      context: context,
      builder: (context) => _OwnerEmailDialog(initial: _controller.ownerEmail),
    );
    if (entered == null || !mounted) return;
    await _run(() => _controller.setOwnerEmail(entered));
  }

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

  Future<void> _createBackup() async {
    await _run(() async {
      final created = await _controller.createBackup();
      if (mounted) {
        setState(() {
          _message = created
              ? 'أُنشئت نسخة اليوم وأُضيفت إلى طابور الرفع.'
              : 'نسخة اليوم موجودة في الطابور مسبقاً.';
        });
      }
    });
  }

  Future<void> _loadBackups() async {
    await _run(() async {
      final backups = await _controller.listBackups();
      if (mounted) {
        setState(() {
          _backups = backups;
          _loadedBackups = true;
          _message = 'عدد النسخ المتاحة: ${backups.length}';
        });
      }
    });
  }

  Future<void> _restoreBackup(DriveFileInfo backup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('استعادة نسخة احتياطية'),
        content: Text(
          'سيُستبدل محتوى هذا الجهاز بنسخة ${backup.name} '
          '(${_formatBytes(backup.size)}). يلزم إغلاق التطبيق وإعادة فتحه بعد ذلك.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('استعادة'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(() async {
      await _controller.restoreBackup(backup);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('اكتملت الاستعادة'),
          content: const Text('أغلق التطبيق وأعد فتحه قبل استخدام البيانات.'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق التطبيق'),
            ),
          ],
        ),
      );
      if (_isAndroid) {
        await SystemNavigator.pop();
      } else if (_isWindows || _isIOS) {
        exit(0);
      }
    });
  }

  String _formatBytes(int? bytes) {
    if (bytes == null || bytes <= 0) return 'حجم غير معروف';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} كيلوبايت';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} ميغابايت';
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(driveAccountProvider);
    final queue = ref.watch(driveQueueProvider);
    final backupStatus = ref.watch(driveBackupStatusProvider);
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
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _controller.ownerEmail.isEmpty
                                ? 'بريد المالك غير مضبوط'
                                : 'بريد المالك المعتمد: ${_controller.ownerEmail}',
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _busy ? null : _editOwnerEmail,
                          icon: const Icon(Icons.edit_rounded),
                          label: Text(
                            _controller.ownerEmail.isEmpty
                                ? 'ضبط البريد'
                                : 'تغيير البريد',
                          ),
                        ),
                      ],
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
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'النسخ الاحتياطية',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'تُنشأ نسخة SQLite يومياً، ويحتفظ Drive بآخر 30 نسخة.',
                    ),
                    if (backupStatus.value != null) ...[
                      const SizedBox(height: 6),
                      Text(backupStatus.value!),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _busy || !_controller.canCreateBackup
                              ? null
                              : _createBackup,
                          icon: const Icon(Icons.backup_rounded),
                          label: const Text('إنشاء نسخة اليوم'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _busy || current?.isOwner != true
                              ? null
                              : _loadBackups,
                          icon: const Icon(Icons.restore_rounded),
                          label: const Text('عرض النسخ للاستعادة'),
                        ),
                      ],
                    ),
                    if (_loadedBackups && _backups.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text('لا توجد نسخ احتياطية في Drive.'),
                      ),
                    for (final backup in _backups)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.storage_rounded),
                        title: Text(backup.name),
                        subtitle: Text(_formatBytes(backup.size)),
                        trailing: TextButton(
                          onPressed: _busy
                              ? null
                              : () => _restoreBackup(backup),
                          child: const Text('استعادة'),
                        ),
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

/// نافذة ضبط بريد حساب Google المالك (يُتحقق منه هنا قبل الحفظ).
class _OwnerEmailDialog extends StatefulWidget {
  const _OwnerEmailDialog({required this.initial});

  final String initial;

  @override
  State<_OwnerEmailDialog> createState() => _OwnerEmailDialogState();
}

class _OwnerEmailDialogState extends State<_OwnerEmailDialog> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initial,
  );
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _save() {
    try {
      Navigator.pop(context, GoogleAccountEmail.normalize(_text.text) ?? '');
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('بريد حساب Google المالك'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'الحساب الذي تُحفظ فيه نسخ المدرسة الاحتياطية. يبقى على هذا الجهاز '
          'ولا يراه المعلمون ولا الأولياء.',
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _text,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(
            labelText: 'البريد الإلكتروني',
            errorText: _error,
          ),
          onSubmitted: (_) => _save(),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('إلغاء'),
      ),
      FilledButton(onPressed: _save, child: const Text('حفظ')),
    ],
  );
}

/// المنصة دون `Platform` في المتصفح (نسخة الويب: لا Drive فيها).
bool get _isAndroid => !kIsWeb && Platform.isAndroid;
bool get _isIOS => !kIsWeb && Platform.isIOS;
bool get _isWindows => !kIsWeb && Platform.isWindows;
