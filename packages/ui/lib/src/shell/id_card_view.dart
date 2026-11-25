import 'package:flutter/material.dart';

import '../clay/clay_display.dart';
import '../clay/clay_qr.dart';
import '../theme/clay_theme.dart';
import '../theme/clay_tokens.dart';

/// البطاقة على الشاشة بتصميم البطاقة المطبوعة (85.6×54): رأس باسم المدرسة، والصورة أو الأحرف الأولى، والاسم
/// والصفة، ورمز QR الذي يُمسح عند الدخول. تظهر في «حسابي» للأستاذ والوليّ فيعرضها صاحبها على الماسح.
class IdCardView extends StatelessWidget {
  const IdCardView({
    required this.schoolName,
    required this.name,
    required this.qrCode,
    this.subtitle,
    this.caption = 'يُمسح الرمز عند الدخول',
    this.photo,
    super.key,
  });

  final String schoolName;
  final String name;
  final String qrCode;
  final String? subtitle;
  final String caption;
  final ImageProvider? photo;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: AspectRatio(
          aspectRatio: 85.6 / 54,
          child: Semantics(
            label: 'بطاقة $name',
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: p.accent, width: 1.5),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      color: p.accent,
                      padding: const EdgeInsets.symmetric(
                        horizontal: ClaySpacing.md,
                        vertical: ClaySpacing.sm,
                      ),
                      child: Text(
                        schoolName.isEmpty ? 'المدرسة' : schoolName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleSmall!.copyWith(color: p.onAccent),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(ClaySpacing.sm),
                        child: Row(
                          children: [
                            ClayAvatar(name: name, image: photo, size: 56),
                            const SizedBox(width: ClaySpacing.sm),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: text.titleMedium!.copyWith(
                                      color: const Color(0xFF1E2433),
                                    ),
                                  ),
                                  if (subtitle != null && subtitle!.isNotEmpty)
                                    Text(
                                      subtitle!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: text.bodySmall!.copyWith(
                                        color: const Color(0xFF5A6378),
                                      ),
                                    ),
                                  const SizedBox(height: 4),
                                  Text(
                                    caption,
                                    style: text.labelSmall!.copyWith(
                                      color: p.accent,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: ClaySpacing.sm),
                            // الرمز على أبيض دائماً (حتى في الوضع الداكن) ليقرأه الماسح.
                            LayoutBuilder(
                              builder: (context, constraints) {
                                // الرمز وهامشه الأبيض (ClaySpacing.md من كل جهة) في ارتفاع البطاقة.
                                final size =
                                    (constraints.maxHeight - 2 * ClaySpacing.md)
                                        .clamp(48.0, 140.0)
                                        .toDouble();
                                return ClayQrCode(
                                  data: qrCode,
                                  size: size,
                                  semanticLabel: 'رمز QR لـ $name',
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
