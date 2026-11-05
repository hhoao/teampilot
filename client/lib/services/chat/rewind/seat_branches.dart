import 'package:teampilot/services/chat/rewind/seat_rewind_store.dart';

/// One version of a user message: the turn it opened.
final class SeatBranchVersion {
  const SeatBranchVersion({
    required this.index,
    required this.count,
    required this.commit,
    required this.siblings,
  });

  /// 1-based position among the versions of this message.
  final int index;

  /// How many versions this message has.
  final int count;

  /// Commit of this version's turn.
  final String commit;

  /// Commits of every version, oldest first.
  final List<String> siblings;

  /// Commit one version older, or null at the oldest end.
  String? get previous => index > 1 ? siblings[index - 2] : null;

  /// Commit one version newer, or null at the newest end.
  String? get next => index < count ? siblings[index] : null;
}

/// Branch tree of one seat, keyed by the user message that opened a turn.
final class SeatBranches {
  const SeatBranches({required this.turns});

  const SeatBranches.empty() : turns = const {};

  final Map<String, SeatBranchVersion> turns;

  SeatBranchVersion? turnOf(String userMessageId) => turns[userMessageId];
}

/// Groups [store]'s checkpoints by parent and indexes them per user message.
Future<SeatBranches> readSeatBranches({required SeatRewindStore store}) async {
  final checkpoints = await store.checkpoints();
  // checkedOut is not part of the version UI and costs one extra git process
  // on every reload; callers that need it read `store.checkedOut()` directly.
  final groups = <String, List<RewindCheckpoint>>{};
  for (final checkpoint in checkpoints) {
    if (checkpoint.userMessageId.isEmpty) continue;
    groups.putIfAbsent(checkpoint.parentCommit, () => []).add(checkpoint);
  }
  final turns = <String, SeatBranchVersion>{};
  for (final group in groups.values) {
    group.sort((a, b) => a.turnAt.compareTo(b.turnAt));
    final siblings = [for (final turn in group) turn.commit];
    for (var index = 0; index < group.length; index++) {
      final checkpoint = group[index];
      turns[checkpoint.userMessageId] = SeatBranchVersion(
        index: index + 1,
        count: group.length,
        commit: checkpoint.commit,
        siblings: List.unmodifiable(siblings),
      );
    }
  }
  return SeatBranches(turns: turns);
}
