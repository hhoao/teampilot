import 'package:flutter/material.dart';

import '../l10n/l10n_extensions.dart';
import '../models/workspace_topology.dart';
import '../theme/workspace_topology_colors.dart';

/// Read-only badge for [WorkspaceTopology.local], [remote], or [mixed].
class WorkspaceTopologyChip extends StatelessWidget {
  const WorkspaceTopologyChip({
    required this.topology,
    this.compact = false,
    super.key,
  });

  final WorkspaceTopology topology;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tt = Theme.of(context).textTheme;
    final color = WorkspaceTopologyColors.of(
      topology: topology,
      colorScheme: Theme.of(context).colorScheme,
      brightness: Theme.of(context).brightness,
    );
    final (label, icon) = switch (topology) {
      WorkspaceTopology.local => (
        l10n.workspaceTopologyLocal,
        Icons.computer_outlined,
      ),
      WorkspaceTopology.remote => (
        l10n.workspaceTopologyRemote,
        Icons.dns_outlined,
      ),
      WorkspaceTopology.mixed => (
        l10n.workspaceTopologyMixed,
        Icons.hub_outlined,
      ),
    };
    final iconSize = compact ? 14.0 : 18.0;
    final labelStyle = compact
        ? tt.labelSmall?.copyWith(color: color)
        : tt.labelLarge?.copyWith(color: color);
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: iconSize, color: color),
        SizedBox(width: compact ? 4 : 6),
        Text(label, style: labelStyle),
      ],
    );
    if (compact) {
      return content;
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: WorkspaceTopologyColors.borderAlpha(color),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: content,
      ),
    );
  }
}
