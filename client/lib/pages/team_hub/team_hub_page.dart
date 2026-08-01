import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

import '../../cubits/team_hub_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/discoverable_team.dart';
import '../../services/app/platform_utils.dart';
import '../../services/team/team_clone_service.dart';
import '../../widgets/settings/workspace_hub_shell.dart';
import '../../widgets/settings/workspace_pane_header.dart';
import '../home_workspace/home_workspace_route.dart';
import 'team_hub_body.dart';
import 'team_hub_clone_feedback.dart';
import 'team_hub_detail_overlay.dart';

/// Single-page team hub: search + inline filters (favorites, category) over a
/// grid, with an embedded detail overlay. No sub-section navigation.
class TeamHubPage extends StatefulWidget {
  const TeamHubPage({super.key});

  @override
  State<TeamHubPage> createState() => _TeamHubPageState();
}

class _TeamHubPageState extends State<TeamHubPage> {
  static const _pageKey = ValueKey('team-hub-workspace');

  DiscoverableTeam? _detail;
  String? _pendingTeamKey;

  @override
  void initState() {
    super.initState();
    final cubit = context.read<TeamHubCubit>();
    if (cubit.state.status == TeamHubLoadStatus.idle) {
      cubit.load();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _tryOpenPendingTeam(cubit.state);
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _pendingTeamKey ??= _readTeamQueryParam();
    if (_pendingTeamKey != null) {
      _tryOpenPendingTeam(context.read<TeamHubCubit>().state);
    }
  }

  String? _readTeamQueryParam() {
    final location = GoRouterState.of(context).uri.toString();
    return HomeWorkspaceRoute.teamHubTeamKey(location);
  }

  void _tryOpenPendingTeam(TeamHubState state) {
    final key = _pendingTeamKey;
    if (key == null || _detail != null) return;
    for (final team in state.allTeams) {
      if (team.key == key) {
        setState(() {
          _detail = team;
          _pendingTeamKey = null;
        });
        return;
      }
    }
    if (state.status == TeamHubLoadStatus.ready) {
      _pendingTeamKey = null;
    }
  }

  Future<void> _clone(TeamHubCubit cubit, DiscoverableTeam team) async {
    final l10n = context.l10n;
    try {
      final result = await cubit.clone(team);
      if (!mounted) return;
      setState(() => _detail = null);
      AppToast.show(
        context,
        message: teamHubCloneToastMessage(
          l10n,
          teamName: team.name,
          result: result,
        ),
        variant: teamHubCloneToastIsWarning(result)
            ? TpToastVariant.warning
            : TpToastVariant.success,
      );
    } on CloneException {
      if (!mounted) return;
      AppToast.show(
        context,
        message: l10n.teamHubCloneFailed,
        variant: TpToastVariant.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<TeamHubCubit, TeamHubState>(
      listenWhen: (a, b) =>
          (_pendingTeamKey != null &&
              (a.allTeams != b.allTeams || a.status != b.status)) ||
          (a.errorMessage != b.errorMessage && b.errorMessage != null),
      listener: (context, state) {
        if (_pendingTeamKey != null) {
          _tryOpenPendingTeam(state);
        }
        if (state.errorMessage == null) return;
        if (!mounted) return;
        AppToast.show(
          context,
          message: context.l10n.teamHubLoadError,
          variant: TpToastVariant.error,
        );
        context.read<TeamHubCubit>().clearError();
      },
      builder: (context, state) {
        final cubit = context.read<TeamHubCubit>();
        final android = useAndroidHubNavigation(context);
        final listInset = android ? 16.0 : 0.0;
        final detailInset = android ? 16.0 : 28.0;
        final detail = _detail;

        final paneKey = ValueKey(detail?.key ?? 'team-hub-list');
        final pane = detail != null
            ? TeamHubDetailOverlay(
                key: paneKey,
                team: detail,
                cloning: state.cloningKeys.contains(detail.key),
                installedDepIds: state.installedDepIds,
                onBack: () => setState(() => _detail = null),
                onClone: () => _clone(cubit, detail),
                inset: detailInset,
              )
            : TeamHubBody(
                key: paneKey,
                cubit: cubit,
                onOpen: (t) => setState(() => _detail = t),
                inset: listInset,
              );

        if (android) {
          return WorkspaceSectionPage(
            pageKey: _pageKey,
            padding: EdgeInsets.zero,
            // Always hosted inside home [WorkspacePageCardShell].
            embedded: true,
            child: pane,
          );
        }

        return Container(
          key: _pageKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (detail == null)
                WorkspacePaneHeader(title: context.l10n.teamHubTitle),
              Expanded(child: pane),
            ],
          ),
        );
      },
    );
  }
}
