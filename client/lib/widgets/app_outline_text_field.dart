import 'package:flutter/material.dart';

/// 应用内统一的「填充 + 细描边」文本框，与 [FlashskyDropdownDecorations.denseField] 的
/// surface / outline 层次对齐，避免裸 [TextField] 依赖默认 [InputDecorationTheme] 导致观感参差。
class AppOutlineTextField extends StatelessWidget {
  const AppOutlineTextField({
    super.key,
    this.controller,
    this.hintText,
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
    this.contentPadding,
    this.borderRadius = 8,
  });

  final TextEditingController? controller;
  final String? hintText;
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
  final EdgeInsetsGeometry? contentPadding;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: key,
      controller: controller,
      obscureText: obscureText,
      autofocus: autofocus,
      readOnly: readOnly,
      enabled: enabled,
      maxLines: maxLines,
      minLines: minLines,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      style: Theme.of(context).textTheme.bodyMedium,
      decoration: AppOutlineInputDecoration.dense(
        context,
        hintText: hintText,
        labelText: labelText,
        prefixIcon: prefixIcon,
        suffixIcon: suffixIcon,
        errorText: errorText,
        contentPadding: contentPadding,
        borderRadius: borderRadius,
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
    String? labelText,
    Widget? prefixIcon,
    Widget? suffixIcon,
    String? errorText,
    EdgeInsetsGeometry? contentPadding,
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

    return InputDecoration(
      filled: true,
      fillColor: cs.surfaceContainerHigh,
      isDense: true,
      hintText: hintText,
      labelText: labelText,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      errorText: errorText,
      floatingLabelBehavior: labelText != null
          ? FloatingLabelBehavior.auto
          : FloatingLabelBehavior.never,
      contentPadding: contentPadding ??
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      hintStyle: theme.textTheme.bodyMedium?.copyWith(color: hintColor),
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
