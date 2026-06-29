import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/layout_cubit.dart';
import '../../models/layout_preferences.dart';
import '../../widgets/resizable_split_view.dart';

/// Project-page-level host for the center workbench and right tools panel.
///
/// The center child is wrapped in [RepaintBoundary] and always occupies the
/// flexible pane — toggling or animating the panel never reparents the terminal.
///
/// Panel width animates over [_revealDuration] when shown or hidden so layout
/// work is spread across frames instead of landing in a single janky build.
class RightToolsHost extends StatefulWidget {
  const RightToolsHost({
    super.key,
    required this.center,
    required this.rightTools,
    required this.onRightToolsWidthChanged,
  });

  final Widget center;
  final Widget rightTools;
  final ValueChanged<double>? onRightToolsWidthChanged;

  static const double _minCenterWidth = 150.0;
  static const Duration _revealDuration = Duration(milliseconds: 200);

  @override
  State<RightToolsHost> createState() => _RightToolsHostState();
}

class _RightToolsHostState extends State<RightToolsHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _revealController;
  Animation<double>? _widthAnimation;
  double _animatedWidth = 0;

  bool _layoutInitialized = false;
  bool? _lastVisible;
  double? _lastStoredWidth;

  @override
  void initState() {
    super.initState();
    _revealController = AnimationController(
      vsync: this,
      duration: RightToolsHost._revealDuration,
    )..addListener(_onRevealTick);
  }

  void _onRevealTick() {
    final animation = _widthAnimation;
    if (animation == null) return;
    setState(() => _animatedWidth = animation.value);
  }

  void _applyLayoutTargets(bool visible, double storedWidth) {
    final clampedStored = storedWidth.clamp(
      LayoutPreferences.minRightToolsWidth,
      double.infinity,
    );
    final targetWidth = visible ? clampedStored : 0.0;

    if (!_layoutInitialized) {
      _layoutInitialized = true;
      _lastVisible = visible;
      _lastStoredWidth = clampedStored;
      _animatedWidth = targetWidth;
      return;
    }

    final visibilityChanged = _lastVisible != visible;
    final widthChanged = _lastStoredWidth != clampedStored;

    if (!visibilityChanged && !widthChanged) {
      return;
    }

    _lastVisible = visible;
    _lastStoredWidth = clampedStored;

    // Divider drag updates stored width — snap immediately, do not fight the gesture.
    if (!visibilityChanged) {
      setState(() => _animatedWidth = targetWidth);
      return;
    }

    _widthAnimation = Tween<double>(
      begin: _animatedWidth,
      end: targetWidth,
    ).animate(
      CurvedAnimation(
        parent: _revealController,
        curve: Curves.easeOutCubic,
      ),
    );
    _revealController.forward(from: 0);
  }

  @override
  void dispose() {
    _revealController.dispose();
    super.dispose();
  }

  bool get _showDivider => _animatedWidth > 0.5;

  @override
  Widget build(BuildContext context) {
    final layout = context.select<LayoutCubit, (bool, double)>(
      (c) => (
        c.state.preferences.rightToolsVisible,
        c.state.preferences.rightToolsWidth,
      ),
    );
    _applyLayoutTargets(layout.$1, layout.$2);

    final panelWidth = _animatedWidth.clamp(0.0, double.infinity);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final maxPanel = (maxW - RightToolsHost._minCenterWidth)
            .clamp(LayoutPreferences.minRightToolsWidth, maxW);
        final clampedPanel = panelWidth.clamp(0.0, maxPanel);

        return ResizableSplitView(
          axis: Axis.horizontal,
          primaryAtEnd: true,
          first: RepaintBoundary(child: widget.center),
          second: ClipRect(
            child: SizedBox(
              width: clampedPanel,
              child: widget.rightTools,
            ),
          ),
          initialPrimarySize: clampedPanel,
          minPrimarySize:
              _showDivider ? LayoutPreferences.minRightToolsWidth : 0,
          minSecondarySize: RightToolsHost._minCenterWidth,
          maxPrimarySize: _showDivider ? maxPanel : 0,
          dividerThickness: _showDivider ? 1 : 0,
          dividerHitBuffer: _showDivider ? 5 : 0,
          onPrimarySizeChanged: widget.onRightToolsWidthChanged,
        );
      },
    );
  }
}
