import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';

import '../models/workspace_topology.dart';
import '../theme/workspace_topology_colors.dart';

/// Topology glyph (local / remote / mixed) using shared accent colors.
class WorkspaceTopologyIcon extends StatelessWidget {
  const WorkspaceTopologyIcon({
    required this.topology,
    this.size,
    super.key,
  });

  final WorkspaceTopology topology;
  final double? size;

  static IconData iconFor(WorkspaceTopology topology) {
    return switch (topology) {
      WorkspaceTopology.local => Icons.computer_outlined,
      WorkspaceTopology.remote => Icons.dns_outlined,
      WorkspaceTopology.mixed => Icons.hub_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = WorkspaceTopologyColors.of(
      topology: topology,
      colorScheme: theme.colorScheme,
      brightness: theme.brightness,
    );
    return Icon(
      iconFor(topology),
      size: size ?? context.appIconSizes.sm,
      color: color,
    );
  }
}
