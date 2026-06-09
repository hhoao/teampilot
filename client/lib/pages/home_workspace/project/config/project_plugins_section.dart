import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../cubits/plugin_cubit.dart';
import '../../../../cubits/project_profile_cubit.dart';
import '../../../../l10n/l10n_extensions.dart';
import '../../home_workspace_global_section.dart';
import '../../../team_config/team_config_cards.dart';
import '../../../team_config/team_config_plugins_section.dart';

class ProjectPluginsSection extends StatelessWidget {
  const ProjectPluginsSection({required this.projectId, super.key});

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
    void onManage() =>
        context.go(HomeWorkspaceGlobalView.plugins.homeLocation);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    final pluginState = context.watch<PluginCubit>().state;
    final syncing = profileState.isSyncingPlugins;
    final installed = pluginState.installed;
    final assignedCount = installed
        .where((p) => profile.pluginIds.contains(p.id))
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
                  title: l10n.projectPluginsAssignedCount(
                    assignedCount,
                    installed.length,
                  ),
                  trailing: OutlinedButton.icon(
                    onPressed: onManage,
                    icon: const Icon(Icons.widgets_outlined),
                    label: Text(l10n.projectPluginsManage),
                  ),
                ),
                if (syncing) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
                const SizedBox(height: 14),
                if (installed.isEmpty)
                  TeamPluginsEmptyBlock(
                    textBase: textBase,
                    onGoPlugins: onManage,
                    emptyTitle: l10n.projectPluginsEmpty,
                    emptyHint: l10n.projectPluginsEmptyHint,
                    actionLabel: l10n.projectPluginsManage,
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final plugin in installed)
                        TeamPluginRow(
                          plugin: plugin,
                          assigned: profile.pluginIds.contains(plugin.id),
                          onAssignedChanged: (assigned) {
                            final ids = List<String>.from(profile.pluginIds);
                            if (assigned) {
                              if (!ids.contains(plugin.id)) ids.add(plugin.id);
                            } else {
                              ids.remove(plugin.id);
                            }
                            cubit.setPluginIds(ids);
                          },
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
