import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

import 'scanner_screen.dart';

/// بطاقة على شاشة المدخل: صاحب الرمز ونتيجة مسحه.
class EntranceCard {
  const EntranceCard({
    required this.owner,
    required this.presentation,
    required this.at,
  });

  final QrEntry owner;
  final ScanPresentation presentation;
  final DateTime at;
}

/// شاشة المدخل (Windows): تُعرض على شاشة موجَّهة للتلاميذ عند الباب، فتظهر
/// بطاقة كبيرة لكل من مسح رمزه (صورته واسمه وحالته بلون واضح). تتلقى الرموز
/// من قارئ USB موصول بالحاسوب، ومن مسح الهاتف في اللحظة التي يصل فيها
/// سجله إلى القاعدة. وتتسع لعدة بطاقات معاً عند ازدحام الطابور، وتزول كل
/// بطاقة بعد [cardLifetime].
class EntranceScreen extends ConsumerStatefulWidget {
  const EntranceScreen({
    this.cardLifetime = const Duration(seconds: 20),
    this.maxCards = 8,
    this.indexRefreshAfter = const Duration(seconds: 10),
    super.key,
  });

  final Duration cardLifetime;
  final int maxCards;
  final Duration indexRefreshAfter;

  @override
  ConsumerState<EntranceScreen> createState() => _EntranceScreenState();
}

class _EntranceScreenState extends ConsumerState<EntranceScreen> {
  /// مسحان لنفس الشخص خلال هذه المدة (محلي ثم وارد من القاعدة) بطاقة واحدة.
  static const Duration _dedupeWindow = Duration(seconds: 10);

  late final ScanService _service = ref.read(scanServiceProvider);
  late final ScanFeedback _feedback = ref.read(scanFeedbackProvider);
  final DateTime _openedAt = DateTime.now();

  QrCodeSource? _reader;
  StreamSubscription<String>? _codes;
  StreamSubscription<List<FeedScan>>? _feed;
  Timer? _expiry;
  Future<void> _queue = Future<void>.value();
  DateTime _indexLoadedAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _disposed = false;

  final List<EntranceCard> _cards = [];
  final Set<String> _seenFeedKeys = {};

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    await _loadIndex();
    if (_disposed) return;
    final reader = ref.read(usbReaderFactoryProvider)();
    _reader = reader;
    _codes = reader.codes.listen(_enqueue);
    await reader.start();
    _feed = ref
        .read(recentScanFeedProvider)
        .watch(since: _openedAt.toUtc().millisecondsSinceEpoch)
        .listen(_onFeed);
    _expiry = Timer.periodic(const Duration(seconds: 1), (_) => _prune());
  }

  Future<void> _loadIndex() async {
    await _service.loadIndex();
    _indexLoadedAt = DateTime.now();
  }

  void _enqueue(String raw) {
    _queue = _queue.then((_) => _handleCode(raw));
  }

  Future<void> _handleCode(String raw) async {
    if (_disposed) return;
    final now = DateTime.now();
    var result = await _service.scan(raw, now: now);
    if (result.outcome == ScanOutcome.unknown &&
        now.difference(_indexLoadedAt) >= widget.indexRefreshAfter) {
      await _loadIndex();
      result = await _service.scan(raw, now: now);
    }
    _show(result, now);
  }

  void _onFeed(List<FeedScan> scans) {
    if (_disposed) return;
    // الأقدم أولاً فتظهر البطاقات بترتيب وصولها.
    for (final scan in scans.reversed) {
      if (!_seenFeedKeys.add(scan.key)) continue;
      _show(scan.result, scan.at);
    }
  }

  void _show(ScanResult result, DateTime at) {
    final owner = result.owner;
    final presentation = ScanPresentation.of(result);
    if (presentation == null || _disposed) return;
    // القراءة المحلية تكتب سجلاً يعود من القاعدة (وقد يسبقها): بطاقة وصوت
    // واحد لأي من الاثنين وصل أولاً.
    final duplicate = _cards.any(
      (c) =>
          owner != null &&
          c.owner.id == owner.id &&
          c.at.difference(at).abs() < _dedupeWindow &&
          c.presentation.headline == presentation.headline,
    );
    if (duplicate) return;
    unawaited(presentation.play(_feedback));
    if (!mounted) return;
    setState(() {
      if (owner != null) _cards.removeWhere((c) => c.owner.id == owner.id);
      _cards.insert(
        0,
        EntranceCard(
          owner:
              owner ??
              const QrEntry(
                kind: QrOwnerKind.student,
                id: '',
                name: 'غير معروف',
              ),
          presentation: presentation,
          at: at,
        ),
      );
      if (_cards.length > widget.maxCards) _cards.removeLast();
    });
  }

  void _prune() {
    if (!mounted || _cards.isEmpty) return;
    final cutoff = DateTime.now().subtract(widget.cardLifetime);
    final before = _cards.length;
    _cards.removeWhere((c) => c.at.isBefore(cutoff));
    if (_cards.length != before) setState(() {});
  }

  @override
  void dispose() {
    _disposed = true;
    _expiry?.cancel();
    unawaited(_codes?.cancel());
    unawaited(_feed?.cancel());
    unawaited(_reader?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    return Scaffold(
      appBar: const ClayAppBar(title: 'شاشة المدخل', showBack: true),
      body: _cards.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(ClaySpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(ClayIcons.scan, size: 96, color: p.accent),
                    const SizedBox(height: ClaySpacing.md),
                    Text(
                      'مرحباً',
                      style: text.displaySmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: ClaySpacing.sm),
                    Text(
                      'مرّر رمزك على القارئ',
                      style: text.titleLarge!.copyWith(color: p.textMuted),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(ClaySpacing.screenPadding),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 360,
                mainAxisExtent: 220,
                crossAxisSpacing: ClaySpacing.md,
                mainAxisSpacing: ClaySpacing.md,
              ),
              itemCount: _cards.length,
              itemBuilder: (context, i) => _CardView(card: _cards[i]),
            ),
    );
  }
}

class _CardView extends StatelessWidget {
  const _CardView({required this.card});

  final EntranceCard card;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final tone = scanToneColor(p, card.presentation.tone);
    return Semantics(
      liveRegion: true,
      label: '${card.owner.name}، ${card.presentation.headline}',
      child: ExcludeSemantics(
        child: Container(
          decoration: BoxDecoration(
            color: tone,
            borderRadius: BorderRadius.circular(ClayRadius.lg),
          ),
          padding: const EdgeInsets.all(ClaySpacing.md),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ClayAvatar(
                name: card.owner.name,
                image: scanPhoto(card.owner),
                size: 96,
              ),
              const SizedBox(height: ClaySpacing.sm),
              Text(
                card.owner.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.titleLarge!.copyWith(color: p.onAccent),
              ),
              Text(
                card.presentation.headline,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.titleMedium!.copyWith(color: p.onAccent),
              ),
              if (card.presentation.detail.isNotEmpty)
                Text(
                  card.presentation.detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: text.bodySmall!.copyWith(color: p.onAccent),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
