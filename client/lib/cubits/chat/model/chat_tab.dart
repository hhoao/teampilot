import 'dart:async';

import '../../../models/app_session.dart';
import '../../../services/team_bus/mcp/teammate_bus_mcp_server.dart';
import '../../../services/team_bus/team_bus.dart';
import '../../../services/terminal/terminal_session.dart';
import 'chat_tab_info.dart';

/// Per-tab runtime aggregate shared by ChatCubit and its collaborators.
/// (Formerly the private `_InternalTab`.)
class ChatTab {
  ChatTab({
    required this.info,
    required this.cliTeamName,
    this.selectedMemberId = '',
  });

  ChatTabInfo info;
  TerminalSession? resumeSession;
  String selectedMemberId;

  /// CLI `--team-name` and config-profiles runtime id ([AppSession.cliTeamName]).
  final String cliTeamName;

  /// Persisted session for team member connect (may be absent before index load).
  AppSession? persistedSession;

  /// Shared [LaunchPlan.memberConfigDir] from first successful member connect.
  String? memberToolConfigDir;

  final Map<String, TerminalSession> memberShells = {};

  /// mixed 模式：本 team 会话的进程内总线与其 loopback MCP server（随 tab 建/销）。
  TeamBus? teamBus;
  TeammateBusMcpServer? mcpServer;

  Future<void> disposeBus() async {
    await mcpServer?.stop();
    teamBus?.dispose();
    teamBus = null;
    mcpServer = null;
  }

  /// Member ids with a scheduled or in-flight member connect.
  final Set<String> membersPendingConnect = {};

  Iterable<TerminalSession> get sessions sync* {
    if (resumeSession != null) yield resumeSession!;
    yield* memberShells.values;
  }

  bool get isRunning => sessions.any((session) => session.isRunning);
}
