import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../cubits/mcp_cubit.dart';
import '../../../../cubits/project_profile_cubit.dart';
import '../../../../l10n/l10n_extensions.dart';
import '../../home_workspace_global_section.dart';
import '../../../team_config/team_config_cards.dart';
import '../../../team_config/team_config_mcp_section.dart';

class ProjectMcpSection extends StatelessWidget {
  const ProjectMcpSection({required this.projectId, super.key});

  final String projectId;

  @override
  Widget build(BuildContext context) {
    final profileState = context.watch<ProjectProfileCubit>().state;
    if (profileState.projectId != projectId ||
        profileState.status == ProjectProfileLoadStatus.loading ||
        profileState.status == ProjectProfileLoadStatus.idle) {
      return const Center(child: CircularProgressIndicator());
    }
    if (profileState.status == ProjectProfileLoadStatus.error) {
      return Center(
        child: Text(profileState.errorMessage ?? 'Failed to load profile'),
      );
    }
    final profile = profileState.profile;
    if (profile == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final l10n = context.l10n;
    void onManage() => context.go(HomeWorkspaceGlobalView.mcp.homeLocation);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    final mcpState = context.watch<McpCubit>().state;
    final enabled = mcpState.servers.where((s) => s.enabled).toList();
    final assignedCount = enabled
        .where((s) => profile.mcpServerIds.contains(s.id))
        .length;
    final cubit = context.read<ProjectProfileCubit>();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TeamConfigCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TeamConfigCardHeader(
                  title: l10n.projectMcpAssignedCount(
                    assignedCount,
                    enabled.length,
                  ),
                  trailing: OutlinedButton.icon(
                    onPressed: onManage,
                    icon: Icon(Icons.hub_outlined),
                    label: Text(l10n.projectMcpManage),
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
                      assigned: profile.mcpServerIds.contains(server.id),
                      onAssignedChanged: (assigned) {
                        final ids = List<String>.from(profile.mcpServerIds);
                        if (assigned) {
                          if (!ids.contains(server.id)) ids.add(server.id);
                        } else {
                          ids.remove(server.id);
                        }
                        cubit.setMcpServerIds(ids);
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
