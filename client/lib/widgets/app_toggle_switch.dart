import 'package:flutter/material.dart';
import 'package:toggle_switch/toggle_switch.dart';

import '../theme/app_icon_sizes.dart';
import '../theme/app_text_styles.dart';
import '../theme/workspace_surface_layers.dart';

/// Default icon size for [AppToggleSwitch] — resolved from theme in [build].
const appToggleSwitchMinHeight = 38.0;

/// Default corner radius for [AppToggleSwitch].
const appToggleSwitchCornerRadius = 30.0;

/// Project-default pill [ToggleSwitch] styling (workspace settings look).
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    final inactiveFg = textBase.withValues(alpha: 0.72);
    final n = totalSwitches;
    final resolvedMinWidth = minWidth ?? (n == 2 ? 112.0 : 100.0);

    return ToggleSwitch(
      totalSwitches: n,
      initialLabelIndex: initialLabelIndex,
      labels: labels,
      icons: icons,
      cornerRadius: cornerRadius,
      radiusStyle: true,
      minHeight: minHeight,
      minWidth: resolvedMinWidth,
      customWidths: customWidths ?? (n == 3 ? <double>[102, 102, 132] : null),
      fontSize:
          Theme.of(context).textTheme.bodyMedium?.fontSize ??
          AppTextStyles.of(context).body.fontSize!,
      iconSize: context.appIconSizes.md,
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
