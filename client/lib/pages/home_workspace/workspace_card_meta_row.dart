import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/workspace.dart';
import '../../models/workspace_topology.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/workspace_topology_chip.dart';

/// Primary directory label + workspace topology badge for home workspace tiles.
class WorkspaceCardMetaRow extends StatelessWidget {
  const WorkspaceCardMetaRow({
    required this.workspace,
    this.showTopologyChip = true,
    super.key,
  });

  final Workspace workspace;
  final bool showTopologyChip;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final hasPrimary = workspace.firstFolderPath.isNotEmpty;
    final primaryLabel = hasPrimary
        ? workspace.firstFolderPath
        : l10n.workspacePrimaryPathNotSelected;

    return Row(
      children: [
        Expanded(
          child: Text(
            primaryLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: styles.bodySmall.copyWith(
              color: hasPrimary
                  ? cs.onSurfaceVariant
                  : cs.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ),
        if (showTopologyChip) ...[
          const SizedBox(width: 8),
          WorkspaceTopologyChip(
            topology: workspaceTopologyOf(workspace.folders),
            compact: true,
          ),
        ],
      ],
    );
  }
}
