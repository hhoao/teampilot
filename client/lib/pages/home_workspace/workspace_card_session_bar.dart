import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/launch_profile.dart';
import '../../models/launch_profile_ref.dart';
import '../../models/workspace.dart';
import '../../models/workspace_topology.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/workspace_topology_icon.dart';
import 'home_workspace_title_bar.dart';
import 'open_workspace_tab_actions.dart';

/// Session count row for workspace cards; optional identity/topology glyph.
class WorkspaceCardSessionBar extends StatelessWidget {
  const WorkspaceCardSessionBar({
    required this.sessionCount,
    required this.sessionCountLabel,
    required this.workspace,
    this.tabIdentity,
    this.launchProfiles = const [],
    this.showContextIcon = false,
    this.topologyIconOnly = false,
    super.key,
  });

  final int sessionCount;
  final String sessionCountLabel;
  final Workspace workspace;
  final LaunchProfileRef? tabIdentity;
  final List<LaunchProfile> launchProfiles;
  final bool showContextIcon;

  /// When true, shows [WorkspaceTopologyIcon] instead of identity-shaped glyph.
  final bool topologyIconOnly;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final topology = workspaceTopologyOf(workspace.folders);
    final showIcon = showContextIcon &&
        (topologyIconOnly || launchProfiles.isNotEmpty);

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
        if (showIcon) ...[
          const SizedBox(width: 8),
          topologyIconOnly
              ? _TopologyOnlyIcon(topology: topology)
              : _SessionContextIcon(
                  workspace: workspace,
                  identity: tabIdentity ?? workspaceCardDisplayIdentity(workspace),
                  launchProfiles: launchProfiles,
                ),
        ],
      ],
    );
  }
}

class _TopologyOnlyIcon extends StatelessWidget {
  const _TopologyOnlyIcon({required this.topology});

  final WorkspaceTopology topology;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Tooltip(
      message: workspaceTopologyLabel(l10n, topology),
      child: WorkspaceTopologyIcon(topology: topology),
    );
  }
}

class _SessionContextIcon extends StatelessWidget {
  const _SessionContextIcon({
    required this.workspace,
    required this.identity,
    required this.launchProfiles,
  });

  final Workspace workspace;
  final LaunchProfileRef identity;
  final List<LaunchProfile> launchProfiles;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final topology = workspaceTopologyOf(workspace.folders);
    final kind = workspaceTabKindForIdentity(
      identity: identity,
      identities: launchProfiles,
    );
    final identityLabel = workspaceTabIdentityLabel(
      l10n: l10n,
      identity: identity,
      identities: launchProfiles,
    );
    final topologyLabel = workspaceTopologyLabel(l10n, topology);
    final iconSize = context.appIconSizes.sm;

    return Tooltip(
      message: '$identityLabel · $topologyLabel',
      child: WorkspaceTabKindTopologyIcon(
        kind: kind,
        topology: topology,
        colorScheme: cs,
        brightness: Theme.of(context).brightness,
        size: iconSize,
      ),
    );
  }
}
