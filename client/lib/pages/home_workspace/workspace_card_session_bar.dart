import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/workspace.dart';
import '../../models/workspace_topology.dart';
import '../../theme/app_text_styles.dart';
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
    final styles = AppTextStyles.of(context);
    final topology = workspaceTopologyOf(workspace.folders);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            '$sessionCount $sessionCountLabel',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: styles.bodySmall.copyWith(color: cs.onSurfaceVariant),
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
