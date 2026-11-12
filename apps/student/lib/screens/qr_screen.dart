import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:school_ui/school_ui.dart';

/// رمز دخول الابن: رمز QR الشخصي الذي يعرضه على الماسح عند دخول القاعة،
/// مع مبدّل الأبناء لمن له أكثر من ابن.
class ChildQrScreen extends ConsumerWidget {
  const ChildQrScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final child = ref.watch(selectedChildProvider);
    return Scaffold(
      appBar: const ClayAppBar(title: 'رمز الدخول', showBack: true),
      body: Column(
        children: [
          const ChildSwitcher(),
          Expanded(
            child: child == null
                ? const ClayEmptyView(
                    title: 'لا أبناء مرتبطون بحسابك',
                    message: 'تواصل مع المدرسة لربط أبنائك بحسابك',
                    icon: ClayIcons.students,
                  )
                : ListView(
                    padding: const EdgeInsets.all(ClaySpacing.screenPadding),
                    children: [
                      ClayCard(
                        child: Column(
                          children: [
                            Text(
                              '${child.firstName} ${child.lastName}',
                              style: text.titleLarge,
                            ),
                            const SizedBox(height: ClaySpacing.md),
                            ClayQrCode(
                              data: child.qrCode,
                              size: 240,
                              semanticLabel:
                                  'رمز QR للتلميذ ${child.firstName} '
                                  '${child.lastName}',
                            ),
                            const SizedBox(height: ClaySpacing.sm),
                            Directionality(
                              textDirection: TextDirection.ltr,
                              child: SelectableText(
                                child.qrCode,
                                style: text.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: ClaySpacing.md),
                      Text(
                        'يعرض ابنك هذا الرمز على الماسح عند دخول قاعة الحصة، '
                        'فيُسجَّل حضوره في الحال. الرمز خاص به فلا يُعطى لغيره.',
                        style: text.bodyMedium!.copyWith(color: p.textMuted),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
