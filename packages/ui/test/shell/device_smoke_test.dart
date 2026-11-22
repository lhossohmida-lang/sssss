import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/device_smoke.dart';

void main() {
  test('الشاشات الأولى المقبولة تتبع وجود دليل المدارس', () {
    expect(smokeFirstScreens(AppIdentity.admin, directory: true), [
      'أدخل رقم هاتفك وكلمة السر',
    ]);
    expect(smokeFirstScreens(AppIdentity.teacher, directory: true), [
      'اختر مدرستك',
    ]);
    expect(smokeFirstScreens(AppIdentity.student, directory: false), [
      pairingFirstScreen,
    ]);
    expect(smokeFirstScreens(AppIdentity.student), [
      pairingFirstScreen,
      'اختر مدرستك',
    ]);
  });

  test('SMOKE_DIRECTORY يُقرأ 1 و0 وغيرهما', () {
    expect(smokeDirectoryExpectation('1'), isTrue);
    expect(smokeDirectoryExpectation(' 0 '), isFalse);
    expect(smokeDirectoryExpectation(''), isNull);
  });

  testWidgets('ينتظر أول نص متوقع ويجمع النصوص الظاهرة', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: _LateText(text: 'اختر مدرستك من القائمة')),
    );
    expect(visibleTexts(), contains('...'));
    final found = await waitForAnyText(tester, const [
      pairingFirstScreen,
      'اختر مدرستك',
    ], timeout: const Duration(seconds: 5));
    expect(found, 'اختر مدرستك');
    expect(visibleTexts(), contains('اختر مدرستك من القائمة'));
    expect(
      await waitForAnyText(tester, const [
        'غير موجود',
      ], timeout: const Duration(seconds: 1)),
      isNull,
    );
  });
}

class _LateText extends StatefulWidget {
  const _LateText({required this.text});

  final String text;

  @override
  State<_LateText> createState() => _LateTextState();
}

class _LateTextState extends State<_LateText> {
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _shown = true);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(children: [const Text('...'), if (_shown) Text(widget.text)]),
  );
}
