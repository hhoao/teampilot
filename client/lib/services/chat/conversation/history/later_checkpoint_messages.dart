import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:teampilot/services/acp/acp_chat_transcript_replay.dart';
import 'package:teampilot/services/acp/acp_session_files.dart';
import 'package:teampilot/services/chat/rewind/seat_rewind_store.dart';
import 'package:teampilot/services/cli/registry/capabilities/ai_history_capability.dart';
import 'package:teampilot/utils/logging/logger.dart';

/// Checkpoint map plus ghost messages that live only on later commits.
final class SeatRewindHistory {
  const SeatRewindHistory({
    required this.checkpointCommits,
    required this.checkedOutCommit,
    required this.laterMessages,
  });

  const SeatRewindHistory.empty()
    : checkpointCommits = const {},
      checkedOutCommit = null,
      laterMessages = const [];

  final Map<String, String> checkpointCommits;
  final String? checkedOutCommit;
  final List<AiMessage> laterMessages;
}

/// Reads later-checkpoint transcripts through [SeatRewindStore.showFile].
///
/// Does not parse CLI transcripts inside `services/chat/rewind/`.
Future<SeatRewindHistory> readSeatRewindHistory({
  required SeatRewindStore store,
  required bool acp,
  AiHistoryCapability? history,
  String? ptyRelativePath,
}) async {
  final checkpoints = await store.checkpoints();
  final checkedOut = await store.checkedOut();
  final commits = <String, String>{
    for (final checkpoint in checkpoints)
      if (checkpoint.messageId.isNotEmpty)
        checkpoint.messageId: checkpoint.commit,
  };
  final later = <AiMessage>[];
  final personal = store.target.seatKey == 'personal';
  final sidecar = acpTranscriptFileName(
    memberId: store.target.memberId,
    personal: personal,
  );
  // Membership is the checked-out commit's transcript, not the paged window.
  final seen = <String>{};
  if (checkedOut != null) {
    final checkedOutMessages = await _messagesOnCommit(
      store: store,
      commit: checkedOut,
      acp: acp,
      sidecar: sidecar,
      history: history,
      ptyRelativePath: ptyRelativePath,
    );
    for (final message in checkedOutMessages) {
      seen.add(message.id);
    }
  }
  for (final checkpoint in checkpoints) {
    if (checkpoint.commit == checkedOut) continue;
    final decoded = await _messagesOnCommit(
      store: store,
      commit: checkpoint.commit,
      acp: acp,
      sidecar: sidecar,
      history: history,
      ptyRelativePath: ptyRelativePath,
    );
    for (final message in decoded) {
      if (!seen.add(message.id)) continue;
      later.add(message);
      commits.putIfAbsent(message.id, () => checkpoint.commit);
    }
  }
  return SeatRewindHistory(
    checkpointCommits: commits,
    checkedOutCommit: checkedOut,
    laterMessages: later,
  );
}

/// Keep-ref ids stay in [SeatRewindHistory.checkpointCommits] even when a
/// blob cannot be decoded. Ghost text is read only from a text transcript.
Future<List<AiMessage>> _messagesOnCommit({
  required SeatRewindStore store,
  required String commit,
  required bool acp,
  required String sidecar,
  required AiHistoryCapability? history,
  required String? ptyRelativePath,
}) async {
  try {
    if (acp) {
      return decodeAcpChatTranscript(await store.showFile(commit, sidecar));
    }
    return await _decodePtyCheckpoint(
      store: store,
      commit: commit,
      history: history,
      ptyRelativePath: ptyRelativePath,
    );
  } on Object catch (error, stackTrace) {
    AppLogger.instance.w(
      '[rewind] skipped checkpoint transcript commit=$commit: $error',
      error: error,
      stackTrace: stackTrace,
    );
    return const [];
  }
}

bool _isTextPtyTranscript(String path) {
  final lower = path.toLowerCase();
  const blocked = ['.db-wal', '.db-shm', '.sqlite3', '.sqlite', '.db'];
  for (final suffix in blocked) {
    if (lower.endsWith(suffix)) return false;
  }
  return true;
}

Future<List<AiMessage>> _decodePtyCheckpoint({
  required SeatRewindStore store,
  required String commit,
  required AiHistoryCapability? history,
  required String? ptyRelativePath,
}) async {
  if (history == null ||
      ptyRelativePath == null ||
      ptyRelativePath.isEmpty ||
      !_isTextPtyTranscript(ptyRelativePath)) {
    return const [];
  }
  final text = await store.showFile(commit, ptyRelativePath);
  if (text == null || text.isEmpty) return const [];
  return history.adapter.parse(
    AiTranscriptBundle(
      adapterId: history.adapter.id,
      fragments: [
        AiTranscriptFragment(name: ptyRelativePath, bytes: utf8.encode(text)),
      ],
    ),
  );
}
