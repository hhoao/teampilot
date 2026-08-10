import '../../cubits/chat/model/chat_tab.dart';
import '../../cubits/chat/model/session_open_request.dart';
import '../../models/app_session.dart';
import '../../models/team_config.dart';
import '../../models/workspace.dart';
import '../../services/terminal/terminal_session.dart';
import '../../utils/logging/logger.dart';

typedef ResolvedLaunchMembers = ({
  TeamProfile? team,
  TeamMemberConfig member,
  CliTool cli,
});

class TabConnectPrepResult {
  const TabConnectPrepResult({
    required this.launchSession,
    required this.resolved,
    required this.shell,
  });

  final AppSession launchSession;
  final ResolvedLaunchMembers resolved;
  final TerminalSession shell;
}

/// Callbacks the shared tab-connect prep pipeline needs from [SessionLaunchService].
typedef SessionTabConnectPrepCallbacks = ({
  Future<AppSession> Function({
    required SessionOpenRequest request,
    required AppSession session,
    required ChatTab tab,
  })
  persistSessionIfNeeded,
  Future<AppSession?> Function({
    required SessionOpenRequest request,
    required AppSession session,
    required Workspace? workspace,
  })
  ensureTeamSessionReady,
  void Function({
    required ChatTab tab,
    required AppSession launchSession,
    required SessionOpenRequest request,
  })
  onMixedPlacementNotReady,
  Future<ResolvedLaunchMembers> Function({
    required AppSession session,
    required SessionOpenRequest request,
    Workspace? workspace,
  })
  resolveLaunchMembers,
  Future<void> Function({
    required ChatTab tab,
    required AppSession session,
    required TeamProfile? team,
    required int generation,
  })
  installTeamRuntimeIfNeeded,
  void Function(String memberId) updateSelectedMember,
  TerminalSession Function({
    required ChatTab tab,
    required String shellKey,
    required CliTool cli,
    required AppSession session,
    String? rosterMemberId,
  })
  shellForLaunch,
  bool Function(ChatTab tab, int generation) launchStillValid,
});

/// Shared persist → readiness → resolve → shell prep for new and existing tabs.
Future<TabConnectPrepResult?> runSessionTabConnectPrep({
  required SessionTabConnectPrepCallbacks callbacks,
  required int generation,
  required ChatTab tab,
  required AppSession session,
  required SessionOpenRequest request,
  required Workspace? workspace,
  required bool installTeamRuntime,
}) async {
  final total = Stopwatch()..start();
  Future<T> step<T>(String name, Future<T> Function() run) async {
    final sw = Stopwatch()..start();
    final result = await run();
    appLogger.d(
      '[session-launch] tab-prep $name '
      'session=${session.sessionId} ms=${sw.elapsedMilliseconds}',
    );
    return result;
  }

  var launchSession = session;
  launchSession = await step(
    'persist',
    () => callbacks.persistSessionIfNeeded(
      request: request,
      session: session,
      tab: tab,
    ),
  );
  if (!callbacks.launchStillValid(tab, generation)) return null;

  final ready = await step(
    'ensure-ready',
    () => callbacks.ensureTeamSessionReady(
      request: request,
      session: launchSession,
      workspace: workspace,
    ),
  );
  if (!callbacks.launchStillValid(tab, generation)) return null;
  if (ready == null) {
    callbacks.onMixedPlacementNotReady(
      tab: tab,
      launchSession: launchSession,
      request: request,
    );
    return null;
  }
  launchSession = ready;
  tab.persistedSession = ready;

  final resolved = await step(
    'resolve-members',
    () => callbacks.resolveLaunchMembers(
      session: launchSession,
      request: request,
      workspace: workspace,
    ),
  );
  if (!callbacks.launchStillValid(tab, generation)) return null;

  if (installTeamRuntime) {
    await step(
      'install-team-runtime',
      () => callbacks.installTeamRuntimeIfNeeded(
        tab: tab,
        session: launchSession,
        team: resolved.team,
        generation: generation,
      ),
    );
    if (!callbacks.launchStillValid(tab, generation)) return null;
  }

  callbacks.updateSelectedMember(resolved.member.id);
  tab.selectedMemberId = resolved.member.id;

  final shell = callbacks.shellForLaunch(
    tab: tab,
    shellKey: resolved.member.id,
    cli: resolved.cli,
    session: launchSession,
    rosterMemberId: request.isPersonal ? null : resolved.member.id,
  );

  appLogger.d(
    '[session-launch] tab-prep done '
    'session=${launchSession.sessionId} ms=${total.elapsedMilliseconds}',
  );
  return TabConnectPrepResult(
    launchSession: launchSession,
    resolved: resolved,
    shell: shell,
  );
}
