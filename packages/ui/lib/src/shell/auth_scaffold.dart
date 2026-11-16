import 'package:flutter/material.dart';
import 'package:school_core/school_core.dart';

import '../clay/clay_container.dart';
import '../theme/clay_theme.dart';
import '../theme/clay_tokens.dart';

/// هيكل شاشات الدخول: بطاقة في الوسط بعرض أقصى مريح للحاسوب.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    required this.app,
    required this.title,
    required this.children,
    this.subtitle,
    super.key,
  });

  final AppIdentity app;
  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(ClaySpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: ClayContainer(
                radius: ClayRadius.xl,
                padding: const EdgeInsets.all(ClaySpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      app.displayName,
                      textAlign: TextAlign.center,
                      style: text.bodyMedium!.copyWith(color: p.accent),
                    ),
                    const SizedBox(height: ClaySpacing.xs),
                    Semantics(
                      header: true,
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: text.headlineMedium,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: ClaySpacing.sm),
                      Text(
                        subtitle!,
                        textAlign: TextAlign.center,
                        style: text.bodyMedium!.copyWith(color: p.textMuted),
                      ),
                    ],
                    const SizedBox(height: ClaySpacing.xl),
                    ...children,
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

/// رسالة خطأ عامة فوق الزر (خطأ الخادم أو الشبكة).
class FormErrorText extends StatelessWidget {
  const FormErrorText(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: ClaySpacing.md),
      child: Semantics(
        liveRegion: true,
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium!
              .copyWith(color: p.status.danger),
        ),
      ),
    );
  }
}
