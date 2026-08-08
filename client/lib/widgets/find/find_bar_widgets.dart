import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import 'find_bar_palette.dart';

/// Compact VS Code-style primitives shared by the chat and editor find bars
/// (built on [FindBarPalette] + the [TpHover] surface).

/// Outer shell of a VS Code-style find widget: panel bg, hairline border,
/// drop shadow, small radius. Rows are stacked inside by the caller.
class FindBarPanel extends StatelessWidget {
  const FindBarPanel({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = FindBarPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: palette.shadow,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: palette.panelBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(color: palette.panelBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
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
    this.onClear,
    this.width,
    super.key,
  });

  static const double kHeight = 26;

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;

  /// Inline toggles rendered at the field's trailing edge.
  final List<Widget> toggles;
  final bool showClear;

  /// Requests focus on the field as soon as it mounts.
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final palette = FindBarPalette.of(context);
    return SizedBox(
      width: width,
      height: kHeight,
      child: ListenableBuilder(
        listenable: focusNode,
        builder: (context, _) {
          final focused = focusNode.hasFocus;
          return Container(
            decoration: BoxDecoration(
              color: palette.fieldBg,
              borderRadius: BorderRadius.circular(2),
              border: Border.all(
                color: focused ? palette.focusBorder : palette.border,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    autofocus: autofocus,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 13,
                      color: palette.text,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: hint,
                      hintStyle: TextStyle(
                        fontSize: 13,
                        color: palette.mutedText,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 6,
                      ),
                    ),
                    onChanged: onChanged,
                  ),
                ),
                ...toggles,
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
                const SizedBox(width: 2),
              ],
            ),
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

/// Small `Aa` / `ab` / `.*` / `AB` option toggle with an on state (bg + border
/// + accent label), like VS Code's find-widget toggles.
class FindToggleButton extends StatelessWidget {
  const FindToggleButton({
    required this.label,
    required this.tooltip,
    required this.checked,
    required this.onTap,
    this.enabled = true,
    super.key,
  });

  static const double kSize = 20;

  final String label;
  final String tooltip;
  final bool checked;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final palette = FindBarPalette.of(context);
    return Tooltip(
      message: tooltip,
      child: TpHover(
        width: kSize,
        height: kSize,
        borderRadius: BorderRadius.circular(3),
        backgroundColor: checked ? palette.activeBg : null,
        hoverColor: checked ? palette.activeBg : palette.hoverBg,
        border: checked
            ? Border.all(color: palette.activeBorder, width: 1)
            : null,
        enabled: enabled,
        onTap: enabled ? onTap : null,
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: checked ? palette.toggleOnText : palette.icon,
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact icon action button (prev / next / find-in-selection / close).
///
/// When [checked] is true the button renders as an active toggle (accent bg +
/// border), for controls that are on/off rather than one-shot actions.
class FindActionButton extends StatelessWidget {
  const FindActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.enabled = true,
    this.checked = false,
    this.size = 22,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool enabled;
  final bool checked;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = FindBarPalette.of(context);
    final iconColor = !enabled
        ? palette.mutedText
        : checked
        ? palette.toggleOnText
        : palette.icon;
    return Tooltip(
      message: tooltip,
      child: TpHover(
        width: size,
        height: size,
        borderRadius: BorderRadius.circular(3),
        backgroundColor: checked ? palette.activeBg : null,
        hoverColor: checked ? palette.activeBg : palette.hoverBg,
        border: checked
            ? Border.all(color: palette.activeBorder, width: 1)
            : null,
        enabled: enabled,
        onTap: enabled ? onTap : null,
        child: Icon(icon, size: 16, color: iconColor),
      ),
    );
  }
}

/// The mockup's `b→c` / `ab→ac` replace buttons (small text + arrow glyphs).
class ReplaceActionButton extends StatelessWidget {
  const ReplaceActionButton({
    required this.source,
    required this.target,
    required this.tooltip,
    required this.onTap,
    this.enabled = true,
    super.key,
  });

  final String source;
  final String target;
  final String tooltip;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final palette = FindBarPalette.of(context);
    final color = enabled ? palette.icon : palette.mutedText;
    final style = TextStyle(
      fontSize: 9,
      fontFamily: 'monospace',
      fontWeight: FontWeight.w600,
      color: color,
    );
    return Tooltip(
      message: tooltip,
      child: TpHover(
        height: 22,
        borderRadius: BorderRadius.circular(3),
        hoverColor: palette.hoverBg,
        padding: const EdgeInsets.symmetric(horizontal: 5),
        enabled: enabled,
        onTap: enabled ? onTap : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(source, style: style),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Icon(
                Icons.arrow_right_rounded,
                size: 11,
                color: color,
              ),
            ),
            Text(target, style: style),
          ],
        ),
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
        style: TextStyle(
          fontSize: 12,
          color: empty ? palette.mutedText : palette.text,
        ),
      ),
    );
  }
}
