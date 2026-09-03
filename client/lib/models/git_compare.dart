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

  @override
  List<Object?> get props => [repoRoot, left, right];
}

bool _looksLikeHash(String s) => RegExp(r'^[0-9a-fA-F]+$').hasMatch(s);
