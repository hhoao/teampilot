import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../cubits/chat_cubit.dart';
import '../../cubits/team_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_project.dart';
import '../../models/app_session.dart';
import '../../models/team_config.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/workspace_surface_layers.dart';
import '../team_config/team_config_section.dart';
import 'home_workspace_project_card.dart';
import 'home_workspace_team_tab.dart';

/// Right-hand content pane: team header, mapped tab bar (Projects / Resources /
/// Members / Skills & Plugins / Settings), a toolbar, and the project grid for
/// the selected team. Read-only — actions show a "coming soon" hint.
class HomeWorkspaceContent extends StatefulWidget {
  const HomeWorkspaceContent({super.key});

  @override
  State<HomeWorkspaceContent> createState() => _HomeWorkspaceContentState();
}

class _HomeWorkspaceContentState extends State<HomeWorkspaceContent> {
  int _tabIndex = 0;
  bool _gridView = true;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final teamCubit = context.watch<TeamCubit>();
    final team = teamCubit.state.selectedTeam;

    final projects = context.select<ChatCubit, List<AppProject>>(
      (c) => c.state.projects,
    );
    final sessions = context.select<ChatCubit, List<AppSession>>(
      (c) => c.state.sessions,
    );

    if (team == null) {
      return ColoredBox(
        color: cs.surface,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    final teamProjects = _projectsForTeam(team, projects, sessions);
    // Tab 0 is Projects; the rest reuse the existing team-config sections in
    // the order the user requested: Members, Skills, Plugins, MCP, Extensions,
    // Team Settings.
    const sections = <TeamConfigSection?>[
      null,
      TeamConfigSection.members,
      TeamConfigSection.skills,
      TeamConfigSection.plugins,
      TeamConfigSection.mcp,
      TeamConfigSection.extensions,
      TeamConfigSection.team,
    ];
    final tabs = <String>[
      l10n.homeWorkspaceTeamProjects,
      for (final section in sections.skip(1)) section!.title(l10n),
    ];
    final activeSection = sections[_tabIndex];

    return Padding(
      padding: const EdgeInsets.fromLTRB(44, 48, 42, 18),
      child: ColoredBox(
        color: cs.workspaceCard,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TeamHeader(team: team),
            const SizedBox(height: 14),
            _TabBar(
              tabs: tabs,
              selectedIndex: _tabIndex,
              onSelect: (i) => setState(() => _tabIndex = i),
            ),
            Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Expanded(
              child:
                  (activeSection == null
                          ? _ProjectsTab(
                              projects: teamProjects,
                              sessions: sessions,
                              gridView: _gridView,
                              onToggleView: (grid) =>
                                  setState(() => _gridView = grid),
                            )
                          : HomeWorkspaceTeamTab(
                              key: ValueKey(
                                'home-team-tab-${activeSection.name}',
                              ),
                              section: activeSection,
                              team: team,
                              cubit: teamCubit,
                            ))
                      // Match the global-navigation section transition: fade + slight
                      // slide-in, replayed whenever the selected tab changes.
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
      ),
    );
  }

  List<AppProject> _projectsForTeam(
    TeamConfig team,
    List<AppProject> projects,
    List<AppSession> sessions,
  ) {
    final teamSessionProjectIds = sessions
        .where((s) => s.sessionTeam == team.id)
        .map((s) => s.projectId)
        .toSet();
    return projects
        .where((p) => teamSessionProjectIds.contains(p.projectId))
        .toList();
  }
}

class _TeamHeader extends StatelessWidget {
  const _TeamHeader({required this.team});

  final TeamConfig team;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final titleStyle = Theme.of(
      context,
    ).textTheme.titleLarge?.copyWith(color: cs.onSurface);
    return Row(
      children: [
        Text(team.name, style: titleStyle),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            color: cs.tertiary.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            context.l10n.homeWorkspaceOwner,
            style: styles.caption.copyWith(
              color: cs.tertiary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({
    required this.tabs,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < tabs.length; i++)
          _TabItem(
            label: tabs[i],
            selected: i == selectedIndex,
            onTap: () => onSelect(i),
          ),
      ],
    );
  }
}

class _TabItem extends StatefulWidget {
  const _TabItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_TabItem> createState() => _TabItemState();
}

class _TabItemState extends State<_TabItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final selected = widget.selected;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? cs.primary : Colors.transparent,
                width: 2.5,
              ),
            ),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: selected
                  ? Colors.transparent
                  : _hovered
                  ? cs.onSurface.withValues(alpha: 0.05)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              widget.label,
              style: styles.prominent.copyWith(
                color: selected
                    ? cs.primary
                    : _hovered
                    ? cs.onSurface
                    : cs.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProjectsTab extends StatelessWidget {
  const _ProjectsTab({
    required this.projects,
    required this.sessions,
    required this.gridView,
    required this.onToggleView,
  });

  final List<AppProject> projects;
  final List<AppSession> sessions;
  final bool gridView;
  final ValueChanged<bool> onToggleView;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Toolbar(gridView: gridView, onToggleView: onToggleView),
        const SizedBox(height: 16),
        Expanded(
          child: projects.isEmpty
              ? const _EmptyProjects()
              : _ProjectGrid(projects: projects, sessions: sessions),
        ),
      ],
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.gridView, required this.onToggleView});

  final bool gridView;
  final ValueChanged<bool> onToggleView;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      children: [
        _ViewToggle(gridView: gridView, onToggleView: onToggleView),
        const SizedBox(width: 8),
        _IconChip(icon: Icons.sort_rounded, onTap: () => _comingSoon(context)),
        const Spacer(),
        _OutlinedAction(
          icon: Icons.file_download_outlined,
          label: l10n.homeWorkspaceImportProject,
          onTap: () => _comingSoon(context),
        ),
        const SizedBox(width: 10),
        _PrimaryAction(
          icon: Icons.add_rounded,
          label: l10n.newProject,
          onTap: () => _comingSoon(context),
        ),
      ],
    );
  }

  void _comingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.homeWorkspaceComingSoon)),
    );
  }
}

class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.gridView, required this.onToggleView});

  final bool gridView;
  final ValueChanged<bool> onToggleView;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToggleCell(
            icon: Icons.grid_view_rounded,
            active: gridView,
            onTap: () => onToggleView(true),
          ),
          _ToggleCell(
            icon: Icons.format_list_bulleted_rounded,
            active: !gridView,
            onTap: () => onToggleView(false),
          ),
        ],
      ),
    );
  }
}

class _ToggleCell extends StatelessWidget {
  const _ToggleCell({
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: active
              ? cs.primary.withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(
          icon,
          size: 16,
          color: active ? cs.primary : cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _IconChip extends StatelessWidget {
  const _IconChip({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
        ),
        child: Icon(icon, size: 16, color: cs.onSurfaceVariant),
      ),
    );
  }
}

class _OutlinedAction extends StatelessWidget {
  const _OutlinedAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.8)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: cs.onSurfaceVariant),
            const SizedBox(width: 7),
            Text(label, style: styles.body.copyWith(color: cs.onSurface)),
          ],
        ),
      ),
    );
  }
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: cs.primary,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: cs.onPrimary),
            const SizedBox(width: 7),
            Text(
              label,
              style: styles.body.copyWith(
                color: cs.onPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectGrid extends StatelessWidget {
  const _ProjectGrid({required this.projects, required this.sessions});

  final List<AppProject> projects;
  final List<AppSession> sessions;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 460,
        mainAxisExtent: 244,
        crossAxisSpacing: 20,
        mainAxisSpacing: 20,
      ),
      itemCount: projects.length,
      itemBuilder: (context, index) {
        final project = projects[index];
        final count = sessions
            .where((s) => s.projectId == project.projectId)
            .length;
        return HomeWorkspaceProjectCard(
          project: project,
          sessionCount: count,
          onTap: () => context.go('/home-v2/project/${project.projectId}'),
        );
      },
    );
  }
}

class _EmptyProjects extends StatelessWidget {
  const _EmptyProjects();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final l10n = context.l10n;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.folder_open_outlined,
            size: 44,
            color: cs.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 14),
          Text(
            l10n.homeWorkspaceEmptyProjects,
            style: styles.body.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.homeWorkspaceEmptyProjectsHint,
            style: styles.bodySmall.copyWith(
              color: cs.onSurfaceVariant.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }
}
