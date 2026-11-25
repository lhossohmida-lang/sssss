import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:school_ui/school_ui.dart';

/// حسابي للوليّ: اسمه وبريده وهاتفه وأسماء أبنائه، وتغيير كلمة السر،
/// والخروج.
class ParentAccountScreen extends ConsumerWidget {
  const ParentAccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parent = ref.watch(myParentProvider).value;
    final children = ref.watch(childrenProvider).value ?? const [];
    final school = ref.watch(schoolNameProvider).value ?? '';
    return AccountScreen(
      // بطاقة كل ابن برمزه: يعرضها على الماسح عند دخول القاعة.
      cards: [
        for (final child in children)
          IdCardView(
            schoolName: school,
            name: '${child.firstName} ${child.lastName}',
            subtitle: 'تلميذ',
            qrCode: child.qrCode,
            photo: localPhoto(child.photoLocalPath),
          ),
      ],
      details: [
        if (parent != null) (label: 'الهاتف', value: parent.phone),
        if (children.isNotEmpty)
          (
            label: 'الأبناء',
            value: [for (final c in children) '${c.firstName} ${c.lastName}']
                .join('، '),
          ),
      ],
    );
  }
}
