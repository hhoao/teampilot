import 'package:flutter/material.dart';

import '../app_keys.dart';
import '../config_controller.dart';
import '../llm_config_controller.dart';
import '../team_config.dart';
import '../team_controller.dart';

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
    final selected = controller.selectedTeam;
    return Container(
      key: AppKeys.contextSidebar,
      width: 260,
      color: const Color(0xFF111827),
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
                      ? 'Configure'
                      : 'Team Sessions',
                  actionLabel: selectedSectionLabel == 'Config' ? '' : '+',
                ),
                if (selectedSectionLabel == 'Config') ...[
                  _SidebarTile(
                    key: AppKeys.configTeamSectionButton,
                    title: 'Team Settings',
                    subtitle: 'workspace teams',
                    selected: configController?.section == ConfigSection.team,
                    onTap: () =>
                        configController?.selectSection(ConfigSection.team),
                  ),
                  _SidebarTile(
                    key: AppKeys.configMembersSectionButton,
                    title: 'Members',
                    subtitle: 'team agents',
                    selected:
                        configController?.section == ConfigSection.members,
                    onTap: () =>
                        configController?.selectSection(ConfigSection.members),
                  ),
                  _SidebarTile(
                    key: AppKeys.configLlmSectionButton,
                    title: 'LLM Config',
                    subtitle: 'providers and models',
                    selected: configController?.section == ConfigSection.llm,
                    onTap: () =>
                        configController?.selectSection(ConfigSection.llm),
                  ),
                  _SidebarTile(
                    key: AppKeys.configLayoutSectionButton,
                    title: 'Layout',
                    subtitle: 'global workbench',
                    selected: configController?.section == ConfigSection.layout,
                    onTap: () =>
                        configController?.selectSection(ConfigSection.layout),
                  ),
                  if (configController?.section == ConfigSection.members) ...[
                    const SizedBox(height: 8),
                    _SidebarSectionTitle(
                      title: 'MEMBER QUICK LIST',
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
                    _SidebarSectionTitle(title: 'PROVIDERS', actionLabel: ''),
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
                  const _SidebarTile(
                    title: 'Shell chat workbench',
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
    return PopupMenuButton<String>(
      tooltip: 'Select team',
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
          color: const Color(0x2B1E40AF),
          border: Border.all(color: const Color(0x5260A5FA)),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.58),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
          if (actionLabel.isNotEmpty)
            Text(actionLabel, style: const TextStyle(color: Color(0xFF93C5FD))),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? const Color(0x2E1E40AF) : const Color(0x9E0F172A),
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
                    ? const Color(0x7360A5FA)
                    : const Color(0x2B94A3B8),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.52),
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
