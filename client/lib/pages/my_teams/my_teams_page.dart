import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../cubits/launch_profile_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/team_config.dart';
import '../../services/hub_publish/hub_publish_record_store.dart';
import 'package:shared_ui/shared_ui.dart';
import '../../widgets/settings/workspace_hub_shell.dart';
import '../home_workspace/home_workspace_new_team_dialog.dart';
import '../home_workspace/home_workspace_route.dart';
import '../hub_publish/show_hub_publish_wizard.dart';
import '../team_config/team_delete_confirm_dialog.dart';
import 'my_teams_card.dart';

/// Ownership surface for local [TeamProfile]s — list, open, new, and delete.
class MyTeamsPage extends StatefulWidget {
  const MyTeamsPage({
    super.key,
    this.onOpenTeam,
    this.initialTeamId,
    this.records,
  });

  /// Clears the global view and opens team config for [id].
  final ValueChanged<String>? onOpenTeam;

  /// Deep-link team id (`?team=` on `/home-v2?global=myTeams`).
  final String? initialTeamId;

  /// Injectable for tests; defaults to [HubPublishRecordStore].
  final HubPublishRecordStore? records;

  static const _pageKey = ValueKey('my-teams-workspace');

  @override
  State<MyTeamsPage> createState() => _MyTeamsPageState();
}

class _MyTeamsPageState extends State<MyTeamsPage> {
  late final HubPublishRecordStore _records =
      widget.records ?? HubPublishRecordStore();
  String? _highlightTeamId;
  var _didAutoOpen = false;
  var _recordsEpoch = 0;

  @override
  void initState() {
    super.initState();
    _highlightTeamId = widget.initialTeamId;
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoOpen());
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    await _records.load();
    if (!mounted) return;
    setState(() => _recordsEpoch++);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final fromRoute = _readTeamQueryParam();
    if (fromRoute != null && fromRoute != _highlightTeamId) {
      _highlightTeamId = fromRoute;
      _didAutoOpen = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoOpen());
    }
  }

  String? _readTeamQueryParam() {
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      return HomeWorkspaceRoute.myTeamsTeamId(
        router.routeInformationProvider.value.uri.toString(),
      );
    }
    return widget.initialTeamId;
  }

  void _maybeAutoOpen() {
    if (_didAutoOpen) return;
    final teamId = _highlightTeamId;
    if (teamId == null) return;
    final cubit = context.read<LaunchProfileCubit>();
    if (!cubit.state.teams.any((team) => team.id == teamId)) return;
    _didAutoOpen = true;
    widget.onOpenTeam?.call(teamId);
  }

  Future<void> _deleteTeam(
    BuildContext context,
    LaunchProfileCubit cubit,
    TeamProfile team,
  ) async {
    final confirmed = await confirmDeleteTeam(context, team.name);
    if (!confirmed || !context.mounted) return;
    await cubit.deleteTeam(team.id);
  }

  Future<void> _uploadTeam(TeamProfile team) async {
    await showHubPublishWizard(
      context,
      kind: HubPublishKind.team,
      team: team,
      records: _records,
    );
    if (!mounted) return;
    await _loadRecords();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      key: MyTeamsPage._pageKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WorkspaceHubTitleBar(
            title: l10n.myTeamsTitle,
            subtitle: l10n.myTeamsSubtitle,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 18, 28, 0),
            child: Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () => showHomeNewTeamDialog(
                  context,
                  context.read<LaunchProfileCubit>(),
                ),
                icon: const Icon(Icons.add),
                label: Text(l10n.homeWorkspaceNewTeam),
              ),
            ),
          ),
          Expanded(
            child: BlocBuilder<LaunchProfileCubit, LaunchProfileState>(
              buildWhen: (a, b) => a.teams != b.teams || a.isLoading != b.isLoading,
              builder: (context, state) {
                if (state.isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }
                final teams = state.teams;
                if (teams.isEmpty) {
                  return TpEmptyState(
                    centered: true,
                    icon: Icons.groups_2_outlined,
                    title: l10n.myTeamsEmptyTitle,
                    hint: l10n.myTeamsEmptyHint,
                    actionLabel: l10n.homeWorkspaceNewTeam,
                    onAction: () => showHomeNewTeamDialog(
                      context,
                      context.read<LaunchProfileCubit>(),
                    ),
                  );
                }
                final highlightId = _highlightTeamId ?? state.selectedTeamId;
                return GridView.builder(
                  key: ValueKey('my-teams-grid-$_recordsEpoch'),
                  padding: const EdgeInsets.fromLTRB(28, 18, 28, 24),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 380,
                    mainAxisExtent: 220,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                  ),
                  itemCount: teams.length,
                  itemBuilder: (context, index) {
                    final team = teams[index];
                    return MyTeamsCard(
                      team: team,
                      selected: team.id == highlightId,
                      publishRecord: _records.findByLocalId(
                        kind: HubPublishKind.team,
                        localId: team.id,
                      ),
                      onOpen: () => widget.onOpenTeam?.call(team.id),
                      onUpload: () => _uploadTeam(team),
                      onDelete: () => _deleteTeam(
                        context,
                        context.read<LaunchProfileCubit>(),
                        team,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
