import 'package:equatable/equatable.dart';

sealed class GitCompareSide extends Equatable {
  const GitCompareSide();

  String get idKey;

  String titleLabel({int shortHashLen = 8});
}

final class GitCompareWorkingTree extends GitCompareSide {
  const GitCompareWorkingTree();

  @override
  String get idKey => 'wt';

  @override
  String titleLabel({int shortHashLen = 8}) => 'Working Tree';

  @override
  List<Object?> get props => const [];
}

final class GitCompareRef extends GitCompareSide {
  const GitCompareRef(this.nameOrHash, {this.titleOverride});

  final String nameOrHash;
  final String? titleOverride;

  @override
  String get idKey => 'ref:$nameOrHash';

  @override
  String titleLabel({int shortHashLen = 8}) =>
      titleOverride ??
      (nameOrHash.length > shortHashLen && _looksLikeHash(nameOrHash)
          ? nameOrHash.substring(0, shortHashLen)
          : nameOrHash);

  @override
  List<Object?> get props => [nameOrHash, titleOverride];
}

class GitCompareSpec extends Equatable {
  const GitCompareSpec({
    required this.repoRoot,
    required this.left,
    required this.right,
  });

  final String repoRoot;
  final GitCompareSide left;
  final GitCompareSide right;

  String get tabId => 'gitCompare:$repoRoot|${left.idKey}|${right.idKey}';

  String tabTitle() => '${left.titleLabel()} ↔ ${right.titleLabel()}';

  /// Reconstructs a [GitCompareSpec] from a [tabId] produced by [tabId]
  /// (`gitCompare:<repoRoot>|<leftKey>|<rightKey>`). Used when the floating
  /// panel only has the tab id string on hand (e.g. restoring an existing
  /// floating tab) instead of the original spec instance. `titleOverride` is
  /// not encoded in the id and is therefore lost on round-trip.
  static GitCompareSpec? tryParseTabId(String tabId) {
    const prefix = 'gitCompare:';
    if (!tabId.startsWith(prefix)) return null;
    final parts = tabId.substring(prefix.length).split('|');
    if (parts.length != 3) return null;
    final repoRoot = parts[0];
    if (repoRoot.isEmpty) return null;
    final left = _parseSideKey(parts[1]);
    final right = _parseSideKey(parts[2]);
    if (left == null || right == null) return null;
    return GitCompareSpec(repoRoot: repoRoot, left: left, right: right);
  }

  static GitCompareSide? _parseSideKey(String key) {
    if (key == 'wt') return const GitCompareWorkingTree();
    if (key.startsWith('ref:')) {
      final nameOrHash = key.substring('ref:'.length);
      if (nameOrHash.isEmpty) return null;
      return GitCompareRef(nameOrHash);
    }
    return null;
  }

  @override
  List<Object?> get props => [repoRoot, left, right];
}

bool _looksLikeHash(String s) => RegExp(r'^[0-9a-fA-F]+$').hasMatch(s);
