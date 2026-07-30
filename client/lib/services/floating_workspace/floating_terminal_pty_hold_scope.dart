import 'package:flutter/material.dart';

import '../../widgets/workspace_terminal_panel.dart';

/// Provides a [WorkspaceTerminalHoldHandle] for floating shell terminals so the
/// panel can bracket PTY resizes while its edge handles are dragged.
class FloatingTerminalPtyHoldScope extends InheritedWidget {
  const FloatingTerminalPtyHoldScope({
    required this.holdHandle,
    required super.child,
    super.key,
  });

  final WorkspaceTerminalHoldHandle holdHandle;

  static WorkspaceTerminalHoldHandle? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<FloatingTerminalPtyHoldScope>()
        ?.holdHandle;
  }

  @override
  bool updateShouldNotify(FloatingTerminalPtyHoldScope oldWidget) =>
      !identical(holdHandle, oldWidget.holdHandle);
}
