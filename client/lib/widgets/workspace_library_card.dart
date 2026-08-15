import 'package:flutter/material.dart';

import '../theme/workspace_surface_layers.dart';

/// Shared bordered card shell for library management pages (Skills, Plugins,
/// MCP, Extensions, Hooks): fixed outer bottom margin + inner padding.
class WorkspaceLibraryCard extends StatelessWidget {
  const WorkspaceLibraryCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: workspaceCardDecoration(cs, radius: 12),
      child: child,
    );
  }
}
