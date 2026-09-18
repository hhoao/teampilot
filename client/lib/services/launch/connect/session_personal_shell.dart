import '../../../cubits/chat/model/chat_tab.dart';
import '../../../models/app_session.dart';
import '../../terminal/terminal_session.dart';

/// Returns the shell currently displayed for a personal session.
///
/// SSH reconnect can leave the shell in [ChatTab.memberShells] rather than in
/// [ChatTab.resumeSession]. Keep the same fallback order for request creation
/// and the executor's actual shell acquisition.
TerminalSession? displayedPersonalResumeShell(ChatTab tab, AppSession session) {
  final candidates = <TerminalSession?>[
    tab.resumeSession,
    tab.memberShells[session.sessionId],
    if (tab.memberShells.length == 1) tab.memberShells.values.first,
  ];
  for (final shell in candidates) {
    if (shell != null && !shell.isDisposed) return shell;
  }
  return null;
}
