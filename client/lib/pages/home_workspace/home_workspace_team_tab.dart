import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';

import '../../cubits/launch_profile_cubit.dart';
import '../../cubits/team/launch_profile_selectors.dart';
import '../../models/team_config.dart';
import '../../theme/app_text_styles.dart';
import '../team_config/team_config_extensions_section.dart';
import '../team_config/team_config_info_section.dart';
import '../team_config/team_config_mcp_section.dart';
import '../team_config/team_config_member_section.dart';
import '../team_config/team_config_plugins_section.dart';
import '../team_config/team_config_section.dart';
import '../team_config/team_config_skills_section.dart';
import 'home_workspace_global_section.dart';

/// Embeds an existing team-config section body inside a workspace-home tab.
/// For the Members section it adds a lightweight member picker (the standalone
/// section only renders one member's detail).
class HomeTeamTab extends StatefulWidget {
  const HomeTeamTab({
    required this.teamId,
    required this.section,
    this.initialMemberId,
    this.onSelectGlobalView,
    super.key,
  });

  final String teamId;
  final TeamConfigSection section;

  /// Member to pre-select in the Members section (deep-link); null picks the
  /// first member.
  final String? initialMemberId;

  /// Switches the workspace right pane to a global management view. Lets the
  /// reused skills/plugins/MCP sections jump to v2 global management instead of
  /// pushing a v1 route.
  final ValueChanged<HomeGlobalView>? onSelectGlobalView;

  @override
  State<HomeTeamTab> createState() => _HomeTeamTabState();
}

class _HomeTeamTabState extends State<HomeTeamTab> {
  late String? _selectedMemberId = widget.initialMemberId;

  String? _resolvedMemberId(List<MemberRosterEntry> roster) {
    if (roster.isEmpty) return null;
    final id = _selectedMemberId;
    if (id != null && roster.any((m) => m.id == id)) return id;
    return roster.first.id;
  }

  LaunchProfileCubit get _cubit => context.read<LaunchProfileCubit>();

  TeamProfile? get _team =>
      LaunchProfileSelectors.teamById(_cubit.state, widget.teamId);

  @override
  Widget build(BuildContext context) {
    if (widget.section == TeamConfigSection.members) {
      return _buildMembers(context);
    }

    final team = context.select<LaunchProfileCubit, TeamProfile?>(
      (c) => LaunchProfileSelectors.teamById(c.state, widget.teamId),
    );
    if (team == null) return const SizedBox.shrink();

    final onGlobal = widget.onSelectGlobalView;
    VoidCallback? manage(HomeGlobalView view) =>
        onGlobal == null ? null : () => onGlobal(view);

    final body = switch (widget.section) {
      TeamConfigSection.team => TeamInfoSection(team: team, cubit: _cubit),
      TeamConfigSection.skills => TeamSkillsSection(
        team: team,
        cubit: _cubit,
        onManageGlobal: manage(HomeGlobalView.skills),
      ),
      TeamConfigSection.plugins => TeamPluginsSection(
        team: team,
        cubit: _cubit,
        onManageGlobal: manage(HomeGlobalView.plugins),
      ),
      TeamConfigSection.mcp => TeamMcpSection(
        team: team,
        cubit: _cubit,
        onManageGlobal: manage(HomeGlobalView.mcp),
      ),
      TeamConfigSection.extensions => TeamExtensionsSection(team: team),
      TeamConfigSection.members => const SizedBox.shrink(),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 16),
      child: body,
    );
  }

  Widget _buildMembers(BuildContext context) {
    final roster = context.select<LaunchProfileCubit, List<MemberRosterEntry>>(
      (c) => LaunchProfileSelectors.memberRoster(
        LaunchProfileSelectors.teamById(c.state, widget.teamId),
      ),
    );
    final memberId = _resolvedMemberId(roster);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MemberPicker(
          roster: roster,
          selectedMemberId: memberId,
          onSelect: (id) => setState(() => _selectedMemberId = id),
          onAddMember: () async {
            await _cubit.addMember();
            final team = _team;
            if (team != null && team.members.isNotEmpty) {
              setState(() => _selectedMemberId = team.members.last.id);
            }
          },
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
            child: TeamMemberDetailSection(
              teamId: widget.teamId,
              selectedMemberId: memberId,
            ),
          ),
        ),
      ],
    );
  }
}

class _MemberPicker extends StatelessWidget {
  const _MemberPicker({
    required this.roster,
    required this.selectedMemberId,
    required this.onSelect,
    required this.onAddMember,
  });

  final List<MemberRosterEntry> roster;
  final String? selectedMemberId;
  final ValueChanged<String> onSelect;
  final Future<void> Function() onAddMember;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final member in roster)
              _MemberChip(
                member: member,
                selected: member.id == selectedMemberId,
                onTap: () => onSelect(member.id),
              ),
            _AddMemberChip(onTap: onAddMember),
          ],
        ),
      ),
    );
  }
}

class _MemberChip extends StatelessWidget {
  const _MemberChip({
    required this.member,
    required this.selected,
    required this.onTap,
  });

  final MemberRosterEntry member;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? cs.primary.withValues(alpha: 0.14)
                : cs.surfaceContainer,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? cs.primary.withValues(alpha: 0.4)
                  : cs.outlineVariant.withValues(alpha: 0.7),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                member.isTeamLead ? Icons.star_rounded : Icons.person_outline,
                size: context.appIconSizes.md,
                color: selected ? cs.primary : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                member.displayName,
                style: styles.bodySmall.copyWith(
                  color: selected ? cs.primary : cs.onSurface,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddMemberChip extends StatelessWidget {
  const _AddMemberChip({required this.onTap});

  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
        ),
        child: Icon(
          Icons.person_add_alt_1_outlined,
          size: context.appIconSizes.md,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}
