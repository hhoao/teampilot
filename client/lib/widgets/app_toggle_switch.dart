import 'package:flutter/material.dart';
import 'package:toggle_switch/toggle_switch.dart';

import '../theme/app_icon_sizes.dart';
import '../theme/app_text_styles.dart';
import '../theme/workspace_surface_layers.dart';

/// Default icon size for [AppToggleSwitch] — resolved from theme in [build].
const appToggleSwitchMinHeight = 38.0;

/// Default corner radius for [AppToggleSwitch].
const appToggleSwitchCornerRadius = 30.0;

/// Horizontal padding inside each [ToggleSwitch] segment (see package default).
const _toggleSegmentHorizontalPadding = 20.0;

/// Gap between icon and label inside each segment.
const _toggleIconTextGap = 5.0;

/// Extra width so labels are not clipped at the ellipsis edge.
const _toggleSegmentWidthSlack = 4.0;

/// Per-segment widths from [labels], [fontSize], and optional [icons].
///
/// Matches [toggle_switch] segment layout: horizontal padding, optional icon
/// + gap, then label. Used when [AppToggleSwitch.customWidths] is omitted so
/// controls stay readable at larger typography scales.
List<double> computeToggleSegmentWidths({
  required List<String> labels,
  required double fontSize,
  required double iconSize,
  required TextStyle textStyle,
  List<IconData?>? icons,
  double minSegmentWidth = 100,
}) {
  final iconList = icons;
  final hasIcons = iconList != null && iconList.isNotEmpty;
  return List.generate(labels.length, (i) {
    final label = labels[i];
    final hasIcon = hasIcons && i < iconList.length && iconList[i] != null;
    final painter = TextPainter(
      text: TextSpan(text: label, style: textStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final iconPart = hasIcon ? iconSize + _toggleIconTextGap : 0.0;
    final width =
        _toggleSegmentHorizontalPadding +
        iconPart +
        painter.width +
        _toggleSegmentWidthSlack;
    return width < minSegmentWidth ? minSegmentWidth : width.ceilToDouble();
  });
}

/// Workspace-default pill [ToggleSwitch] styling (workspace settings look).
class AppToggleSwitch extends StatelessWidget {
  const AppToggleSwitch({
    super.key,
    required this.totalSwitches,
    required this.initialLabelIndex,
    required this.labels,
    required this.onToggle,
    this.icons,
    this.minWidth,
    this.customWidths,
    this.minHeight = appToggleSwitchMinHeight,
    this.cornerRadius = appToggleSwitchCornerRadius,
  });

  final int totalSwitches;
  final int initialLabelIndex;
  final List<String> labels;
  final List<IconData?>? icons;
  final OnToggle? onToggle;
  final double? minWidth;
  final List<double>? customWidths;
  final double minHeight;
  final double cornerRadius;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final textBase = cs.onSurface;
    final inactiveFg = textBase.withValues(alpha: 0.72);
    final n = totalSwitches;
    final resolvedMinWidth = minWidth ?? (n == 2 ? 112.0 : 100.0);
    final fontSize = styles.md.fontSize!;
    final iconSize = context.appIconSizes.md;
    final resolvedCustomWidths =
        customWidths ??
        computeToggleSegmentWidths(
          labels: labels,
          fontSize: fontSize,
          iconSize: iconSize,
          icons: icons,
          minSegmentWidth: resolvedMinWidth,
          textStyle: styles.md,
        );

    return ToggleSwitch(
      totalSwitches: n,
      initialLabelIndex: initialLabelIndex,
      labels: labels,
      icons: icons,
      cornerRadius: cornerRadius,
      radiusStyle: true,
      minHeight: minHeight,
      minWidth: resolvedMinWidth,
      customWidths: resolvedCustomWidths,
      fontSize: fontSize,
      iconSize: iconSize,
      activeFgColor: Colors.white,
      inactiveFgColor: inactiveFg,
      inactiveBgColor: cs.workspaceInset,
      dividerColor: Colors.transparent,
      dividerMargin: 0,
      activeBgColors: List.generate(n, (_) => <Color>[cs.primary]),
      animate: false,
      onToggle: onToggle,
    );
  }
}
