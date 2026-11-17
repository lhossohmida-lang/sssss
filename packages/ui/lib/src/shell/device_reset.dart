import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:school_core/school_core.dart';

import '../clay/clay_overlays.dart';
import 'providers.dart';
import 'school_bootstrap.dart';

/// يطلب تأكيد «إعادة تعيين بيانات الجهاز»: خطوة واحدة، وخطوتان حين توجد بيانات معرّضة للضياع
/// ([unsyncedChanges] تغييرات لم تصل الخادم، أو [localOnly] معاينة لا نسخة لبياناتها غير الجهاز).
Future<bool> confirmDeviceReset(
  BuildContext context, {
  int unsyncedChanges = 0,
  bool localOnly = false,
}) async {
  final risky = localOnly || unsyncedChanges > 0;
  final warnings = [
    if (localOnly)
      'هذه معاينة محلية لا نسخة لبياناتها غير هذا الجهاز، وستضيع نهائياً.',
    if (unsyncedChanges > 0)
      'لم يصل إلى الخادم بعد $unsyncedChanges تغيير من هذا الجهاز، وسيضيع.',
  ];
  final first = await showClayConfirm(
    context,
    title: 'إعادة تعيين بيانات الجهاز',
    message:
        'سيُمسح من هذا الجهاز كل ما حفظه التطبيق: بيانات المدارس والصور والملفات '
        'وربط المدرسة وتسجيل الدخول، ويعود التطبيق كأول تشغيل. لا يُمسّ شيء على '
        'خادم المدرسة، وتعود البيانات إلى الجهاز بعد الدخول من جديد.'
        '${warnings.isEmpty ? '' : '\n\n${warnings.join('\n')}'}',
    confirmLabel: risky ? 'متابعة' : 'مسح وإعادة التعيين',
    danger: true,
  );
  if (!first || !risky || !context.mounted) return first;
  return showClayConfirm(
    context,
    title: 'هل أنت متأكد؟',
    message: 'ستضيع هذه البيانات نهائياً ولا يمكن استرجاعها.',
    confirmLabel: 'نعم، امسح كل شيء',
    danger: true,
  );
}

/// تدفق الزر: يعدّ التغييرات غير المرسلة، ويطلب التأكيد، ثم يخرج من الحساب (وتُلغى
/// تسجيلات الإشعارات) ويمسح بيانات الجهاز ويعيد التطبيق كأول تشغيل.
Future<void> runDeviceReset(BuildContext context, WidgetRef ref) async {
  final connection = SchoolBootstrap.connectionOf(context);
  if (connection == null) return;
  final runtime = ref.read(runtimeProvider);
  var unsynced = 0;
  try {
    unsynced = await countUnsyncedChanges(runtime.db);
  } on Object {
    // قاعدة تالفة: لا عدّاد، ويكفي التأكيد العادي.
  }
  if (!context.mounted) return;
  final ok = await confirmDeviceReset(
    context,
    unsyncedChanges: unsynced,
    localOnly: runtime.isLocalMode,
  );
  if (!ok) return;
  try {
    await ref.read(pushNotificationsProvider).signOut();
  } on Object {
    // لا يمنع المسح.
  }
  await connection.factoryReset();
}
