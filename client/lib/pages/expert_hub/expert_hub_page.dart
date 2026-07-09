import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:teampilot/theme/app_toast_theme.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

import '../../cubits/expert_hub_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/discoverable_member.dart';
import '../../services/app/platform_utils.dart';
import '../../services/expert_hub/member_roster_service.dart';
import '../../widgets/settings/workspace_hub_shell.dart';
import '../home_workspace/home_workspace_route.dart';
import 'expert_hub_body.dart';
import 'expert_hub_detail_overlay.dart';
import 'expert_editor_dialog.dart';
import 'member_hub_add_feedback.dart';

typedef ExpertAddToTeamHandler =
    Future<void> Function(
      BuildContext context,
      ExpertHubCubit cubit,
      DiscoverableMember member,
    );

typedef ExpertLaunchInWorkspaceHandler =
    void Function(BuildContext context, DiscoverableMember member);

/// Single-page expert hub: search + inline filters over a grid, with an
/// embedded detail overlay. No sub-section navigation.
class ExpertHubPage extends StatefulWidget {
  const ExpertHubPage({
    super.key,
    this.onAddToTeam,
    this.onLaunchInWorkspace,
  });

  /// When null, [Add to team] is a no-op until Task 9 wires the team picker.
  final ExpertAddToTeamHandler? onAddToTeam;

  /// When null, [Launch in workspace] is a no-op until Task 9 wires the picker.
  final ExpertLaunchInWorkspaceHandler? onLaunchInWorkspace;

  @override
  State<ExpertHubPage> createState() => _ExpertHubPageState();
}

class _ExpertHubPageState extends State<ExpertHubPage> {
  static const _pageKey = ValueKey('expert-hub-workspace');

  DiscoverableMember? _detail;
  String? _pendingMemberKey;

  @override
  void initState() {
    super.initState();
    final cubit = context.read<ExpertHubCubit>();
    if (cubit.state.status == ExpertHubLoadStatus.idle) {
      cubit.load();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _tryOpenPendingMember(cubit.state);
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // GoRouterState.of depends on ModalRoute — unsafe in initState.
    _pendingMemberKey ??= _readMemberQueryParam();
    if (_pendingMemberKey != null) {
      _tryOpenPendingMember(context.read<ExpertHubCubit>().state);
    }
  }

  String? _readMemberQueryParam() {
    final location = GoRouterState.of(context).uri.toString();
    return HomeWorkspaceRoute.expertHubMemberKey(location);
  }

  void _tryOpenPendingMember(ExpertHubState state) {
    final key = _pendingMemberKey;
    if (key == null || _detail != null) return;
    for (final member in state.allMembers) {
      if (member.key == key) {
        setState(() {
          _detail = member;
          _pendingMemberKey = null;
        });
        return;
      }
    }
    if (state.status == ExpertHubLoadStatus.ready) {
      _pendingMemberKey = null;
    }
  }

  Future<void> _handleAddToTeam(
    ExpertHubCubit cubit,
    DiscoverableMember member,
  ) async {
    final handler = widget.onAddToTeam;
    if (handler == null) return;

    final l10n = context.l10n;
    try {
      await handler(context, cubit, member);
      if (!mounted) return;
      setState(() => _detail = null);
    } on MemberAddException {
      if (!mounted) return;
      AppToast.show(
        context,
        message: l10n.expertHubAddFailed,
        variant: AppToastVariant.error,
      );
    }
  }

  void _handleLaunchInWorkspace(DiscoverableMember member) {
    widget.onLaunchInWorkspace?.call(context, member);
  }

  Future<void> _handleCreate() async {
    final saved = await showExpertEditorDialog(context);
    if (saved == null || !mounted) return;
    await context.read<ExpertHubCubit>().load(forceRefresh: true);
  }

  /// Shows a success/warning toast after [cubit.addToTeam] completes.
  Future<void> addToTeamWithFeedback({
    required ExpertHubCubit cubit,
    required String teamId,
    required DiscoverableMember member,
  }) async {
    final l10n = context.l10n;
    try {
      final result = await cubit.addToTeam(teamId: teamId, member: member);
      if (!mounted) return;
      setState(() => _detail = null);
      AppToast.show(
        context,
        message: memberHubAddToastMessage(
          l10n,
          memberName: member.name,
          result: result,
        ),
        variant: memberHubAddToastIsWarning(result)
            ? AppToastVariant.warning
            : AppToastVariant.success,
      );
    } on MemberAddException {
      if (!mounted) return;
      AppToast.show(
        context,
        message: l10n.expertHubAddFailed,
        variant: AppToastVariant.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ExpertHubCubit, ExpertHubState>(
      listenWhen: (a, b) =>
          (_pendingMemberKey != null &&
              (a.allMembers != b.allMembers || a.status != b.status)) ||
          (a.errorMessage != b.errorMessage && b.errorMessage != null),
      listener: (context, state) {
        if (_pendingMemberKey != null) {
          _tryOpenPendingMember(state);
        }
        if (state.errorMessage == null) return;
        if (!mounted) return;
        AppToast.show(
          context,
          message: context.l10n.expertHubLoadError,
          variant: AppToastVariant.error,
        );
        context.read<ExpertHubCubit>().clearError();
      },
      builder: (context, state) {
        final cubit = context.read<ExpertHubCubit>();
        final android = useAndroidHubNavigation(context);
        final inset = android ? 16.0 : 28.0;
        final detail = _detail;

        final paneKey = ValueKey(detail?.key ?? 'expert-hub-list');
        final pane = detail != null
            ? ExpertHubDetailOverlay(
                key: paneKey,
                member: detail,
                favorited: state.favorites.contains(detail.key),
                adding: state.addingKeys.contains(detail.key),
                installedDepIds: state.installedDepIds,
                onBack: () => setState(() => _detail = null),
                onToggleFavorite: () => cubit.toggleFavorite(detail.key),
                onAddToTeam: widget.onAddToTeam == null
                    ? () {}
                    : () => _handleAddToTeam(cubit, detail),
                onLaunchInWorkspace: widget.onLaunchInWorkspace == null
                    ? () {}
                    : () => _handleLaunchInWorkspace(detail),
                inset: inset,
              )
            : ExpertHubBody(
                key: paneKey,
                cubit: cubit,
                onOpen: (m) => setState(() => _detail = m),
                onCreate: _handleCreate,
                inset: inset,
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
                  title: context.l10n.expertHubTitle,
                  subtitle: context.l10n.expertHubSubtitle,
                ),
              Expanded(child: pane),
            ],
          ),
        );
      },
    );
  }
}
