import 'package:teampilot/services/acp/acp_session_files.dart';

/// Mixed-seat rewind is implemented but deliberately not exposed yet.
/// Flip this when team-session branching ships; every entry point reads it.
const bool kMixedSeatRewindEnabled = false;

enum SeatRewindKind { personalAcp, mixedAcp, personalPty, mixedPty }

const rewindExcludeNames = {'plugins', 'skills', 'node_modules', 'cache'};

/// One canonical target for a seat, so the checkpoint writers and the UI
/// reader agree on the kind/tool/member triple.
SeatRewindTarget resolveSeatRewindTarget({
  required bool personal,
  required bool acp,
  required String tool,
  String? memberId,
}) {
  return SeatRewindTarget(
    kind: acp
        ? (personal ? SeatRewindKind.personalAcp : SeatRewindKind.mixedAcp)
        : (personal ? SeatRewindKind.personalPty : SeatRewindKind.mixedPty),
    tool: tool,
    memberId: personal ? null : memberId,
  );
}

final class SeatRewindTarget {
  const SeatRewindTarget({
    required this.kind,
    required this.tool,
    this.memberId,
  });

  final SeatRewindKind kind;
  final String tool;
  final String? memberId;

  bool get _personal =>
      kind == SeatRewindKind.personalAcp || kind == SeatRewindKind.personalPty;

  bool get _acp =>
      kind == SeatRewindKind.personalAcp || kind == SeatRewindKind.mixedAcp;

  String get seatKey => _personal ? 'personal' : memberId!.trim();

  String get _toolDirPrefix => _personal ? tool : '${memberId!.trim()}/$tool';

  /// Repo-relative paths that `git add` / checkout may touch.
  List<String> get includedPrefixes {
    final prefixes = <String>[_toolDirPrefix];
    if (_acp) {
      prefixes.add(
        acpTranscriptFileName(memberId: memberId, personal: _personal),
      );
      prefixes.add(
        acpAgentSessionFileName(memberId: memberId, personal: _personal),
      );
    }
    return prefixes;
  }

  bool includes(String repoRelativePath) {
    for (final prefix in includedPrefixes) {
      if (repoRelativePath == prefix ||
          repoRelativePath.startsWith('$prefix/')) {
        return true;
      }
    }
    return false;
  }

  bool isExcluded(String repoRelativePath) {
    for (final segment in repoRelativePath.split('/')) {
      if (rewindExcludeNames.contains(segment)) {
        return true;
      }
    }
    return false;
  }
}
