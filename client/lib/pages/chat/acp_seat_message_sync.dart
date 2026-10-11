import 'package:ai_message_core/ai_message_core.dart';

import '../../cubits/session/acp/acp_chat_runtime_cubit.dart';

/// True while the ACP cubit has not yet replayed `acp-transcript.jsonl`.
///
/// The history seat defaults to [AiHistoryViewStatus.empty], which would flash
/// "no prior messages" until hydrate finishes. Keep the PTY-style loading
/// pane until [historyHydrated] or a live bubble exists.
bool shouldShowAcpHistoryLoading({
  required List<AiMessage> cubitMessages,
  required bool historyHydrated,
}) => cubitMessages.isEmpty && !historyHydrated;

/// Whether ACP cubit messages should replace the history seat.
///
/// Handshake starts with an empty cubit. Publishing that list would wipe a
/// landing pending bubble until [AcpChatRuntimeCubit.start] finishes, and
/// would flash the empty-history pane before JSONL hydrate.
bool shouldPublishAcpSeatMessages({
  required List<AiMessage> cubitMessages,
  required AcpChatPhase phase,
  required bool seatHasMessages,
  required bool historyHydrated,
}) {
  if (shouldShowAcpHistoryLoading(
    cubitMessages: cubitMessages,
    historyHydrated: historyHydrated,
  )) {
    return false;
  }
  if (cubitMessages.isEmpty &&
      phase == AcpChatPhase.launching &&
      seatHasMessages) {
    return false;
  }
  return true;
}
