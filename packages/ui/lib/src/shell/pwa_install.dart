import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../clay/clay_button.dart';
import '../clay/clay_container.dart';
import '../theme/clay_theme.dart';
import '../theme/clay_tokens.dart';
import 'pwa_bridge.dart';

/// بطاقة «ثبّت التطبيق على الشاشة الرئيسية» تحت كل الشاشات في نسخة الويب ما دامت لم تُفتح من أيقونتها:
/// على Android والحاسوب يثبّتها الزر مباشرة، وعلى iPhone (Safari لا يسمح لأي موقع بالتثبيت) تنفتح الخطوات
/// مرسومة داخل البطاقة. «لاحقاً» يخفيها حتى الفتح التالي. لا شيء خارج المتصفح.
///
/// البطاقة شريط تحت الملّاح (`ClayApp.footer`) لا داخله: فلا نوافذ ولا تلميحات منها، وكل ما تعرضه داخلها.
/// نصوصها وخطواتها بلغة المتصفح (العربية أو الفرنسية أو الإنجليزية)، فيقرأ المستخدم أسماء أزرار Safari كما
/// تظهر على هاتفه.
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
    final words = PwaInstallTexts.of(bridge.language);
    // شريط تحت الصفحة بلون خلفيتها (لا فوقها)، فلا يغطي زر «دخول» ولا غيره.
    return ColoredBox(
      color: p.background,
      child: Align(
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
                  child: Directionality(
                    textDirection: words.direction,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.install_mobile_rounded, color: p.accent),
                            const SizedBox(width: ClaySpacing.sm),
                            Expanded(
                              child: Text(words.title, style: text.bodyMedium),
                            ),
                            const SizedBox(width: ClaySpacing.sm),
                            if (!_steps)
                              ClayButton(
                                label: words.install,
                                onPressed: _install,
                              ),
                            Semantics(
                              button: true,
                              label: words.later,
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
                          PwaInstallSteps(ios: bridge.isIos, texts: words),
                          const SizedBox(height: ClaySpacing.sm),
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: ClayButton(
                              label: words.gotIt,
                              kind: ClayButtonKind.secondary,
                              onPressed: () => setState(() => _steps = false),
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
        ),
      ),
    );
  }
}

/// نصوص بطاقة التثبيت وخطواتها بلغة المتصفح. على iPhone لغة Safari هي لغة الجهاز، فتُذكر أسماء أزراره
/// («مشاركة» و«إضافة إلى الشاشة الرئيسية» و«إضافة») كما تظهر للمستخدم. العربية لكل لغة غير الفرنسية
/// والإنجليزية.
class PwaInstallTexts {
  const PwaInstallTexts._({
    required this.code,
    required this.direction,
    required this.title,
    required this.install,
    required this.later,
    required this.gotIt,
    required this.iosSteps,
    required this.iosNote,
    required this.otherSteps,
  });

  /// النصوص الموافقة للغة مثل `fr-FR` أو `en-US` أو `ar-DZ`.
  factory PwaInstallTexts.of(String language) {
    final code = language.toLowerCase().split(RegExp('[-_]')).first;
    return switch (code) {
      'fr' => french,
      'en' => english,
      _ => arabic,
    };
  }

  final String code;
  final TextDirection direction;
  final String title;
  final String install;
  final String later;
  final String gotIt;

  /// على iPhone وiPad: «مشاركة» ثم «إضافة إلى الشاشة الرئيسية» ثم «إضافة».
  final List<String> iosSteps;
  final String iosNote;

  /// متصفح آخر لا يتيح التثبيت بضغطة: من قائمته.
  final List<String> otherSteps;

  static const arabic = PwaInstallTexts._(
    code: 'ar',
    direction: TextDirection.rtl,
    title: 'ثبّت التطبيق على الشاشة الرئيسية: يُفتح بأيقونته ويعمل دون إنترنت',
    install: 'تثبيت',
    later: 'لاحقاً',
    gotIt: 'فهمت',
    iosSteps: [
      'اضغط زر «مشاركة» أسفل Safari (مربع فيه سهم للأعلى). إن لم تره فاضغط '
          '«⋯» أولاً',
      'اختر «إضافة إلى الشاشة الرئيسية» (مرّر القائمة للأسفل إن لم يظهر)',
      'اضغط «إضافة» أعلى الشاشة',
    ],
    iosNote: 'تظهر أيقونة التطبيق على الشاشة الرئيسية؛ افتحه منها دائماً.',
    otherSteps: [
      'افتح قائمة المتصفح (النقاط الثلاث)',
      'اختر «تثبيت التطبيق» أو «إضافة إلى الشاشة الرئيسية»',
    ],
  );

  static const french = PwaInstallTexts._(
    code: 'fr',
    direction: TextDirection.ltr,
    title:
        "Installez l'application sur l'écran d'accueil : elle s'ouvre depuis "
        'son icône et fonctionne sans Internet',
    install: 'Installer',
    later: 'Plus tard',
    gotIt: 'Compris',
    iosSteps: [
      'Touchez le bouton « Partager » en bas de Safari (un carré avec une '
          "flèche vers le haut). Si vous ne le voyez pas, touchez d'abord « ⋯ »",
      "Choisissez « Sur l'écran d'accueil » (faites défiler la liste si "
          'besoin)',
      "Touchez « Ajouter » en haut de l'écran",
    ],
    iosNote:
        "L'icône de l'application apparaît sur l'écran d'accueil ; "
        'ouvrez-la toujours depuis cette icône.',
    otherSteps: [
      'Ouvrez le menu du navigateur (les trois points)',
      "Choisissez « Installer l'application » ou « Ajouter à l'écran "
          "d'accueil »",
    ],
  );

  static const english = PwaInstallTexts._(
    code: 'en',
    direction: TextDirection.ltr,
    title:
        'Install the app on your Home Screen: it opens from its icon and '
        'works offline',
    install: 'Install',
    later: 'Later',
    gotIt: 'Got it',
    iosSteps: [
      'Tap the Share button at the bottom of Safari (a square with an up '
          'arrow). If you don’t see it, tap “⋯” first',
      'Choose “Add to Home Screen” (scroll down the list if needed)',
      'Tap “Add” at the top of the screen',
    ],
    iosNote:
        'The app icon appears on your Home Screen; always open it from there.',
    otherSteps: [
      'Open the browser menu (the three dots)',
      'Choose “Install app” or “Add to Home screen”',
    ],
  );
}

/// خطوات الإضافة إلى الشاشة الرئيسية حين لا يتيح المتصفح التثبيت بضغطة (iPhone وiPad، أو متصفح آخر).
class PwaInstallSteps extends StatelessWidget {
  const PwaInstallSteps({
    required this.ios,
    this.texts = PwaInstallTexts.arabic,
    super.key,
  });

  final bool ios;
  final PwaInstallTexts texts;

  static const _iosIcons = [
    Icons.ios_share_rounded,
    Icons.add_box_outlined,
    Icons.check_circle_outline_rounded,
  ];
  static const _otherIcons = [
    Icons.more_vert_rounded,
    Icons.install_mobile_rounded,
  ];

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
    return Directionality(
      textDirection: texts.direction,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: ios
            ? [
                for (var i = 0; i < texts.iosSteps.length; i++)
                  step(i + 1, _iosIcons[i], texts.iosSteps[i]),
                Text(
                  texts.iosNote,
                  style: text.bodySmall!.copyWith(color: p.textMuted),
                ),
              ]
            : [
                for (var i = 0; i < texts.otherSteps.length; i++)
                  step(i + 1, _otherIcons[i], texts.otherSteps[i]),
              ],
      ),
    );
  }
}
