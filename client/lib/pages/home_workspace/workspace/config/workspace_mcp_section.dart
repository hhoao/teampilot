import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../cubits/mcp_cubit.dart';
import '../../../../cubits/workspace_project_config_cubit.dart';
import '../../../../l10n/l10n_extensions.dart';
import '../../home_workspace_global_section.dart';
import '../../../team_config/team_config_cards.dart';
import '../../../team_config/team_config_mcp_section.dart';
import 'package:shared_ui/shared_ui.dart';

class WorkspaceMcpSection extends StatelessWidget {
  const WorkspaceMcpSection({required this.workspaceId, super.key});

  final String workspaceId;

  @override
  Widget build(BuildContext context) {
    final projectState = context.watch<WorkspaceProjectConfigCubit>().state;
    if (projectState.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final l10n = context.l10n;
    void onManage() => context.go(HomeGlobalView.mcp.homeLocation);
    final enabled = context.watch<McpCubit>().state.servers
        .where((s) => s.enabled)
        .toList();
    final mcpIds = projectState.config.bundle.mcpServerIds;
    final assignedCount = enabled.where((s) => mcpIds.contains(s.id)).length;
    final projectCubit = context.read<WorkspaceProjectConfigCubit>();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TeamConfigCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TeamConfigCardHeader(
                  title: l10n.workspaceMcpAssignedCount(
                    assignedCount,
                    enabled.length,
                  ),
                  trailing: OutlinedButton.icon(
                    onPressed: onManage,
                    icon: Icon(Icons.hub_outlined),
                    label: Text(l10n.workspaceMcpManage),
                  ),
                ),
                const SizedBox(height: 14),
                if (enabled.isEmpty)
                  TpEmptyState(
                    icon: Icons.dns_outlined,
                    title: l10n.mcpNoInstalled,
                    hint: l10n.mcpNoInstalledHint,
                    actionLabel: l10n.workspaceMcpManage,
                    onAction: onManage,
                  )
                else
                  for (final server in enabled)
                    TeamMcpRow(
                      server: server,
                      assigned: mcpIds.contains(server.id),
                      onAssignedChanged: (assigned) {
                        final ids = List<String>.from(mcpIds);
                        if (assigned) {
                          if (!ids.contains(server.id)) ids.add(server.id);
                        } else {
                          ids.remove(server.id);
                        }
                        unawaited(
                          projectCubit.updateBundle(
                            projectState.config.bundle.copyWith(
                              mcpServerIds: List<String>.unmodifiable(ids),
                            ),
                          ),
                        );
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
