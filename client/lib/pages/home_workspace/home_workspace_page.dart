import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/launch_profile_cubit.dart';
import '../../cubits/team/launch_profile_selectors.dart';
import '../../models/launch_profile_kind.dart';
import '../../models/personal_profile.dart';
import '../../models/team_config.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../widgets/deferred_mount_shell.dart';
import '../team_config/team_config_section.dart';
import 'home_all_workspaces_pane.dart';
import 'home_workspace_content.dart';
import 'home_workspace_global_section.dart';
import 'home_workspace_library_section.dart';
import 'home_workspace_library_view.dart';
import 'home_workspace_personal_content.dart';
import 'home_workspace_sidebar.dart';
import 'workspace_pane_animations.dart';

/// New Apifox-style workspace home body (workspaces rail + right pane). The
/// window chrome (title bar + open workspace tabs) is provided by
/// [HomeShell].
class HomePage extends StatefulWidget {
  const HomePage({
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
  /// workspace management "manage all" actions).
  final HomeGlobalView? initialGlobalView;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  var _allWorkspacesActive = true;
  String? _selectedIdentityId;

  /// Null means the team view; otherwise a global management section.
  late HomeGlobalView? _globalView = widget.initialGlobalView;

  /// Favorites / recent library pane; mutually exclusive with [_globalView].
  HomeLibraryView? _libraryView;

  @override
  void initState() {
    super.initState();
    if (widget.initialGlobalView != null) {
      _allWorkspacesActive = false;
    }
    if (widget.initialSection != null) {
      _allWorkspacesActive = false;
      _selectedIdentityId =
          context.read<LaunchProfileCubit>().state.selectedTeam?.id;
    }
  }

  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialGlobalView == oldWidget.initialGlobalView) return;
    setState(() {
      _globalView = widget.initialGlobalView;
      if (widget.initialGlobalView != null) {
        _allWorkspacesActive = false;
        _libraryView = null;
      }
    });
  }

  void _selectIdentity(String profileId) {
    setState(() {
      _selectedIdentityId = profileId;
      _allWorkspacesActive = false;
      _globalView = null;
      _libraryView = null;
    });
    final identity = context.read<LaunchProfileCubit>().byId(profileId);
    if (identity is TeamProfile) {
      context.read<LaunchProfileCubit>().selectTeam(
        profileId,
        syncResources: false,
        silent: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final globalView = _globalView;
    final libraryView = _libraryView;

    return WorkspacePageCardShell(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HomeSidebar(
            activeGlobalView: globalView,
            activeLibraryView: libraryView,
            allWorkspacesActive:
                _allWorkspacesActive && globalView == null && libraryView == null,
            selectedIdentityId: _allWorkspacesActive
                ? null
                : (_selectedIdentityId ??
                    context.select<LaunchProfileCubit, String?>(
                      (c) => c.state.selectedTeamId,
                    )),
            onSelectAllWorkspaces: () => setState(() {
              _allWorkspacesActive = true;
              _globalView = null;
              _libraryView = null;
              _selectedIdentityId = null;
            }),
            onSelectGlobalView: (view) => setState(() {
              _allWorkspacesActive = false;
              _globalView = view;
              _libraryView = null;
            }),
            onSelectLibraryView: (view) => setState(() {
              _allWorkspacesActive = false;
              _libraryView = view;
              _globalView = null;
            }),
            onSelectIdentity: _selectIdentity,
          ),
          Expanded(
            child: DeferredMountShell(
              delayFrames: 2,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(44, 48, 42, 18),
                child: _HomeRightPane(
                  globalView: globalView,
                  libraryView: libraryView,
                  allWorkspacesActive: _allWorkspacesActive,
                  selectedIdentityId: _selectedIdentityId,
                  initialSection: widget.initialSection,
                  initialMemberId: widget.initialMemberId,
                  onSelectGlobalView: (view) => setState(() {
                    _allWorkspacesActive = false;
                    _globalView = view;
                    _libraryView = null;
                  }),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeRightPane extends StatefulWidget {
  const _HomeRightPane({
    required this.globalView,
    required this.libraryView,
    required this.allWorkspacesActive,
    required this.selectedIdentityId,
    required this.initialSection,
    required this.initialMemberId,
    required this.onSelectGlobalView,
  });

  final HomeGlobalView? globalView;
  final HomeLibraryView? libraryView;
  final bool allWorkspacesActive;
  final String? selectedIdentityId;
  final TeamConfigSection? initialSection;
  final String? initialMemberId;
  final ValueChanged<HomeGlobalView> onSelectGlobalView;

  @override
  State<_HomeRightPane> createState() => _HomeRightPaneState();
}

class _HomeRightPaneState extends State<_HomeRightPane> {
  WorkspaceRightPaneDescriptor? _previousDescriptor;
  var _consumedTeamDeepLink = false;
  final Map<String, int> _teamTabIndexById = {};

  static const _teamSections = <TeamConfigSection>[
    TeamConfigSection.skills,
    TeamConfigSection.plugins,
    TeamConfigSection.mcp,
    TeamConfigSection.extensions,
    TeamConfigSection.members,
    TeamConfigSection.team,
  ];

  int _teamTabIndex(String teamId, TeamConfigSection? deepLinkSection) {
    if (deepLinkSection != null) {
      final index = _teamSections.indexOf(deepLinkSection);
      if (index >= 0) return index;
    }
    return _teamTabIndexById[teamId] ?? 0;
  }

  void _rememberTeamTabIndex(String teamId, int index) {
    _teamTabIndexById[teamId] = index;
  }

  ({TeamConfigSection? section, String? memberId}) _takeTeamDeepLink() {
    if (_consumedTeamDeepLink) {
      return (section: null, memberId: null);
    }
    _consumedTeamDeepLink = true;
    return (
      section: widget.initialSection,
      memberId: widget.initialMemberId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final descriptor = _resolveDescriptor(context);
    final previous = _previousDescriptor;

    final pane = WorkspacePaneAnimations.switcher(
      context: context,
      descriptor: descriptor,
      previous: previous,
      child: _buildPane(context, descriptor),
    );

    if (previous != descriptor) {
      _previousDescriptor = descriptor;
    }

    return pane;
  }

  WorkspaceRightPaneDescriptor _resolveDescriptor(BuildContext context) {
    if (widget.globalView != null) {
      return WorkspaceRightPaneDescriptor.global(widget.globalView!);
    }
    if (widget.libraryView != null) {
      return WorkspaceRightPaneDescriptor.library(widget.libraryView!);
    }
    if (widget.allWorkspacesActive) {
      return const WorkspaceRightPaneDescriptor.allWorkspaces();
    }

    final resolvedProfileId =
        widget.selectedIdentityId ??
        context.select<LaunchProfileCubit, String?>(
          (c) => c.state.selectedTeamId,
        );
    final identityKind = context.select<LaunchProfileCubit, LaunchProfileKind?>(
      (c) {
        final id = resolvedProfileId;
        if (id == null) return null;
        return c.byId(id)?.kind;
      },
    );

    return switch (identityKind) {
      LaunchProfileKind.personal =>
        WorkspaceRightPaneDescriptor.personal(resolvedProfileId ?? ''),
      LaunchProfileKind.team =>
        WorkspaceRightPaneDescriptor.team(resolvedProfileId ?? ''),
      _ => const WorkspaceRightPaneDescriptor.allWorkspaces(),
    };
  }

  Widget _buildPane(
    BuildContext context,
    WorkspaceRightPaneDescriptor descriptor,
  ) {
    return switch (descriptor.kind) {
      WorkspaceRightPaneKind.allWorkspaces => const HomeAllWorkspacesPane(),
      WorkspaceRightPaneKind.global => HomeGlobalSection(
        view: descriptor.globalView!,
      ),
      WorkspaceRightPaneKind.library => HomeLibrarySection(
        view: descriptor.libraryView!,
      ),
      WorkspaceRightPaneKind.personal => _HomePersonalPane(
        profileId: descriptor.identityId ?? '',
        onSelectGlobalView: widget.onSelectGlobalView,
      ),
      WorkspaceRightPaneKind.team => () {
        final deepLink = _takeTeamDeepLink();
        final teamId = descriptor.identityId ?? '';
        return _HomeTeamPane(
          teamId: teamId,
          initialTabIndex: _teamTabIndex(teamId, deepLink.section),
          initialMemberId: deepLink.memberId,
          onTabIndexChanged: (index) => _rememberTeamTabIndex(teamId, index),
          onSelectGlobalView: widget.onSelectGlobalView,
        );
      }(),
    };
  }
}

class _HomePersonalPane extends StatelessWidget {
  const _HomePersonalPane({
    required this.profileId,
    required this.onSelectGlobalView,
  });

  final String profileId;
  final ValueChanged<HomeGlobalView> onSelectGlobalView;

  @override
  Widget build(BuildContext context) {
    final personal = context.select<LaunchProfileCubit, PersonalProfile?>(
      (c) {
        final identity = c.byId(profileId);
        return identity is PersonalProfile ? identity : null;
      },
    );
    if (personal == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return HomePersonalContent(
      personal: personal,
      cubit: context.read<LaunchProfileCubit>(),
      onSelectGlobalView: onSelectGlobalView,
    );
  }
}

class _HomeTeamPane extends StatelessWidget {
  const _HomeTeamPane({
    required this.teamId,
    required this.initialTabIndex,
    required this.initialMemberId,
    required this.onTabIndexChanged,
    required this.onSelectGlobalView,
  });

  final String teamId;
  final int initialTabIndex;
  final String? initialMemberId;
  final ValueChanged<int> onTabIndexChanged;
  final ValueChanged<HomeGlobalView> onSelectGlobalView;

  @override
  Widget build(BuildContext context) {
    final team = context.select<LaunchProfileCubit, TeamProfile?>(
      (c) => LaunchProfileSelectors.teamById(c.state, teamId),
    );
    if (team == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return HomeContent(
      team: team,
      cubit: context.read<LaunchProfileCubit>(),
      initialTabIndex: initialTabIndex,
      initialMemberId: initialMemberId,
      onTabIndexChanged: onTabIndexChanged,
      onSelectGlobalView: onSelectGlobalView,
    );
  }
}
