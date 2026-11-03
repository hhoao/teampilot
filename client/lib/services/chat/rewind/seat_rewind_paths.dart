import 'package:teampilot/services/acp/acp_session_files.dart';

enum SeatRewindKind { personalAcp, mixedAcp, personalPty, mixedPty }

const rewindExcludeNames = {'plugins', 'skills', 'node_modules', 'cache'};

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

  String get _toolDirPrefix =>
      _personal ? tool : '${memberId!.trim()}/$tool';

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
