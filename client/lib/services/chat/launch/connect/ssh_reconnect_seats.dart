import '../../../../models/app_session.dart';
import '../../../terminal/terminal_session.dart';
import '../../session/chat_tab_store.dart';
import 'session_personal_shell.dart';

/// One open session SSH reconnect may retarget.
final class SshReconnectOpenSession {
  const SshReconnectOpenSession({
    required this.sessionId,
    required this.session,
  });

  final String sessionId;
  final AppSession session;
}

/// Runtime seats SSH reconnect needs. ChatTab stays behind this port.
abstract interface class SshReconnectSeatPort {
  Iterable<SshReconnectOpenSession> get openSessions;

  TerminalSession? memberShell(String sessionId, String memberId);

  TerminalSession? personalResumeShell(String sessionId, AppSession session);

  Future<void> closeMemberRemotePlane(String sessionId, String memberId);
}

/// [ChatTabStore] adapter so [SessionSshProfileReconnect] does not import ChatTab.
final class ChatTabStoreSshReconnectSeats implements SshReconnectSeatPort {
  ChatTabStoreSshReconnectSeats(this._tabs);

  final ChatTabStore _tabs;

  @override
  Iterable<SshReconnectOpenSession> get openSessions => [
    for (final tab in _tabs.openTabs)
      if (tab.persistedSession != null)
        SshReconnectOpenSession(
          sessionId: tab.info.id,
          session: tab.persistedSession!,
        ),
  ];

  @override
  TerminalSession? memberShell(String sessionId, String memberId) =>
      _tabs.getOpenTabBySessionId(sessionId)?.memberShells[memberId];

  @override
  TerminalSession? personalResumeShell(String sessionId, AppSession session) {
    final tab = _tabs.getOpenTabBySessionId(sessionId);
    if (tab == null) return null;
    return displayedPersonalResumeShell(
      sessionId: session.sessionId,
      resumeSession: tab.resumeSession,
      memberShells: tab.memberShells,
    );
  }

  @override
  Future<void> closeMemberRemotePlane(String sessionId, String memberId) async {
    await _tabs.getOpenTabBySessionId(sessionId)?.closeMemberRemotePlane(
      memberId,
    );
  }
}
