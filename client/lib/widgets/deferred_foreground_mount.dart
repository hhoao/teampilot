import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Defers [builder] until the frame after [active] becomes true so heavy
/// children (e.g. Alacritty) do not share the tab-switch frame.
///
/// When [retainWhenInactive] is true, the child stays mounted after the first
/// show even if [active] becomes false — callers should hide it with [Offstage].
class DeferredForegroundMount extends StatefulWidget {
  const DeferredForegroundMount({
    required this.active,
    required this.builder,
    this.placeholder,
    this.retainWhenInactive = false,
    super.key,
  });

  final bool active;
  final WidgetBuilder builder;
  final Widget? placeholder;

  /// Keep [builder] mounted after the first show when [active] goes false.
  final bool retainWhenInactive;

  @override
  State<DeferredForegroundMount> createState() =>
      _DeferredForegroundMountState();
}

class _DeferredForegroundMountState extends State<DeferredForegroundMount> {
  var _showChild = false;

  @override
  void initState() {
    super.initState();
    if (widget.active) {
      _scheduleShow();
    }
  }

  @override
  void didUpdateWidget(covariant DeferredForegroundMount oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.active) {
      if (!widget.retainWhenInactive) {
        _showChild = false;
      }
      return;
    }
    if (!oldWidget.active && !_showChild) {
      _scheduleShow();
    }
  }

  void _scheduleShow() {
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      if (!mounted || !widget.active || _showChild) return;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !widget.active) return;
        setState(() => _showChild = true);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_showChild) {
      return widget.placeholder ?? const SizedBox.expand();
    }
    return widget.builder(context);
  }
}
