import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../cubits/plugin_cubit.dart';
import '../../cubits/team_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/plugin.dart';
import '../../models/team_config.dart';
import '../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/github_source_url.dart';
import '../../widgets/github_details_button.dart';
import '../../widgets/settings/workspace_settings_widgets.dart';
import 'team_config_cards.dart';

class TeamPluginsSection extends StatelessWidget {
  const TeamPluginsSection({super.key, required this.team, required this.cubit});

  final TeamConfig team;
  final TeamCubit cubit;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    final pluginState = context.watch<PluginCubit>().state;
    final teamState = context.watch<TeamCubit>().state;
    final syncing = teamState.isSyncingPlugins;
    final conflicts = teamState.pluginSyncConflicts;
    final installed = pluginState.installed;
    final installedIds = installed.map((p) => p.id).toSet();
    final missingIds = team.pluginIds
        .where((id) => !installedIds.contains(id))
        .toList(growable: false);
    final assignedCount = installed
        .where((p) => team.pluginIds.contains(p.id))
        .length;
    final teamToolDef = CliToolRegistryScope.maybeOf(
      context,
    )?.tryGet(team.cli.value);
    final codexUnsupported = teamToolDef?.isLaunchSupported == false;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (codexUnsupported)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TeamConfigCard(
                child: Text(
                  l10n.teamPluginsCliUnsupportedBanner,
                  style: AppTextStyles.of(
                    context,
                  ).body.copyWith(color: textBase.withValues(alpha: 0.6)),
                ),
              ),
            ),
          TeamConfigCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TeamConfigCardHeader(
                  title: l10n.teamPluginsAssignedCount(
                    assignedCount,
                    installed.length,
                  ),
                  trailing: OutlinedButton.icon(
                    onPressed: () => context.go('/plugins'),
                    icon: const Icon(Icons.widgets_outlined, size: AppIconSizes.md),
                    label: Text(l10n.teamPluginsManage),
                  ),
                ),
                if (syncing) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
                if (missingIds.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.errorContainer.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      l10n.teamPluginsMissing(missingIds.length),
                      style: AppTextStyles.of(context).bodySmall.copyWith(
                        color: textBase.withValues(alpha: 0.75),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                if (installed.isEmpty && missingIds.isEmpty)
                  TeamPluginsEmptyBlock(
                    textBase: textBase,
                    onGoPlugins: () => context.go('/plugins/discovery'),
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final plugin in installed)
                        TeamPluginRow(
                          plugin: plugin,
                          assigned: team.pluginIds.contains(plugin.id),
                          conflictDir: conflicts[plugin.id],
                          onAssignedChanged: (assigned) {
                            final ids = List<String>.from(team.pluginIds);
                            if (assigned) {
                              if (!ids.contains(plugin.id)) ids.add(plugin.id);
                            } else {
                              ids.remove(plugin.id);
                            }
                            cubit.updateSelected(team.copyWith(pluginIds: ids));
                          },
                        ),
                      for (final id in missingIds)
                        TeamMissingPluginRow(
                          pluginId: id,
                          onRemove: () {
                            final ids = List<String>.from(team.pluginIds)
                              ..remove(id);
                            cubit.updateSelected(team.copyWith(pluginIds: ids));
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

class TeamPluginsEmptyBlock extends StatelessWidget {
  const TeamPluginsEmptyBlock({super.key, 
    required this.textBase,
    required this.onGoPlugins,
  });

  final Color textBase;
  final VoidCallback onGoPlugins;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: AppIconSizes.md,
            color: textBase.withValues(alpha: 0.35),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.teamPluginsEmpty,
            style: AppTextStyles.of(
              context,
            ).body.copyWith(fontWeight: FontWeight.w700, color: textBase),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.teamPluginsEmptyHint,
            textAlign: TextAlign.center,
            style: AppTextStyles.of(
              context,
            ).bodySmall.copyWith(color: textBase.withValues(alpha: 0.55)),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: onGoPlugins,
            icon: const Icon(Icons.search, size: AppIconSizes.md),
            label: Text(l10n.teamPluginsGoDiscovery),
          ),
        ],
      ),
    );
  }
}

class TeamPluginRow extends StatelessWidget {
  const TeamPluginRow({super.key, 
    required this.plugin,
    required this.assigned,
    required this.onAssignedChanged,
    this.conflictDir,
  });

  final Plugin plugin;
  final bool assigned;
  final ValueChanged<bool> onAssignedChanged;
  final String? conflictDir;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    final sourceLabel =
        plugin.marketplaceOwner != null && plugin.marketplaceName != null
        ? '${plugin.marketplaceOwner}/${plugin.marketplaceName}'
        : 'local';

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
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          plugin.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.of(context).body.copyWith(
                            fontWeight: FontWeight.w700,
                            color: textBase,
                          ),
                        ),
                      ),
                      if (plugin.version.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(
                          'v${plugin.version}',
                          style: AppTextStyles.of(context).caption.copyWith(
                            fontWeight: FontWeight.w600,
                            color: textBase.withValues(alpha: 0.55),
                          ),
                        ),
                      ],
                      const SizedBox(width: 8),
                      Text(
                        sourceLabel,
                        style: AppTextStyles.of(context).caption.copyWith(
                          color: textBase.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                  if (plugin.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      plugin.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.of(context).bodySmall.copyWith(
                        color: textBase.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                  if (conflictDir != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: AppIconSizes.md,
                          color: cs.tertiary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            l10n.teamPluginsNameConflict(conflictDir!),
                            style: AppTextStyles.of(context).caption.copyWith(
                              color: textBase.withValues(alpha: 0.65),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            GithubDetailsButton(
              url: plugin.githubBrowseUrl,
              label: l10n.pluginsCardDetails,
            ),
            const SizedBox(width: 8),
            Switch(value: assigned, onChanged: onAssignedChanged),
          ],
        ),
      ),
    );
  }
}

class TeamMissingPluginRow extends StatelessWidget {
  const TeamMissingPluginRow({super.key, required this.pluginId, required this.onRemove});

  final String pluginId;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: workspaceInsetDecoration(
          cs,
          radius: 10,
        ).copyWith(color: cs.surfaceContainerHighest.withValues(alpha: 0.35)),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pluginId,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.of(context).body.copyWith(
                      fontWeight: FontWeight.w600,
                      color: textBase.withValues(alpha: 0.55),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.teamPluginsMissingLabel,
                    style: AppTextStyles.of(
                      context,
                    ).caption.copyWith(color: cs.error.withValues(alpha: 0.85)),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: onRemove,
              child: Text(l10n.teamPluginsRemoveMissing),
            ),
          ],
        ),
      ),
    );
  }
}
