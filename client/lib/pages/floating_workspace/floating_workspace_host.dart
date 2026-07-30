import 'package:flutter/material.dart';

import 'floating_workspace_panel.dart';
import 'floating_workspace_toggle.dart';

/// Stacks the floating workspace panel + toggle above [child] (HomeShell body).
///
/// Z-order: [child] → panel → toggle (toggle on top).
class FloatingWorkspaceHost extends StatelessWidget {
  const FloatingWorkspaceHost({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        const FloatingWorkspacePanel(),
        const FloatingWorkspaceToggle(),
      ],
    );
  }
}
