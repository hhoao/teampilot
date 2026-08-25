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

/// 图上单个提交节点：所在 lane + 解析期分配的调色板序号。
class GitGraphNode extends Equatable {
  const GitGraphNode(this.lane, this.colorIndex);

  final int lane;
  final int colorIndex;

  @override
  List<Object?> get props => [lane, colorIndex];
}

/// 一行内的一段连线：from=行顶 lane，to=行底 lane；相等画竖线，不等画 S 曲线。
class GitGraphEdge extends Equatable {
  const GitGraphEdge(this.fromLane, this.toLane, this.colorIndex);

  final int fromLane;
  final int toLane;
  final int colorIndex;

  bool get isStraight => fromLane == toLane;

  @override
  List<Object?> get props => [fromLane, toLane, colorIndex];
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
