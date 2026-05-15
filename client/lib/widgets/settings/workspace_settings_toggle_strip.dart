import 'package:flutter/material.dart';
import 'package:toggle_switch/toggle_switch.dart';

const _segmentedIconSize = 18.0;
const _toggleStripFontSize = 13.0;

/// One option in [WorkspaceSettingsToggleStrip].
class WorkspaceToggleSegment<T extends Object> {
  const WorkspaceToggleSegment({
    required this.value,
    required this.label,
    required this.icon,
  });

  final T value;
  final String label;
  final IconData icon;
}

/// Pill-shaped segmented control (uses [toggle_switch]) for settings rows.
class WorkspaceSettingsToggleStrip<T extends Object> extends StatelessWidget {
  const WorkspaceSettingsToggleStrip({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  final List<WorkspaceToggleSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    final inactiveFg = textBase.withValues(alpha: 0.72);
    final idx = segments.indexWhere((s) => s.value == selected);
    final initialIndex = idx >= 0 ? idx : 0;
    final n = segments.length;
    final minW = n == 2 ? 112.0 : 100.0;
    final customWidths = n == 3 ? <double>[102, 102, 132] : null;

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child: ToggleSwitch(
        key: ValueKey<T>(selected),
        totalSwitches: n,
        initialLabelIndex: initialIndex,
        labels: segments.map((e) => e.label).toList(),
        icons: segments.map((e) => e.icon).toList(),
        cornerRadius: 30,
        radiusStyle: true,
        minHeight: 38,
        minWidth: minW,
        customWidths: customWidths,
        fontSize: _toggleStripFontSize,
        iconSize: _segmentedIconSize,
        activeFgColor: Colors.white,
        inactiveFgColor: inactiveFg,
        inactiveBgColor: cs.surfaceContainerHigh,
        dividerColor: Colors.transparent,
        dividerMargin: 0,
        activeBgColors: List.generate(n, (_) => <Color>[cs.primary]),
        animate: true,
        animationDuration: 220,
        curve: Curves.easeOutCubic,
        onToggle: (index) {
          if (index == null || index < 0 || index >= segments.length) {
            return;
          }
          onChanged(segments[index].value);
        },
      ),
    );
  }
}
