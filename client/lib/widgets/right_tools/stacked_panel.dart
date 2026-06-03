import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/layout_cubit.dart';
import '../../models/layout_preferences.dart';
import '../split_layout.dart';

/// Vertically stacked tool panels with a persisted primary split.
class StackedPanel extends StatelessWidget {
  const StackedPanel({
    required this.panels,
    required this.preferences,
    super.key,
  });

  final List<Widget> panels;
  final LayoutPreferences preferences;

  @override
  Widget build(BuildContext context) {
    if (panels.isEmpty) return const SizedBox.shrink();
    if (panels.length == 1) return panels.single;
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalHeight = constraints.maxHeight;
        final minTop = totalHeight * 0.25;
        final maxTop = totalHeight * 0.75;
        // First split persists via membersSplit; any panels beyond the first
        // are stacked evenly in the lower pane (not persisted).
        return TwoPaneSplitView(
          axis: Axis.vertical,
          initialFraction: preferences.membersSplit,
          minSize: minTop,
          minSecondarySize: minTop,
          maxSize: maxTop,
          first: panels.first,
          second: _evenStack(panels.sublist(1)),
          onSizeChanged: (topHeight) {
            context.read<LayoutCubit>().setMembersSplit(
              (topHeight / totalHeight).clamp(0.25, 0.75),
            );
          },
        );
      },
    );
  }

  /// Stacks [items] vertically with even, non-persisted splits.
  Widget _evenStack(List<Widget> items) {
    if (items.length == 1) return items.single;
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        return TwoPaneSplitView(
          axis: Axis.vertical,
          initialFraction: 1 / items.length,
          minSize: height * 0.2,
          minSecondarySize: height * 0.2,
          maxSize: height * 0.8,
          first: items.first,
          second: _evenStack(items.sublist(1)),
        );
      },
    );
  }
}
