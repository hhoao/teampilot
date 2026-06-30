import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../services/app/workspace_search_field_warmup.dart';

/// Lays out one workspace search [TextField] off-screen under the real
/// [ThemeData] from the first [MaterialApp] frame (splash cross-fade) so
/// [RenderEditable] is warm before interaction. Glyph shaping runs earlier in
/// [UiInteractiveWarmup] during the boot gate.
class UiWarmup extends StatelessWidget {
  const UiWarmup({required this.child, super.key});

  final Widget child;

  static bool get _inTest {
    try {
      return Platform.environment.containsKey('FLUTTER_TEST');
    } on Object {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_inTest) return child;

    return Stack(
      clipBehavior: Clip.hardEdge,
      fit: StackFit.passthrough,
      children: [
        child,
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
