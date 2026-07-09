import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:teampilot/theme/app_toast_theme.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

import '../../cubits/expert_hub_cubit.dart';
import '../../cubits/launch_profile_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/discoverable_member.dart';
import '../../models/team_config.dart';
import '../../services/expert_hub/local_expert_writer.dart';
import '../../services/expert_hub/member_roster_service.dart';
import '../../services/hub_publish/hub_publish_record_store.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/empty_state_block.dart';
import '../../widgets/settings/workspace_hub_shell.dart';
import '../expert_hub/expert_editor_dialog.dart';
import '../expert_hub/expert_team_picker_dialog.dart';
import '../expert_hub/member_hub_add_feedback.dart';
import '../home_workspace/home_workspace_route.dart';
import '../hub_publish/show_hub_publish_wizard.dart';
import 'my_experts_card.dart';

/// Ownership surface for local expert templates — list, create, edit, delete.
class MyExpertsPage extends StatefulWidget {
  const MyExpertsPage({
    super.key,
    this.writer,
    this.initialMemberKey,
  });

  /// Injectable for tests; defaults to [LocalExpertWriter].
  final LocalExpertWriter? writer;

  /// Deep-link member key (`?member=` on `/home-v2?global=myExperts`).
  final String? initialMemberKey;

  static const _pageKey = ValueKey('my-experts-workspace');

  @override
  State<MyExpertsPage> createState() => _MyExpertsPageState();
}

class _MyExpertsPageState extends State<MyExpertsPage> {
  late final LocalExpertWriter _writer =
      widget.writer ?? LocalExpertWriter();
  List<DiscoverableMember> _members = const [];
  var _loading = true;
  String? _highlightMemberKey;
  var _didAutoOpenEditor = false;

  @override
  void initState() {
    super.initState();
    _highlightMemberKey = widget.initialMemberKey;
    _reload();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final fromRoute = _readMemberQueryParam();
    if (fromRoute != null && fromRoute != _highlightMemberKey) {
      _highlightMemberKey = fromRoute;
      _didAutoOpenEditor = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoOpenEditor());
    }
  }

  String? _readMemberQueryParam() {
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      return HomeWorkspaceRoute.myExpertsMemberKey(
        router.routeInformationProvider.value.uri.toString(),
      );
    }
    return widget.initialMemberKey;
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final members = await _writer.loadAll();
    members.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (!mounted) return;
    setState(() {
      _members = members;
      _loading = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoOpenEditor());
  }

  void _maybeAutoOpenEditor() {
    if (_didAutoOpenEditor || _loading) return;
    final key = _highlightMemberKey;
    if (key == null) return;
    DiscoverableMember? match;
    for (final m in _members) {
      if (m.key == key) {
        match = m;
        break;
      }
    }
    if (match == null) return;
    _didAutoOpenEditor = true;
    _edit(match);
  }

  Future<void> _create() async {
    final saved = await showExpertEditorDialog(context, writer: _writer);
    if (saved == null || !mounted) return;
    await _reload();
  }

  Future<void> _edit(DiscoverableMember member) async {
    final saved = await showExpertEditorDialog(
      context,
      writer: _writer,
      initial: member,
    );
    if (saved == null || !mounted) return;
    await _reload();
  }

  List<TeamProfile> _referencingTeams(String expertKey) {
    final launch = context.read<LaunchProfileCubit>();
    return [
      for (final team in launch.state.teams)
        if (team.roster.any((slot) => slot.expertKey.trim() == expertKey))
          team,
    ];
  }

  Future<void> _delete(DiscoverableMember member) async {
    final l10n = context.l10n;
    final refs = _referencingTeams(member.key);
    if (refs.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AppDialog(
          maxWidth: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppDialogHeader(
                title: l10n.myExpertsDelete,
                onClose: () => Navigator.of(ctx).pop(),
              ),
              const SizedBox(height: 16),
              Text(l10n.myExpertsDeleteReferenced(member.name)),
              AppDialogActions(
                children: [
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(l10n.cancel),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        maxWidth: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppDialogHeader(
              title: l10n.myExpertsDelete,
              onClose: () => Navigator.of(ctx).pop(false),
            ),
            const SizedBox(height: 16),
            Text(l10n.myExpertsDeleteConfirm(member.name)),
            AppDialogActions(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text(l10n.cancel),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(ctx).colorScheme.error,
                  ),
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: Text(l10n.delete),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    await _writer.delete(member.key);
    if (!mounted) return;
    ExpertHubCubit? hub;
    try {
      hub = context.read<ExpertHubCubit>();
    } catch (_) {
      hub = null;
    }
    if (hub != null) {
      try {
        await hub.load(forceRefresh: true);
      } catch (_) {}
    }
    if (!mounted) return;
    await _reload();
  }

  Future<void> _addToTeam(DiscoverableMember member) async {
    final teamId = await showExpertTeamPickerDialog(context);
    if (teamId == null || !mounted) return;

    ExpertHubCubit? hub;
    try {
      hub = context.read<ExpertHubCubit>();
    } catch (_) {
      hub = null;
    }
    if (hub == null) return;

    final l10n = context.l10n;
    try {
      final result = await hub.addToTeam(teamId: teamId, member: member);
      if (!mounted) return;
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

  Future<void> _upload(DiscoverableMember member) async {
    await showHubPublishWizard(
      context,
      kind: HubPublishKind.expert,
      member: member,
    );
  }

  void _onCardAction(DiscoverableMember member, MyExpertsCardAction action) {
    switch (action) {
      case MyExpertsCardAction.edit:
        _edit(member);
      case MyExpertsCardAction.delete:
        _delete(member);
      case MyExpertsCardAction.addToTeam:
        _addToTeam(member);
      case MyExpertsCardAction.upload:
        _upload(member);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      key: MyExpertsPage._pageKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WorkspaceHubTitleBar(
            title: l10n.myExpertsTitle,
            subtitle: l10n.myExpertsSubtitle,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 18, 28, 0),
            child: Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                key: const Key('my-experts-create'),
                onPressed: _create,
                icon: const Icon(Icons.add),
                label: Text(l10n.myExpertsCreate),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _members.isEmpty
                ? EmptyStateBlock(
                    centered: true,
                    icon: Icons.person_outline,
                    title: l10n.myExpertsEmptyTitle,
                    hint: l10n.myExpertsEmptyHint,
                    actionLabel: l10n.myExpertsCreate,
                    onAction: _create,
                  )
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(28, 18, 28, 24),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 380,
                      mainAxisExtent: 186,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                    ),
                    itemCount: _members.length,
                    itemBuilder: (context, index) {
                      final member = _members[index];
                      return MyExpertsCard(
                        member: member,
                        selected: member.key == _highlightMemberKey,
                        onTap: () => _edit(member),
                        onAction: (action) => _onCardAction(member, action),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
