// Adapted from flutter-shadcn-ui ShadInputDecorator — Material / AppTextStyles layout.

import 'package:flutter/material.dart';

import '../../theme/app_text_styles.dart';

/// Label / control / description / error stack for [AppFormField].
class AppFormFieldLayout extends StatelessWidget {
  const AppFormFieldLayout({
    super.key,
    this.child,
    this.label,
    this.error,
    this.description,
  });

  final Widget? child;
  final Widget? label;
  final Widget? error;
  final Widget? description;

  @override
  Widget build(BuildContext context) {
    final styles = AppTextStyles.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: DefaultTextStyle(
              style: styles.smMediumColored(scheme.onSurface),
              child: label!,
            ),
          ),
        if (child != null) child!,
        if (description != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: DefaultTextStyle(
              style: styles.smColored(scheme.onSurfaceVariant),
              child: description!,
            ),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: DefaultTextStyle(
              style: styles.smMediumColored(scheme.error),
              child: error!,
            ),
          ),
      ],
    );
  }
}
