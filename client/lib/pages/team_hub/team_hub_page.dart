import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:teampilot/theme/app_toast_theme.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

import '../../cubits/team_hub_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/discoverable_team.dart';
import '../../services/app/platform_utils.dart';
import '../../services/team/team_clone_service.dart';
import '../../widgets/settings/workspace_hub_shell.dart';
import 'team_hub_body.dart';
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
  bool _detailForward = true;

  @override
  void initState() {
    super.initState();
    final cubit = context.read<TeamHubCubit>();
    if (cubit.state.status == TeamHubLoadStatus.idle) {
      cubit.load();
    }
  }

  Future<void> _clone(TeamHubCubit cubit, DiscoverableTeam team) async {
    final l10n = context.l10n;
    try {
      final result = await cubit.clone(team);
      if (!mounted) return;
      setState(() {
        _detailForward = false;
        _detail = null;
      });
      final failed = result.failedDeps.length;
      AppToast.show(
        context,
        message: failed == 0
            ? l10n.teamHubCloneSuccess(team.name)
            : l10n.teamHubClonePartial(team.name, failed),
        variant: failed == 0
            ? AppToastVariant.success
            : AppToastVariant.warning,
      );
    } on CloneException {
      if (!mounted) return;
      AppToast.show(
        context,
        message: l10n.teamHubCloneFailed,
        variant: AppToastVariant.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<TeamHubCubit, TeamHubState>(
      listenWhen: (a, b) =>
          a.errorMessage != b.errorMessage && b.errorMessage != null,
      listener: (context, state) {
        if (!mounted) return;
        AppToast.show(
          context,
          message: context.l10n.teamHubLoadError,
          variant: AppToastVariant.error,
        );
        context.read<TeamHubCubit>().clearError();
      },
      builder: (context, state) {
        final cubit = context.read<TeamHubCubit>();
        final android = useAndroidHubNavigation(context);
        final inset = android ? 16.0 : 28.0;
        final detail = _detail;

        final paneKey = ValueKey(detail?.key ?? 'team-hub-list');
        final pane = (detail != null
                ? TeamHubDetailOverlay(
                    key: paneKey,
                    team: detail,
                    cloning: state.cloningKeys.contains(detail.key),
                    installedDepIds: state.installedDepIds,
                    onBack: () => setState(() {
                      _detailForward = false;
                      _detail = null;
                    }),
                    onClone: () => _clone(cubit, detail),
                    inset: inset,
                  )
                : TeamHubBody(
                    key: paneKey,
                    cubit: cubit,
                    onOpen: (t) => setState(() {
                      _detailForward = true;
                      _detail = t;
                    }),
                    inset: inset,
                  ))
            .animate(key: paneKey)
            .fadeIn(duration: 180.ms, curve: Curves.easeOut)
            .slideX(
              begin: _detailForward ? 0.025 : -0.025,
              end: 0,
              duration: 220.ms,
              curve: Curves.easeOutCubic,
            );

        if (android) {
          return WorkspaceSectionPage(
            pageKey: _pageKey,
            padding: EdgeInsets.zero,
            child: pane,
          );
        }

        return Container(
          key: _pageKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (detail == null)
                WorkspaceHubTitleBar(
                  title: context.l10n.teamHubTitle,
                  subtitle: context.l10n.teamHubSubtitle,
                ),
              Expanded(child: pane),
            ],
          ),
        );
      },
    );
  }
}
