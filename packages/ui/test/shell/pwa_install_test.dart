import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart' show AppIdentity;
import 'package:school_ui/school_ui.dart';

class FakeBridge implements PwaBridge {
  FakeBridge({
    this.isStandalone = false,
    this.isIos = false,
    this.canPrompt = false,
    this.language = 'ar-DZ',
  });

  @override
  bool isStandalone;
  @override
  bool isIos;
  @override
  bool canPrompt;
  @override
  String language;
  bool accept = true;
  int prompts = 0;
  final _changes = StreamController<void>.broadcast();

  @override
  Future<bool> prompt() async {
    prompts++;
    canPrompt = false;
    return accept;
  }

  @override
  Stream<void> get changes => _changes.stream;

  void announce() => _changes.add(null);
}

/// كما في التطبيق: البطاقة شريط `footer` في `ClayApp` تحت الملّاح لا داخله (لا Overlay ولا Navigator فوقها).
Future<void> pump(WidgetTester tester, FakeBridge bridge, {bool web = true}) =>
    tester.pumpWidget(
      ClayApp(
        app: AppIdentity.admin,
        home: const Scaffold(body: Center(child: Text('الشاشة'))),
        footer: PwaInstallOverlay(bridge: bridge, web: web),
      ),
    );

void main() {
  testWidgets('outside the browser, or opened from the home screen: no card', (
    tester,
  ) async {
    await pump(tester, FakeBridge(), web: false);
    expect(find.text('تثبيت'), findsNothing);
    await pump(tester, FakeBridge(isStandalone: true));
    expect(find.text('تثبيت'), findsNothing);
  });

  testWidgets('the card sits at the bottom with its natural height', (
    tester,
  ) async {
    await pump(tester, FakeBridge(isIos: true));
    expect(tester.takeException(), isNull);
    expect(find.text('الشاشة'), findsOneWidget);
    expect(tester.getSize(find.byType(ClayCard)).height, lessThan(160));
  });

  testWidgets('the card takes its own space under the page: it never covers '
      'the bottom button of the page', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(
      ClayApp(
        app: AppIdentity.admin,
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ElevatedButton(
              onPressed: () => pressed++,
              child: const Text('دخول'),
            ),
          ),
        ),
        footer: PwaInstallOverlay(bridge: FakeBridge(isIos: true), web: true),
      ),
    );
    final button = tester.getRect(find.text('دخول'));
    final card = tester.getRect(find.byType(ClayCard));
    expect(button.bottom, lessThanOrEqualTo(card.top));
    await tester.tap(find.text('دخول'));
    expect(pressed, 1);
  });

  testWidgets(
    'iPhone: the button opens the Share then Add to Home Screen steps',
    (tester) async {
      final bridge = FakeBridge(isIos: true);
      await pump(tester, bridge);
      expect(
        find.textContaining('ثبّت التطبيق على الشاشة الرئيسية'),
        findsOneWidget,
      );
      await tester.tap(find.text('تثبيت'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.ios_share_rounded), findsOneWidget);
      expect(find.textContaining('إضافة إلى الشاشة الرئيسية'), findsOneWidget);
      expect(bridge.prompts, 0);
      await tester.tap(find.text('فهمت'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.ios_share_rounded), findsNothing);
      expect(find.text('تثبيت'), findsOneWidget);
    },
  );

  testWidgets('Android and computers: the button installs in one tap', (
    tester,
  ) async {
    final bridge = FakeBridge();
    await pump(tester, bridge);
    bridge
      ..canPrompt = true
      ..announce();
    await tester.pump();
    await tester.tap(find.text('تثبيت'));
    await tester.pumpAndSettle();
    expect(bridge.prompts, 1);
    expect(find.text('تثبيت'), findsNothing);
  });

  testWidgets('Later hides the card', (tester) async {
    await pump(tester, FakeBridge(isIos: true));
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    expect(find.text('تثبيت'), findsNothing);
  });

  testWidgets('an iPhone in French: the card and the steps name Safari\'s '
      'French buttons', (tester) async {
    await pump(tester, FakeBridge(isIos: true, language: 'fr-FR'));
    expect(find.text('Installer'), findsOneWidget);
    await tester.tap(find.text('Installer'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('« Partager »'), findsOneWidget);
    expect(find.textContaining("« Sur l'écran d'accueil »"), findsOneWidget);
    expect(find.textContaining('« Ajouter »'), findsOneWidget);
    expect(find.text('Compris'), findsOneWidget);
  });

  testWidgets('an iPhone in English: Share, Add to Home Screen, Add', (
    tester,
  ) async {
    await pump(tester, FakeBridge(isIos: true, language: 'en-US'));
    await tester.tap(find.text('Install'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Share button'), findsOneWidget);
    expect(find.textContaining('“Add to Home Screen”'), findsOneWidget);
    expect(find.textContaining('“Add”'), findsOneWidget);
  });

  test('other languages fall back to Arabic', () {
    expect(PwaInstallTexts.of('de-DE').code, 'ar');
    expect(PwaInstallTexts.of('ar').code, 'ar');
    expect(PwaInstallTexts.of('FR_ca').code, 'fr');
    expect(PwaInstallTexts.of('en').code, 'en');
  });
}
