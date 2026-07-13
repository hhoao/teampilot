// Adapted from flutter-shadcn-ui ShadInputDecorator — Material / AppTextStyles layout.

import 'package:flutter/material.dart';

import '../../theme/app_text_styles.dart';

/// How [AppFormFieldLayout] places [label] relative to the control.
enum AppFormFieldLayoutStyle {
  /// Label above the control (default).
  stacked,

  /// Label and control on one row (IDEA-style form rows).
  inline,
}

/// Label / control / description / error layout for [AppFormField].
class AppFormFieldLayout extends StatelessWidget {
  const AppFormFieldLayout({
    super.key,
    this.child,
    this.label,
    this.error,
    this.description,
    this.style = AppFormFieldLayoutStyle.stacked,
    this.labelWidth = 140,
  });

  final Widget? child;
  final Widget? label;
  final Widget? error;
  final Widget? description;
  final AppFormFieldLayoutStyle style;

  /// Fixed label column width when [style] is [AppFormFieldLayoutStyle.inline].
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    final styles = AppTextStyles.of(context);
    final scheme = Theme.of(context).colorScheme;
    final labelStyle = styles.smMediumColored(scheme.onSurface);
    final descriptionStyle = styles.smColored(scheme.onSurfaceVariant);
    final errorStyle = styles.smMediumColored(scheme.error);

    final labeledControl = style == AppFormFieldLayoutStyle.inline
        ? _inlineRow(labelStyle)
        : _stackedColumn(labelStyle);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        labeledControl,
        if (description != null)
          Padding(
            padding: EdgeInsets.only(
              top: 8,
              left: style == AppFormFieldLayoutStyle.inline ? labelWidth + 12 : 0,
            ),
            child: DefaultTextStyle(
              style: descriptionStyle,
              child: description!,
            ),
          ),
        if (error != null)
          Padding(
            padding: EdgeInsets.only(
              top: 8,
              left: style == AppFormFieldLayoutStyle.inline ? labelWidth + 12 : 0,
            ),
            child: DefaultTextStyle(
              style: errorStyle,
              child: error!,
            ),
          ),
      ],
    );
  }

  Widget _stackedColumn(TextStyle labelStyle) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: DefaultTextStyle(style: labelStyle, child: label!),
          ),
        if (child != null) child!,
      ],
    );
  }

  Widget _inlineRow(TextStyle labelStyle) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null)
          SizedBox(
            width: labelWidth,
            child: Padding(
              // Align with dense input text baseline (~12–14px top inset).
              padding: const EdgeInsets.only(right: 12, top: 10),
              child: DefaultTextStyle(
                style: labelStyle,
                textAlign: TextAlign.left,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: label!,
                ),
              ),
            ),
          )
        else
          SizedBox(width: labelWidth + 12),
        if (child != null) Expanded(child: child!),
      ],
    );
  }
}
