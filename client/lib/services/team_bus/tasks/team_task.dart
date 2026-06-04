/// work-queue 任务态。pull 式自均衡：leader 入队 `pending`，空闲 worker 认领
/// → `claimed`，完成/失败/取消为终态。`claimed` 超租约且 worker 不在线时由
/// [TaskQueue.reclaimExpired] 退回 `pending`，避免任务卡死在掉线成员上。
enum TaskStatus {
  pending,
  claimed,
  done,
  failed,
  cancelled;

  bool get isTerminal =>
      this == TaskStatus.done ||
      this == TaskStatus.failed ||
      this == TaskStatus.cancelled;

  static TaskStatus parse(String? raw) {
    for (final s in TaskStatus.values) {
      if (s.name == raw) return s;
    }
    return TaskStatus.pending;
  }
}

/// 队列里的单个任务（不可变值；状态变更走 [copyWith]）。
///
/// 跨 CLI bus（mixed 模式）专用——纯 Claude swarm 复用 Claude 原生任务表，不经此处。
class TeamTask {
  const TeamTask({
    required this.id,
    required this.seq,
    required this.title,
    required this.brief,
    required this.createdBy,
    required this.createdAt,
    this.status = TaskStatus.pending,
    this.assignee,
    this.claimedAt,
    this.finishedAt,
    this.result,
    this.dependsOn = const [],
  });

  /// 唯一 id（认领 / 更新 / 去重）。
  final String id;

  /// 入队序号（FIFO 排序，单一来源 [TaskQueue]）。
  final int seq;

  /// 一行摘要（看板展示）。
  final String title;

  /// 完整任务简报（投给 worker 执行）。
  final String brief;

  /// 入队者 memberId（通常是 leader）。
  final String createdBy;

  final int createdAt;

  final TaskStatus status;

  /// 认领者 memberId（`pending` 时为 null）。
  final String? assignee;

  final int? claimedAt;
  final int? finishedAt;

  /// 完成备注 / 失败原因（worker 回填）。
  final String? result;

  /// 依赖的任务 id；全部 `done` 才可认领。空 = 无依赖。
  final List<String> dependsOn;

  bool get isClaimable => status == TaskStatus.pending;

  TeamTask copyWith({
    TaskStatus? status,
    String? assignee,
    int? claimedAt,
    int? finishedAt,
    String? result,
  }) {
    return TeamTask(
      id: id,
      seq: seq,
      title: title,
      brief: brief,
      createdBy: createdBy,
      createdAt: createdAt,
      status: status ?? this.status,
      assignee: assignee ?? this.assignee,
      claimedAt: claimedAt ?? this.claimedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      result: result ?? this.result,
      dependsOn: dependsOn,
    );
  }
}

/// 入队草稿（leader 通过 `add_tasks` 提交，id/seq 由队列分配）。
class TeamTaskDraft {
  const TeamTaskDraft({
    required this.title,
    required this.brief,
    this.dependsOn = const [],
  });

  final String title;
  final String brief;
  final List<String> dependsOn;
}
