import 'package:flutter/material.dart';

import '../l10n/l10n_extensions.dart';
import '../models/workspace_topology.dart';

/// Read-only badge for [WorkspaceTopology.local], [remote], or [mixed].
class WorkspaceTopologyChip extends StatelessWidget {
  const WorkspaceTopologyChip({required this.topology, super.key});

  final WorkspaceTopology topology;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tt = Theme.of(context).textTheme;
    final (label, icon, color) = switch (topology) {
      WorkspaceTopology.local => (
        l10n.workspaceTopologyLocal,
        Icons.computer_outlined,
        Theme.of(context).colorScheme.primary,
      ),
      WorkspaceTopology.remote => (
        l10n.workspaceTopologyRemote,
        Icons.dns_outlined,
        Theme.of(context).colorScheme.tertiary,
      ),
      WorkspaceTopology.mixed => (
        l10n.workspaceTopologyMixed,
        Icons.hub_outlined,
        Theme.of(context).colorScheme.secondary,
      ),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: tt.labelLarge?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}
