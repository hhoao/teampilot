part of '../context_sidebar.dart';

void _navigateToSessionInChat(BuildContext context, AppSession session) {
  final l10n = context.l10n;
  final teamCubit = context.read<TeamCubit>();
  final chatCubit = context.read<ChatCubit>();

  chatCubit.selectSession(session.sessionId);

  final matchingTeam = teamCubit.state.selectedTeam;
  if (matchingTeam == null) return;

  final lead = matchingTeam.members.where((m) => m.id == 'team-lead');
  final repo = context.read<SessionRepository>();
  if (lead.isNotEmpty) {
    unawaited(
      chatCubit.openSessionTab(
        session,
        team: matchingTeam,
        member: lead.first,
        repo: repo,
        emptyDisplayTitleFallback: l10n.defaultNewChatSessionTitle,
      ),
    );
  } else {
    unawaited(
      chatCubit.openSessionTab(
        session,
        repo: repo,
        emptyDisplayTitleFallback: l10n.defaultNewChatSessionTitle,
      ),
    );
    chatCubit.addSystemMessage('FlashskyAI requires a member named team-lead.');
  }

  goFromSidebar(context, '/chat');
}

Future<void> _createSessionAndOpenChat(
  BuildContext context,
  String projectId,
) async {
  final repo = context.read<SessionRepository>();
  final team = context.read<TeamCubit>().state.selectedTeam;
  final teamId = team?.id ?? '';
  final session = await context.read<ChatCubit>().createSession(
    projectId,
    repo,
    sessionTeamId: teamId,
    rosterMembers: team?.members ?? const [],
  );
  if (!context.mounted) return;
  _navigateToSessionInChat(context, session);
}

AppProject? _mostRecentProject(
  List<AppProject> projects,
  List<AppSession> sessions,
) {
  if (projects.isEmpty) return null;
  final sorted = List<AppProject>.from(projects)
    ..sort(
      (a, b) =>
          _projectRecency(b, sessions).compareTo(_projectRecency(a, sessions)),
    );
  return sorted.first;
}

String _projectDisplayName(AppProject project, AppLocalizations l10n) {
  if (project.effectiveDisplay.isNotEmpty) return project.effectiveDisplay;
  if (project.primaryPath.isNotEmpty) {
    return project.primaryPath.split(RegExp(r'[/\\]')).last;
  }
  return l10n.unknownFolder;
}

List<AppProject> _sortedProjects(
  List<AppProject> projects,
  List<AppSession> sessions,
) {
  final sorted = List<AppProject>.from(projects)
    ..sort(
      (a, b) =>
          _projectRecency(b, sessions).compareTo(_projectRecency(a, sessions)),
    );
  return sorted;
}

AppProject? _resolveSelectedProject(
  List<AppProject> projects,
  List<AppSession> sessions,
  String? selectedProjectId,
) {
  if (projects.isEmpty) return null;
  if (selectedProjectId != null) {
    for (final p in projects) {
      if (p.projectId == selectedProjectId) return p;
    }
  }
  return _mostRecentProject(projects, sessions);
}

Future<void> _startNewChat(
  BuildContext context, {
  String? preferredProjectId,
}) async {
  closeAndroidDrawerIfOpen(context);
  final chatCubit = context.read<ChatCubit>();
  final repo = context.read<SessionRepository>();
  final teamId = context.read<TeamCubit>().state.selectedTeam?.id ?? '';
  final projects = chatCubit.state.visibleProjects;
  final sessions = chatCubit.state.visibleSessions;

  AppProject? project;
  if (preferredProjectId != null && preferredProjectId.isNotEmpty) {
    for (final p in projects) {
      if (p.projectId == preferredProjectId) {
        project = p;
        break;
      }
    }
  }
  project ??= _mostRecentProject(projects, sessions);
  if (project != null) {
    await _createSessionAndOpenChat(context, project.projectId);
    return;
  }

  try {
    final team = context.read<TeamCubit>().state.selectedTeam;
    await chatCubit.createProjectWithFirstSession(
      AppStorage.cwd,
      repo,
      sessionTeamId: teamId,
      rosterMembers: team?.members ?? const [],
    );
  } on Object catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${context.l10n.defaultNewChatSessionTitle}: $error'),
      ),
    );
    return;
  }
  if (!context.mounted) return;

  final created = context.read<ChatCubit>().state.visibleSessions;
  if (created.isEmpty) return;
  final newest = created.reduce((a, b) => a.createdAt >= b.createdAt ? a : b);
  _navigateToSessionInChat(context, newest);
}

Future<void> _promptAddTeam(BuildContext context, TeamCubit teamCubit) async {
  final l10n = context.l10n;
  final result = await showDialog<
      ({String name, CliTool cli, TeamMode teamMode})?>(
    context: context,
    builder: (dialogContext) => _AddTeamDialog(l10n: l10n),
  );
  if (result == null || !context.mounted) return;
  final now = DateTime.now().millisecondsSinceEpoch;
  await teamCubit.addTeam(
    result.name,
    cli: result.cli,
    teamMode: result.teamMode,
    members: DefaultTeamRoster.localized(l10n, joinedAt: now),
  );
}

/// Owns the team name [TextEditingController] for the add-team dialog.
///
/// The dialog route can still be animating after [showDialog]'s future
/// completes; disposing the controller in the caller would race updates
/// against a still-mounted [TextField].
class _AddTeamDialog extends StatefulWidget {
  const _AddTeamDialog({required this.l10n});

  final AppLocalizations l10n;

  @override
  State<_AddTeamDialog> createState() => _AddTeamDialogState();
}

class _AddTeamDialogState extends State<_AddTeamDialog> {
  late final TextEditingController _nameController;
  TeamMode _selectedMode = TeamMode.native;
  CliTool _selectedCli = CliTool.flashskyai;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final launchable = CliToolRegistryScope.of(context).launchable.toList()
      ..sort((a, b) => a.id.value.compareTo(b.id.value));
    return AlertDialog(
      title: Text(l10n.addTeamTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: AppKeys.teamNameDialogField,
            controller: _nameController,
            autofocus: true,
            decoration: InputDecoration(labelText: l10n.teamName),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.teamModeLabel,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          RadioGroup<TeamMode>(
            groupValue: _selectedMode,
            onChanged: (value) {
              if (value == null) return;
              setState(() => _selectedMode = value);
            },
            child: Column(
              children: [
                RadioListTile<TeamMode>(
                  value: TeamMode.native,
                  title: Text(l10n.teamModeNative),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                RadioListTile<TeamMode>(
                  value: TeamMode.mixed,
                  title: Text(l10n.teamModeMixed),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.teamCliLabel,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 4),
          Text(
            l10n.teamCliSubtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          RadioGroup<CliTool>(
            groupValue: _selectedCli,
            onChanged: (value) {
              if (value == null) return;
              setState(() => _selectedCli = value);
            },
            child: Column(
              children: [
                for (final def in launchable)
                  RadioListTile<CliTool>(
                    value: CliTool.decode(def.id),
                    title: Text(cliDisplayName(def, l10n)),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () {
            final name = _nameController.text.trim();
            if (name.isEmpty) return;
            Navigator.pop(
              context,
              (name: name, cli: _selectedCli, teamMode: _selectedMode),
            );
          },
          child: Text(l10n.add),
        ),
      ],
    );
  }
}
