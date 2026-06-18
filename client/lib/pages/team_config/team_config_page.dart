import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../cubits/team_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/team_config.dart';
import '../../services/app/platform_utils.dart';
import '../../utils/app_keys.dart';
import '../../utils/debounce/debounce.dart';
import '../../utils/team_member_naming.dart';
import '../../widgets/settings/workspace_hub_shell.dart';
import '../../widgets/settings/workspace_section_host.dart';
import 'team_config_extensions_section.dart';
import 'team_config_info_section.dart';
import 'team_config_mcp_section.dart';
import 'team_config_member_section.dart';
import 'team_config_nav_panel.dart';
import 'team_config_plugins_section.dart';
import 'team_config_section.dart';
import 'team_config_skills_section.dart';

export 'team_config_section.dart';

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
      WorkspaceHubEntry(
        title: l10n.teamMcpNav,
        icon: Icons.hub_outlined,
        onTap: throttledTap(
          'team_config_hub_mcp',
          () => context.push('/team-config/mcp'),
        ),
      ),
      WorkspaceHubEntry(
        title: l10n.teamExtensionsNav,
        icon: Icons.power_outlined,
        onTap: throttledTap(
          'team_config_hub_extensions',
          () => context.push('/team-config/extensions'),
        ),
      ),
      for (final member in team.members)
        WorkspaceHubEntry(
          title: member.name.trim().isEmpty ? l10n.memberName : member.name,
          showLeaderBadge: TeamMemberNaming.isTeamLead(member),
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

  String? _memberRouteId(TeamIdentity team, {String? preferred}) {
    if (team.members.isEmpty) return null;
    final sid = preferred;
    if (sid != null && team.members.any((m) => m.id == sid)) return sid;
    return team.members.first.id;
  }

  String? _effectiveMemberId(TeamIdentity team) {
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
      TeamConfigSection.team => TeamInfoSection(team: team, cubit: teamCubit),
      TeamConfigSection.skills => TeamSkillsSection(
          team: team,
          cubit: teamCubit,
        ),
      TeamConfigSection.plugins => TeamPluginsSection(
          team: team,
          cubit: teamCubit,
        ),
      TeamConfigSection.mcp => TeamMcpSection(team: team, cubit: teamCubit),
      TeamConfigSection.extensions => TeamExtensionsSection(team: team),
      TeamConfigSection.members => TeamMemberDetailSection(
          team: team,
          cubit: teamCubit,
          selectedMemberId: resolvedMemberId,
        ),
    };

    return WorkspaceAdaptiveSectionPage(
      pageKey: AppKeys.teamConfigWorkspace,
      title: l10n.teamConfig,
      subtitle: l10n.teamSettingsSubtitle,
      bodyAnimationKey: ValueKey(
        'team-config-body-${section.name}-${resolvedMemberId ?? ''}',
      ),
      nav: TeamConfigNavPanel(
        team: team,
        section: section,
        selectedMemberId: resolvedMemberId,
        onSelect: (s) {
          if (s == TeamConfigSection.members) {
            final id = _memberRouteId(team, preferred: memberId);
            if (id != null) {
              navigateWorkspaceRoute(
                context,
                memberRoutePath('/team-config', id),
              );
            }
            return;
          }
          navigateWorkspaceRoute(context, s.routePath('/team-config'));
        },
        onSelectMember: (id) => navigateWorkspaceRoute(
          context,
          memberRoutePath('/team-config', id),
        ),
        onAddMember: () async {
          await teamCubit.addMember();
          final t = teamCubit.state.selectedTeam;
          if (t != null && t.members.isNotEmpty && context.mounted) {
            navigateWorkspaceRoute(
              context,
              memberRoutePath('/team-config', t.members.last.id),
            );
          }
        },
        l10n: l10n,
      ),
      body: body,
    );
  }
}
