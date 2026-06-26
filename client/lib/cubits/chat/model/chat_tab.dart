import 'dart:async';

import '../../../models/app_session.dart';
import '../../../services/ssh/ssh_member_session.dart';
import '../../../services/team_bus/mcp/teammate_bus_mcp_server.dart';
import '../../../services/team_bus/remote/remote_bus_mount.dart';
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
    this.workspaceId = '',
  });

  ChatTabInfo info;
  TerminalSession? resumeSession;
  String selectedMemberId;

  /// Owning workspace bucket in [ChatTabStore]. Empty for legacy/local scratch
  /// tabs created without a workspace context.
  String workspaceId;

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

  /// Per-member reverse-tunnel bus mounts (session plane). One mount per remote
  /// roster member so auto-launching multiple ssh members does not tear down
  /// siblings.
  final Map<String, RemoteBusMount> memberRemoteBusMounts = {};

  /// Session-plane SSH connections keyed by roster member id (or session id for
  /// personal remote). Closed when the member shell disconnects or the tab bus
  /// is disposed — not pooled with storage SFTP.
  final Map<String, SshMemberSession> memberSshSessions = {};

  Future<void> closeMemberRemoteBusMount(String memberId) async {
    await memberRemoteBusMounts.remove(memberId)?.close();
  }

  void closeMemberSshSession(String memberId) {
    memberSshSessions.remove(memberId)?.close();
  }

  /// Tears down one member's session-plane SSH connection and bus mount.
  Future<void> closeMemberRemotePlane(String memberId) async {
    await closeMemberRemoteBusMount(memberId);
    closeMemberSshSession(memberId);
  }

  Future<void> disposeBus() async {
    for (final id in memberRemoteBusMounts.keys.toList()) {
      await closeMemberRemoteBusMount(id);
    }
    for (final id in memberSshSessions.keys.toList()) {
      closeMemberSshSession(id);
    }
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
