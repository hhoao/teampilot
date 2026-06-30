import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Defers [child] until the frame after first build so [MaterialApp] + router
/// gates can paint once under the boot splash before [HomeShell] mounts.
class SplashDeferredShell extends StatefulWidget {
  const SplashDeferredShell({required this.child, super.key});

  final Widget child;

  @override
  State<SplashDeferredShell> createState() => _SplashDeferredShellState();
}

class _SplashDeferredShellState extends State<SplashDeferredShell> {
  static var _shellDeferredForSession = false;

  var _showChild = _shellDeferredForSession;

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
    if (_inTest) {
      _showChild = true;
      return;
    }
    if (_showChild) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _shellDeferredForSession = true;
      setState(() => _showChild = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_inTest || _showChild) return widget.child;
    return ColoredBox(color: Theme.of(context).colorScheme.surface);
  }
}
