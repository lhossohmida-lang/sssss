import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../clay/clay_button.dart';
import '../clay/clay_container.dart';
import '../theme/clay_theme.dart';
import '../theme/clay_tokens.dart';
import 'pwa_bridge.dart';

/// بطاقة «ثبّت التطبيق على الشاشة الرئيسية» فوق كل الشاشات في نسخة الويب ما دامت لم تُفتح من أيقونتها:
/// على Android والحاسوب يثبّتها الزر مباشرة، وعلى iPhone (Safari لا يسمح لأي موقع بالتثبيت) تنفتح الخطوات
/// مرسومة داخل البطاقة. «لاحقاً» يخفيها حتى الفتح التالي. لا شيء خارج المتصفح.
///
/// البطاقة طبقة فوق الملّاح (`ClayApp.overlay`) لا داخله: فلا نوافذ ولا تلميحات منها، وكل ما تعرضه داخلها.
class PwaInstallOverlay extends StatefulWidget {
  const PwaInstallOverlay({
    this.bridge = const PwaBridge(),
    this.web = kIsWeb,
    super.key,
  });

  final PwaBridge bridge;

  /// للاختبار؛ الافتراضي: هل يعمل التطبيق في متصفح.
  final bool web;

  @override
  State<PwaInstallOverlay> createState() => _PwaInstallOverlayState();
}

class _PwaInstallOverlayState extends State<PwaInstallOverlay> {
  bool _hidden = false;
  bool _steps = false;
  StreamSubscription<void>? _changes;

  @override
  void initState() {
    super.initState();
    _changes = widget.bridge.changes.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  Future<void> _install() async {
    final bridge = widget.bridge;
    if (bridge.canPrompt) {
      final accepted = await bridge.prompt();
      if (accepted && mounted) setState(() => _hidden = true);
      return;
    }
    setState(() => _steps = true);
  }

  @override
  Widget build(BuildContext context) {
    final bridge = widget.bridge;
    if (!widget.web || _hidden || bridge.isStandalone) {
      return const SizedBox.shrink();
    }
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Material(
            type: MaterialType.transparency,
            child: Padding(
              padding: const EdgeInsets.all(ClaySpacing.screenPadding),
              child: ClayCard(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.install_mobile_rounded, color: p.accent),
                        const SizedBox(width: ClaySpacing.sm),
                        Expanded(
                          child: Text(
                            'ثبّت التطبيق على الشاشة الرئيسية: يُفتح بأيقونته '
                            'ويعمل دون إنترنت',
                            style: text.bodyMedium,
                          ),
                        ),
                        const SizedBox(width: ClaySpacing.sm),
                        if (!_steps)
                          // ارتفاع محدد: الزر يملأ ما يُتاح له طولاً (محاذاة وسطية).
                          SizedBox(
                            height: 44,
                            child: ClayButton(
                              label: 'تثبيت',
                              onPressed: _install,
                            ),
                          ),
                        Semantics(
                          button: true,
                          label: 'لاحقاً',
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => setState(() => _hidden = true),
                            child: SizedBox.square(
                              dimension: 44,
                              child: Icon(
                                Icons.close_rounded,
                                color: p.textMuted,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_steps) ...[
                      const SizedBox(height: ClaySpacing.md),
                      PwaInstallSteps(ios: bridge.isIos),
                      const SizedBox(height: ClaySpacing.sm),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: SizedBox(
                          height: 44,
                          child: ClayButton(
                            label: 'فهمت',
                            kind: ClayButtonKind.secondary,
                            onPressed: () => setState(() => _steps = false),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// خطوات الإضافة إلى الشاشة الرئيسية حين لا يتيح المتصفح التثبيت بضغطة (iPhone وiPad، أو متصفح آخر).
class PwaInstallSteps extends StatelessWidget {
  const PwaInstallSteps({required this.ios, super.key});

  final bool ios;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    Widget step(int n, IconData icon, String label) => Padding(
      padding: const EdgeInsets.only(bottom: ClaySpacing.sm),
      child: Row(
        children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: p.accent,
            child: Text(
              '$n',
              style: text.labelLarge!.copyWith(color: p.onAccent),
            ),
          ),
          const SizedBox(width: ClaySpacing.sm),
          Icon(icon, color: p.accent),
          const SizedBox(width: ClaySpacing.sm),
          Expanded(child: Text(label, style: text.bodyMedium)),
        ],
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: ios
          ? [
              step(
                1,
                Icons.ios_share_rounded,
                'اضغط زر المشاركة أسفل Safari (المربع والسهم للأعلى)',
              ),
              step(
                2,
                Icons.add_box_outlined,
                'اختر «إضافة إلى الشاشة الرئيسية» (مرّر القائمة للأسفل إن لم يظهر)',
              ),
              step(3, Icons.check_circle_outline_rounded, 'اضغط «إضافة»'),
              Text(
                'تظهر أيقونة التطبيق على الشاشة الرئيسية؛ افتحه منها دائماً.',
                style: text.bodySmall!.copyWith(color: p.textMuted),
              ),
            ]
          : [
              step(
                1,
                Icons.more_vert_rounded,
                'افتح قائمة المتصفح (النقاط الثلاث)',
              ),
              step(
                2,
                Icons.install_mobile_rounded,
                'اختر «تثبيت التطبيق» أو «إضافة إلى الشاشة الرئيسية»',
              ),
            ],
    );
  }
}
