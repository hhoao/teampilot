import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../cubits/identity_cubit.dart';
import '../../../../cubits/mcp_cubit.dart';
import '../../../../l10n/l10n_extensions.dart';
import '../../../../models/personal_identity.dart';
import '../../home_workspace_global_section.dart';
import '../../../team_config/team_config_cards.dart';
import '../../../team_config/team_config_mcp_section.dart';

class ProjectMcpSection extends StatelessWidget {
  const ProjectMcpSection({
    required this.projectId,
    required this.identityId,
    super.key,
  });

  final String projectId;
  final String identityId;

  @override
  Widget build(BuildContext context) {
    final identityCubit = context.watch<IdentityCubit>();
    final personal = identityCubit.byId(identityId);
    if (personal is! PersonalIdentity) {
      return const Center(child: CircularProgressIndicator());
    }

    final l10n = context.l10n;
    void onManage() => context.go(HomeGlobalView.mcp.homeLocation);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    final mcpState = context.watch<McpCubit>().state;
    final enabled = mcpState.servers.where((s) => s.enabled).toList();
    final mcpIds = personal.bundle.mcpServerIds;
    final assignedCount =
        enabled.where((s) => mcpIds.contains(s.id)).length;

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
                      assigned: mcpIds.contains(server.id),
                      onAssignedChanged: (assigned) {
                        final ids = List<String>.from(mcpIds);
                        if (assigned) {
                          if (!ids.contains(server.id)) ids.add(server.id);
                        } else {
                          ids.remove(server.id);
                        }
                        unawaited(
                          identityCubit.savePersonal(
                            personal.copyWith(
                              bundle: personal.bundle.copyWith(
                                mcpServerIds: List<String>.unmodifiable(ids),
                              ),
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
