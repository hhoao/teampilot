import '../../cubits/chat/model/session_open_request.dart';
import '../../cubits/chat/model/session_open_status.dart';
import '../../cubits/chat/session_launch_host.dart';
import '../../models/team_config.dart';
import '../../models/workspace.dart';
import '../../repositories/session_repository.dart';
import '../../utils/logging/logger.dart';
import 'session_launch_workspace_index.dart';

typedef SessionOpenFn = Future<SessionOpenStatus> Function(SessionOpenRequest);

/// Creates and opens the first team/personal session when the tab store is empty.
class SessionDefaultMaterializer {
  SessionDefaultMaterializer({
    required SessionLaunchHost host,
    required SessionOpenFn openSession,
    required SessionLaunchWorkspaceIndex Function() workspaceIndex,
    required bool Function() isTabsEmpty,
    required String Function() activeBucketKey,
  }) : _host = host,
       _openSession = openSession,
       _workspaceIndex = workspaceIndex,
       _isTabsEmpty = isTabsEmpty,
       _activeBucketKey = activeBucketKey;

  final SessionLaunchHost _host;
  final SessionOpenFn _openSession;
  final SessionLaunchWorkspaceIndex Function() _workspaceIndex;
  final bool Function() _isTabsEmpty;
  final String Function() _activeBucketKey;

  Future<void> materializeTeamSession(
    TeamProfile team,
    SessionRepository repo, {
    required bool connectImmediately,
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
      await _openSession(
        SessionOpenRequest(
          session: existingSession,
          workspace: index.byId(existingSession.workspaceId),
          team: team,
          member: memberForInitialShell,
          repo: repo,
          connectImmediately: connectImmediately,
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

    var session = index.firstForWorkspaceAndTeam(workspace.workspaceId, team.id);
    session ??= await repo.createSession(
      workspace.workspaceId,
      sessionTeam: team.id,
      rosterMembers: team.members,
    );
    if (_host.isClosed) return;
    await _host.loadWorkspaceData(repo);
    if (_host.isClosed) return;
    await _openSession(
      SessionOpenRequest(
        session: session,
        workspace: workspace,
        team: team,
        member: memberForInitialShell,
        repo: repo,
        connectImmediately: connectImmediately,
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
    final existingSession = index.firstForPersonalWorkspace(workspace.workspaceId);
    if (existingSession != null) {
      await _openSession(
        SessionOpenRequest(
          session: existingSession,
          workspace: workspace,
          repo: repo,
          connectImmediately: connectImmediately,
        ),
      );
      return;
    }

    final cli = cliOverride ?? CliTool.claude;

    final session = await repo.createSession(
      workspace.workspaceId,
      cli: cli,
    );
    if (_host.isClosed) return;
    await _host.loadWorkspaceData(repo);
    if (_host.isClosed) return;
    await _openSession(
      SessionOpenRequest(
        session: session,
        workspace: workspace,
        repo: repo,
        connectImmediately: connectImmediately,
      ),
    );
  }
}
