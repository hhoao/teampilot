import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../services/app/workspace_search_field_warmup.dart';
import '../utils/yield_ui_frame.dart';

/// Lays out one workspace search [TextField] off-screen under the real
/// [ThemeData] while the boot splash is still visible so [RenderEditable] is
/// warm before interaction. Glyph shaping runs earlier in [UiInteractiveWarmup].
///
/// Waits one frame after [SplashDeferredShell] mounts [HomeShell] so the search
/// field does not share a frame with the first home chrome build.
class UiWarmup extends StatefulWidget {
  const UiWarmup({required this.child, super.key});

  final Widget child;

  @override
  State<UiWarmup> createState() => _UiWarmupState();
}

class _UiWarmupState extends State<UiWarmup> {
  static var _searchFieldWarmed = false;

  var _mountSearchField = false;

  @override
  void initState() {
    super.initState();
    if (_inTest || _searchFieldWarmed) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      unawaited(_warmSearchField());
    });
  }

  Future<void> _warmSearchField() async {
    // Let SplashDeferredShell + HomeShell finish their frame first.
    await yieldUiFrame();
    if (!mounted || _searchFieldWarmed) return;
    setState(() => _mountSearchField = true);
    await yieldUiFrame();
    if (!mounted) return;
    setState(() => _mountSearchField = false);
    _searchFieldWarmed = true;
  }

  static bool get _inTest {
    try {
      return Platform.environment.containsKey('FLUTTER_TEST');
    } on Object {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_mountSearchField) return widget.child;

    return Stack(
      clipBehavior: Clip.hardEdge,
      fit: StackFit.passthrough,
      children: [
        widget.child,
        const Positioned(
          left: -WorkspaceSearchFieldWarmup.fieldWidth - 64,
          top: 0,
          width: WorkspaceSearchFieldWarmup.fieldWidth,
          height: WorkspaceSearchFieldWarmup.fieldHeight,
          child: IgnorePointer(
            child: WorkspaceSearchFieldWarmup(),
          ),
        ),
      ],
    );
  }
}
