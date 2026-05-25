import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../cubits/app_provider_cubit.dart';
import '../cubits/plugin_cubit.dart';
import '../cubits/skill_cubit.dart';
import '../cubits/team_cubit.dart';
import '../models/app_provider_config.dart';
import '../l10n/l10n_extensions.dart';
import '../models/plugin.dart';
import '../models/skill.dart';
import '../models/team_config.dart';
import '../models/team_member_prompt_presets.dart';
import '../services/flashskyai_agent_catalog_service.dart';
import '../services/flashskyai_storage_roots.dart';
import '../services/claude_official_provider.dart';
import '../services/platform_utils.dart';
import '../utils/app_keys.dart';
import '../utils/app_provider_model_candidates.dart';
import '../utils/debounce/debounce.dart';
import '../widgets/app_outline_text_field.dart';
import '../widgets/app_provider/team_tool_provider_selectors.dart';
import '../widgets/dropdown/flashsky_dropdown_field.dart';
import '../widgets/dropdown/flashskyai_dropdown_decoration.dart';
import '../widgets/settings/workspace_hub_shell.dart';
import '../theme/workspace_surface_layers.dart';

enum TeamConfigSection { team, skills, plugins, members }

extension TeamConfigSectionRoute on TeamConfigSection {
  String routeSegment() => switch (this) {
    TeamConfigSection.team => 'team',
    TeamConfigSection.skills => 'skills',
    TeamConfigSection.plugins => 'plugins',
    TeamConfigSection.members => 'members',
  };
}

/// Same mapping as [TeamToolProviderSelectors]: member provider catalog is
/// `<appData>/providers/<cli>/providers.json` per [AppProviderRepository].
AppProviderCli _appCatalogCliForTeam(TeamCli cli) => switch (cli) {
  TeamCli.flashskyai => AppProviderCli.flashskyai,
  TeamCli.codex => AppProviderCli.codex,
  TeamCli.claude => AppProviderCli.claude,
};

String _teamCliDisplayLabel(AppLocalizations l10n, TeamCli cli) {
  return switch (cli) {
    TeamCli.flashskyai => l10n.appProviderToolFlashskyai,
    TeamCli.codex => l10n.appProviderToolCodex,
    TeamCli.claude => l10n.appProviderToolClaude,
  };
}

String _teamLoopChoiceLabel(AppLocalizations l10n, String? key) {
  switch (key) {
    case 'true':
      return l10n.teamLoopTrue;
    case 'false':
      return l10n.teamLoopFalse;
    case '__default__':
    default:
      return l10n.teamLoopDefault;
  }
}

String _memberAgentDropdownItemLabel(
  BuildContext context,
  AppLocalizations l10n,
  String value, {
  List<String> userAgentIds = const [],
}) {
  if (value == FlashskyaiAgentCatalog.noneDropdownValue) {
    return l10n.agentBuiltInNone;
  }
  if (value == FlashskyaiAgentCatalog.customDropdownValue) {
    return l10n.agentBuiltInCustom;
  }
  final ent = FlashskyaiAgentCatalog.tryParseBuiltinId(value);
  if (ent != null) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final hint = zh ? ent.modelHintZh : ent.modelHintEn;
    return '${ent.id} · $hint';
  }
  if (userAgentIds.contains(value)) {
    return value;
  }
  return value;
}

/// Android hub: team settings sections as a list (each opens a full page).
class TeamConfigHubPage extends StatelessWidget {
  const TeamConfigHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final teamCubit = context.watch<TeamCubit>();
    final team = teamCubit.state.selectedTeam;

    if (team == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final entries = <WorkspaceHubEntry>[
      WorkspaceHubEntry(
        title: l10n.teamSettings,
        icon: Icons.groups_outlined,
        onTap: throttledTap(
          'team_config_hub_team',
          () => context.push('/team-config/team'),
        ),
      ),
      WorkspaceHubEntry(
        title: l10n.teamSkillsNav,
        icon: Icons.extension_outlined,
        onTap: throttledTap(
          'team_config_hub_skills',
          () => context.push('/team-config/skills'),
        ),
      ),
      WorkspaceHubEntry(
        title: l10n.teamPluginsNav,
        icon: Icons.widgets_outlined,
        onTap: throttledTap(
          'team_config_hub_plugins',
          () => context.push('/team-config/plugins'),
        ),
      ),
      for (final member in team.members)
        WorkspaceHubEntry(
          title: member.name.trim().isEmpty ? l10n.memberName : member.name,
          icon: Icons.person_outline,
          onTap: throttledTap(
            'team_config_hub_member_${member.id}',
            () => context.push('/team-config/members/${member.id}'),
          ),
        ),
      WorkspaceHubEntry(
        title: '${l10n.add} ${l10n.memberName}',
        icon: Icons.person_add_outlined,
        onTap: throttledAsync('team_config_hub_add_member', () async {
          await teamCubit.addMember();
          final updated = teamCubit.state.selectedTeam;
          if (!context.mounted || updated == null || updated.members.isEmpty) {
            return;
          }
          context.push('/team-config/members/${updated.members.last.id}');
        }),
      ),
    ];

    return WorkspaceHubPage(
      pageKey: AppKeys.teamConfigHub,
      title: l10n.teamConfig,
      subtitle: l10n.teamSettingsSubtitle,
      entries: entries,
    );
  }
}

class TeamConfigPage extends StatelessWidget {
  const TeamConfigPage({required this.section, this.memberId, super.key});

  final TeamConfigSection section;
  final String? memberId;

  /// Resolves a member id for routing; does not depend on [section].
  String? _memberRouteId(TeamConfig team, {String? preferred}) {
    if (team.members.isEmpty) return null;
    final sid = preferred;
    if (sid != null && team.members.any((m) => m.id == sid)) return sid;
    return team.members.first.id;
  }

  String? _effectiveMemberId(TeamConfig team) {
    if (section != TeamConfigSection.members) return null;
    return _memberRouteId(team, preferred: memberId);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final teamCubit = context.watch<TeamCubit>();
    final team = teamCubit.state.selectedTeam;

    if (team == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final resolvedMemberId = _effectiveMemberId(team);
    final body = switch (section) {
      TeamConfigSection.team => _TeamInfoSection(team: team, cubit: teamCubit),
      TeamConfigSection.skills => _TeamSkillsSection(
        team: team,
        cubit: teamCubit,
      ),
      TeamConfigSection.plugins => _TeamPluginsSection(
        team: team,
        cubit: teamCubit,
      ),
      TeamConfigSection.members => _MemberDetailSection(
        team: team,
        cubit: teamCubit,
        selectedMemberId: resolvedMemberId,
      ),
    };

    if (useAndroidHubNavigation(context)) {
      return WorkspaceSectionPage(
        pageKey: AppKeys.teamConfigWorkspace,
        child: body,
      );
    }

    return Container(
      color: Theme.of(context).colorScheme.workspacePage,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WorkspaceHubTitleBar(
            title: l10n.teamConfig,
            subtitle: l10n.teamSettingsSubtitle,
          ),
          Expanded(
            child: WorkspaceSplitShell(
              bodyAnimationKey: ValueKey(
                'team-config-body-${section.name}-${resolvedMemberId ?? ''}',
              ),
              nav: _NavPanel(
                team: team,
                section: section,
                selectedMemberId: resolvedMemberId,
                onSelect: (s) {
                  if (s == TeamConfigSection.members) {
                    final id = _memberRouteId(team, preferred: memberId);
                    if (id != null) {
                      context.go('/team-config/members/$id');
                    }
                    return;
                  }
                  context.go('/team-config/${s.routeSegment()}');
                },
                onSelectMember: (id) => context.go('/team-config/members/$id'),
                onAddMember: () async {
                  await teamCubit.addMember();
                  final t = teamCubit.state.selectedTeam;
                  if (t != null && t.members.isNotEmpty && context.mounted) {
                    context.go('/team-config/members/${t.members.last.id}');
                  }
                },
                l10n: l10n,
              ),
              body: body,
            ),
          ),
        ],
      ),
    );
  }
}

class _NavPanel extends StatelessWidget {
  const _NavPanel({
    required this.team,
    required this.section,
    required this.selectedMemberId,
    required this.onSelect,
    required this.onSelectMember,
    required this.onAddMember,
    required this.l10n,
  });

  final TeamConfig team;
  final TeamConfigSection section;
  final String? selectedMemberId;
  final ValueChanged<TeamConfigSection> onSelect;
  final ValueChanged<String> onSelectMember;
  final VoidCallback onAddMember;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.workspacePage,
      padding: const EdgeInsets.fromLTRB(24, 28, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _NavItem(
            title: l10n.teamSettings,
            icon: Icons.groups_outlined,
            selected: section == TeamConfigSection.team,
            onTap: throttledTap(
              'team_config_nav_team',
              () => onSelect(TeamConfigSection.team),
            ),
          ),
          _NavItem(
            title: l10n.teamSkillsNav,
            icon: Icons.extension_outlined,
            selected: section == TeamConfigSection.skills,
            onTap: throttledTap(
              'team_config_nav_skills',
              () => onSelect(TeamConfigSection.skills),
            ),
          ),
          _NavItem(
            title: l10n.teamPluginsNav,
            icon: Icons.widgets_outlined,
            selected: section == TeamConfigSection.plugins,
            onTap: throttledTap(
              'team_config_nav_plugins',
              () => onSelect(TeamConfigSection.plugins),
            ),
          ),
          _NavItem(
            title: l10n.members,
            icon: Icons.person_outline,
            selected: section == TeamConfigSection.members,
            onTap: throttledTap(
              'team_config_nav_members',
              () => onSelect(TeamConfigSection.members),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(left: 14, right: 2),
              children: [
                for (final m in team.members)
                  _MemberNavSubItem(
                    member: m,
                    selected:
                        section == TeamConfigSection.members &&
                        m.id == selectedMemberId,
                    onTap: throttledTap(
                      'team_config_nav_member_${m.id}',
                      () => onSelectMember(m.id),
                    ),
                  ),
                _MemberNavAddTile(l10n: l10n, onTap: onAddMember),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberNavSubItem extends StatelessWidget {
  const _MemberNavSubItem({
    required this.member,
    required this.selected,
    required this.onTap,
  });

  final TeamMemberConfig member;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    final muted = textBase.withValues(alpha: 0.64);
    final label = member.name.trim().isEmpty
        ? l10n.memberName
        : member.name.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected ? cs.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: SizedBox(
            height: 44,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Icon(
                    Icons.person_outline,
                    size: 19,
                    color: selected ? textBase : muted,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w600,
                        color: selected ? textBase : muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MemberNavAddTile extends StatelessWidget {
  const _MemberNavAddTile({required this.l10n, required this.onTap});

  final AppLocalizations l10n;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    final muted = textBase.withValues(alpha: 0.72);
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 6),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: DottedBorderContainer(
            color: cs.outlineVariant,
            radius: 10,
            child: SizedBox(
              height: 44,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Icon(Icons.add, size: 19, color: muted),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${l10n.add} ${l10n.memberName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.title,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    final muted = textBase.withValues(alpha: 0.64);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? cs.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(
            height: 54,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                children: [
                  Icon(icon, color: selected ? textBase : muted, size: 21),
                  SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  // ignore: unused_element_parameter
  const _Card({required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: padding ?? const EdgeInsets.all(18),
      decoration: workspaceCardDecoration(cs, radius: 12),
      child: child,
    );
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({required this.title, this.subtitle, this.trailing});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    final titleWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: textBase,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle!,
            style: TextStyle(
              fontSize: 13,
              color: textBase.withValues(alpha: 0.64),
            ),
          ),
        ],
      ],
    );
    if (trailing == null) return titleWidget;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: titleWidget),
        trailing!,
      ],
    );
  }
}

class _TeamSkillsSection extends StatelessWidget {
  const _TeamSkillsSection({required this.team, required this.cubit});

  final TeamConfig team;
  final TeamCubit cubit;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    final skillState = context.watch<SkillCubit>().state;
    final syncing = context.watch<TeamCubit>().state.isSyncingSkills;
    final enabled = skillState.installed
        .where((s) => s.enabled)
        .toList(growable: false);
    final assignedCount = enabled
        .where((s) => team.skillIds.contains(s.id))
        .length;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _CardHeader(
                  title: l10n.teamSkillsAssignedCount(
                    assignedCount,
                    enabled.length,
                  ),
                  trailing: OutlinedButton.icon(
                    onPressed: () => context.go('/skills'),
                    icon: const Icon(Icons.extension_outlined, size: 16),
                    label: Text(l10n.teamSkillsManage),
                  ),
                ),
                if (syncing) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
                const SizedBox(height: 14),
                if (enabled.isEmpty)
                  _TeamSkillsEmptyBlock(
                    textBase: textBase,
                    onGoSkills: () => context.go('/skills'),
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final skill in enabled)
                        _TeamSkillRow(
                          skill: skill,
                          assigned: team.skillIds.contains(skill.id),
                          onAssignedChanged: (assigned) {
                            final ids = List<String>.from(team.skillIds);
                            if (assigned) {
                              if (!ids.contains(skill.id)) ids.add(skill.id);
                            } else {
                              ids.remove(skill.id);
                            }
                            cubit.updateSelected(team.copyWith(skillIds: ids));
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

class _TeamSkillsEmptyBlock extends StatelessWidget {
  const _TeamSkillsEmptyBlock({
    required this.textBase,
    required this.onGoSkills,
  });

  final Color textBase;
  final VoidCallback onGoSkills;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 36,
            color: textBase.withValues(alpha: 0.35),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.skillsNoInstalled,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: textBase,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.skillsNoInstalledHint,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: textBase.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: onGoSkills,
            icon: const Icon(Icons.extension_outlined, size: 16),
            label: Text(l10n.teamSkillsManage),
          ),
        ],
      ),
    );
  }
}

class _TeamSkillRow extends StatelessWidget {
  const _TeamSkillRow({
    required this.skill,
    required this.assigned,
    required this.onAssignedChanged,
  });

  final Skill skill;
  final bool assigned;
  final ValueChanged<bool> onAssignedChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    final sourceLabel = skill.repoOwner != null && skill.repoName != null
        ? '${skill.repoOwner}/${skill.repoName}'
        : l10n.skillsLocal;

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
                          skill.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: textBase,
                          ),
                        ),
                      ),
                      if (skill.readmeUrl != null) ...[
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: () => _openSkillUrl(skill.readmeUrl!),
                          child: Icon(
                            Icons.open_in_new,
                            size: 14,
                            color: textBase.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                      const SizedBox(width: 8),
                      Text(
                        sourceLabel,
                        style: TextStyle(
                          fontSize: 11,
                          color: textBase.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                  if (skill.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      skill.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: textBase.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Switch(value: assigned, onChanged: onAssignedChanged),
          ],
        ),
      ),
    );
  }
}

class _TeamPluginsSection extends StatelessWidget {
  const _TeamPluginsSection({required this.team, required this.cubit});

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
    final codexUnsupported = team.cli == TeamCli.codex;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (codexUnsupported)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _Card(
                child: Text(
                  l10n.teamPluginsCliUnsupportedBanner,
                  style: TextStyle(
                    fontSize: 13,
                    color: textBase.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _CardHeader(
                  title: l10n.teamPluginsAssignedCount(
                    assignedCount,
                    installed.length,
                  ),
                  trailing: OutlinedButton.icon(
                    onPressed: () => context.go('/plugins'),
                    icon: const Icon(Icons.widgets_outlined, size: 16),
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
                      color: Theme.of(context)
                          .colorScheme
                          .errorContainer
                          .withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      l10n.teamPluginsMissing(missingIds.length),
                      style: TextStyle(
                        fontSize: 12,
                        color: textBase.withValues(alpha: 0.75),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                if (installed.isEmpty && missingIds.isEmpty)
                  _TeamPluginsEmptyBlock(
                    textBase: textBase,
                    onGoPlugins: () => context.go('/plugins/discovery'),
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final plugin in installed)
                        _TeamPluginRow(
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
                            cubit.updateSelected(
                              team.copyWith(pluginIds: ids),
                            );
                          },
                        ),
                      for (final id in missingIds)
                        _TeamMissingPluginRow(
                          pluginId: id,
                          onRemove: () {
                            final ids = List<String>.from(team.pluginIds)
                              ..remove(id);
                            cubit.updateSelected(
                              team.copyWith(pluginIds: ids),
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

class _TeamPluginsEmptyBlock extends StatelessWidget {
  const _TeamPluginsEmptyBlock({
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
            size: 36,
            color: textBase.withValues(alpha: 0.35),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.teamPluginsEmpty,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: textBase,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.teamPluginsEmptyHint,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: textBase.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: onGoPlugins,
            icon: const Icon(Icons.search, size: 16),
            label: Text(l10n.teamPluginsGoDiscovery),
          ),
        ],
      ),
    );
  }
}

class _TeamPluginRow extends StatelessWidget {
  const _TeamPluginRow({
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
    final sourceLabel = plugin.marketplaceOwner != null &&
            plugin.marketplaceName != null
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
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: textBase,
                          ),
                        ),
                      ),
                      if (plugin.version.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(
                          'v${plugin.version}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: textBase.withValues(alpha: 0.55),
                          ),
                        ),
                      ],
                      if (plugin.readmeUrl != null) ...[
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: () => _openSkillUrl(plugin.readmeUrl!),
                          child: Icon(
                            Icons.open_in_new,
                            size: 14,
                            color: textBase.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                      const SizedBox(width: 8),
                      Text(
                        sourceLabel,
                        style: TextStyle(
                          fontSize: 11,
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
                      style: TextStyle(
                        fontSize: 12,
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
                          size: 14,
                          color: cs.tertiary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            l10n.teamPluginsNameConflict(conflictDir!),
                            style: TextStyle(
                              fontSize: 11,
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
            const SizedBox(width: 12),
            Switch(value: assigned, onChanged: onAssignedChanged),
          ],
        ),
      ),
    );
  }
}

class _TeamMissingPluginRow extends StatelessWidget {
  const _TeamMissingPluginRow({
    required this.pluginId,
    required this.onRemove,
  });

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
        decoration: workspaceInsetDecoration(cs, radius: 10).copyWith(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        ),
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
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: textBase.withValues(alpha: 0.55),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.teamPluginsMissingLabel,
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.error.withValues(alpha: 0.85),
                    ),
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

Future<void> _openSkillUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _TeamInfoSection extends StatefulWidget {
  const _TeamInfoSection({required this.team, required this.cubit});

  final TeamConfig team;
  final TeamCubit cubit;

  @override
  State<_TeamInfoSection> createState() => _TeamInfoSectionState();
}

class _TeamInfoSectionState extends State<_TeamInfoSection> {
  late TextEditingController _nameCtl;
  late TextEditingController _descCtl;
  late TextEditingController _argsCtl;
  late String _trackedTeamId;

  @override
  void initState() {
    super.initState();
    _nameCtl = TextEditingController(text: widget.team.name);
    _descCtl = TextEditingController(text: widget.team.description);
    _argsCtl = TextEditingController(text: widget.team.extraArgs);
    _trackedTeamId = widget.team.id;
  }

  @override
  void didUpdateWidget(covariant _TeamInfoSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.team.id != _trackedTeamId) {
      _trackedTeamId = widget.team.id;
      _nameCtl.text = widget.team.name;
      _descCtl.text = widget.team.description;
      _argsCtl.text = widget.team.extraArgs;
    } else if (widget.team.name != _nameCtl.text) {
      _nameCtl.text = widget.team.name;
    }
    if (widget.team.description != _descCtl.text) {
      _descCtl.text = widget.team.description;
    }
  }

  @override
  void dispose() {
    unawaited(_commitName());
    _nameCtl.dispose();
    _descCtl.dispose();
    _argsCtl.dispose();
    super.dispose();
  }

  Future<void> _commitName() async {
    final trimmed = _nameCtl.text.trim();
    if (trimmed == widget.team.name) return;
    final ok = await widget.cubit.renameSelectedTeamName(trimmed);
    if (!mounted) return;
    if (!ok) {
      _nameCtl.text = widget.team.name;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _CardHeader(
                  title: l10n.teamSettings,
                  subtitle: l10n.editTeamSubtitle,
                ),
                const SizedBox(height: 18),
                _FieldLabel(text: l10n.teamName),
                const SizedBox(height: 6),
                AppOutlineTextField(
                  key: AppKeys.teamNameField,
                  controller: _nameCtl,
                  onSubmitted: (_) => unawaited(_commitName()),
                ),
                const SizedBox(height: 14),
                _FieldLabel(text: l10n.teamDescription),
                const SizedBox(height: 6),
                AppOutlineTextField(
                  controller: _descCtl,
                  maxLines: 3,
                  hintText: l10n.teamDescriptionHint,
                  onChanged: (v) => widget.cubit.updateSelected(
                    widget.team.copyWith(description: v),
                  ),
                ),
                const SizedBox(height: 14),
                _FieldLabel(text: l10n.teamLoop),
                const SizedBox(height: 6),
                FlashskyDropdownField<String>(
                  key: ValueKey(
                    'team-loop-${widget.team.id}-${widget.team.loop ?? 'nil'}',
                  ),
                  items: const ['__default__', 'true', 'false'],
                  initialItem: widget.team.loop == null
                      ? '__default__'
                      : (widget.team.loop! ? 'true' : 'false'),
                  hintText: l10n.teamLoopDefault,
                  decoration: FlashskyDropdownDecorations.denseField(context),
                  overlayHeight: 200,
                  listItemMaxLines: 2,
                  itemLabel: (k) => _teamLoopChoiceLabel(l10n, k),
                  onChanged: (value) {
                    final key = value ?? '__default__';
                    final bool? next = key == '__default__'
                        ? null
                        : key == 'true';
                    widget.cubit.updateSelected(
                      widget.team.copyWith(loop: next, updateLoop: true),
                    );
                  },
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.teamLoopSubtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: textBase.withValues(alpha: 0.58),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 18),
                _FieldLabel(text: l10n.teamCliLabel),
                const SizedBox(height: 6),
                Text(
                  _teamCliDisplayLabel(l10n, widget.team.cli),
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.teamCliLockedSubtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: textBase.withValues(alpha: 0.58),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 14),
                _FieldLabel(text: l10n.teamExtraArgs),
                const SizedBox(height: 6),
                AppOutlineTextField(
                  controller: _argsCtl,
                  hintText: l10n.teamExtraArgsHint,
                  onChanged: (v) => widget.cubit.updateSelected(
                    widget.team.copyWith(extraArgs: v),
                  ),
                ),
                if (widget.team.cli == TeamCli.claude) ...[
                  const SizedBox(height: 18),
                  TeamToolProviderSelectors(
                    team: widget.team,
                    onChanged: widget.cubit.updateSelected,
                  ),
                ],
              ],
            ),
          ),
          _DangerZone(team: widget.team, cubit: widget.cubit),
        ],
      ),
    );
  }
}

class _DangerZone extends StatelessWidget {
  const _DangerZone({required this.team, required this.cubit});

  final TeamConfig team;
  final TeamCubit cubit;

  Future<void> _confirmDelete(BuildContext context) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteTeam),
        content: Text(l10n.deleteTeamConfirm(team.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await cubit.deleteSelected();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final errorColor = Theme.of(context).colorScheme.error;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardHeader(
            title: l10n.dangerZone,
            subtitle: l10n.deleteTeamSubtitle,
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: AppKeys.deleteButton,
              onPressed: () => _confirmDelete(context),
              icon: Icon(Icons.delete_outline, size: 18, color: errorColor),
              label: Text(l10n.deleteTeam, style: TextStyle(color: errorColor)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: errorColor.withValues(alpha: 0.4)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: textBase.withValues(alpha: 0.7),
      ),
    );
  }
}

Future<void> _confirmDeleteMember(
  BuildContext context,
  TeamCubit cubit,
  TeamMemberConfig member,
  AppLocalizations l10n,
) async {
  final name = member.name.trim().isEmpty ? l10n.memberName : member.name;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.delete),
      content: Text(name),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(l10n.delete),
        ),
      ],
    ),
  );
  if (confirmed == true) {
    await cubit.deleteMember(member.id);
  }
}

class _MemberDetailSection extends StatelessWidget {
  const _MemberDetailSection({
    required this.team,
    required this.cubit,
    required this.selectedMemberId,
  });

  final TeamConfig team;
  final TeamCubit cubit;
  final String? selectedMemberId;

  TeamMemberConfig? _memberOrNull() {
    final id = selectedMemberId;
    if (id == null || team.members.isEmpty) return null;
    for (final m in team.members) {
      if (m.id == id) return m;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    final member = _memberOrNull();
    if (member == null) {
      return Center(
        child: Text(
          l10n.openMember,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: textBase.withValues(alpha: 0.55),
          ),
        ),
      );
    }

    final canDelete = team.members.length > 1;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 14, left: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    member.name.trim().isEmpty ? l10n.memberName : member.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: textBase,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: l10n.delete,
                  onPressed: !canDelete
                      ? null
                      : throttledAsync(
                          'team_delete_member_${member.id}',
                          () => _confirmDeleteMember(
                            context,
                            cubit,
                            member,
                            l10n,
                          ),
                        ),
                  icon: const Icon(Icons.delete_outline, size: 20),
                ),
              ],
            ),
          ),
          _Card(
            child: _MemberConfigForm(
              key: ValueKey(member.id),
              team: team,
              member: member,
              cubit: cubit,
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberConfigForm extends StatefulWidget {
  const _MemberConfigForm({
    super.key,
    required this.team,
    required this.member,
    required this.cubit,
  });

  final TeamConfig team;
  final TeamMemberConfig member;
  final TeamCubit cubit;

  @override
  State<_MemberConfigForm> createState() => _MemberConfigFormState();
}

class _MemberConfigFormState extends State<_MemberConfigForm> {
  late TextEditingController _nameCtl;
  late TextEditingController _agentCtl;
  late TextEditingController _argsCtl;
  late TextEditingController _promptCtl;
  List<String> _userAgentIds = const [];

  @override
  void initState() {
    super.initState();
    _syncControllers(widget.member);
    _loadUserAgents();
  }

  Future<void> _loadUserAgents() async {
    final storageRoots = context.read<FlashskyaiStorageRoots>();
    final ids = await FlashskyaiAgentCatalogService(
      storageRoots: storageRoots,
    ).listUserAgentIds();
    if (!mounted) return;
    setState(() => _userAgentIds = ids);
  }

  void _syncControllers(TeamMemberConfig m) {
    _nameCtl = TextEditingController(text: m.name);
    _agentCtl = TextEditingController(text: m.agent);
    _argsCtl = TextEditingController(text: m.extraArgs);
    _promptCtl = TextEditingController(text: m.prompt);
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _agentCtl.dispose();
    _argsCtl.dispose();
    _promptCtl.dispose();
    super.dispose();
  }

  void _update(TeamMemberConfig next) {
    widget.cubit.updateMember(widget.member.id, next);
  }

  void _applyPromptPreset(String presetId) {
    final l10n = context.l10n;
    final text = teamMemberPromptPresetText(l10n, presetId);
    if (text.isEmpty) return;
    _promptCtl.text = text;
    _promptCtl.selection = TextSelection.collapsed(offset: text.length);
    _update(widget.member.copyWith(prompt: text));
  }

  List<String> _modelNamesForClaudeProvider({
    required String providerId,
    required AppProviderConfig? appProvider,
    required String currentModel,
  }) {
    if (appProvider == null) {
      final trimmed = currentModel.trim();
      return trimmed.isEmpty ? <String>[] : [trimmed];
    }
    return collectClaudeModelCandidates(
      appProvider,
      currentModel: currentModel,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final m = widget.member;
    final memberCatalogCli = _appCatalogCliForTeam(widget.team.cli);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);

    final prov = m.provider;
    final appProviders = context
        .watch<AppProviderCubit>()
        .state
        .providersFor(memberCatalogCli)
        .toList(growable: false);
    final providerIds = appProviders.map((p) => p.id).toList()..sort();
    if (prov.trim().isNotEmpty && !providerIds.contains(prov)) {
      providerIds.add(prov);
    }
    final providerLabels = {
      for (final p in appProviders) p.id: p.name,
      if (prov.trim().isNotEmpty && !appProviders.any((p) => p.id == prov))
        prov: prov,
    };

    AppProviderConfig? selectedAppProvider;
    if (prov.trim().isNotEmpty) {
      for (final p in context.read<AppProviderCubit>().state.providersFor(
        memberCatalogCli,
      )) {
        if (p.id == prov) {
          selectedAppProvider = p;
          break;
        }
      }
    }

    final modelNames = List<String>.of(
      _modelNamesForClaudeProvider(
        providerId: prov,
        appProvider: selectedAppProvider,
        currentModel: m.model,
      ),
    )..sort();
    final model = m.model;
    final hideModelPicker =
        widget.team.cli == TeamCli.claude &&
        selectedAppProvider != null &&
        isOfficialClaudeProvider(selectedAppProvider);

    final dropdownDeco = FlashskyDropdownDecorations.denseField(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CardHeader(title: l10n.configure, subtitle: l10n.editMemberSubtitle),
        const SizedBox(height: 18),
        _FieldLabel(text: l10n.memberName),
        const SizedBox(height: 6),
        AppOutlineTextField(
          controller: _nameCtl,
          onChanged: (v) => _update(m.copyWith(name: v)),
        ),
        const SizedBox(height: 12),
        _FieldLabel(text: l10n.provider),
        const SizedBox(height: 6),
        FlashskyDropdownField<String>(
          items: providerIds,
          initialItem: prov.isEmpty ? null : prov,
          hintText: l10n.selectProvider,
          decoration: dropdownDeco,
          onChanged: (value) {
            final newProv = value ?? '';
            var newModel = m.model;
            AppProviderConfig? nextProvider;
            for (final p in context.read<AppProviderCubit>().state.providersFor(
              memberCatalogCli,
            )) {
              if (p.id == newProv) {
                nextProvider = p;
                break;
              }
            }
            if (nextProvider != null && isOfficialClaudeProvider(nextProvider)) {
              newModel = '';
            } else {
              final defaultModel = nextProvider?.defaultModel.trim() ?? '';
              final names = _modelNamesForClaudeProvider(
                providerId: newProv,
                appProvider: nextProvider,
                currentModel: m.model,
              );
              final stillValid = names.contains(newModel);
              if (!stillValid) {
                newModel = defaultModel.isNotEmpty ? defaultModel : '';
              }
            }
            _update(m.copyWith(provider: newProv, model: newModel));
          },
          itemLabel: (value) => providerLabels[value] ?? value,
        ),
        const SizedBox(height: 12),
        if (hideModelPicker) ...[
          Text(
            l10n.memberOfficialClaudeModelHint,
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: textBase.withValues(alpha: 0.58),
            ),
          ),
        ] else ...[
          _FieldLabel(text: l10n.model),
          const SizedBox(height: 6),
          FlashskyDropdownField<String>(
            items: modelNames,
            initialItem: model.isEmpty ? null : model,
            hintText: l10n.selectModel,
            decoration: dropdownDeco,
            onChanged: (value) => _update(m.copyWith(model: value ?? '')),
            itemLabel: (value) => value,
          ),
        ],
        const SizedBox(height: 12),
        _FieldLabel(text: l10n.agent),
        const SizedBox(height: 4),
        Text(
          l10n.agentBuiltInSubtitle,
          style: TextStyle(
            fontSize: 12,
            height: 1.35,
            color: textBase.withValues(alpha: 0.58),
          ),
        ),
        const SizedBox(height: 8),
        FlashskyDropdownField<String>(
          key: ValueKey(
            'member-agent-dd-${widget.member.id}-${m.agent}-${_userAgentIds.join(",")}',
          ),
          items: FlashskyaiAgentCatalog.dropdownValues(
            userAgentIds: _userAgentIds,
          ),
          initialItem: FlashskyaiAgentCatalog.activeDropdownValue(
            m.agent,
            userAgentIds: _userAgentIds,
          ),
          hintText: l10n.selectAgent,
          decoration: dropdownDeco,
          headerMaxLines: 2,
          listItemMaxLines: 2,
          itemLabel: (value) => _memberAgentDropdownItemLabel(
            context,
            l10n,
            value,
            userAgentIds: _userAgentIds,
          ),
          onChanged: (value) {
            final v = value ?? FlashskyaiAgentCatalog.noneDropdownValue;
            if (v == FlashskyaiAgentCatalog.noneDropdownValue) {
              _agentCtl.clear();
              _update(m.copyWith(agent: ''));
            } else if (v == FlashskyaiAgentCatalog.customDropdownValue) {
              final current = m.agent.trim();
              final next =
                  FlashskyaiAgentCatalog.isKnownAgentId(
                    current,
                    userAgentIds: _userAgentIds,
                  )
                  ? ''
                  : current;
              _agentCtl.text = next;
              _update(m.copyWith(agent: next));
            } else {
              _agentCtl.text = v;
              _update(m.copyWith(agent: v));
            }
          },
        ),
        if (FlashskyaiAgentCatalog.activeDropdownValue(
              m.agent,
              userAgentIds: _userAgentIds,
            ) ==
            FlashskyaiAgentCatalog.customDropdownValue) ...[
          const SizedBox(height: 8),
          AppOutlineTextField(
            controller: _agentCtl,
            hintText: l10n.agentCustomIdHint,
            onChanged: (v) => _update(m.copyWith(agent: v)),
          ),
        ],
        const SizedBox(height: 12),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: Text(
            l10n.memberDangerouslySkipPermissions,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: textBase,
            ),
          ),
          subtitle: Text(
            l10n.memberDangerouslySkipPermissionsHint,
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: textBase.withValues(alpha: 0.62),
            ),
          ),
          value: m.dangerouslySkipPermissions,
          onChanged: (v) => _update(m.copyWith(dangerouslySkipPermissions: v)),
        ),
        const SizedBox(height: 12),
        _FieldLabel(text: l10n.memberExtraArgs),
        const SizedBox(height: 6),
        AppOutlineTextField(
          controller: _argsCtl,
          onChanged: (v) => _update(m.copyWith(extraArgs: v)),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: _FieldLabel(text: l10n.prompt)),
            Text(
              l10n.memberPromptPresetsLabel,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: textBase.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final preset in TeamMemberPromptPreset.all)
              ActionChip(
                label: Text(
                  teamMemberPromptPresetLabel(l10n, preset.id),
                  style: const TextStyle(fontSize: 12),
                ),
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                onPressed: () => _applyPromptPreset(preset.id),
              ),
          ],
        ),
        const SizedBox(height: 8),
        AppOutlineTextField(
          controller: _promptCtl,
          minLines: 3,
          maxLines: 6,
          onChanged: (v) => _update(m.copyWith(prompt: v)),
        ),
      ],
    );
  }
}

class DottedBorderContainer extends StatelessWidget {
  const DottedBorderContainer({
    required this.child,
    required this.color,
    required this.radius,
    super.key,
  });

  final Widget child;
  final Color color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(color: color, radius: radius),
      child: child,
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    final dashed = Path();
    const dashLength = 6.0;
    const gapLength = 4.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + dashLength).clamp(0, metric.length);
        dashed.addPath(
          metric.extractPath(distance, next.toDouble()),
          Offset.zero,
        );
        distance = next + gapLength;
      }
    }
    canvas.drawPath(dashed, paint);
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}
