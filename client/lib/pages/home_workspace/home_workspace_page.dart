import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/launch_profile_cubit.dart';
import '../../models/personal_profile.dart';
import '../../models/team_config.dart';
import '../../models/launch_profile.dart';
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

  Widget _identityPane(
    LaunchProfileCubit identityCubit,
    LaunchProfile identity,
  ) {
    return switch (identity) {
      PersonalProfile personal => HomePersonalContent(
          personal: personal,
          cubit: identityCubit,
          onSelectGlobalView: (view) => setState(() {
            _allWorkspacesActive = false;
            _globalView = view;
            _libraryView = null;
          }),
        ),
      TeamProfile _ => HomeContent(
          initialSection: widget.initialSection,
          initialMemberId: widget.initialMemberId,
          onSelectGlobalView: (view) => setState(() {
            _allWorkspacesActive = false;
            _globalView = view;
            _libraryView = null;
          }),
        ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }

  @override
  Widget build(BuildContext context) {
    final globalView = _globalView;
    final libraryView = _libraryView;
    final identityCubit = context.watch<LaunchProfileCubit>();
    final selectedIdentity = _selectedIdentityId != null
        ? identityCubit.byId(_selectedIdentityId!)
        : identityCubit.state.selectedTeam;
    final paneKey = ValueKey(
      globalView?.name ??
          libraryView?.name ??
          (_allWorkspacesActive
              ? 'all-workspaces'
              : 'identity-${selectedIdentity?.id ?? 'none'}'),
    );

    final body = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeSidebar(
          activeGlobalView: globalView,
          activeLibraryView: libraryView,
          allWorkspacesActive:
              _allWorkspacesActive && globalView == null && libraryView == null,
          selectedIdentityId: _allWorkspacesActive ? null : selectedIdentity?.id,
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
            child: _buildRightPane(
              globalView: globalView,
              libraryView: libraryView,
              identityCubit: identityCubit,
              selectedIdentity: selectedIdentity,
              paneKey: paneKey,
            ),
          ),
        ),
      ],
    );

    return WorkspacePageCardShell(child: body);
  }

  Widget _buildRightPane({
    required HomeGlobalView? globalView,
    required HomeLibraryView? libraryView,
    required LaunchProfileCubit identityCubit,
    required LaunchProfile? selectedIdentity,
    required ValueKey<String> paneKey,
  }) {
    final Widget pane;
    if (globalView != null) {
      pane = HomeGlobalSection(view: globalView);
    } else if (libraryView != null) {
      pane = HomeLibrarySection(view: libraryView);
    } else if (_allWorkspacesActive) {
      return const HomeAllWorkspacesPane();
    } else if (selectedIdentity != null) {
      pane = _identityPane(identityCubit, selectedIdentity);
    } else {
      return const HomeAllWorkspacesPane();
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
