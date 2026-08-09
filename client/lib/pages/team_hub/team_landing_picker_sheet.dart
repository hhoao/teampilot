import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

import '../../cubits/launch_profile_cubit.dart';
import '../../cubits/team_hub_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/discoverable_team.dart';
import '../../models/team_config.dart';
import '../../services/team/team_landing_recent_store.dart';
import '../../services/team/team_landing_selection.dart';

import 'team_hub_clone_feedback.dart';
import 'team_hub_clone_options_dialog.dart';
import 'team_hub_detail_overlay.dart';
import 'team_landing_catalog.dart';
import 'team_landing_picker_catalog_body.dart';
import 'team_landing_picker_local_detail.dart';

/// Landing team picker — returns the selected local [teamId], or `null`.
Future<String?> showTeamLandingPickerSheet(
  BuildContext context, {
  String? selectedTeamId,
  Future<void> Function(String teamId)? touchRecent,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => TeamLandingPickerDialog(
      selectedTeamId: selectedTeamId,
      touchRecent: touchRecent,
    ),
  );
}

/// Team Hub–style dialog: My Teams + discovery → detail → Confirm.
class TeamLandingPickerDialog extends StatefulWidget {
  const TeamLandingPickerDialog({
    this.selectedTeamId,
    this.touchRecent,
    super.key,
  });

  final String? selectedTeamId;

  /// Defaults to [TeamLandingRecentStore.touch].
  final Future<void> Function(String teamId)? touchRecent;

  @override
  State<TeamLandingPickerDialog> createState() =>
      _TeamLandingPickerDialogState();
}

class _TeamLandingPickerDialogState extends State<TeamLandingPickerDialog> {
  TeamLandingEntry? _detail;
  TeamLandingSourceFilter _sourceFilter = TeamLandingSourceFilter.all;
  String _search = '';
  bool _favoritesOnly = false;
  String? _category;
  bool _confirming = false;

  TeamLandingSelection get _selection => TeamLandingSelection(
    cloneTeam: (team, {teamMode, cli}) =>
        context.read<TeamHubCubit>().clone(team, teamMode: teamMode, cli: cli),
    touchRecent: widget.touchRecent ?? TeamLandingRecentStore().touch,
  );

  @override
  void initState() {
    super.initState();
    final cubit = context.read<TeamHubCubit>();
    if (cubit.state.allTeams.isEmpty &&
        cubit.state.status != TeamHubLoadStatus.loading) {
      unawaited(cubit.load());
    }
  }

  Future<void> _refreshLocalTeams() async {
    try {
      await context.read<LaunchProfileCubit>().load(bootSilent: true);
    } catch (_) {
      // Toast already shown; list refresh is best-effort.
    }
  }

  Future<void> _confirmLocal(TeamProfile team) async {
    if (_confirming) return;
    setState(() => _confirming = true);
    final l10n = context.l10n;
    try {
      final teams = context.read<LaunchProfileCubit>().state.teams;
      final result = await _selection.resolveLocal(
        teamId: team.id,
        teams: teams,
      );
      if (!mounted) return;
      Navigator.of(context).pop(result.teamId);
    } on TeamLandingSelectionException {
      if (!mounted) return;
      AppToast.show(
        context,
        message: l10n.teamHubNotFound,
        variant: TpToastVariant.error,
      );
      setState(() {
        _confirming = false;
        _detail = null;
      });
      unawaited(_refreshLocalTeams());
    } catch (_) {
      if (!mounted) return;
      AppToast.show(
        context,
        message: l10n.teamHubNotFound,
        variant: TpToastVariant.error,
      );
      setState(() {
        _confirming = false;
        _detail = null;
      });
      unawaited(_refreshLocalTeams());
    }
  }

  Future<void> _confirmHub(DiscoverableTeam team) async {
    if (_confirming) return;
    setState(() => _confirming = true);
    final l10n = context.l10n;
    try {
      final options = await resolveTeamHubCloneOptions(context, team);
      if (!mounted) return;
      if (options == null) {
        setState(() => _confirming = false);
        return; // 用户取消：不克隆
      }
      final teams = context.read<LaunchProfileCubit>().state.teams;
      final result = await _selection.resolveHub(
        team: team,
        teams: teams,
        teamMode: options.teamMode,
        cli: options.cli,
      );
      if (!mounted) return;
      final clone = result.cloneResult;
      if (clone != null) {
        AppToast.show(
          context,
          message: teamHubCloneToastMessage(
            l10n,
            teamName: team.name,
            result: clone,
          ),
          variant: teamHubCloneToastIsWarning(clone)
              ? TpToastVariant.warning
              : TpToastVariant.success,
        );
      }
      Navigator.of(context).pop(result.teamId);
    } on TeamLandingSelectionException {
      if (!mounted) return;
      AppToast.show(
        context,
        message: l10n.teamHubCloneFailed,
        variant: TpToastVariant.error,
      );
      setState(() => _confirming = false);
    } catch (_) {
      if (!mounted) return;
      AppToast.show(
        context,
        message: l10n.teamHubCloneFailed,
        variant: TpToastVariant.error,
      );
      setState(() => _confirming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;

    return PopScope(
      canPop: _detail == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_detail != null) {
          setState(() => _detail = null);
        }
      },
      child: TpDialog(
        maxWidth: 960,
        maxHeight: maxHeight,
        contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: SizedBox(
          height: maxHeight - 32,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TpDialogHeader(title: l10n.teamHubTitle),
              const SizedBox(height: 8),
              Expanded(
                child: BlocConsumer<TeamHubCubit, TeamHubState>(
                  listenWhen: (a, b) =>
                      a.errorMessage != b.errorMessage &&
                      b.errorMessage != null,
                  listener: (context, state) {
                    if (state.errorMessage == null) return;
                    AppToast.show(
                      context,
                      message: context.l10n.teamHubLoadError,
                      variant: TpToastVariant.error,
                    );
                    context.read<TeamHubCubit>().clearError();
                  },
                  builder: (context, hubState) {
                    final launchState =
                        context.watch<LaunchProfileCubit>().state;
                    final detail = _detail;
                    if (detail is TeamLandingLocalEntry) {
                      return TeamLandingPickerLocalDetail(
                        team: detail.team,
                        confirming: _confirming,
                        inset: 12,
                        onBack: () => setState(() => _detail = null),
                        onConfirm: () => _confirmLocal(detail.team),
                      );
                    }
                    if (detail is TeamLandingHubEntry) {
                      final hubCloning =
                          hubState.cloningKeys.contains(detail.team.key);
                      final willClone =
                          detail.localTeamId == null && _confirming;
                      return TeamHubDetailOverlay(
                        key: ValueKey(detail.team.key),
                        team: detail.team,
                        cloning: hubCloning || willClone,
                        confirming: _confirming,
                        installedDepIds: hubState.installedDepIds,
                        pickerMode: true,
                        alreadyAdded: detail.localTeamId != null,
                        inset: 12,
                        onBack: () => setState(() => _detail = null),
                        onClone: () {},
                        onConfirm: () => _confirmHub(detail.team),
                      );
                    }
                    return TeamLandingPickerCatalogBody(
                      hubState: hubState,
                      localTeams: launchState.teams,
                      sourceFilter: _sourceFilter,
                      search: _search,
                      favoritesOnly: _favoritesOnly,
                      category: _category,
                      selectedTeamId: widget.selectedTeamId,
                      onSourceFilter: (f) =>
                          setState(() => _sourceFilter = f),
                      onSearch: (q) => setState(() => _search = q),
                      onFavoritesOnly: (v) =>
                          setState(() => _favoritesOnly = v),
                      onCategory: (c) => setState(() => _category = c),
                      onOpen: (entry) => setState(() => _detail = entry),
                      onToggleFavorite: (key) =>
                          context.read<TeamHubCubit>().toggleFavorite(key),
                      onRefresh: () => context
                          .read<TeamHubCubit>()
                          .load(forceRefresh: true),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
