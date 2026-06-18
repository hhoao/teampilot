import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/launch_profile_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../theme/workspace_surface_layers.dart';
import '../team_config/team_config_section.dart';
import 'home_workspace_content_header.dart';
import 'home_workspace_global_section.dart';
import 'home_workspace_team_tab.dart';

/// Right-hand content pane: team header, config tabs (Members / Skills / …),
/// and the selected team-config section. Read-only — actions show hints.
class HomeContent extends StatefulWidget {
  const HomeContent({
    this.initialSection,
    this.initialMemberId,
    this.onSelectGlobalView,
    super.key,
  });

  /// Team-config tab to select on first build; null shows Members.
  final TeamConfigSection? initialSection;

  /// Member to focus when [initialSection] is [TeamConfigSection.members].
  final String? initialMemberId;

  /// Switches the workspace right pane to a global management view, used by the
  /// embedded team skills/plugins/MCP tabs to jump to global management.
  final ValueChanged<HomeGlobalView>? onSelectGlobalView;

  @override
  State<HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends State<HomeContent> {
  static const _sections = <TeamConfigSection>[
    TeamConfigSection.members,
    TeamConfigSection.skills,
    TeamConfigSection.plugins,
    TeamConfigSection.mcp,
    TeamConfigSection.extensions,
    TeamConfigSection.team,
  ];

  late int _tabIndex = _initialTabIndex();

  int _initialTabIndex() {
    final section = widget.initialSection;
    if (section == null) return 0;
    final index = _sections.indexOf(section);
    return index < 0 ? 0 : index;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final teamCubit = context.watch<LaunchProfileCubit>();
    final team = teamCubit.state.selectedTeam;

    if (team == null) {
      return ColoredBox(
        color: cs.surface,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    final tabs = [for (final section in _sections) section.title(l10n)];
    final activeSection = _sections[_tabIndex];

    return ColoredBox(
      color: cs.workspaceCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HomeTeamHeader(team: team),
          const SizedBox(height: 14),
          HomeContentTabBar(
            tabs: tabs,
            selectedIndex: _tabIndex,
            onSelect: (i) => setState(() => _tabIndex = i),
          ),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Expanded(
            child: HomeTeamTab(
              key: ValueKey('home-team-tab-${activeSection.name}'),
              section: activeSection,
              team: team,
              cubit: teamCubit,
              initialMemberId: activeSection == TeamConfigSection.members
                  ? widget.initialMemberId
                  : null,
              onSelectGlobalView: widget.onSelectGlobalView,
            )
                .animate(key: ValueKey('home-content-tab-$_tabIndex'))
                .fadeIn(duration: 180.ms, curve: Curves.easeOut)
                .slideX(
                  begin: 0.025,
                  end: 0,
                  duration: 220.ms,
                  curve: Curves.easeOutCubic,
                ),
          ),
        ],
      ),
    );
  }
}
