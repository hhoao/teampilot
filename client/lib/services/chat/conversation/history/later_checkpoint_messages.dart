import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:teampilot/services/acp/acp_chat_transcript_replay.dart';
import 'package:teampilot/services/acp/acp_session_files.dart';
import 'package:teampilot/services/chat/rewind/seat_rewind_store.dart';
import 'package:teampilot/services/cli/registry/capabilities/ai_history_capability.dart';

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
  required List<AiMessage> live,
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
  final seen = {for (final message in live) message.id};
  final later = <AiMessage>[];
  final personal = store.target.seatKey == 'personal';
  final sidecar = acpTranscriptFileName(
    memberId: store.target.memberId,
    personal: personal,
  );
  for (final checkpoint in checkpoints) {
    if (checkpoint.commit == checkedOut) continue;
    final decoded = acp
        ? decodeAcpChatTranscript(
            await store.showFile(checkpoint.commit, sidecar),
          )
        : await _decodePtyCheckpoint(
            store: store,
            commit: checkpoint.commit,
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

Future<List<AiMessage>> _decodePtyCheckpoint({
  required SeatRewindStore store,
  required String commit,
  required AiHistoryCapability? history,
  required String? ptyRelativePath,
}) async {
  if (history == null || ptyRelativePath == null || ptyRelativePath.isEmpty) {
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
