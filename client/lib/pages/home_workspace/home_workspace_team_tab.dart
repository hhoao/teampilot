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
import 'home_workspace_lazy_mount.dart';

/// Embeds an existing team-config section body inside a workspace-home tab.
/// For the Members section it adds a lightweight member picker (the standalone
/// section only renders one member's detail).
class HomeTeamTab extends StatefulWidget {
  const HomeTeamTab({
    required this.team,
    required this.section,
    required this.cubit,
    this.initialMemberId,
    this.onSelectGlobalView,
    super.key,
  });

  final TeamProfile team;
  final TeamConfigSection section;
  final LaunchProfileCubit cubit;

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

  LaunchProfileCubit get _cubit => widget.cubit;

  @override
  Widget build(BuildContext context) {
    if (widget.section == TeamConfigSection.members) {
      return _buildMembers(context);
    }

    final team = widget.team;
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MemberPickerHost(
          teamId: widget.team.id,
          selectedMemberId: _selectedMemberId,
          onSelect: (id) => setState(() => _selectedMemberId = id),
          onAddMember: () async {
            await _cubit.addMember();
            final team = LaunchProfileSelectors.teamById(
              _cubit.state,
              widget.team.id,
            );
            if (team != null && team.members.isNotEmpty) {
              setState(() => _selectedMemberId = team.members.last.id);
            }
          },
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
            child: RepaintBoundary(
              child: HomeWorkspaceLazyMount(
                mountKey: widget.team.id,
                child: _MemberDetailHost(
                  teamId: widget.team.id,
                  selectedMemberId: _selectedMemberId,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Subscribes only to roster identity — name edits do not rebuild the detail pane.
class _MemberPickerHost extends StatelessWidget {
  const _MemberPickerHost({
    required this.teamId,
    required this.selectedMemberId,
    required this.onSelect,
    required this.onAddMember,
  });

  final String teamId;
  final String? selectedMemberId;
  final ValueChanged<String> onSelect;
  final Future<void> Function() onAddMember;

  @override
  Widget build(BuildContext context) {
    final roster = context.select<LaunchProfileCubit, List<MemberRosterEntry>>(
      (c) => LaunchProfileSelectors.memberRoster(
        LaunchProfileSelectors.teamById(c.state, teamId),
      ),
    );
    final resolvedId = _resolvedMemberId(roster, selectedMemberId);
    return _MemberPicker(
      roster: roster,
      selectedMemberId: resolvedId,
      onSelect: onSelect,
      onAddMember: onAddMember,
    );
  }

  String? _resolvedMemberId(
    List<MemberRosterEntry> roster,
    String? selectedMemberId,
  ) {
    if (roster.isEmpty) return null;
    final id = selectedMemberId;
    if (id != null && roster.any((m) => m.id == id)) return id;
    return roster.first.id;
  }
}

/// Resolves the active member id without subscribing to roster display names.
class _MemberDetailHost extends StatelessWidget {
  const _MemberDetailHost({
    required this.teamId,
    required this.selectedMemberId,
  });

  final String teamId;
  final String? selectedMemberId;

  @override
  Widget build(BuildContext context) {
    final memberId = context.select<LaunchProfileCubit, String?>(
      (c) => _resolveMemberId(
        LaunchProfileSelectors.teamById(c.state, teamId),
        selectedMemberId,
      ),
    );
    return TeamMemberDetailSection(
      key: ValueKey('member-detail-$memberId'),
      teamId: teamId,
      selectedMemberId: memberId,
    );
  }

  static String? _resolveMemberId(TeamProfile? team, String? selectedMemberId) {
    if (team == null || team.members.isEmpty) return null;
    final id = selectedMemberId;
    if (id != null) {
      for (final member in team.members) {
        if (member.id == id) return id;
      }
    }
    return team.members.first.id;
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

class _MemberChip extends StatefulWidget {
  const _MemberChip({
    required this.member,
    required this.selected,
    required this.onTap,
  });

  final MemberRosterEntry member;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_MemberChip> createState() => _MemberChipState();
}

class _MemberChipState extends State<_MemberChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final selected = widget.selected;
    final restingBg = selected
        ? cs.primary.withValues(alpha: 0.14)
        : cs.surfaceContainer;
    final hoverTint = cs.onSurface.withValues(alpha: 0.06);
    final background = _hovered
        ? Color.alphaBlend(hoverTint, restingBg)
        : restingBg;
    final borderColor = selected
        ? cs.primary.withValues(alpha: 0.4)
        : _hovered
        ? cs.primary.withValues(alpha: 0.35)
        : cs.outlineVariant.withValues(alpha: 0.7);

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.member.isTeamLead
                      ? Icons.star_rounded
                      : Icons.person_outline,
                  size: context.appIconSizes.md,
                  color: selected ? cs.primary : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  widget.member.displayName,
                  style: styles.bodySmall.copyWith(
                    color: selected ? cs.primary : cs.onSurface,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
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

class _AddMemberChip extends StatefulWidget {
  const _AddMemberChip({required this.onTap});

  final Future<void> Function() onTap;

  @override
  State<_AddMemberChip> createState() => _AddMemberChipState();
}

class _AddMemberChipState extends State<_AddMemberChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hoverTint = cs.onSurface.withValues(alpha: 0.06);
    final background = _hovered
        ? Color.alphaBlend(hoverTint, cs.surfaceContainer)
        : cs.surfaceContainer;
    final borderColor = _hovered
        ? cs.primary.withValues(alpha: 0.35)
        : cs.outlineVariant.withValues(alpha: 0.7);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor),
          ),
          child: Icon(
            Icons.person_add_alt_1_outlined,
            size: context.appIconSizes.md,
            color: cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
