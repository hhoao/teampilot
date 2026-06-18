import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../cubits/mcp_cubit.dart';
import '../../cubits/identity_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/mcp_server.dart';
import '../../models/team_config.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/settings/workspace_settings_widgets.dart';
import 'team_config_cards.dart';

class TeamMcpSection extends StatelessWidget {
  const TeamMcpSection({
    super.key,
    required this.team,
    required this.cubit,
    this.onManageGlobal,
  });

  final TeamIdentity team;
  final IdentityCubit cubit;

  /// Opens global MCP management. When null, falls back to the v1 `/mcp`
  /// route so this section stays usable outside the v2 workspace.
  final VoidCallback? onManageGlobal;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final onManage = onManageGlobal ?? () => context.go('/mcp');
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    final mcpState = context.watch<McpCubit>().state;
    final enabled = mcpState.servers.where((s) => s.enabled).toList();
    final assignedCount = enabled
        .where((s) => team.mcpServerIds.contains(s.id))
        .length;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TeamConfigCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TeamConfigCardHeader(
                  title: l10n.teamMcpAssignedCount(
                    assignedCount,
                    enabled.length,
                  ),
                  trailing: OutlinedButton.icon(
                    onPressed: onManage,
                    icon: Icon(Icons.hub_outlined, size: context.appIconSizes.md),
                    label: Text(l10n.teamMcpManage),
                  ),
                ),
                const SizedBox(height: 14),
                if (enabled.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        l10n.mcpEmpty,
                        style: TextStyle(
                          color: textBase.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  )
                else
                  for (final server in enabled)
                    TeamMcpRow(
                      server: server,
                      assigned: team.mcpServerIds.contains(server.id),
                      onAssignedChanged: (assigned) {
                        final ids = List<String>.from(team.mcpServerIds);
                        if (assigned) {
                          if (!ids.contains(server.id)) ids.add(server.id);
                        } else {
                          ids.remove(server.id);
                        }
                        cubit.updateSelected(team.copyWith(mcpServerIds: ids));
                      },
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class TeamMcpRow extends StatelessWidget {
  const TeamMcpRow({super.key, 
    required this.server,
    required this.assigned,
    required this.onAssignedChanged,
  });

  final McpServer server;
  final bool assigned;
  final ValueChanged<bool> onAssignedChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: workspaceInsetDecoration(cs, radius: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    server.name,
                    style: AppTextStyles.of(
                      context,
                    ).body.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    server.server['type']?.toString() ?? 'stdio',
                    style: AppTextStyles.of(context).bodySmall.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            Switch(value: assigned, onChanged: onAssignedChanged),
          ],
        ),
      ),
    );
  }
}
