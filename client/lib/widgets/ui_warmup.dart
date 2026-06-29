import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../services/app/workspace_search_field_warmup.dart';
import '../utils/yield_ui_frame.dart';

/// Formerly warmed fonts, glyphs, and the terminal engine on the first main-ui
/// frame (blocking interaction). Glyph + terminal work runs in [UiInteractiveWarmup]
/// during the boot gate; this widget lays out one workspace search [TextField] on
/// the first post-frame pass under the real [ThemeData].
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
    SchedulerBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _searchFieldWarmed) return;
      setState(() => _mountSearchField = true);
      await yieldUiFrame();
      if (!mounted) return;
      setState(() => _mountSearchField = false);
      _searchFieldWarmed = true;
    });
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
