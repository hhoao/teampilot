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
    return Chip(
      avatar: Icon(icon, size: 18, color: color),
      label: Text(label),
      side: BorderSide(color: color.withValues(alpha: 0.4)),
      visualDensity: VisualDensity.compact,
    );
  }
}
