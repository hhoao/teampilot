import 'dart:async';

import 'package:uuid/uuid.dart';

import 'task_log.dart';
import 'task_router.dart';
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
      final stage = d.preferredAssignee != null
          ? RoutingStage.reserved
          : RoutingStage.matched;
      final task = TeamTask(
        id: _ids(),
        seq: _nextSeq++,
        title: d.title.trim(),
        brief: d.brief,
        createdBy: createdBy,
        createdAt: _clock(),
        dependsOn: List.unmodifiable(d.dependsOn),
        requiredCapabilities: d.requiredCapabilities,
        preferredCapabilities: d.preferredCapabilities,
        preferredAssignee: d.preferredAssignee,
        routing: RoutingPolicy(stage: stage, escalatedAt: _clock()),
      );
      _tasks[task.id] = task;
      created.add(task);
      _persist(() => _log?.appendAdd(task));
    }
    if (created.isNotEmpty) _wake();
    return created;
  }

  /// 原子认领下一个**对该成员合格**的可执行任务（deps 全 done）。合格集内按
  /// (score 降序, seq 升序) 排序。无可认领返回 null。
  /// **此方法体内不得有 await**——保证选择 + 标记在同一微任务内完成。
  TeamTask? claimNext(String memberId, Set<String> memberCaps) {
    final candidates = _tasks.values
        .where((t) => t.isClaimable && _depsSatisfied(t))
        .toList()
      ..sort((a, b) {
        final sa = TaskRouter.score(memberCaps, a);
        final sb = TaskRouter.score(memberCaps, b);
        if (sa != sb) return sb.compareTo(sa);
        return a.seq.compareTo(b.seq);
      });
    for (final t in candidates) {
      if (!TaskRouter.eligible(memberId, memberCaps, t)) continue;
      return _markClaimed(t, memberId);
    }
    return null;
  }

  /// pull 式自取：认领一个指定任务（worker 主动从看板挑）。不存在/已被领/被依赖卡住/
  /// 不合格则返回 null。同样同步原子。
  TeamTask? claimSpecific(
    String taskId,
    String memberId,
    Set<String> memberCaps,
  ) {
    final t = _tasks[taskId];
    if (t == null || !t.isClaimable || !_depsSatisfied(t)) return null;
    if (!TaskRouter.eligible(memberId, memberCaps, t)) return null;
    return _markClaimed(t, memberId);
  }

  TeamTask _markClaimed(TeamTask t, String memberId) {
    final claimed = t.copyWith(
      status: TaskStatus.claimed,
      assignee: memberId,
      claimedAt: _clock(),
    );
    _tasks[t.id] = claimed;
    _persist(() => _log?.appendClaim(t.id, memberId, claimed.claimedAt!));
    return claimed;
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

  /// 推进每个 pending 任务的路由阶段（单调）。[hasEligibleLiveMember] 由调用方注入,
  /// 表示「当前是否存在能领该任务的在线成员」——为 false 且超时才降级要求。返回阶段
  /// 发生变化的任务,并唤醒等待者（让更宽的合格 worker 来认领）。
  List<TeamTask> reconcile(
    int now,
    bool Function(TeamTask) hasEligibleLiveMember,
  ) {
    final changed = <TeamTask>[];
    for (final t in _tasks.values.toList()) {
      if (t.status != TaskStatus.pending) continue;
      final next = TaskRouter.nextStage(t, now, hasEligibleLiveMember(t));
      if (next == t.routing.stage) continue;
      final updated = t.copyWith(
        routing: t.routing.copyWith(stage: next, escalatedAt: now),
      );
      _tasks[t.id] = updated;
      _persist(() => _log?.appendEscalate(t.id, next, now));
      changed.add(updated);
    }
    if (changed.isNotEmpty) _wake();
    return changed;
  }

  /// 任务快照（看板 / `list_tasks`）；[status] 非空时过滤，按 seq 升序。
  List<TeamTask> list({TaskStatus? status}) {
    final all = _tasks.values.where((t) => status == null || t.status == status);
    return all.toList()..sort((a, b) => a.seq.compareTo(b.seq));
  }

  /// 当前可认领任务数（依赖已满足的 pending）。
  int get claimableCount => _tasks.values.where(_isClaimableNow).length;

  bool get hasClaimable => _tasks.values.any(_isClaimableNow);

  /// 阻塞到**对该成员合格**的可认领任务出现。**必须**与 [claimNext] 共用同一套
  /// 合格判定([TaskRouter.eligible])：否则不合格 worker 会在 [receiveWork] 里
  /// claimNext→null、waitForClaimable→立即返回 之间紧凑自旋(烧 CPU)且每圈泄漏一个
  /// 信箱 waiter。只在「有对本 worker 合格的可认领任务」时短路返回，否则 park 到
  /// [_wake]（新任务 / reconcile 放宽 / release / reclaim）。
  Future<void> waitForClaimable(String memberId, Set<String> memberCaps) {
    if (_hasClaimableFor(memberId, memberCaps)) return Future.value();
    final existing = _waiter;
    if (existing != null && !existing.isCompleted) return existing.future;
    final completer = Completer<void>();
    _waiter = completer;
    return completer.future;
  }

  bool _hasClaimableFor(String memberId, Set<String> memberCaps) =>
      _tasks.values.any(
        (t) => _isClaimableNow(t) && TaskRouter.eligible(memberId, memberCaps, t),
      );

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
