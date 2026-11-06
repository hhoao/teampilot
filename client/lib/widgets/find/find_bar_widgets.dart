import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_ui/shared_ui.dart';

import 'find_bar_palette.dart';

/// Compact VS Code-style primitives shared by the chat and editor find bars
/// (built on [FindBarPalette] + the [TpHover] surface).

/// Asset paths for the find-widget SVG icons (`assets/icons/svg`).
abstract final class FindBarIcons {
  static const String caseSensitive = 'assets/icons/svg/case_sensitive.svg';
  static const String wholeWord = 'assets/icons/svg/whole_word.svg';
  static const String regexp = 'assets/icons/svg/regexp.svg';
  static const String upperCase = 'assets/icons/svg/upper_case.svg';
  static const String replace = 'assets/icons/svg/replace.svg';
  static const String replaceAll = 'assets/icons/svg/replace_all.svg';
}

/// Outer shell of a VS Code-style find widget: panel bg, hairline border,
/// drop shadow. Rows are stacked inside by the caller.
class FindBarPanel extends StatelessWidget {
  const FindBarPanel({
    required this.child,
    this.borderRadius = kPillRadius,
    this.focusNode,
    super.key,
  });

  static const double kPillRadius = tpSearchPillRadius;
  static const double kCardRadius = 16;

  final Widget child;
  final double borderRadius;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final palette = FindBarPalette.of(context);
    final radius = BorderRadius.circular(borderRadius);

    Widget buildPanel(Color borderColor) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: palette.shadow,
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: palette.panelBg,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(color: borderColor),
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      );
    }

    final node = focusNode;
    if (node == null) {
      return buildPanel(palette.panelBorder);
    }
    return ListenableBuilder(
      listenable: node,
      builder: (context, _) {
        return buildPanel(
          node.hasFocus ? palette.focusBorder : palette.panelBorder,
        );
      },
    );
  }
}

/// Vertical hairline separating search / counter / navigation groups.
class FindBarDivider extends StatelessWidget {
  const FindBarDivider({this.height = 18, super.key});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: height,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: FindBarPalette.of(context).panelBorder,
    );
  }
}

/// A 26px compact input field with optional inline option toggles on the
/// trailing edge — mirrors the VS Code find widget, where toggles live inside
/// the field.
class FindField extends StatelessWidget {
  const FindField({
    required this.controller,
    required this.focusNode,
    required this.hint,
    this.toggles = const [],
    this.showClear = false,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
    this.onClear,
    this.width,
    this.standalone = false,
    this.trailing,
    super.key,
  });

  /// Tall enough for the md text + vertical padding without clipping.
  static const double kHeight = 34;

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final List<Widget> toggles;
  final bool showClear;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onClear;
  final double? width;

  /// When true the field is not inside a [FindBarPanel] and draws its own
  /// pill border (right-tools search panel).
  final bool standalone;

  /// Optional non-interactive trailing content (e.g. terminal find status).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = FindBarPalette.of(context);
    final styles = TpTextStyles.of(context);

    return SizedBox(
      width: width,
      height: kHeight,
      child: ListenableBuilder(
        listenable: focusNode,
        builder: (context, _) {
          final focused = focusNode.hasFocus;
          final row = Row(
            children: [
              const SizedBox(width: 8),
              Icon(
                Icons.search_rounded,
                size: context.tpIconSizes.md,
                color: palette.mutedText,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  autofocus: autofocus,
                  maxLines: 1,
                  style: styles.md.copyWith(color: palette.text),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: hint,
                    hintStyle: styles.md.copyWith(color: palette.mutedText),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 0,
                      vertical: 5,
                    ),
                  ),
                  onChanged: onChanged,
                  onSubmitted: onSubmitted,
                ),
              ),
              ...toggles,
              if (trailing != null) trailing!,
              if (showClear)
                ListenableBuilder(
                  listenable: controller,
                  builder: (context, _) => _ClearButton(
                    visible: controller.text.isNotEmpty,
                    color: palette.icon,
                    hoverColor: palette.hoverBg,
                    onTap: onClear,
                  ),
                ),
              const SizedBox(width: 4),
            ],
          );
          if (!standalone) {
            return row;
          }
          return Container(
            decoration: BoxDecoration(
              color: palette.fieldBg,
              borderRadius: BorderRadius.circular(FindBarPanel.kPillRadius),
              border: Border.all(
                color: focused ? palette.focusBorder : palette.border,
              ),
            ),
            child: row,
          );
        },
      ),
    );
  }
}

class _ClearButton extends StatelessWidget {
  const _ClearButton({
    required this.visible,
    required this.color,
    required this.hoverColor,
    required this.onTap,
  });

  final bool visible;
  final Color color;
  final Color hoverColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (!visible) {
      return const SizedBox(width: 18, height: 18);
    }
    return TpHover(
      width: 18,
      height: 18,
      borderRadius: BorderRadius.circular(3),
      hoverColor: hoverColor,
      onTap: onTap,
      child: Icon(Icons.close, size: 12, color: color),
    );
  }
}

/// Small `Aa` / `ab` / `.*` / `AB` option toggle with an on state shown only
/// by the icon color (no background box), like VS Code's find-widget toggles.
class FindToggleButton extends StatelessWidget {
  const FindToggleButton({
    required this.iconAsset,
    required this.tooltip,
    required this.checked,
    required this.onTap,
    this.enabled = true,
    super.key,
  });

  static const double kSize = 20;

  /// `assets/icons/svg/*.svg` asset rendered at the theme's md icon size.
  final String iconAsset;
  final String tooltip;
  final bool checked;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final palette = FindBarPalette.of(context);
    final color = checked ? palette.toggleOnText : palette.icon;
    return Tooltip(
      message: tooltip,
      child: TpHover(
        width: kSize,
        height: kSize,
        borderRadius: BorderRadius.circular(3),
        // Transparent surface: these live inside the input field, so the on
        // state is conveyed purely by the icon color.
        backgroundColor: Colors.transparent,
        hoverColor: Colors.transparent,
        enabled: enabled,
        onTap: enabled ? onTap : null,
        child: SvgPicture.asset(
          iconAsset,
          width: context.tpIconSizes.md,
          height: context.tpIconSizes.md,
          colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
        ),
      ),
    );
  }
}

/// Compact icon action button (prev / next / find-in-selection / close /
/// replace). Renders a Material [icon] or, when [assetPath] is set, the SVG
/// asset from `assets/icons/svg`.
///
/// When [checked] is true the button renders as an active toggle (accent bg +
/// border), for controls that are on/off rather than one-shot actions.
class FindActionButton extends StatelessWidget {
  const FindActionButton({
    required this.tooltip,
    required this.onTap,
    this.icon,
    this.assetPath,
    this.enabled = true,
    this.checked = false,
    this.width = FindField.kHeight,
    this.height = FindField.kHeight,
    super.key,
  });

  /// Material icon shown when [assetPath] is null.
  final IconData? icon;

  /// `assets/icons/svg/*.svg` asset rendered instead of [icon] when set.
  final String? assetPath;
  final String tooltip;
  final VoidCallback onTap;
  final bool enabled;
  final bool checked;
  final double width;

  /// Matches the input field height so the buttons align with the rows.
  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = FindBarPalette.of(context);
    final iconColor = !enabled
        ? palette.mutedText
        : checked
        ? palette.toggleOnText
        : palette.icon;
    final double iconSize = context.tpIconSizes.md;
    final Widget glyph = assetPath != null
        ? SvgPicture.asset(
            assetPath!,
            width: iconSize,
            height: iconSize,
            colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
          )
        : Icon(icon, size: iconSize, color: iconColor);
    return Tooltip(
      message: tooltip,
      child: TpHover(
        width: width,
        height: height,
        borderRadius: BorderRadius.circular(3),
        backgroundColor: checked ? palette.activeBg : null,
        hoverColor: checked ? palette.activeBg : palette.hoverBg,
        border: checked
            ? Border.all(color: palette.activeBorder, width: 1)
            : null,
        enabled: enabled,
        onTap: enabled ? onTap : null,
        child: glyph,
      ),
    );
  }
}

/// n/N (or "no results") counter label.
class FindCounterText extends StatelessWidget {
  const FindCounterText({
    required this.label,
    this.empty = false,
    this.width = 52,
    super.key,
  });

  final String label;
  final bool empty;
  final double width;

  @override
  Widget build(BuildContext context) {
    final palette = FindBarPalette.of(context);
    return SizedBox(
      width: width,
      child: Text(
        label,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TpTextStyles.of(
          context,
        ).md.copyWith(color: empty ? palette.mutedText : palette.text),
      ),
    );
  }
}
