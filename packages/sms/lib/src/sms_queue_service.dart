import 'package:drift/drift.dart';
import 'package:school_core/school_core.dart';

import 'sms_settings.dart';

typedef SmsSender = Future<void> Function(SmsQueueRow message);

/// فشل الإرسال مع بيان إن كان يمكن إعادة المحاولة.
class SmsTransportException implements Exception {
  const SmsTransportException(this.message, {this.retryable = true});

  final String message;
  final bool retryable;

  @override
  String toString() => message;
}

enum SmsProcessKind { empty, busy, deferred, sent, retryScheduled, failed }

class SmsProcessResult {
  const SmsProcessResult(
    this.kind, {
    this.messageId,
    this.scheduledAt,
    this.error,
  });

  final SmsProcessKind kind;
  final String? messageId;
  final DateTime? scheduledAt;
  final String? error;
}

/// ساعات الهدوء المحلية: تؤجَّل الرسائل من 21:00 حتى 07:00.
abstract final class SmsQuietHours {
  static const int startsAtMinute = 21 * 60;
  static const int endsAtMinute = 7 * 60;

  static bool contains(DateTime localTime) {
    final minute = localTime.hour * 60 + localTime.minute;
    return minute >= startsAtMinute || minute < endsAtMinute;
  }

  /// يعيد الوقت نفسه خارج الهدوء، أو أقرب 07:00 مسموحة.
  static DateTime nextAllowedAt(DateTime localTime) {
    final local = localTime.toLocal();
    if (!contains(local)) return local;
    if (local.hour * 60 + local.minute >= startsAtMinute) {
      return DateTime(local.year, local.month, local.day + 1, 7);
    }
    return DateTime(local.year, local.month, local.day, 7);
  }
}

/// طابور محلي متزامن مع سياسة وقت الإرسال والحد الشهري وإعادة المحاولة.
///
/// يرسل عنصراً واحداً في كل استدعاء؛ يوفّر تطبيق Android الناقل الفعلي في
/// المهمة 5.2. كل انتقال حالة يُحفظ عبر [SyncWriter].
class SmsQueueService {
  SmsQueueService(
    this.db,
    this.writer, {
    SmsSettingsService? settings,
    DateTime Function()? now,
  }) : settings = settings ?? SmsSettingsService(db, writer),
       _now = now ?? DateTime.now;

  static const int maxAttempts = 5;
  static const List<Duration> retryDelays = [
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 15),
    Duration(minutes: 60),
  ];
  static const Duration interruptedSendAge = Duration(minutes: 2);
  static const String interruptedSendMessage =
      'انقطع التطبيق قبل تأكيد الإرسال؛ تحقّق من وصول الرسالة قبل إعادة المحاولة.';

  static const Set<String> _sensitiveKinds = {
    SmsTemplateKeys.accountCreated,
    SmsTemplateKeys.passwordReset,
  };

  final AppDatabase db;
  final SyncWriter writer;
  final SmsSettingsService settings;
  final DateTime Function() _now;
  bool _processing = false;

  Future<SmsQueueRow> enqueue({
    required String phone,
    required String message,
    String kind = 'custom',
  }) async {
    if (!PhoneNumbers.isValid(phone)) {
      throw FormatException('رقم هاتف غير صالح', phone);
    }
    final body = message.trim();
    if (body.isEmpty) throw ArgumentError('نص الرسالة لا يمكن أن يكون فارغاً');

    final now = _localNow();
    final allowedAt = SmsQuietHours.nextAllowedAt(now);
    final stamp = writer.now();
    final id = writer.newId();
    await writer.save(
      db.smsQueue,
      SmsQueueCompanion.insert(
        id: id,
        createdAt: stamp,
        updatedAt: stamp,
        phone: PhoneNumbers.toInternational(phone),
        message: body,
        status: Value(SmsStatus.pending.code),
        kind: Value(kind),
        notBefore: Value(allowedAt.isAfter(now) ? _epoch(allowedAt) : null),
        createdBy: Value(writer.actor().userId),
      ),
      key: {'id': id},
    );
    return (db.select(
      db.smsQueue,
    )..where((row) => row.id.equals(id))).getSingle();
  }

  Future<SmsQueueRow> enqueueTemplate({
    required String phone,
    required String templateKey,
    required Map<String, String> values,
  }) async {
    final body = await SmsTemplateRenderer(db).render(templateKey, values);
    if (body.trim().isEmpty) {
      throw ArgumentError.value(
        templateKey,
        'templateKey',
        'القالب غير موجود أو فارغ',
      );
    }
    return enqueue(phone: phone, message: body, kind: templateKey);
  }

  Stream<List<SmsQueueRow>> watchQueue({int limit = 200}) {
    if (limit < 1) {
      throw ArgumentError.value(limit, 'limit', 'يجب أن يكون موجباً');
    }
    return (db.select(db.smsQueue)
          ..orderBy([
            (row) => OrderingTerm.desc(row.createdAt),
            (row) => OrderingTerm.desc(row.id),
          ])
          ..limit(limit))
        .watch();
  }

  /// أعداد الحالات الدقيقة لكل الطابور، دون تحميل الرسائل إلى الذاكرة.
  Stream<Map<String, int>> watchStatusCounts() => db
      .customSelect(
        'SELECT status, COUNT(*) AS count FROM sms_queue GROUP BY status',
        readsFrom: {db.smsQueue},
      )
      .watch()
      .map(
        (rows) => {
          for (final row in rows)
            row.read<String>('status'): row.read<int>('count'),
        },
      );

  Future<List<SmsQueueRow>> loadQueue({int limit = 200}) {
    if (limit < 1) {
      throw ArgumentError.value(limit, 'limit', 'يجب أن يكون موجباً');
    }
    return (db.select(db.smsQueue)
          ..orderBy([
            (row) => OrderingTerm.desc(row.createdAt),
            (row) => OrderingTerm.desc(row.id),
          ])
          ..limit(limit))
        .get();
  }

  Future<int> pendingCount() async {
    final row = await db
        .customSelect(
          'SELECT COUNT(*) AS count FROM sms_queue WHERE status = ?',
          variables: [Variable<String>(SmsStatus.pending.code)],
          readsFrom: {db.smsQueue},
        )
        .getSingle();
    return row.read<int>('count');
  }

  /// يحوّل عمليات الإرسال القديمة إلى فشل يحتاج مراجعة يدوية.
  ///
  /// لا نعيد الإرسال تلقائياً لأن رسالة SMS قد تكون وصلت قبل أن ينقطع
  /// تأكيد Android، وإعادتها قد تكرر بيانات الحساب أو كلمة السر.
  Future<int> recoverInterruptedSends({
    Duration olderThan = interruptedSendAge,
  }) async {
    if (olderThan <= Duration.zero) {
      throw ArgumentError.value(
        olderThan,
        'olderThan',
        'يجب أن تكون المهلة موجبة',
      );
    }
    final cutoff = _epoch(_localNow().subtract(olderThan));
    final interrupted = await (db.select(
      db.smsQueue,
    )..where((row) => row.status.equals(SmsStatus.sending.code))).get();
    var recovered = 0;
    for (final row in interrupted) {
      if (row.updatedAt > cutoff) continue;
      final changed = await writer.patch(
        db.smsQueue,
        key: {'id': row.id},
        values: {
          'status': SmsStatus.failed.code,
          'last_error': interruptedSendMessage,
          'not_before': null,
        },
      );
      if (changed) recovered++;
    }
    return recovered;
  }

  /// يرسل أقدم رسالة جاهزة، أو يحدّث وقتها إن وقعت في الهدوء/تجاوزت الحد.
  Future<SmsProcessResult> processNext(SmsSender send) async {
    if (_processing) return const SmsProcessResult(SmsProcessKind.busy);
    _processing = true;
    try {
      final now = _localNow();
      final nowStamp = _epoch(now);
      final pending =
          await (db.select(db.smsQueue)
                ..where((row) => row.status.equals(SmsStatus.pending.code))
                ..orderBy([
                  (row) => OrderingTerm.asc(row.createdAt),
                  (row) => OrderingTerm.asc(row.id),
                ]))
              .get();
      if (pending.isEmpty) return const SmsProcessResult(SmsProcessKind.empty);

      SmsQueueRow? row;
      for (final candidate in pending) {
        if (candidate.notBefore == null || candidate.notBefore! <= nowStamp) {
          row = candidate;
          break;
        }
      }
      if (row == null) {
        final nextStamp = pending
            .map((candidate) => candidate.notBefore!)
            .reduce((a, b) => a < b ? a : b);
        return SmsProcessResult(
          SmsProcessKind.deferred,
          scheduledAt: _fromEpoch(nextStamp),
        );
      }

      final allowedAt = SmsQuietHours.nextAllowedAt(now);
      if (allowedAt.isAfter(now)) {
        await _defer(row.id, allowedAt);
        return SmsProcessResult(
          SmsProcessKind.deferred,
          messageId: row.id,
          scheduledAt: allowedAt,
        );
      }

      final limit = await settings.monthlyLimit();
      if (limit != null && await _sentThisMonth(now) >= limit) {
        final monthStart = DateTime(now.year, now.month + 1);
        final nextMonthAllowed = SmsQuietHours.nextAllowedAt(monthStart);
        await _defer(row.id, nextMonthAllowed);
        return SmsProcessResult(
          SmsProcessKind.deferred,
          messageId: row.id,
          scheduledAt: nextMonthAllowed,
        );
      }

      final attempt = row.attempts + 1;
      final claimed = await writer.patch(
        db.smsQueue,
        key: {'id': row.id},
        values: {
          'status': SmsStatus.sending.code,
          'attempts': attempt,
          'not_before': null,
          'last_error': null,
        },
      );
      if (!claimed) return const SmsProcessResult(SmsProcessKind.empty);

      try {
        await send(row);
      } catch (error) {
        final retryable = error is! SmsTransportException || error.retryable;
        final message = error.toString();
        if (retryable && attempt < maxAttempts) {
          final retryAt = SmsQuietHours.nextAllowedAt(
            _localNow().add(retryDelays[attempt - 1]),
          );
          await writer.patch(
            db.smsQueue,
            key: {'id': row.id},
            values: {
              'status': SmsStatus.pending.code,
              'last_error': message,
              'not_before': _epoch(retryAt),
            },
          );
          return SmsProcessResult(
            SmsProcessKind.retryScheduled,
            messageId: row.id,
            scheduledAt: retryAt,
            error: message,
          );
        }
        await writer.patch(
          db.smsQueue,
          key: {'id': row.id},
          values: {
            'status': SmsStatus.failed.code,
            'last_error': message,
            'not_before': null,
          },
        );
        return SmsProcessResult(
          SmsProcessKind.failed,
          messageId: row.id,
          error: message,
        );
      }

      await writer.patch(
        db.smsQueue,
        key: {'id': row.id},
        values: {
          'status': SmsStatus.sent.code,
          'sent_at': _epoch(_localNow()),
          'last_error': null,
          'not_before': null,
          if (_sensitiveKinds.contains(row.kind)) 'message': '',
        },
      );
      return SmsProcessResult(SmsProcessKind.sent, messageId: row.id);
    } finally {
      _processing = false;
    }
  }

  /// يعيد رسالة فاشلة إلى الطابور ويبدأ عدّ محاولاتها من جديد.
  Future<bool> retry(String id) async {
    final row = await (db.select(
      db.smsQueue,
    )..where((item) => item.id.equals(id))).getSingleOrNull();
    if (row == null || row.status != SmsStatus.failed.code) return false;
    return writer.patch(
      db.smsQueue,
      key: {'id': id},
      values: {
        'status': SmsStatus.pending.code,
        'attempts': 0,
        'last_error': null,
        'not_before': null,
      },
    );
  }

  Future<void> _defer(String id, DateTime at) async {
    await writer.patch(
      db.smsQueue,
      key: {'id': id},
      values: {'not_before': _epoch(at)},
    );
  }

  Future<int> _sentThisMonth(DateTime localNow) async {
    final start = DateTime(localNow.year, localNow.month);
    final end = DateTime(localNow.year, localNow.month + 1);
    final row = await db
        .customSelect(
          'SELECT COUNT(*) AS count FROM sms_queue '
          'WHERE status = ? AND sent_at >= ? AND sent_at < ?',
          variables: [
            Variable<String>(SmsStatus.sent.code),
            Variable<int>(_epoch(start)),
            Variable<int>(_epoch(end)),
          ],
          readsFrom: {db.smsQueue},
        )
        .getSingle();
    return row.read<int>('count');
  }

  DateTime _localNow() => _now().toLocal();

  static int _epoch(DateTime localTime) =>
      localTime.toUtc().millisecondsSinceEpoch;

  static DateTime _fromEpoch(int stamp) =>
      DateTime.fromMillisecondsSinceEpoch(stamp, isUtc: true).toLocal();
}
