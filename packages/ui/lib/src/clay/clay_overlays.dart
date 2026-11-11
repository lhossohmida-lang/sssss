import 'package:flutter/material.dart';

import '../theme/clay_theme.dart';
import '../theme/clay_tokens.dart';
import 'clay_button.dart';
import 'clay_container.dart';

/// حوار بسطح طيني: عنوان، محتوى، وأزرار.
class ClayDialog extends StatelessWidget {
  const ClayDialog({
    required this.title,
    this.message,
    this.content,
    this.actions = const [],
    super.key,
  }) : assert(
         message == null || content == null,
         'حدّد message أو content لا الاثنين',
       );

  final String title;

  /// نص بسيط تحت العنوان.
  final String? message;

  /// محتوى مخصص (نموذج مثلاً).
  final Widget? content;

  /// الأزرار؛ الأول هو الإجراء الأساسي ويُعرض أولاً (على اليمين في RTL).
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(ClaySpacing.xl),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: ClayContainer(
          radius: ClayRadius.xl,
          elevation: 6,
          padding: const EdgeInsets.all(ClaySpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(title, style: text.titleLarge),
              ),
              if (message != null) ...[
                const SizedBox(height: ClaySpacing.md),
                Text(
                  message!,
                  style: text.bodyMedium!.copyWith(color: p.textMuted),
                ),
              ],
              if (content != null) ...[
                const SizedBox(height: ClaySpacing.md),
                Flexible(child: SingleChildScrollView(child: content)),
              ],
              if (actions.isNotEmpty) ...[
                const SizedBox(height: ClaySpacing.xl),
                Wrap(
                  spacing: ClaySpacing.md,
                  runSpacing: ClaySpacing.sm,
                  alignment: WrapAlignment.start,
                  children: actions,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// يعرض [ClayDialog] ويعيد ما يُمرَّر إلى `Navigator.pop`.
Future<T?> showClayDialog<T>(
  BuildContext context, {
  required String title,
  String? message,
  Widget? content,
  List<Widget> actions = const [],
  bool barrierDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (_) => ClayDialog(
      title: title,
      message: message,
      content: content,
      actions: actions,
    ),
  );
}

/// حوار تأكيد: يعيد `true` عند التأكيد و`false` عند الإلغاء أو الإغلاق.
///
/// [danger] للعمليات التي لا رجعة فيها (حذف، إلغاء حصة).
Future<bool> showClayConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'تأكيد',
  String cancelLabel = 'إلغاء',
  bool danger = false,
}) async {
  final result = await showClayDialog<bool>(
    context,
    title: title,
    message: message,
    actions: [
      Builder(
        builder: (context) => ClayButton(
          label: confirmLabel,
          kind: danger ? ClayButtonKind.danger : ClayButtonKind.primary,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ),
      Builder(
        builder: (context) => ClayButton(
          label: cancelLabel,
          kind: ClayButtonKind.secondary,
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ),
    ],
  );
  return result ?? false;
}

/// ورقة سفلية بسطح طيني مدوّر من الأعلى ومقبض سحب.
class ClayBottomSheet extends StatelessWidget {
  const ClayBottomSheet({required this.child, this.title, super.key});

  final Widget child;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: ClaySpacing.sm,
          right: ClaySpacing.sm,
          bottom: MediaQuery.viewInsetsOf(context).bottom + ClaySpacing.sm,
        ),
        child: ClayContainer(
          radius: ClayRadius.xl,
          elevation: 6,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: ClaySpacing.sm),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: p.outline,
                    borderRadius: BorderRadius.circular(ClayRadius.pill),
                  ),
                ),
              ),
              if (title != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    ClaySpacing.xl,
                    ClaySpacing.md,
                    ClaySpacing.xl,
                    0,
                  ),
                  child: Semantics(
                    header: true,
                    child: Text(title!, style: text.titleLarge),
                  ),
                ),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.all(ClaySpacing.xl),
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// يعرض [ClayBottomSheet] ويعيد ما يُمرَّر إلى `Navigator.pop`.
Future<T?> showClayBottomSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  String? title,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    elevation: 0,
    useSafeArea: false,
    builder: (context) =>
        ClayBottomSheet(title: title, child: builder(context)),
  );
}
