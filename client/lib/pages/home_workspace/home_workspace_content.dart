import 'package:flutter/material.dart';

import '../../cubits/launch_profile_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/team_config.dart';
import '../team_config/team_config_section.dart';
import 'home_workspace_content_header.dart';
import 'home_workspace_global_section.dart';
import 'home_workspace_identity_content_shell.dart';
import 'home_workspace_team_tab.dart';

/// Canonical tab order of team-config sections in the home team pane. Also the
/// index basis for deep-link resolution ([HomeWorkspacePage]) — keep every
/// consumer on this single list so `?section=` lands on the rendered tab.
const teamHomeTabSections = <TeamConfigSection>[
  TeamConfigSection.team,
  TeamConfigSection.members,
  TeamConfigSection.skills,
  TeamConfigSection.plugins,
  TeamConfigSection.mcp,
  TeamConfigSection.extensions,
  TeamConfigSection.hooks,
];

/// Resolves a deep-linked [TeamConfigSection] to its tab index in
/// [teamHomeTabSections]; null (no deep link) or unknown sections yield -1.
int teamHomeTabIndex(TeamConfigSection? section) =>
    section == null ? -1 : teamHomeTabSections.indexOf(section);

/// Right-hand content pane: team header, config tabs (Skills / Plugins / …),
/// and the selected team-config section.
class HomeContent extends StatefulWidget {
  const HomeContent({
    required this.team,
    required this.cubit,
    required this.initialTabIndex,
    this.initialMemberId,
    this.onTabIndexChanged,
    this.onSelectGlobalView,
    super.key,
  });

  final TeamProfile team;
  final LaunchProfileCubit cubit;
  final int initialTabIndex;

  /// Member to focus when the Members tab is active (deep-link).
  final String? initialMemberId;

  final ValueChanged<int>? onTabIndexChanged;
  final ValueChanged<HomeGlobalView>? onSelectGlobalView;

  @override
  State<HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends State<HomeContent> {
  late int _tabIndex = widget.initialTabIndex.clamp(0, teamHomeTabSections.length - 1);

  @override
  void didUpdateWidget(covariant HomeContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.team.id != oldWidget.team.id) {
      _tabIndex = widget.initialTabIndex.clamp(0, teamHomeTabSections.length - 1);
    }
  }

  void _onTabSelected(int index) {
    setState(() => _tabIndex = index);
    widget.onTabIndexChanged?.call(index);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final team = widget.team;
    final tabs = [for (final section in teamHomeTabSections) section.title(l10n)];
    final activeSection = teamHomeTabSections[_tabIndex];

    return HomeIdentityContentShell(
      header: HomeTeamHeader.fromTeam(team),
      tabs: tabs,
      selectedTabIndex: _tabIndex,
      onTabSelected: _onTabSelected,
      bodyAnimationKey: ValueKey('home-team-content-${team.id}-$_tabIndex'),
      tabBody: HomeTeamTab(
        key: ValueKey('home-team-tab-${activeSection.name}'),
        team: team,
        section: activeSection,
        cubit: widget.cubit,
        initialMemberId: activeSection == TeamConfigSection.members
            ? widget.initialMemberId
            : null,
        onSelectGlobalView: widget.onSelectGlobalView,
      ),
    );
  }
}
