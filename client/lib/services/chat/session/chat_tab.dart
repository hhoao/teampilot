import 'dart:async';

import '../../../models/app_session.dart';
import '../../../models/member_remote_provision_progress.dart';
import '../../../cubits/session/acp/acp_chat_runtime_cubit.dart';
import '../../ssh/ssh_member_session.dart';
import '../team_bus/mcp/teammate_bus_session_registry.dart';
import '../team_bus/remote/remote_bus_mount.dart';
import '../team_bus/team_bus.dart';
import '../../terminal/terminal_session.dart';
import 'chat_tab_info.dart';
import 'session_workbench_view.dart';

/// True when [session] is a terminal-less ACP chat session (phase 1: a
/// personal gemini session). Such sessions skip shell-connect and attach an
/// [AcpChatRuntimeCubit] instead; the chat center view is their only view.
bool isAcpChatSession(AppSession session) => session.isSimple && session.acp;

bool isAcpChatSeat(AppSession session, String memberId) =>
    !session.isSimple && (session.bindingFor(memberId)?.acp ?? false);

/// Cubit for the chat surface the user is looking at.
///
/// Personal ACP reads the session-id alias. A mixed seat reads that member's
/// entry and nothing else, so a lead cubit is not shown for a PTY teammate.
AcpChatRuntimeCubit? acpRuntimeForView({
  required AppSession session,
  required ChatTab tab,
  required String selectedMemberId,
}) {
  if (isAcpChatSession(session)) return tab.acpRuntime;
  return tab.memberAcpRuntimes[selectedMemberId];
}

/// Chat-only seats have no terminal view to toggle to.
bool hideTerminalToggle({
  required AppSession session,
  required String selectedMemberId,
}) => isAcpChatSession(session) || isAcpChatSeat(session, selectedMemberId);

/// Per-tab runtime aggregate shared by ChatCubit and its collaborators.
/// (Formerly the private `_InternalTab`.)
class ChatTab {
  ChatTab({
    required this.info,
    required this.cliTeamName,
    this.selectedMemberId = '',
    this.workspaceId = '',
    this.workbenchView = SessionWorkbenchView.chat,
  });

  ChatTabInfo info;
  TerminalSession? resumeSession;
  String selectedMemberId;

  /// Center body: chat vs live terminal (independent of [isRunning]).
  SessionWorkbenchView workbenchView;

  /// Owning workspace bucket in [ChatTabStore]. Empty for legacy/local scratch
  /// tabs created without a workspace context.
  String workspaceId;

  /// CLI `--team-name` and config-profiles runtime id ([AppSession.cliTeamName]).
  final String cliTeamName;

  /// [cliTeamName] from construction, or [AppSession.cliTeamName] once persisted.
  ///
  /// Staged tabs start with an empty provisional name; roster presence and
  /// launch paths must read this instead of the immutable [cliTeamName] field.
  String get effectiveCliTeamName {
    final persisted = persistedSession?.cliTeamName.trim() ?? '';
    if (persisted.isNotEmpty) return persisted;
    return cliTeamName.trim();
  }

  /// Persisted session for team member connect (may be absent before index load).
  AppSession? persistedSession;

  /// Shared [LaunchPlan.memberConfigDir] from the most recent member connect
  /// (used by presence). Per-member paths live in [memberConfigDirs].
  String? memberToolConfigDir;

  /// Per-member [LaunchPlan.memberConfigDir] from successful connects.
  final Map<String, String> memberConfigDirs = {};

  final Map<String, TerminalSession> memberShells = {};

  /// Per-member terminal-less ACP chat runtimes (parallel to [memberShells]).
  /// Closed with the tab in [disposeBus].
  final Map<String, AcpChatRuntimeCubit> memberAcpRuntimes = {};

  /// Personal-session alias into [memberAcpRuntimes] for the tab's own session
  /// seat. Team UI must not use this for a selected teammate — use the map.
  AcpChatRuntimeCubit? get acpRuntime {
    final key = persistedSession?.sessionId ?? info.id;
    return memberAcpRuntimes[key];
  }

  set acpRuntime(AcpChatRuntimeCubit? value) {
    final key = persistedSession?.sessionId ?? info.id;
    if (value == null) {
      memberAcpRuntimes.remove(key);
    } else {
      memberAcpRuntimes[key] = value;
    }
  }

  /// mixed 模式：本 team 会话的进程内总线与其 gateway 注册（随 tab 建/销）。
  TeamBus? teamBus;
  TeammateBusSessionRegistration? busSessionRegistration;

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
    teamBus?.dispose();
    teamBus = null;
    busSessionRegistration = null;
    final cubits = memberAcpRuntimes.values.toList();
    memberAcpRuntimes.clear();
    for (final cubit in cubits) {
      await cubit.close();
    }
  }

  /// Member ids with a scheduled or in-flight member connect.
  final Set<String> membersPendingConnect = {};

  /// Members whose live terminal was reclaimed for idle and not yet
  /// re-materialized. The UI shows a "reclaimed" placeholder for these.
  final Set<String> reclaimedMemberIds = {};

  /// Per-member remote workspace/CLI provision UI (SSH off-home connect).
  final Map<String, MemberRemoteProvisionProgress> memberRemoteProvision = {};

  Iterable<TerminalSession> get sessions sync* {
    if (resumeSession != null) yield resumeSession!;
    yield* memberShells.values;
  }

  /// Member ACP seats that are still live (not yet ended, not closed).
  ///
  /// Terminal-less: they never appear in [sessions], so callers asking "is this
  /// tab doing work" must consult both.
  Iterable<AcpChatRuntimeCubit> get liveAcpRuntimes sync* {
    for (final cubit in memberAcpRuntimes.values) {
      if (!cubit.isClosed && cubit.state.phase != AcpChatPhase.ended) {
        yield cubit;
      }
    }
  }

  bool get isRunning =>
      sessions.any((session) => session.isRunning) ||
      liveAcpRuntimes.isNotEmpty;
}
