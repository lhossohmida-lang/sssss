import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show ProviderObserver, ProviderObserverContext;

/// نسخة الويب: ما يفشل في شاشة يُكتب عليها بدل المربع الرمادي (ErrorWidget في بناء الإصدار)، مع اسم الـprovider
/// الذي فشل وأول أسطر مكانه، فتكفي لقطة شاشة من أي جهاز لمعرفة السبب.
class WebFailureLog {
  WebFailureLog._();

  static final List<String> _recent = [];

  /// آخر الإخفاقات (الأحدث أولاً).
  static List<String> get recent => List.unmodifiable(_recent);

  static void record(String entry) {
    _recent.insert(0, entry);
    if (_recent.length > 4) _recent.removeLast();
  }

  static String stackHead(StackTrace? stack, [int lines = 10]) =>
      (stack?.toString() ?? '')
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .take(lines)
          .join('\n');
}

/// يسجّل كل provider يفشل (نوعه وخطؤه ومكانه) في وحدة التحكم وفي [WebFailureLog].
final class WebFailureObserver extends ProviderObserver {
  const WebFailureObserver();

  @override
  void providerDidFail(
    ProviderObserverContext context,
    Object error,
    StackTrace stackTrace,
  ) {
    final entry =
        'provider: ${context.provider}\n$error\n'
        '${WebFailureLog.stackHead(stackTrace)}';
    WebFailureLog.record(entry);
    debugPrint('school-provider-failed: $entry');
  }
}

/// يجعل خطأ البناء نصاً مقروءاً في نسخة الويب بدل المربع الرمادي.
void installWebErrorView() {
  if (!kIsWeb) return;
  ErrorWidget.builder = (details) => WebErrorView(details: details);
}

class WebErrorView extends StatelessWidget {
  const WebErrorView({required this.details, super.key});

  final FlutterErrorDetails details;

  @override
  Widget build(BuildContext context) {
    final report = [
      details.exceptionAsString(),
      WebFailureLog.stackHead(details.stack, 8),
      for (final failure in WebFailureLog.recent) '— $failure',
    ].where((part) => part.isNotEmpty).join('\n\n');
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: const Color(0xFFFFF4F2),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: DefaultTextStyle(
            style: const TextStyle(
              color: Color(0xFF7A1A10),
              fontSize: 12,
              height: 1.3,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'خطأ في هذه الشاشة — صوّرها وأرسلها',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                SelectableText(report),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
