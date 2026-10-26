import 'package:ai_message_core/ai_message_core.dart';

import '../../../../models/app_session.dart';
import '../../../acp/acp_chat_transcript.dart';
import '../../../acp/acp_session_files.dart';
import '../../../storage/home_storage.dart';

/// Reads one seat's app-owned ACP transcript snapshot **without attaching the
/// ACP runtime** (no adapter process, no `session/load`).
///
/// A terminal-less ACP session's chat transcript is written by
/// [AcpChatTranscriptWriter] on every commit. Opening an existing session in
/// history-only mode (the default: "start the terminal when opening an
/// existing session" off) must paint that snapshot — otherwise the history
/// seat has nothing to show and stays on the full-pane loading state forever.
///
/// Returns an empty list when the seat has no snapshot yet (a session that was
/// created but never prompted, or a reclaimed runtime that had not committed).
class AcpSeatTranscriptReader {
  AcpSeatTranscriptReader({required HomeStorage storage}) : _storage = storage;

  final HomeStorage _storage;

  Future<List<AiMessage>> load({
    required AppSession session,
    required String memberId,
    required bool personal,
  }) {
    final layout = _storage.context.layout;
    final path = layout.pathContext.join(
      layout.workspace.sessionRuntimeDir(
        session.workspaceId,
        session.sessionId,
      ),
      acpTranscriptFileName(
        memberId: personal ? null : memberId,
        personal: personal,
      ),
    );
    return AcpChatTranscriptWriter(fs: _storage.fs, path: path).loadMessages();
  }
}
