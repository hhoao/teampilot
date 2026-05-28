import 'package:flutter/material.dart';
import 'package:toggle_switch/toggle_switch.dart';

import '../../theme/app_text_styles.dart';
import '../../theme/workspace_surface_layers.dart';

const _segmentedIconSize = 18.0;

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
class WorkspaceSettingsToggleStrip<T extends Object> extends StatefulWidget {
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
  State<WorkspaceSettingsToggleStrip<T>> createState() =>
      _WorkspaceSettingsToggleStripState<T>();
}

class _WorkspaceSettingsToggleStripState<T extends Object>
    extends State<WorkspaceSettingsToggleStrip<T>> {
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = _indexFor(widget.selected);
  }

  @override
  void didUpdateWidget(covariant WorkspaceSettingsToggleStrip<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) {
      _index = _indexFor(widget.selected);
    }
  }

  int _indexFor(T value) {
    final idx = widget.segments.indexWhere((s) => s.value == value);
    return idx >= 0 ? idx : 0;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    final inactiveFg = textBase.withValues(alpha: 0.72);
    final n = widget.segments.length;
    final minW = n == 2 ? 112.0 : 100.0;
    final customWidths = n == 3 ? <double>[102, 102, 132] : null;

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child: ToggleSwitch(
        totalSwitches: n,
        initialLabelIndex: _index,
        labels: widget.segments.map((e) => e.label).toList(),
        icons: widget.segments.map((e) => e.icon).toList(),
        cornerRadius: 30,
        radiusStyle: true,
        minHeight: 38,
        minWidth: minW,
        customWidths: customWidths,
        fontSize:
            Theme.of(context).textTheme.bodyMedium?.fontSize ??
            AppTextStyles.of(context).body.fontSize!,
        iconSize: _segmentedIconSize,
        activeFgColor: Colors.white,
        inactiveFgColor: inactiveFg,
        inactiveBgColor: cs.workspaceInset,
        dividerColor: Colors.transparent,
        dividerMargin: 0,
        activeBgColors: List.generate(n, (_) => <Color>[cs.primary]),
        animate: false,
        onToggle: (index) {
          if (index == null || index < 0 || index >= widget.segments.length) {
            return;
          }
          setState(() => _index = index);
          widget.onChanged(widget.segments[index].value);
        },
      ),
    );
  }
}
