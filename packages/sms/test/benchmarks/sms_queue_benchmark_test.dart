import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/testing.dart';
import 'package:school_sms/school_sms.dart';

/// قياس طابور الرسائل بخمسين ألف رسالة (90٪ مرسلة و5٪ منتظرة و5٪ فاشلة):
/// عرض الطابور وعدّادات الحالات وأخذ الرسالة التالية وإضافة رسالة. أسرع
/// ثلاث مرات لكل عملية، وميزانياتها بنحو خمسة أضعاف ما يقيسه حاسوب التطوير.
void main() {
  late AppDatabase db;
  late SmsQueueService queue;
  final timings = <String, int>{};
  // السبت 2025-09-06 الساعة 12:00 (خارج ساعات الهدوء الليلية).
  final now = DateTime(2025, 9, 6, 12);

  setUpAll(() async {
    db = AppDatabase(NativeDatabase.memory());
    await PerfDataGenerator(db).generate();
    var ids = 0;
    final writer = SyncWriter(
      db,
      actor: () => const Actor(userId: 'perf-owner', userName: 'المدير'),
      clock: () => now.toUtc().millisecondsSinceEpoch,
      idGenerator: () => 'sms-bench-${++ids}',
    );
    queue = SmsQueueService(
      db,
      writer,
      settings: SmsSettingsService(db, writer),
      now: () => now,
    );
  });
  tearDownAll(() async {
    final names = timings.keys.toList()..sort();
    // ignore: avoid_print
    print(
      '\nزمن طابور الرسائل (مللي ثانية، أسرع ثلاث مرات):\n'
      '${[for (final n in names) '  $n: ${timings[n]}'].join('\n')}',
    );
    await db.close();
  });

  Future<int> measure(String name, Future<Object?> Function() action) async {
    var best = 1 << 30;
    for (var i = 0; i < 3; i++) {
      final watch = Stopwatch()..start();
      await action();
      watch.stop();
      if (watch.elapsedMilliseconds < best) best = watch.elapsedMilliseconds;
    }
    timings[name] = best;
    return best;
  }

  test('الطابور بخمسين ألف رسالة', () async {
    final counts = await queue.watchStatusCounts().first;
    expect(counts[SmsStatus.sent.code], 45000);
    expect(counts[SmsStatus.pending.code], 2500);
    expect(counts[SmsStatus.failed.code], 2500);
  });

  test('عرض الطابور وعدّاداته وعدد المنتظر', () async {
    final load = await measure('عرض الطابور (200 رسالة)', queue.loadQueue);
    final counts = await measure(
      'عدّادات الحالات (50 ألفاً)',
      () => queue.watchStatusCounts().first,
    );
    final pending = await measure('عدد المنتظر', queue.pendingCount);
    expect(load, lessThan(150));
    expect(counts, lessThan(250));
    expect(pending, lessThan(100));
  });

  test('إضافة رسالة وأخذ التالية من الطابور الكبير', () async {
    final enqueue = await measure(
      'إضافة رسالة',
      () => queue.enqueue(phone: '0550123456', message: 'رسالة قياس'),
    );
    final next = await measure(
      'أخذ الرسالة التالية وإرسالها',
      () => queue.processNext((_) async {}),
    );
    expect(enqueue, lessThan(150));
    expect(next, lessThan(250));
  });
}
