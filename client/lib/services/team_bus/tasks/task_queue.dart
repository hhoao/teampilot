import 'dart:async';

import 'package:uuid/uuid.dart';

import 'task_log.dart';
import 'team_task.dart';

/// 跨 CLI bus（mixed 模式）的 **pull 式共享任务队列**：leader 入队，空闲 worker
/// 认领。整个 bus 跑在单个 Dart isolate 内，[claimNext] 是同步 map 改写——天然原子，
/// **不可能两个 worker 抢到同一任务**，无需锁（对比 Claude 的多进程 lockfile 认领）。
///
/// 内存为权威工作集，持久化对调用方 fire-and-forget（崩溃只丢未落盘尾部，语义同
/// [MemberInbox]）。租约由 [reclaimExpired] 兜底：claimed 超时且认领者掉线则退回
/// pending。
class TaskQueue {
  TaskQueue({TaskLog? log, String Function()? ids, int Function()? clock})
    : _log = log,
      _ids = ids ?? (() => const Uuid().v4()),
      _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  final TaskLog? _log;
  final String Function() _ids;
  final int Function() _clock;

  final Map<String, TeamTask> _tasks = {};
  int _nextSeq = 0;

  /// 有新 pending 任务可认领时完成，唤醒阻塞中的 [waitForClaimable]。
  Completer<void>? _waiter;

  /// 开 session：回放日志重建任务表与 seq 游标。
  Future<void> rehydrate() async {
    final log = _log;
    if (log == null) return;
    for (final t in await log.load()) {
      _tasks[t.id] = t;
      if (t.seq >= _nextSeq) _nextSeq = t.seq + 1;
    }
  }

  /// leader 批量入队。返回新建任务（含分配的 id/seq）；唤醒等待中的 worker。
  List<TeamTask> addTasks(String createdBy, List<TeamTaskDraft> drafts) {
    final created = <TeamTask>[];
    for (final d in drafts) {
      final task = TeamTask(
        id: _ids(),
        seq: _nextSeq++,
        title: d.title.trim(),
        brief: d.brief,
        createdBy: createdBy,
        createdAt: _clock(),
        dependsOn: List.unmodifiable(d.dependsOn),
      );
      _tasks[task.id] = task;
      created.add(task);
      _persist(() => _log?.appendAdd(task));
    }
    if (created.isNotEmpty) _wake();
    return created;
  }

  /// 原子认领下一个可执行任务（FIFO + 依赖全 done）。无可认领返回 null。
  /// **此方法体内不得有 await**——保证选择 + 标记在同一微任务内完成。
  TeamTask? claimNext(String memberId) {
    final ordered = _tasks.values.toList()
      ..sort((a, b) => a.seq.compareTo(b.seq));
    for (final t in ordered) {
      if (!t.isClaimable) continue;
      if (!_depsSatisfied(t)) continue;
      final claimed = t.copyWith(
        status: TaskStatus.claimed,
        assignee: memberId,
        claimedAt: _clock(),
      );
      _tasks[t.id] = claimed;
      _persist(() => _log?.appendClaim(t.id, memberId, claimed.claimedAt!));
      return claimed;
    }
    return null;
  }

  /// 释放认领但未完成的任务，退回 pending（统一 idle 原语在结果写回失败/客户端断连
  /// 时调用，避免任务卡在没收到它的 worker 上——比等租约回收更及时）。
  void release(String taskId) {
    final t = _tasks[taskId];
    if (t == null || t.status != TaskStatus.claimed) return;
    _tasks[taskId] = t.copyWith(status: TaskStatus.pending);
    _persist(() => _log?.appendReclaim(taskId, _clock()));
    _wake();
  }

  /// worker 汇报终态（done/failed/cancelled）。非认领者或不存在则返回 false。
  bool update(
    String taskId,
    TaskStatus status, {
    String? result,
    String? byMember,
  }) {
    final t = _tasks[taskId];
    if (t == null || !status.isTerminal) return false;
    if (byMember != null && t.assignee != null && t.assignee != byMember) {
      return false; // 只有认领者能改自己的任务
    }
    final at = _clock();
    _tasks[taskId] = t.copyWith(status: status, result: result, finishedAt: at);
    _persist(() => _log?.appendUpdate(taskId, status, result, at));
    return true;
  }

  /// 租约回收：claimed 且（[claimedAt] + [leaseMs] < now）且认领者经 [isAlive]
  /// 判定已掉线的任务退回 pending，避免卡死在掉线成员上。返回被回收的任务。
  List<TeamTask> reclaimExpired({
    required int leaseMs,
    required bool Function(String memberId) isAlive,
  }) {
    final now = _clock();
    final reclaimed = <TeamTask>[];
    for (final t in _tasks.values.toList()) {
      if (t.status != TaskStatus.claimed) continue;
      final claimedAt = t.claimedAt;
      if (claimedAt == null || now - claimedAt < leaseMs) continue;
      final assignee = t.assignee;
      if (assignee != null && isAlive(assignee)) continue;
      _tasks[t.id] = t.copyWith(status: TaskStatus.pending);
      _persist(() => _log?.appendReclaim(t.id, now));
      reclaimed.add(_tasks[t.id]!);
    }
    if (reclaimed.isNotEmpty) _wake();
    return reclaimed;
  }

  /// 任务快照（看板 / `list_tasks`）；[status] 非空时过滤，按 seq 升序。
  List<TeamTask> list({TaskStatus? status}) {
    final all = _tasks.values.where((t) => status == null || t.status == status);
    return all.toList()..sort((a, b) => a.seq.compareTo(b.seq));
  }

  /// 当前可认领任务数（依赖已满足的 pending）。
  int get claimableCount => _tasks.values.where(_isClaimableNow).length;

  bool get hasClaimable => _tasks.values.any(_isClaimableNow);

  /// 阻塞到有可认领任务（供 `get_work` 合并式实现复用；当前不被 MCP 直接调用）。
  Future<void> waitForClaimable() {
    if (hasClaimable) return Future.value();
    final existing = _waiter;
    if (existing != null && !existing.isCompleted) return existing.future;
    final completer = Completer<void>();
    _waiter = completer;
    return completer.future;
  }

  void dispose() {
    final waiter = _waiter;
    _waiter = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }

  // --- internals ---

  bool _isClaimableNow(TeamTask t) => t.isClaimable && _depsSatisfied(t);

  bool _depsSatisfied(TeamTask t) {
    for (final dep in t.dependsOn) {
      if (_tasks[dep]?.status != TaskStatus.done) return false;
    }
    return true;
  }

  void _wake() {
    final waiter = _waiter;
    if (waiter == null || waiter.isCompleted) return;
    _waiter = null;
    waiter.complete();
  }

  void _persist(Future<void>? Function() op) {
    final future = op();
    if (future == null) return;
    unawaited(future.catchError((Object _) {}));
  }
}
