import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:school_ui/school_ui.dart';

/// حسابي: بيانات الأستاذ من سجله (الهاتف والصورة)، وتغيير كلمة السر،
/// والخروج.
class TeacherAccountScreen extends ConsumerWidget {
  const TeacherAccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teacher = ref.watch(myTeacherProvider).value;
    return AccountScreen(
      photo: localPhoto(teacher?.photoLocalPath),
      details: [if (teacher != null) (label: 'الهاتف', value: teacher.phone)],
    );
  }
}
