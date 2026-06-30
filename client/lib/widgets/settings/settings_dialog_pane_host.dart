import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Lazily mounts settings panes on first visit and keeps them alive afterward.
///
/// The active pane defers its first [builder] call by one frame so the dialog
/// chrome can paint before a heavy config subtree builds.
class SettingsDialogPaneHost extends StatefulWidget {
  const SettingsDialogPaneHost({
    required this.paneCount,
    required this.selectedIndex,
    required this.builder,
    super.key,
  });

  final int paneCount;
  final int selectedIndex;
  final Widget Function(BuildContext context, int index) builder;

  @override
  State<SettingsDialogPaneHost> createState() => _SettingsDialogPaneHostState();
}

class _SettingsDialogPaneHostState extends State<SettingsDialogPaneHost> {
  late final List<bool> _visited;
  var _selectionEpoch = 0;

  @override
  void initState() {
    super.initState();
    _visited = List<bool>.filled(widget.paneCount, false)
      ..[widget.selectedIndex] = true;
  }

  @override
  void didUpdateWidget(covariant SettingsDialogPaneHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.paneCount != oldWidget.paneCount) {
      final next = List<bool>.filled(widget.paneCount, false);
      for (var i = 0; i < _visited.length && i < next.length; i++) {
        next[i] = _visited[i];
      }
      _visited
        ..clear()
        ..addAll(next);
    }
    if (widget.selectedIndex != oldWidget.selectedIndex) {
      _selectionEpoch++;
      if (!_visited[widget.selectedIndex]) {
        _visited[widget.selectedIndex] = true;
      }
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: widget.selectedIndex,
      sizing: StackFit.expand,
      children: [
        for (var i = 0; i < widget.paneCount; i++)
          _SettingsLazyPane(
            key: ValueKey('settings-pane-$i'),
            mount: _visited[i],
            deferFirstBuild: i == widget.selectedIndex,
            isActive: i == widget.selectedIndex,
            sectionAnimationKey: i == widget.selectedIndex
                ? ValueKey('settings-section-$i-$_selectionEpoch')
                : null,
            builder: (context) => widget.builder(context, i),
          ),
      ],
    );
  }
}

class _SettingsLazyPane extends StatefulWidget {
  const _SettingsLazyPane({
    required this.mount,
    required this.deferFirstBuild,
    required this.isActive,
    required this.sectionAnimationKey,
    required this.builder,
    super.key,
  });

  final bool mount;
  final bool deferFirstBuild;
  final bool isActive;
  final Key? sectionAnimationKey;
  final WidgetBuilder builder;

  @override
  State<_SettingsLazyPane> createState() => _SettingsLazyPaneState();
}

class _SettingsLazyPaneState extends State<_SettingsLazyPane>
    with AutomaticKeepAliveClientMixin {
  var _contentReady = false;
  var _builtOnce = false;

  @override
  bool get wantKeepAlive => _builtOnce;

  @override
  void initState() {
    super.initState();
    _maybeScheduleContent();
  }

  @override
  void didUpdateWidget(covariant _SettingsLazyPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.mount && !_contentReady) {
      _maybeScheduleContent();
    }
  }

  void _maybeScheduleContent() {
    if (!widget.mount || _contentReady) return;
    if (!widget.deferFirstBuild) {
      _markContentReady();
      return;
    }
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _contentReady) return;
      _markContentReady();
    });
  }

  void _markContentReady() {
    setState(() {
      _contentReady = true;
      _builtOnce = true;
    });
    updateKeepAlive();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!widget.mount || !_contentReady) {
      return const SizedBox.expand();
    }
    final content = widget.builder(context);
    if (!widget.isActive || widget.sectionAnimationKey == null) {
      return content;
    }
    return content
        .animate(key: widget.sectionAnimationKey)
        .fadeIn(duration: 180.ms, curve: Curves.easeOut)
        .slideX(
          begin: 0.025,
          end: 0,
          duration: 220.ms,
          curve: Curves.easeOutCubic,
        );
  }
}
