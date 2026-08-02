import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/team/launch_profile_selectors.dart';
import '../../widgets/settings/workspace_section_tab_bar.dart';
import '../../models/team_config.dart';
import '../../l10n/l10n_extensions.dart';
import '../../utils/team/launch_profile_display_name.dart';

class HomeTeamHeader extends StatelessWidget {
  const HomeTeamHeader({super.key, required this.snapshot});

  final TeamHeaderSnapshot snapshot;

  factory HomeTeamHeader.fromTeam(TeamProfile team) {
    return HomeTeamHeader(snapshot: LaunchProfileSelectors.teamHeader(team)!);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final l10n = context.l10n;
    final titleStyle = styles.xl;
    final isMixed = snapshot.teamMode == TeamMode.mixed;
    final modeLabel = isMixed
        ? l10n.teamModeMixedTitle
        : l10n.teamModeNativeTitle;
    final badgeColor = isMixed ? cs.tertiary : cs.primary;
    final title =
        builtInTeamDisplayName(l10n, snapshot.id) ?? snapshot.display;
    return Row(
      children: [
        Icon(Icons.groups_2_outlined, color: cs.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: titleStyle,
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            color: badgeColor.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            modeLabel,
            style: styles.xsSemiboldColored(badgeColor),
          ),
        ),
      ],
    );
  }
}

class HomeContentTabBar extends StatelessWidget {
  const HomeContentTabBar({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return WorkspaceSectionTabBar(
      tabs: tabs,
      selectedIndex: selectedIndex,
      onSelect: onSelect,
    );
  }
}
