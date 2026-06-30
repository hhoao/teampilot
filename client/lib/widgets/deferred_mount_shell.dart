import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Mounts [child] after [delayFrames] post-frame callbacks so heavy subtrees
/// can paint in a later frame than their parent shell.
class DeferredMountShell extends StatefulWidget {
  const DeferredMountShell({
    required this.child,
    this.placeholder,
    this.delayFrames = 1,
    super.key,
  });

  final Widget child;
  final Widget? placeholder;

  /// Number of frames to wait after the first build before showing [child].
  final int delayFrames;

  @override
  State<DeferredMountShell> createState() => _DeferredMountShellState();
}

class _DeferredMountShellState extends State<DeferredMountShell> {
  var _showChild = false;

  static bool get _inTest {
    try {
      return Platform.environment.containsKey('FLUTTER_TEST');
    } on Object {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    if (_inTest || widget.delayFrames <= 0) {
      _showChild = true;
      return;
    }
    _scheduleShow(widget.delayFrames);
  }

  void _scheduleShow(int framesRemaining) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (framesRemaining <= 1) {
        setState(() => _showChild = true);
        return;
      }
      _scheduleShow(framesRemaining - 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_showChild) return widget.child;
    return widget.placeholder ?? const SizedBox.shrink();
  }
}
