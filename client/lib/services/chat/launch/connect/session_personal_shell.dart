import '../../../terminal/terminal_session.dart';

/// Returns the shell currently displayed for a personal session.
///
/// SSH reconnect can leave the shell in [memberShells] rather than in
/// [resumeSession]. Keep the same fallback order for request creation
/// and the executor's actual shell acquisition.
TerminalSession? displayedPersonalResumeShell({
  required String sessionId,
  TerminalSession? resumeSession,
  required Map<String, TerminalSession> memberShells,
}) {
  final candidates = <TerminalSession?>[
    resumeSession,
    memberShells[sessionId],
    if (memberShells.length == 1) memberShells.values.first,
  ];
  for (final shell in candidates) {
    if (shell != null && !shell.isDisposed) return shell;
  }
  return null;
}
