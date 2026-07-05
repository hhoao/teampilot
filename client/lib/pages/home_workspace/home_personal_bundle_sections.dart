import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../cubits/launch_profile_cubit.dart';
import '../../cubits/mcp_cubit.dart';
import '../../cubits/plugin_cubit.dart';
import '../../cubits/skill_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/personal_profile.dart';
import 'home_workspace_global_section.dart';
import '../../widgets/empty_state_block.dart';
import '../team_config/team_config_cards.dart';
import '../team_config/team_config_mcp_section.dart';
import '../team_config/team_config_plugins_section.dart';
import '../team_config/team_config_skills_section.dart';

class HomePersonalSkillsSection extends StatelessWidget {
  const HomePersonalSkillsSection({required this.profileId, super.key});

  final String profileId;

  @override
  Widget build(BuildContext context) {
    final identityCubit = context.watch<LaunchProfileCubit>();
    final personal = identityCubit.byId(profileId);
    if (personal is! PersonalProfile) {
      return const Center(child: CircularProgressIndicator());
    }

    final l10n = context.l10n;
    void onManage() => context.go(HomeGlobalView.skills.homeLocation);
    final enabled = context.watch<SkillCubit>().state.installed
        .where((s) => s.enabled)
        .toList(growable: false);
    final skillIds = personal.bundle.skillIds;
    final assignedCount = enabled.where((s) => skillIds.contains(s.id)).length;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TeamConfigCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TeamConfigCardHeader(
                  title: l10n.workspaceSkillsAssignedCount(
                    assignedCount,
                    enabled.length,
                  ),
                  trailing: OutlinedButton.icon(
                    onPressed: onManage,
                    icon: Icon(Icons.extension_outlined),
                    label: Text(l10n.workspaceSkillsManage),
                  ),
                ),
                const SizedBox(height: 14),
                if (enabled.isEmpty)
                  EmptyStateBlock(
                    icon: Icons.inventory_2_outlined,
                    title: l10n.skillsNoInstalled,
                    hint: l10n.skillsNoInstalledHint,
                    actionLabel: l10n.workspaceSkillsManage,
                    onAction: onManage,
                  )
                else
                  for (final skill in enabled)
                    TeamSkillRow(
                      skill: skill,
                      assigned: skillIds.contains(skill.id),
                      onAssignedChanged: (assigned) {
                        final ids = List<String>.from(skillIds);
                        if (assigned) {
                          if (!ids.contains(skill.id)) ids.add(skill.id);
                        } else {
                          ids.remove(skill.id);
                        }
                        unawaited(
                          identityCubit.savePersonal(
                            personal.copyWith(
                              bundle: personal.bundle.copyWith(
                                skillIds: List<String>.unmodifiable(ids),
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

class HomePersonalPluginsSection extends StatelessWidget {
  const HomePersonalPluginsSection({required this.profileId, super.key});

  final String profileId;

  @override
  Widget build(BuildContext context) {
    final identityCubit = context.watch<LaunchProfileCubit>();
    final personal = identityCubit.byId(profileId);
    if (personal is! PersonalProfile) {
      return const Center(child: CircularProgressIndicator());
    }

    final l10n = context.l10n;
    void onManage() => context.go(HomeGlobalView.plugins.homeLocation);
    final installed = context.watch<PluginCubit>().state.installed;
    final pluginIds = personal.bundle.pluginIds;
    final assignedCount = installed
        .where((p) => pluginIds.contains(p.id))
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
                  title: l10n.workspacePluginsAssignedCount(
                    assignedCount,
                    installed.length,
                  ),
                  trailing: OutlinedButton.icon(
                    onPressed: onManage,
                    icon: Icon(Icons.widgets_outlined),
                    label: Text(l10n.workspacePluginsManage),
                  ),
                ),
                const SizedBox(height: 14),
                if (installed.isEmpty)
                  EmptyStateBlock(
                    icon: Icons.inventory_2_outlined,
                    title: l10n.workspacePluginsEmpty,
                    hint: l10n.workspacePluginsEmptyHint,
                    actionLabel: l10n.workspacePluginsManage,
                    onAction: onManage,
                  )
                else
                  for (final plugin in installed)
                    TeamPluginRow(
                      plugin: plugin,
                      assigned: pluginIds.contains(plugin.id),
                      onAssignedChanged: (assigned) {
                        final ids = List<String>.from(pluginIds);
                        if (assigned) {
                          if (!ids.contains(plugin.id)) ids.add(plugin.id);
                        } else {
                          ids.remove(plugin.id);
                        }
                        unawaited(
                          identityCubit.savePersonal(
                            personal.copyWith(
                              bundle: personal.bundle.copyWith(
                                pluginIds: List<String>.unmodifiable(ids),
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

class HomePersonalMcpSection extends StatelessWidget {
  const HomePersonalMcpSection({required this.profileId, super.key});

  final String profileId;

  @override
  Widget build(BuildContext context) {
    final identityCubit = context.watch<LaunchProfileCubit>();
    final personal = identityCubit.byId(profileId);
    if (personal is! PersonalProfile) {
      return const Center(child: CircularProgressIndicator());
    }

    final l10n = context.l10n;
    void onManage() => context.go(HomeGlobalView.mcp.homeLocation);
    final enabled = context.watch<McpCubit>().state.servers
        .where((s) => s.enabled)
        .toList();
    final mcpIds = personal.bundle.mcpServerIds;
    final assignedCount = enabled.where((s) => mcpIds.contains(s.id)).length;

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
                  EmptyStateBlock(
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
