import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/workspace.dart';
import '../../models/workspace_topology.dart';
import '../../widgets/workspace_topology_icon.dart';
import 'open_workspace_tab_actions.dart';

/// Session count row for workspace cards; optional topology glyph.
class WorkspaceCardSessionBar extends StatelessWidget {
  const WorkspaceCardSessionBar({
    required this.sessionCount,
    required this.sessionCountLabel,
    required this.workspace,
    this.showContextIcon = false,
    super.key,
  });

  final int sessionCount;
  final String sessionCountLabel;
  final Workspace workspace;
  final bool showContextIcon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final topology = workspaceTopologyOf(workspace.folders);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            '$sessionCount $sessionCountLabel',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: styles.smColored(cs.onSurfaceVariant),
          ),
        ),
        if (showContextIcon) ...[
          const SizedBox(width: 8),
          Tooltip(
            message: workspaceTopologyLabel(context.l10n, topology),
            child: WorkspaceTopologyIcon(topology: topology),
          ),
        ],
      ],
    );
  }
}
