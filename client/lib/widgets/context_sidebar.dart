import 'package:flutter/material.dart';

import '../utils/app_keys.dart';
import '../controllers/config_controller.dart';
import '../l10n/app_localizations.dart';
import '../controllers/llm_config_controller.dart';
import '../models/team_config.dart';
import '../controllers/team_controller.dart';
import '../theme/app_theme.dart';

class ContextSidebar extends StatelessWidget {
  const ContextSidebar({
    required this.controller,
    required this.selectedSectionLabel,
    this.configController,
    this.llmConfigController,
    super.key,
  });

  final TeamController controller;
  final String selectedSectionLabel;
  final ConfigController? configController;
  final LlmConfigController? llmConfigController;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = context.l10n;
    final selected = controller.selectedTeam;
    return Container(
      key: AppKeys.contextSidebar,
      width: 260,
      color: colors.sidebarBackground,
      padding: const EdgeInsets.all(13),
      child: selected == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TeamSelector(controller: controller, selected: selected),
                const SizedBox(height: 14),
                _SidebarSectionTitle(
                  title: selectedSectionLabel == 'Config'
                      ? l10n.configure
                      : l10n.teamSessions,
                  actionLabel: selectedSectionLabel == 'Config' ? '' : '+',
                ),
                if (selectedSectionLabel == 'Config') ...[
                  _SidebarTile(
                    key: AppKeys.configTeamSectionButton,
                    title: l10n.teamSettings,
                    subtitle: l10n.teamSettingsSubtitle,
                    selected: configController?.section == ConfigSection.team,
                    onTap: () =>
                        configController?.selectSection(ConfigSection.team),
                  ),
                  _SidebarTile(
                    key: AppKeys.configMembersSectionButton,
                    title: l10n.members,
                    subtitle: l10n.membersSubtitle,
                    selected:
                        configController?.section == ConfigSection.members,
                    onTap: () =>
                        configController?.selectSection(ConfigSection.members),
                  ),
                  _SidebarTile(
                    key: AppKeys.configLlmSectionButton,
                    title: l10n.llmConfig,
                    subtitle: l10n.llmConfigSubtitle,
                    selected: configController?.section == ConfigSection.llm,
                    onTap: () =>
                        configController?.selectSection(ConfigSection.llm),
                  ),
                  _SidebarTile(
                    key: AppKeys.configLayoutSectionButton,
                    title: l10n.layout,
                    subtitle: l10n.layoutSubtitle,
                    selected: configController?.section == ConfigSection.layout,
                    onTap: () =>
                        configController?.selectSection(ConfigSection.layout),
                  ),
                  if (configController?.section == ConfigSection.members) ...[
                    const SizedBox(height: 8),
                    _SidebarSectionTitle(
                      title: l10n.memberQuickList,
                      actionLabel: '',
                    ),
                    for (final member in selected.members)
                      _SidebarTile(
                        key: AppKeys.memberRow(member.id),
                        title: member.name,
                        subtitle: member.id,
                        selected:
                            configController?.selectedMemberId == member.id,
                        onTap: () => configController?.selectMember(member.id),
                      ),
                  ],
                  if (configController?.section == ConfigSection.llm &&
                      llmConfigController != null) ...[
                    const SizedBox(height: 8),
                    _SidebarSectionTitle(title: l10n.providers, actionLabel: ''),
                    for (final provider
                        in llmConfigController!.config.providers.values)
                      _SidebarTile(
                        title: provider.name,
                        subtitle:
                            '${provider.type} / ${llmConfigController!.config.models.values.where((m) => m.provider == provider.name).length} models',
                        selected:
                            llmConfigController!.selectedProviderName ==
                            provider.name,
                        onTap: () =>
                            llmConfigController!.selectProvider(provider.name),
                      ),
                  ],
                ] else ...[
                  _SidebarTile(
                    title: l10n.shellChatWorkbench,
                    subtitle: 'team-lead / local',
                    selected: true,
                  ),
                  const _SidebarTile(
                    title: 'Fix Linux launch',
                    subtitle: 'reviewer / stopped',
                    selected: false,
                  ),
                  const _SidebarTile(
                    title: 'Docs cleanup',
                    subtitle: 'team-lead / unknown',
                    selected: false,
                  ),
                ],
              ],
            ),
    );
  }
}

class _TeamSelector extends StatelessWidget {
  const _TeamSelector({required this.controller, required this.selected});

  final TeamController controller;
  final TeamConfig selected;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = context.l10n;
    return PopupMenuButton<String>(
      tooltip: l10n.selectTeam,
      onSelected: controller.selectTeam,
      itemBuilder: (context) => [
        for (final team in controller.teams)
          PopupMenuItem(value: team.id, child: Text(team.name)),
      ],
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: colors.teamSelectorBackground,
          border: Border.all(color: colors.teamSelectorBorder),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                selected.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const Icon(Icons.expand_more, size: 18),
          ],
        ),
      ),
    );
  }
}

class _SidebarSectionTitle extends StatelessWidget {
  const _SidebarSectionTitle({required this.title, required this.actionLabel});

  final String title;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: textBase.withValues(alpha: 0.58),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
          if (actionLabel.isNotEmpty)
            Text(actionLabel, style: TextStyle(color: colors.linkText)),
        ],
      ),
    );
  }
}

class _SidebarTile extends StatelessWidget {
  const _SidebarTile({
    required this.title,
    required this.subtitle,
    required this.selected,
    this.onTap,
    super.key,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? colors.selectedBackground : colors.unselectedBackground,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected
                    ? colors.selectedBorder
                    : colors.unselectedBorder,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w700, color: textBase),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textBase.withValues(alpha: 0.52),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
