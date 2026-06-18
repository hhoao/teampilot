import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/team_cubit.dart';
import '../../theme/workspace_surface_layers.dart';
import '../team_config/team_config_section.dart';
import 'home_workspace_all_projects_pane.dart';
import 'home_workspace_content.dart';
import 'home_workspace_global_section.dart';
import 'home_workspace_library_section.dart';
import 'home_workspace_library_view.dart';
import 'home_workspace_sidebar.dart';

/// New Apifox-style workspace home body (teams rail + right pane). The window
/// chrome (title bar + open project tabs) is provided by [HomeWorkspaceShell].
/// The right pane shows either all projects, the selected team config, or a
/// global management section (Skills / Plugins / MCP / Extensions).
class HomeWorkspacePage extends StatefulWidget {
  const HomeWorkspacePage({
    this.initialSection,
    this.initialMemberId,
    this.initialGlobalView,
    super.key,
  });

  /// Team-config tab to open on first build (deep-link from e.g. the launch
  /// config-incomplete dialog).
  final TeamConfigSection? initialSection;

  /// Member to focus when [initialSection] is [TeamConfigSection.members].
  final String? initialMemberId;

  /// Global management sidebar entry to open on first build (deep-link from
  /// project management "manage all" actions).
  final HomeWorkspaceGlobalView? initialGlobalView;

  @override
  State<HomeWorkspacePage> createState() => _HomeWorkspacePageState();
}

class _HomeWorkspacePageState extends State<HomeWorkspacePage> {
  var _allProjectsActive = true;

  /// Null means the team view; otherwise a global management section.
  late HomeWorkspaceGlobalView? _globalView = widget.initialGlobalView;

  /// Favorites / recent library pane; mutually exclusive with [_globalView].
  HomeWorkspaceLibraryView? _libraryView;

  @override
  void initState() {
    super.initState();
    if (widget.initialGlobalView != null) {
      _allProjectsActive = false;
    }
    if (widget.initialSection != null) {
      _allProjectsActive = false;
    }
  }

  @override
  void didUpdateWidget(covariant HomeWorkspacePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialGlobalView == oldWidget.initialGlobalView) return;
    setState(() {
      _globalView = widget.initialGlobalView;
      if (widget.initialGlobalView != null) {
        _allProjectsActive = false;
        _libraryView = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final globalView = _globalView;
    final libraryView = _libraryView;
    final teamId = context.watch<TeamCubit>().state.selectedTeam?.id ?? 'none';
    final paneKey = ValueKey(
      globalView?.name ??
          libraryView?.name ??
          (_allProjectsActive ? 'all-projects' : 'team-$teamId'),
    );

    final body = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeWorkspaceSidebar(
          activeGlobalView: globalView,
          activeLibraryView: libraryView,
          allProjectsActive:
              _allProjectsActive && globalView == null && libraryView == null,
          onSelectAllProjects: () => setState(() {
            _allProjectsActive = true;
            _globalView = null;
            _libraryView = null;
          }),
          onSelectGlobalView: (view) => setState(() {
            _allProjectsActive = false;
            _globalView = view;
            _libraryView = null;
          }),
          onSelectLibraryView: (view) => setState(() {
            _allProjectsActive = false;
            _libraryView = view;
            _globalView = null;
          }),
          onSelectTeam: (teamId) {
            context.read<TeamCubit>().selectTeam(teamId);
            setState(() {
              _allProjectsActive = false;
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
                    : _allProjectsActive
                    ? const HomeWorkspaceAllProjectsPane()
                    : HomeWorkspaceContent(
                        initialSection: widget.initialSection,
                        initialMemberId: widget.initialMemberId,
                        onSelectGlobalView: (view) => setState(() {
                          _allProjectsActive = false;
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

    return WorkspacePageCardShell(child: body);
  }
}
