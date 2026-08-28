import 'package:ai_message_core/ai_message_core.dart';

/// Windowed rendering for session history review.
const int kSessionHistoryInitialTurns = 30;

const int kSessionHistoryOlderPageSize = 20;

/// Below/equal this available width, the chat column follows the pane.
const double kSessionHistoryColumnMinWidth = 1080;

/// Chat column ceiling.
const double kSessionHistoryColumnMaxWidth = 1600;

/// First pane excess required to leave min and jump chat by
/// [kSessionHistoryColumnFirstJumpGrowth].
const double kSessionHistoryColumnFirstJumpSpan = 400;

/// Chat growth on the first jump.
const double kSessionHistoryColumnFirstJumpGrowth = 200;

/// Later pane steps: each +span jumps chat by the same amount.
const double kSessionHistoryColumnLaterJumpSpan = 200;

/// Resolves session history column width for the center-pane [availableWidth].
///
/// Stepped (not continuous) growth above [kSessionHistoryColumnMinWidth]:
/// - `available <= min`: follow available
/// - until `min + 400`: hold at min
/// - at `min + 400`: jump to `min + 200`
/// - then every +200 available: jump chat +200
/// - capped at [kSessionHistoryColumnMaxWidth]
double resolveSessionHistoryColumnWidth(double availableWidth) {
  if (!availableWidth.isFinite) {
    return kSessionHistoryColumnMaxWidth;
  }
  if (availableWidth <= 0) {
    return 0;
  }
  if (availableWidth <= kSessionHistoryColumnMinWidth) {
    return availableWidth;
  }

  final firstThreshold =
      kSessionHistoryColumnMinWidth + kSessionHistoryColumnFirstJumpSpan;
  if (availableWidth < firstThreshold) {
    return kSessionHistoryColumnMinWidth;
  }

  final firstChat =
      kSessionHistoryColumnMinWidth + kSessionHistoryColumnFirstJumpGrowth;
  final stepsAfterFirst =
      ((availableWidth - firstThreshold) / kSessionHistoryColumnLaterJumpSpan)
          .floor();
  final chat = firstChat + stepsAfterFirst * kSessionHistoryColumnLaterJumpSpan;
  return chat < kSessionHistoryColumnMaxWidth
      ? chat
      : kSessionHistoryColumnMaxWidth;
}

/// Prepends [older] before [recent], dropping older ids already present in
/// [recent] so the existing suffix keeps its object identity.
List<AiMessage> prependOlderHistoryMessages({
  required List<AiMessage> older,
  required List<AiMessage> recent,
}) {
  if (older.isEmpty) return recent;
  if (recent.isEmpty) return List<AiMessage>.of(older);
  final recentIds = {for (final m in recent) m.id};
  final prefix = [for (final m in older) if (!recentIds.contains(m.id)) m];
  if (prefix.isEmpty) return recent;
  return [...prefix, ...recent];
}

/// Reuses [previous] instances when id and content match. A same-id stream
/// update (new instance, new parts) keeps [next] so live History can move.
List<AiMessage> reuseHistoryMessageIdentity({
  required List<AiMessage> previous,
  required List<AiMessage> next,
}) {
  if (previous.isEmpty) return next;
  final previousById = {for (final m in previous) m.id: m};
  return [
    for (final m in next) _reuseUnchangedMessage(previousById[m.id], m),
  ];
}

AiMessage _reuseUnchangedMessage(AiMessage? previous, AiMessage next) {
  if (previous == null) return next;
  if (identical(previous, next)) return previous;
  if (messageContentIdentity(previous) == messageContentIdentity(next)) {
    return previous;
  }
  return next;
}
