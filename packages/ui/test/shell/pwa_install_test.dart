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
  });

  @override
  bool isStandalone;
  @override
  bool isIos;
  @override
  bool canPrompt;
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

Future<void> pump(WidgetTester tester, FakeBridge bridge, {bool web = true}) =>
    tester.pumpWidget(
      MaterialApp(
        theme: ClayThemeData.light(AppIdentity.admin),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: PwaInstallOverlay(bridge: bridge, web: web),
          ),
        ),
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

  testWidgets(
    'iPhone: the button shows the Share then Add to Home Screen steps',
    (tester) async {
      final bridge = FakeBridge(isIos: true);
      await pump(tester, bridge);
      expect(
        find.textContaining('ثبّت التطبيق على الشاشة الرئيسية'),
        findsOneWidget,
      );
      await tester.tap(find.text('تثبيت'));
      await tester.pumpAndSettle();
      expect(find.text('التثبيت على الشاشة الرئيسية'), findsOneWidget);
      expect(find.byIcon(Icons.ios_share_rounded), findsOneWidget);
      expect(find.textContaining('إضافة إلى الشاشة الرئيسية'), findsOneWidget);
      expect(bridge.prompts, 0);
      await tester.tap(find.text('فهمت'));
      await tester.pumpAndSettle();
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
    await tester.tap(find.byTooltip('لاحقاً'));
    await tester.pump();
    expect(find.text('تثبيت'), findsNothing);
  });
}
