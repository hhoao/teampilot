import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';

import '../../cubits/identity_cubit.dart';
import '../../models/team_config.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/team_member_naming.dart';
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
    required this.section,
    required this.team,
    required this.cubit,
    this.initialMemberId,
    this.onSelectGlobalView,
    super.key,
  });

  final TeamConfigSection section;
  final TeamIdentity team;
  final IdentityCubit cubit;

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

  String? get _resolvedMemberId {
    final members = widget.team.members;
    if (members.isEmpty) return null;
    final id = _selectedMemberId;
    if (id != null && members.any((m) => m.id == id)) return id;
    return members.first.id;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.section == TeamConfigSection.members) {
      return _buildMembers(context);
    }

    final onGlobal = widget.onSelectGlobalView;
    VoidCallback? manage(HomeGlobalView view) =>
        onGlobal == null ? null : () => onGlobal(view);

    final body = switch (widget.section) {
      TeamConfigSection.team => TeamInfoSection(
        team: widget.team,
        cubit: widget.cubit,
      ),
      TeamConfigSection.skills => TeamSkillsSection(
        team: widget.team,
        cubit: widget.cubit,
        onManageGlobal: manage(HomeGlobalView.skills),
      ),
      TeamConfigSection.plugins => TeamPluginsSection(
        team: widget.team,
        cubit: widget.cubit,
        onManageGlobal: manage(HomeGlobalView.plugins),
      ),
      TeamConfigSection.mcp => TeamMcpSection(
        team: widget.team,
        cubit: widget.cubit,
        onManageGlobal: manage(HomeGlobalView.mcp),
      ),
      TeamConfigSection.extensions => TeamExtensionsSection(team: widget.team),
      TeamConfigSection.members => const SizedBox.shrink(),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 16),
      child: body,
    );
  }

  Widget _buildMembers(BuildContext context) {
    final memberId = _resolvedMemberId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MemberPicker(
          team: widget.team,
          cubit: widget.cubit,
          selectedMemberId: memberId,
          onSelect: (id) => setState(() => _selectedMemberId = id),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
            child: TeamMemberDetailSection(
              team: widget.team,
              cubit: widget.cubit,
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
    required this.team,
    required this.cubit,
    required this.selectedMemberId,
    required this.onSelect,
  });

  final TeamIdentity team;
  final IdentityCubit cubit;
  final String? selectedMemberId;
  final ValueChanged<String> onSelect;

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
            for (final member in team.members)
              _MemberChip(
                member: member,
                selected: member.id == selectedMemberId,
                onTap: () => onSelect(member.id),
              ),
            _AddMemberChip(cubit: cubit, onAdded: onSelect),
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

  final TeamMemberConfig member;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final isLead = TeamMemberNaming.isTeamLead(member);
    final name = member.name.trim().isEmpty ? member.id : member.name;

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
                isLead ? Icons.star_rounded : Icons.person_outline,
                size: context.appIconSizes.md,
                color: selected ? cs.primary : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                name,
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
  const _AddMemberChip({required this.cubit, required this.onAdded});

  final IdentityCubit cubit;
  final ValueChanged<String> onAdded;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () async {
        await cubit.addMember();
        final team = cubit.state.selectedTeam;
        if (team != null && team.members.isNotEmpty) {
          onAdded(team.members.last.id);
        }
      },
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
