import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/team_cubit.dart';
import '../../theme/workspace_surface_layers.dart';
import '../team_config/team_config_section.dart';
import 'home_workspace_content.dart';
import 'home_workspace_global_section.dart';
import 'home_workspace_library_section.dart';
import 'home_workspace_library_view.dart';
import 'home_workspace_sidebar.dart';

/// New Apifox-style workspace home body (teams rail + right pane). The window
/// chrome (title bar + open project tabs) is provided by [HomeWorkspaceShell].
/// The right pane shows either the selected team (projects + tabs) or a global
/// management section (Skills / Plugins / MCP / Extensions).
class HomeWorkspacePage extends StatefulWidget {
  const HomeWorkspacePage({
    this.initialSection,
    this.initialMemberId,
    super.key,
  });

  /// Team-config tab to open on first build (deep-link from e.g. the launch
  /// config-incomplete dialog); null shows the default Projects tab.
  final TeamConfigSection? initialSection;

  /// Member to focus when [initialSection] is [TeamConfigSection.members].
  final String? initialMemberId;

  @override
  State<HomeWorkspacePage> createState() => _HomeWorkspacePageState();
}

class _HomeWorkspacePageState extends State<HomeWorkspacePage> {
  /// Null means the team view; otherwise a global management section.
  HomeWorkspaceGlobalView? _globalView;

  /// Favorites / recent library pane; mutually exclusive with [_globalView].
  HomeWorkspaceLibraryView? _libraryView;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final globalView = _globalView;
    final libraryView = _libraryView;
    final teamId = context.watch<TeamCubit>().state.selectedTeam?.id ?? 'none';
    final paneKey = ValueKey(
      globalView?.name ?? libraryView?.name ?? 'team-$teamId',
    );

    final body = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeWorkspaceSidebar(
          activeGlobalView: globalView,
          activeLibraryView: libraryView,
          onSelectGlobalView: (view) => setState(() {
            _globalView = view;
            _libraryView = null;
          }),
          onSelectLibraryView: (view) => setState(() {
            _libraryView = view;
            _globalView = null;
          }),
          onSelectTeam: (teamId) {
            context.read<TeamCubit>().selectTeam(teamId);
            setState(() {
              _globalView = null;
              _libraryView = null;
            });
          },
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(44, 48, 42, 18),
            child: (globalView != null
                    ? HomeWorkspaceGlobalSection(view: globalView)
                    : libraryView != null
                    ? HomeWorkspaceLibrarySection(view: libraryView)
                    : HomeWorkspaceContent(
                        initialSection: widget.initialSection,
                        initialMemberId: widget.initialMemberId,
                        onSelectGlobalView: (view) => setState(() {
                          _globalView = view;
                          _libraryView = null;
                        }),
                      ))
                .animate(key: paneKey)
                .fadeIn(duration: 180.ms, curve: Curves.easeOut)
                .slideX(
                  begin: 0.025,
                  end: 0,
                  duration: 220.ms,
                  curve: Curves.easeOutCubic,
                ),
          ),
        ),
      ],
    );

    // Float the whole workspace as a single rounded card on a subtle backdrop.
    return ColoredBox(
      color: cs.workspacePage,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: cs.workspaceCard,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.08),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          // Border drawn in front of the children so the edge-to-edge sidebar /
          // content surfaces can't paint over it; this also makes the rounded
          // corners read against the near-identical page background.
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
          ),
          child: body,
        ),
      ),
    );
  }
}
