import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

/// سجل مسح في قائمة الجلسة.
class ScanEntry {
  const ScanEntry({
    required this.time,
    required this.name,
    required this.presentation,
  });

  final DateTime time;
  final String name;
  final ScanPresentation presentation;
}

/// صورة صاحب الرمز من ملفه المحلي إن وُجد.
ImageProvider? scanPhoto(QrEntry? owner) {
  final path = owner?.photoLocalPath;
  if (path == null || path.isEmpty) return null;
  return FileImage(File(path));
}

/// لون خلفية الحالة (الأخضر والبرتقالي والأحمر) مع نص يبقى مقروءاً.
Color scanToneColor(ClayPalette p, ClayTone tone) => switch (tone) {
  ClayTone.success => p.status.success,
  ClayTone.warning => p.status.warning,
  ClayTone.danger => p.status.danger,
  ClayTone.info => p.status.info,
  ClayTone.excused => p.status.excused,
  ClayTone.neutral => p.accent,
};

/// ماسح المدخل على الهاتف: الكاميرا تبقى شغّالة، وكل رمز يُعالج فوراً
/// ويُعرض أخضر (حاضر) أو برتقالياً (عليه مستحقات) أو أحمر (لا حصة له) مع
/// صوت واهتزاز، ويسجَّل في قائمة أسفل الشاشة.
class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({
    this.indexRefreshAfter = const Duration(seconds: 10),
    super.key,
  });

  /// أقل مدة بين تحديثين لفهرس الرموز عند ظهور رمز مجهول.
  final Duration indexRefreshAfter;

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen> {
  static const int _historyLimit = 30;

  late final ScanService _service = ref.read(scanServiceProvider);
  late final ScanFeedback _feedback = ref.read(scanFeedbackProvider);
  QrCodeSource? _source;
  StreamSubscription<String>? _subscription;
  Future<void> _queue = Future<void>.value();
  DateTime _indexLoadedAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _ready = false;
  bool _disposed = false;

  ScanEntry? _last;
  QrEntry? _lastOwner;
  final List<ScanEntry> _history = [];

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    await _loadIndex();
    final factory = ref.read(qrCameraFactoryProvider);
    if (_disposed || factory == null) {
      if (mounted) setState(() => _ready = true);
      return;
    }
    final source = factory();
    _source = source;
    _subscription = source.codes.listen(_enqueue);
    await source.start();
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _loadIndex() async {
    await _service.loadIndex();
    _indexLoadedAt = DateTime.now();
  }

  /// الرموز تُعالج بالتتابع فلا يتداخل مسحان.
  void _enqueue(String raw) {
    _queue = _queue.then((_) => _handle(raw));
  }

  Future<void> _handle(String raw) async {
    if (_disposed) return;
    final now = DateTime.now();
    var result = await _service.scan(raw, now: now);
    // رمز مجهول قد يكون لتلميذ سُجّل بعد فتح الشاشة: يُحدَّث الفهرس مرة
    // (بحد أدنى بين تحديثين) ثم يُعاد المسح.
    if (result.outcome == ScanOutcome.unknown &&
        now.difference(_indexLoadedAt) >= widget.indexRefreshAfter) {
      await _loadIndex();
      result = await _service.scan(raw, now: now);
    }
    final presentation = ScanPresentation.of(result);
    if (presentation == null || _disposed) return;
    unawaited(presentation.play(_feedback));
    final entry = ScanEntry(
      time: now,
      name: result.owner?.name ?? 'غير معروف',
      presentation: presentation,
    );
    if (!mounted) return;
    setState(() {
      _last = entry;
      _lastOwner = result.owner;
      _history.insert(0, entry);
      if (_history.length > _historyLimit) _history.removeLast();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription?.cancel());
    unawaited(_source?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final source = _source;
    return Scaffold(
      appBar: const ClayAppBar(title: 'الماسح', showBack: true),
      body: !_ready
          ? const ClayLoadingView()
          : Column(
              children: [
                Expanded(
                  flex: 5,
                  child: source == null
                      ? const ClayEmptyView(
                          title: 'الكاميرا غير متاحة على هذا الجهاز',
                          message:
                              'استعمل ماسح الهاتف أو شاشة المدخل في '
                              'الحاسوب',
                          icon: ClayIcons.scan,
                        )
                      : ClipRect(child: source.buildPreview(context)),
                ),
                _ResultPanel(entry: _last, owner: _lastOwner),
                Expanded(
                  flex: 4,
                  child: _history.isEmpty
                      ? const ClayEmptyView(
                          title: 'وجّه الكاميرا نحو الرمز',
                          icon: ClayIcons.scan,
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(
                            horizontal: ClaySpacing.screenPadding,
                          ),
                          itemCount: _history.length,
                          itemExtent: 64,
                          itemBuilder: (context, i) =>
                              _HistoryTile(entry: _history[i]),
                        ),
                ),
              ],
            ),
    );
  }
}

/// لوحة آخر نتيجة بلون الحالة.
class _ResultPanel extends StatelessWidget {
  const _ResultPanel({required this.entry, required this.owner});

  final ScanEntry? entry;
  final QrEntry? owner;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final e = entry;
    if (e == null) return const SizedBox(height: ClaySpacing.sm);
    final color = scanToneColor(p, e.presentation.tone);
    return Semantics(
      liveRegion: true,
      label: '${e.name}، ${e.presentation.headline}',
      child: ExcludeSemantics(
        child: Container(
          width: double.infinity,
          color: color,
          padding: const EdgeInsets.all(ClaySpacing.md),
          child: Row(
            children: [
              ClayAvatar(name: e.name, image: scanPhoto(owner), size: 56),
              const SizedBox(width: ClaySpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium!.copyWith(color: p.onAccent),
                    ),
                    Text(
                      e.presentation.headline,
                      style: text.titleSmall!.copyWith(color: p.onAccent),
                    ),
                    if (e.presentation.detail.isNotEmpty)
                      Text(
                        e.presentation.detail,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall!.copyWith(color: p.onAccent),
                      ),
                  ],
                ),
              ),
              Icon(e.presentation.icon, color: p.onAccent, size: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.entry});

  final ScanEntry entry;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final hh = entry.time.hour.toString().padLeft(2, '0');
    final mm = entry.time.minute.toString().padLeft(2, '0');
    return ClayListTile(
      title: entry.name,
      subtitle: entry.presentation.headline,
      leading: Icon(
        entry.presentation.icon,
        color: scanToneColor(p, entry.presentation.tone),
      ),
      trailing: [
        Directionality(
          textDirection: TextDirection.ltr,
          child: Text('$hh:$mm', style: text.labelMedium),
        ),
      ],
    );
  }
}
