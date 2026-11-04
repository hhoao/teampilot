import 'package:teampilot/services/chat/rewind/seat_rewind_store.dart';

/// Ordered checkpoints of one seat, plus the commit written into its runtime.
final class SeatRewindHistory {
  const SeatRewindHistory({
    required this.checkpointCommits,
    required this.orderedCommits,
    required this.checkedOutCommit,
  });

  const SeatRewindHistory.empty()
    : checkpointCommits = const {},
      orderedCommits = const [],
      checkedOutCommit = null;

  /// Message id of the turn that closed each checkpoint → its commit.
  final Map<String, String> checkpointCommits;

  /// Every checkpoint commit, oldest first.
  final List<String> orderedCommits;

  /// Commit currently written into the seat's runtime, or null with no
  /// checkpoints.
  final String? checkedOutCommit;

  /// 1-based position of [checkedOutCommit] among [orderedCommits].
  int? get checkedOutIndex {
    final commit = checkedOutCommit;
    if (commit == null) return null;
    final index = orderedCommits.indexOf(commit);
    return index < 0 ? null : index + 1;
  }

  /// Commit one step older than [checkedOutCommit], or null at the oldest end.
  String? get previousCommit {
    final index = checkedOutIndex;
    if (index == null || index < 2) return null;
    return orderedCommits[index - 2];
  }

  /// Commit one step newer than [checkedOutCommit], or null at the newest end.
  String? get nextCommit {
    final index = checkedOutIndex;
    if (index == null || index >= orderedCommits.length) return null;
    return orderedCommits[index];
  }
}

/// Reads the checkpoint list of [store] without touching the work tree.
Future<SeatRewindHistory> readSeatRewindHistory({
  required SeatRewindStore store,
}) async {
  final checkpoints = await store.checkpoints();
  final checkedOut = await store.checkedOut();
  return SeatRewindHistory(
    checkpointCommits: {
      for (final checkpoint in checkpoints)
        if (checkpoint.messageId.isNotEmpty)
          checkpoint.messageId: checkpoint.commit,
    },
    orderedCommits: [for (final checkpoint in checkpoints) checkpoint.commit],
    checkedOutCommit: checkedOut,
  );
}
