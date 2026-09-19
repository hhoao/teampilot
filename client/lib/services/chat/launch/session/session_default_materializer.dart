import '../../session/session_open_request.dart';
import '../session_launch_host.dart';
import '../../../../models/member_instance.dart';
import '../../../../models/team_config.dart';
import '../../../../models/workspace.dart';
import '../../../../repositories/session_repository.dart';
import 'session_member_cli_locks.dart';
import '../../../../utils/logging/logger.dart';
import 'session_launch_coordinator.dart';
import 'session_launch_workspace_index.dart';

/// Creates and opens the first team/personal session when the tab store is empty.
class SessionDefaultMaterializer {
  SessionDefaultMaterializer({
    required SessionLaunchHost host,
    required SessionLaunchIntentPort coordinator,
    required SessionLaunchWorkspaceIndex Function() workspaceIndex,
    required bool Function() isTabsEmpty,
    required String Function() activeBucketKey,
  }) : _host = host,
       _coordinator = coordinator,
       _workspaceIndex = workspaceIndex,
       _isTabsEmpty = isTabsEmpty,
       _activeBucketKey = activeBucketKey;

  final SessionLaunchHost _host;
  final SessionLaunchIntentPort _coordinator;
  final SessionLaunchWorkspaceIndex Function() _workspaceIndex;
  final bool Function() _isTabsEmpty;
  final String Function() _activeBucketKey;

  Future<void> materializeTeamSession(
    TeamProfile team,
    SessionRepository repo, {
    required bool connectImmediately,
    bool scheduleConnect = true,
    required TeamMemberConfig memberForInitialShell,
    String? workspaceCwd,
  }) async {
    if (!_isTabsEmpty()) return;

    final index = _workspaceIndex();
    final cwd = SessionLaunchWorkspaceIndex.resolveWorkspaceCwd(
      explicitCwd: workspaceCwd,
      activeBucketKey: _activeBucketKey(),
      index: index,
    );
    final existingSession = index.existingTeamSessionForMaterialize(
      team: team,
      workspaceCwd: cwd,
    );
    if (existingSession != null) {
      await _coordinator.open(
        SessionOpenRequest(
          session: existingSession,
          workspace: index.byId(existingSession.workspaceId),
          team: team,
          member: memberForInitialShell,
          repo: repo,
          connectImmediately: connectImmediately,
          scheduleConnect: scheduleConnect,
          waitForCompletion: true,
        ),
      );
      return;
    }

    if (cwd == null || cwd.isEmpty) {
      const message = 'Open a workspace before starting a team session.';
      appLogger.w('[session] $message');
      _host.failSessionConnect('pending', message);
      return;
    }

    final workspace = index.matchingPath(cwd);
    if (workspace == null) {
      final message = 'Workspace not found for $cwd.';
      appLogger.w('[session] $message');
      _host.failSessionConnect('pending', message);
      return;
    }

    var session = index.firstForWorkspaceAndTeam(
      workspace.workspaceId,
      team.id,
    );
    final created = await repo.createSession(
      workspace.workspaceId,
      sessionTeam: team.id,
      rosterMembers: runtimeRosterMembers(team),
      memberClis: resolveSessionMemberCliLocks(
        team: team,
        rosterMembers: runtimeRosterMembers(team),
        globalPresets: _host.lifecycle.globalPresets,
      ),
    );
    session = created.session;
    if (_host.isClosed) return;
    _host.emitSnapshot(
      _host.dataStore.snapshotWithWorkspace(
        _host.stateSnapshot(),
        created.workspace,
      ),
    );
    _host.appendSessionSnapshot(session);
    if (_host.isClosed) return;
    await _coordinator.open(
      SessionOpenRequest(
        session: session,
        workspace: workspace,
        team: team,
        member: memberForInitialShell,
        repo: repo,
        connectImmediately: connectImmediately,
        scheduleConnect: scheduleConnect,
        waitForCompletion: true,
      ),
    );
  }

  Future<void> materializePersonalSession(
    Workspace workspace,
    SessionRepository repo, {
    required bool connectImmediately,
    CliTool? cliOverride,
  }) async {
    if (!_isTabsEmpty()) return;

    final index = _workspaceIndex();
    final existingSession = index.firstForPersonalWorkspace(
      workspace.workspaceId,
    );
    if (existingSession != null) {
      await _coordinator.open(
        SessionOpenRequest(
          session: existingSession,
          workspace: workspace,
          repo: repo,
          connectImmediately: connectImmediately,
          waitForCompletion: true,
        ),
      );
      return;
    }

    final cli = cliOverride ?? CliTool.claude;

    final created = await repo.createSession(workspace.workspaceId, cli: cli);
    final session = created.session;
    if (_host.isClosed) return;
    _host.emitSnapshot(
      _host.dataStore.snapshotWithWorkspace(
        _host.stateSnapshot(),
        created.workspace,
      ),
    );
    _host.appendSessionSnapshot(session);
    if (_host.isClosed) return;
    await _coordinator.open(
      SessionOpenRequest(
        session: session,
        workspace: workspace,
        repo: repo,
        connectImmediately: connectImmediately,
        waitForCompletion: true,
      ),
    );
  }
}
