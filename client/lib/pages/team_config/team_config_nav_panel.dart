import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/team_config.dart';
import '../../utils/debounce/debounce.dart';
import '../../utils/team_member_naming.dart';
import '../../widgets/settings/workspace_hub_shell.dart';
import '../../widgets/settings/workspace_section_host.dart';
import 'dotted_border_container.dart';
import 'team_config_section.dart';

class TeamConfigNavPanel extends StatelessWidget {
  const TeamConfigNavPanel({super.key, 
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
    const primarySections = TeamConfigSection.values;
    return WorkspaceCompositeNavPanel(
      primaryEntries: [
        for (final s in primarySections)
          WorkspaceHubEntry(
            title: s.title(l10n),
            icon: s.icon,
            selected: section == s,
            density: WorkspaceHubNavDensity.relaxed,
            onTap: throttledTap('team_config_nav_${s.name}', () => onSelect(s)),
          ),
      ],
      trailingChildren: [
        for (final m in team.members)
          WorkspaceHubNavItem(
            title: m.name.trim().isEmpty ? l10n.memberName : m.name.trim(),
            showLeaderBadge: TeamMemberNaming.isTeamLead(m),
            icon: Icons.person_outline,
            density: WorkspaceHubNavDensity.subItem,
            selected:
                section == TeamConfigSection.members &&
                m.id == selectedMemberId,
            onTap: throttledTap(
              'team_config_nav_member_${m.id}',
              () => onSelectMember(m.id),
            ),
          ),
        TeamConfigMemberNavAddTile(l10n: l10n, onTap: onAddMember),
      ],
    );
  }
}

class TeamConfigMemberNavAddTile extends StatelessWidget {
  const TeamConfigMemberNavAddTile({super.key, required this.l10n, required this.onTap});

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
                    Icon(Icons.add, size: AppIconSizes.md, color: muted),
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
