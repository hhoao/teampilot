import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../cubits/plugin_cubit.dart';
import '../../../../cubits/workspace_project_config_cubit.dart';
import '../../../../l10n/l10n_extensions.dart';
import '../../home_workspace_global_section.dart';
import '../../../team_config/team_config_cards.dart';
import '../../../team_config/team_config_plugins_section.dart';
import 'package:shared_ui/shared_ui.dart';

class WorkspacePluginsSection extends StatelessWidget {
  const WorkspacePluginsSection({required this.workspaceId, super.key});

  final String workspaceId;

  @override
  Widget build(BuildContext context) {
    final projectState = context.watch<WorkspaceProjectConfigCubit>().state;
    if (projectState.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final l10n = context.l10n;
    void onManage() => context.go(HomeGlobalView.plugins.homeLocation);
    final installed = context.watch<PluginCubit>().state.installed;
    final pluginIds = projectState.config.bundle.pluginIds;
    final assignedCount = installed
        .where((p) => pluginIds.contains(p.id))
        .length;
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
                  TpEmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: l10n.workspacePluginsEmpty,
                    hint: l10n.workspacePluginsEmptyHint,
                    actionLabel: l10n.workspacePluginsManage,
                    onAction: onManage,
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
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
                              projectCubit.updateBundle(
                                projectState.config.bundle.copyWith(
                                  pluginIds: List<String>.unmodifiable(ids),
                                ),
                              ),
                            );
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
