import 'package:flutter/material.dart';

/// 应用内统一的「填充 + 细描边」文本框，与 [FlashskyDropdownDecorations.denseField] 的
/// surface / outline 层次对齐，避免裸 [TextField] 依赖默认 [InputDecorationTheme] 导致观感参差。
class AppOutlineTextField extends StatelessWidget {
  const AppOutlineTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.hintText,
    this.hintMaxLines,
    this.labelText,
    this.prefixIcon,
    this.suffixIcon,
    this.errorText,
    this.obscureText = false,
    this.autofocus = false,
    this.readOnly = false,
    this.enabled = true,
    this.maxLines = 1,
    this.minLines,
    this.onChanged,
    this.onSubmitted,
    this.style,
    this.hintStyle,
    this.fillColor,
    this.contentPadding,
    this.constraints,
    this.borderRadius = 8,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;

  /// Shown inside the field when [controller] text is empty.
  final String? hintText;
  final int? hintMaxLines;

  /// Shrink-wrapped floating label inside the outline.
  final String? labelText;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final String? errorText;
  final bool obscureText;
  final bool autofocus;
  final bool readOnly;
  final bool enabled;
  final int? maxLines;
  final int? minLines;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// Overrides [DefaultTextTheme.bodyMedium]-based input style when set.
  final TextStyle? style;

  /// Overrides theme-derived hint styling when set.
  final TextStyle? hintStyle;

  /// Overrides [AppOutlineInputDecoration] fill; defaults to theme surface tone.
  final Color? fillColor;

  /// Inner padding inside the bordered area.
  final EdgeInsetsGeometry? contentPadding;

  /// Optional min/max size for tight layouts (e.g. dropdown search bar height).
  final BoxConstraints? constraints;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: key,
      controller: controller,
      focusNode: focusNode,
      obscureText: obscureText,
      autofocus: autofocus,
      readOnly: readOnly,
      enabled: enabled,
      maxLines: maxLines,
      minLines: minLines,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      style: style ?? Theme.of(context).textTheme.bodyMedium,
      decoration: AppOutlineInputDecoration.dense(
        context,
        hintText: hintText,
        hintMaxLines: hintMaxLines,
        labelText: labelText,
        prefixIcon: prefixIcon,
        suffixIcon: suffixIcon,
        errorText: errorText,
        fillColor: fillColor,
        contentPadding: contentPadding,
        constraints: constraints,
        borderRadius: borderRadius,
        hintStyleOverride: hintStyle,
      ),
    );
  }
}

/// 生成与 [AppOutlineTextField] 相同的 [InputDecoration]，便于在 [Row] 等布局里手写 [TextField]。
class AppOutlineInputDecoration {
  AppOutlineInputDecoration._();

  static InputDecoration dense(
    BuildContext context, {
    String? hintText,
    int? hintMaxLines,
    String? labelText,
    Widget? prefixIcon,
    Widget? suffixIcon,
    String? errorText,
    Color? fillColor,
    EdgeInsetsGeometry? contentPadding,
    BoxConstraints? constraints,
    TextStyle? hintStyleOverride,
    double borderRadius = 8,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final outline = cs.outlineVariant;
    final radius = BorderRadius.circular(borderRadius);

    OutlineInputBorder outlineBorder(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: color, width: width),
        );

    final hintColor = cs.onSurfaceVariant.withValues(alpha: 0.72);
    final labelColor = cs.onSurfaceVariant.withValues(alpha: 0.9);

    final hintStyleComputed =
        hintStyleOverride ??
        theme.inputDecorationTheme.hintStyle?.copyWith(color: hintColor) ??
        (theme.textTheme.labelSmall ??
                theme.textTheme.bodySmall ??
                theme.textTheme.bodyMedium!)
            .copyWith(
              color: hintColor,
              height: 1.35,
              fontWeight: FontWeight.w500,
            );

    return InputDecoration(
      filled: true,
      fillColor: fillColor ?? cs.surfaceContainerHigh,
      constraints: constraints,
      isDense: true,
      hintText: hintText,
      hintMaxLines: hintMaxLines,
      labelText: labelText,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      errorText: errorText,
      floatingLabelBehavior: labelText != null
          ? FloatingLabelBehavior.auto
          : FloatingLabelBehavior.never,
      contentPadding:
          contentPadding ??
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      hintStyle: hintStyleComputed,
      labelStyle: theme.textTheme.bodyMedium?.copyWith(color: labelColor),
      floatingLabelStyle: theme.textTheme.labelLarge?.copyWith(
        color: cs.primary,
        fontWeight: FontWeight.w500,
      ),
      border: outlineBorder(outline),
      enabledBorder: outlineBorder(outline),
      focusedBorder: outlineBorder(cs.primary, 1.5),
      errorBorder: outlineBorder(cs.error),
      focusedErrorBorder: outlineBorder(cs.error, 1.5),
      disabledBorder: outlineBorder(outline.withValues(alpha: 0.38)),
    );
  }
}
