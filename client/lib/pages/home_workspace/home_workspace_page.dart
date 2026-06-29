import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/launch_profile_cubit.dart';
import '../../models/launch_profile_kind.dart';
import '../../models/personal_profile.dart';
import '../../models/team_config.dart';
import '../../theme/workspace_surface_layers.dart';
import '../team_config/team_config_section.dart';
import 'home_all_workspaces_pane.dart';
import 'home_workspace_content.dart';
import 'home_workspace_global_section.dart';
import 'home_workspace_library_section.dart';
import 'home_workspace_library_view.dart';
import 'home_workspace_personal_content.dart';
import 'home_workspace_sidebar.dart';

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
    final identity = context.read<LaunchProfileCubit>().byId(profileId);
    if (identity is TeamProfile) {
      context.read<LaunchProfileCubit>().selectTeam(profileId);
    }
    setState(() {
      _selectedIdentityId = profileId;
      _allWorkspacesActive = false;
      _globalView = null;
      _libraryView = null;
    });
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
        ],
      ),
    );
  }
}

class _HomeRightPane extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final paneKey = ValueKey(
      globalView?.name ??
          libraryView?.name ??
          (allWorkspacesActive
              ? 'all-workspaces'
              : 'identity-${selectedIdentityId ?? context.select<LaunchProfileCubit, String?>((c) => c.state.selectedTeamId) ?? 'none'}'),
    );

    if (globalView != null) {
      return HomeGlobalSection(view: globalView!)
          .animate(key: paneKey)
          .fadeIn(duration: 180.ms, curve: Curves.easeOut)
          .slideX(
            begin: 0.025,
            end: 0,
            duration: 220.ms,
            curve: Curves.easeOutCubic,
          );
    }
    if (libraryView != null) {
      return HomeLibrarySection(view: libraryView!)
          .animate(key: paneKey)
          .fadeIn(duration: 180.ms, curve: Curves.easeOut)
          .slideX(
            begin: 0.025,
            end: 0,
            duration: 220.ms,
            curve: Curves.easeOutCubic,
          );
    }
    if (allWorkspacesActive) {
      return const HomeAllWorkspacesPane();
    }

    final resolvedProfileId = selectedIdentityId ??
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
    if (identityKind == null) {
      return const HomeAllWorkspacesPane();
    }

    final Widget pane;
    switch (identityKind) {
      case LaunchProfileKind.personal:
        pane = _HomePersonalPane(
          profileId: resolvedProfileId ?? '',
          onSelectGlobalView: onSelectGlobalView,
        );
      case LaunchProfileKind.team:
        pane = HomeContent(
          initialSection: initialSection,
          initialMemberId: initialMemberId,
          onSelectGlobalView: onSelectGlobalView,
        );
    }

    return pane
        .animate(key: paneKey)
        .fadeIn(duration: 180.ms, curve: Curves.easeOut)
        .slideX(
          begin: 0.025,
          end: 0,
          duration: 220.ms,
          curve: Curves.easeOutCubic,
        );
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
