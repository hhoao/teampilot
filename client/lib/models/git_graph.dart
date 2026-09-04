import 'package:equatable/equatable.dart';

enum GitSearchMode { message, author, hash }

enum GitResetMode { soft, mixed, hard }

enum GitRefDecorationKind { head, localBranch, remoteBranch, tag }

class GitRefDecoration extends Equatable {
  const GitRefDecoration(this.kind, this.name);

  final GitRefDecorationKind kind;
  final String name;

  @override
  List<Object?> get props => [kind, name];
}

/// 图上单个提交节点：所在 slot + 解析期分配的调色板序号。
///
/// slot 即 `git log --graph` 的字符列号（偶数 = lane 中心，奇数 = lane 间空隙）。
class GitGraphNode extends Equatable {
  const GitGraphNode(this.slot, this.colorIndex);

  final int slot;
  final int colorIndex;

  @override
  List<Object?> get props => [slot, colorIndex];
}

/// 一行内的一段连线：from=行顶 slot，to=行底 slot；相等画竖线，不等画 S 曲线。
/// 偶数 slot 是 lane 中心；奇数 slot 是 lane 间空隙（跨 lane 穿越/交换的中转位）。
class GitGraphEdge extends Equatable {
  const GitGraphEdge(this.fromSlot, this.toSlot, this.colorIndex);

  final int fromSlot;
  final int toSlot;
  final int colorIndex;

  bool get isStraight => fromSlot == toSlot;

  @override
  List<Object?> get props => [fromSlot, toSlot, colorIndex];
}

sealed class GitGraphRow extends Equatable {
  const GitGraphRow({required this.edges});

  final List<GitGraphEdge> edges;

  @override
  List<Object?> get props => [edges];
}

/// 有提交记录的行。
class GitCommitRow extends GitGraphRow {
  const GitCommitRow({
    required super.edges,
    required this.node,
    required this.hash,
    required this.parents,
    required this.authorName,
    required this.authorEmail,
    required this.authorDate,
    required this.subject,
    required this.refs,
  });

  final GitGraphNode node;
  final String hash;
  final List<String> parents;
  final String authorName;
  final String authorEmail;
  final DateTime authorDate;
  final String subject;
  final List<GitRefDecoration> refs;

  @override
  List<Object?> get props => [
        ...super.props,
        node,
        hash,
        parents,
        authorName,
        authorEmail,
        authorDate,
        subject,
        refs,
      ];
}

/// 无提交记录的纯拓扑行（merge 的 |\ 、|/ 等），渲染为半高连线。
class GitGraphSpacerRow extends GitGraphRow {
  const GitGraphSpacerRow({required super.edges});
}

/// 单个提交的完整详情（`git show -s` 元数据 + diff-tree 文件清单）。
class GitCommitDetail extends Equatable {
  const GitCommitDetail({
    required this.hash,
    required this.parents,
    required this.authorName,
    required this.authorEmail,
    required this.authorDate,
    required this.subject,
    required this.body,
    required this.files,
  });

  final String hash;
  final List<String> parents;
  final String authorName;
  final String authorEmail;
  final DateTime authorDate;
  final String subject;
  final String body;
  final List<GitCommitFileChange> files;

  @override
  List<Object?> get props => [
        hash,
        parents,
        authorName,
        authorEmail,
        authorDate,
        subject,
        body,
        files,
      ];
}

/// diff-tree --name-status 的字母状态映射。
enum GitCommitFileStatus { added, modified, deleted, renamed, typeChanged }

/// 提交内单个文件的变更（rename 时带 [previousPath]）。
class GitCommitFileChange extends Equatable {
  const GitCommitFileChange(this.path, this.status, {this.previousPath});

  final String path;
  final GitCommitFileStatus status;
  final String? previousPath;

  @override
  List<Object?> get props => [path, status, previousPath];
}

/// 本地或远程分支（[isCurrent] 仅对本地分支有意义）。
class GitBranchInfo extends Equatable {
  const GitBranchInfo(
    this.name,
    this.hash, {
    required this.isRemote,
    required this.isCurrent,
  });

  final String name;
  final String hash;
  final bool isRemote;
  final bool isCurrent;

  @override
  List<Object?> get props => [name, hash, isRemote, isCurrent];
}

/// 标签。
class GitTagInfo extends Equatable {
  const GitTagInfo(this.name, this.hash);

  final String name;
  final String hash;

  @override
  List<Object?> get props => [name, hash];
}

/// 一条 stash 记录（[selector] 如 stash@{0}）。
class GitStashEntry extends Equatable {
  const GitStashEntry(this.selector, this.hash, this.subject);

  final String selector;
  final String hash;
  final String subject;

  @override
  List<Object?> get props => [selector, hash, subject];
}
