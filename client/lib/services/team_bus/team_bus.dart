import 'dart:async';

import 'agent_node.dart';
import 'cancellation.dart';
import 'coordination/coordination_policy.dart';
import 'coordination/leader_star_coordination_policy.dart';
import 'env/bus_environment.dart';
import 'env/bus_observation.dart';
import 'member_launcher.dart';
import 'persistence/bus_message_log.dart';
import 'persistence/bus_message_page.dart';
import 'state/bus_effect.dart';
import 'state/bus_effect_dispatcher.dart';
import 'state/bus_event.dart';
import 'state/presence.dart';
import 'state/presence_reducer.dart';
import 'tasks/task_queue.dart';
import 'tasks/team_task.dart';
import 'team_message.dart';
import 'teammate_roster_profile.dart';
import 'teammate_snapshot.dart';

/// 进程内消息总线：路由 + 每成员信箱 + 纯函数状态机（[PresenceReducer]）+ 效果即
/// 数据（[BusEffect]）+ 可插拔协调策略（[CoordinationPolicy]）+ 惰性物化。
class TeamBus implements CoordinationView {
  TeamBus({
    required MemberLauncher launcher,
    BusEnvironment? environment,
    String Function()? idGenerator, // sugar over BusEnvironment.ids
    int Function()? clock, // sugar over BusEnvironment.clock
    BusMessageLog? messageLog,
    CoordinationPolicy? coordination,
    TaskQueue? taskQueue,
    this.maxHop = 8,
  }) : _env = environment ?? BusEnvironment(ids: idGenerator, clock: clock),
       _messageLog = messageLog,
       _taskQueue = taskQueue,
       _dispatcher = BusEffectDispatcher(
         launcher: launcher,
         doorbellNotice: doorbellNotice,
       ) {
    _coordination = coordination ??
        LeaderStarCoordinationPolicy(environment: _env);
  }

  /// 新消息 id(MCP handler 复用,统一 id 源)。
  String newMessageId() => _env.ids();

  /// 门铃：信箱有积压时提示 pull。
  static const String doorbellNotice =
      '[teammate-bus] You have unread teammate messages — call '
      'wait_for_message to read them. (From the bus, not your operator.)';

  /// [TeamMessage.from] when the human operator submits while the member waits.
  static const String userSenderId = 'user';

  final BusEnvironment _env;
  final BusMessageLog? _messageLog;
  final TaskQueue? _taskQueue;
  final BusEffectDispatcher _dispatcher;
  late final CoordinationPolicy _coordination;
  final int maxHop;
  final Map<String, AgentNode> _members = {};
  TeamSessionContext? _sessionContext;

  @override
  AgentNode? member(String memberId) => _members[memberId];

  @override
  String? get teamLeadId => _teamLeadMemberId();

  void installSessionContext(TeamSessionContext context) {
    _sessionContext = context;
  }

  TeamSessionContext? get sessionContext => _sessionContext;

  /// 注册成员 → [MemberLifecycle.declared]。绑定日志层(单一事实源)。
  void declareMember(AgentNode node) {
    _members[node.memberId] = node;
    final log = _messageLog;
    if (log != null) node.inbox.bindLog(log, _env.clock);
  }

  AgentNode? memberById(String memberId) => _members[memberId];

  /// PTY 已 spawn → [MemberLifecycle.running] + [MemberActivity.turnDoneReady]。
  void markMemberRunning(String memberId) {
    final node = _members[memberId];
    if (node == null) return;
    _apply(node, const PtySpawned());
  }

  /// 跑 reducer：算出新在线态写回 node，返回待落地的效果。
  List<BusEffect> _reduce(AgentNode node, BusEvent event) {
    final t = PresenceReducer.reduce(
      Presence(node.lifecycle, node.activity),
      event,
      PresenceContext(memberId: node.memberId, hasUnread: !node.inbox.isEmpty),
    );
    node.lifecycle = t.presence.lifecycle;
    node.activity = t.presence.activity;
    return t.effects;
  }

  /// 同步路径（效果仅含 doorbell，wake 在当前微任务内同步触发，保序）。
  void _apply(AgentNode node, BusEvent event) {
    unawaited(_dispatcher.dispatchAll(_observe(node, _reduce(node, event))));
  }

  /// 异步路径（含 materialize：须 await PTY 拉起后才继续）。
  Future<void> _applyAsync(AgentNode node, BusEvent event) {
    return _dispatcher.dispatchAll(_observe(node, _reduce(node, event)));
  }

  /// 把效果落成可观测事件后原样返回(门铃)。
  List<BusEffect> _observe(AgentNode node, List<BusEffect> effects) {
    for (final e in effects) {
      if (e is DoorbellEffect) {
        _env.events.emit(MemberDoorbelled(e.memberId));
      }
    }
    return effects;
  }

  /// 成员是否正 park 在 MCP `wait_for_message`。
  bool isWaitingForMessage(String memberId) =>
      _members[memberId]?.waitingForMessage ?? false;

  /// 全队 roster（MCP `list_teammates`）；leader 在前，其余按 member id 排序。
  TeamRosterSnapshot rosterSnapshot() {
    final snapshots = _members.values
        .map(
          (node) => TeammateSnapshot(
            profile: node.profile,
            lifecycle: node.lifecycle,
            activity: node.activity,
            unreadCount: _hotUnreadCount(node),
          ),
        )
        .toList();
    snapshots.sort((a, b) {
      if (a.profile.isTeamLead != b.profile.isTeamLead) {
        return a.profile.isTeamLead ? -1 : 1;
      }
      return a.memberId.compareTo(b.memberId);
    });
    return TeamRosterSnapshot(team: _sessionContext, members: snapshots);
  }

  /// 兼容旧调用。
  List<TeammateSnapshot> listTeammates() => rosterSnapshot().members;

  /// 阻塞接收（MCP `wait_for_message` 落点）；[timeout] 为 null 时无限等待。
  ///
  /// 取走并 **立即** 标记已读 —— 仅当传输层确保能把结果送达 CLI 时才该用它
  /// （例如非流式调用 / 测试）。流式 SSE 路径请改用
  /// [receivePending] + [acknowledgeDelivery] / [redeliver]，否则客户端中途断连
  /// 会「已读但未投递」丢消息。
  Future<List<TeamMessage>> receive(
    String memberId, {
    Duration? timeout,
    CancellationToken? cancel,
  }) async {
    final batch = await receivePending(memberId, timeout: timeout, cancel: cancel);
    if (batch.isNotEmpty) {
      await acknowledgeDelivery(memberId, batch.map((m) => m.id));
    }
    return batch;
  }

  /// 取走未读但 **不** 标记已读（日志仍为未读）。流式传输层在结果写回成功后调
  /// [acknowledgeDelivery]，失败（客户端断连）则调 [redeliver] 回滚。[cancel]
  /// 触发（客户端断连）时以空批解除阻塞，避免 park 泄漏。
  Future<List<TeamMessage>> receivePending(
    String memberId, {
    Duration? timeout,
    CancellationToken? cancel,
  }) async {
    final node = _members[memberId];
    if (node == null) {
      return const <TeamMessage>[];
    }
    _apply(node, const WaitEntered());
    try {
      final batch = await node.inbox.waitAndTake(timeout: timeout, cancel: cancel);
      if (batch.isNotEmpty) {
        _env.events.emit(BatchTaken(memberId: memberId, count: batch.length));
      }
      return batch;
    } finally {
      _apply(node, const WaitExited());
    }
  }

  /// 结果已成功送达 CLI → 落 read 事件（取走已发生在 [receivePending]）。
  Future<void> acknowledgeDelivery(
    String memberId,
    Iterable<String> messageIds,
  ) async {
    final ids = messageIds.toList(growable: false);
    await _members[memberId]?.inbox.confirmRead(ids);
    if (ids.isNotEmpty) {
      _env.events.emit(DeliveryConfirmed(memberId: memberId, count: ids.length));
    }
  }

  /// 结果写回失败（SSE 断连）→ 把取走但未确认的批次放回未读集，避免「已读但未
  /// 投递」丢失。日志从未落 read 事件，重连安全。
  void redeliver(String memberId, List<TeamMessage> batch) {
    if (batch.isEmpty) return;
    _members[memberId]?.inbox.restore(batch);
    _env.events.emit(DeliveryRolledBack(memberId: memberId, count: batch.length));
  }

  /// **统一 idle 原语**（`wait_for_message` 落点）：阻塞到 **有消息或有可认领任务**，
  /// 醒来返回其一。优先级 **消息 > 队列任务 > 阻塞**（消息可能改写/重排 worker 当前
  /// 要做的事）。消息取走但 **不** 标记已读（传输层成功写回后 [acknowledgeDelivery]，
  /// 断连则 [redeliver]）；任务已原子认领（断连则 [releaseTask] 退回 pending）。
  /// team-lead 不自动认领任务（[_taskQueue] 为空亦然），退化为纯消息等待。
  Future<WorkBatch> receiveWork(String memberId, {CancellationToken? cancel}) async {
    final node = _members[memberId];
    if (node == null) return const EmptyWork();
    // team-lead 永不自动认领任务；非 mixed 模式 _taskQueue 为空 → 纯消息等待。
    final queue = node.profile.isTeamLead ? null : _taskQueue;
    _apply(node, const WaitEntered());
    try {
      while (true) {
        if (cancel?.isCancelled ?? false) return const EmptyWork();
        // 1) 消息优先（非空时立即取走，不阻塞）。
        if (!node.inbox.isEmpty) {
          final batch = await node.inbox.waitAndTake(cancel: cancel);
          if (batch.isNotEmpty) {
            _env.events.emit(BatchTaken(memberId: memberId, count: batch.length));
            return MessageWork(batch);
          }
        }
        // 2) 否则原子认领一个队列任务（worker only）。
        if (queue != null) {
          final task = queue.claimNext(memberId);
          if (task != null) return TaskWork(task);
        }
        // 3) 两者皆空 → race 信箱到达 / 队列可认领 / 取消，醒来重判。
        final wake = Completer<void>();
        void signal() {
          if (!wake.isCompleted) wake.complete();
        }

        unawaited(node.inbox.waitForArrival(cancel: cancel).then((_) => signal()));
        if (queue != null) {
          unawaited(queue.waitForClaimable().then((_) => signal()));
        }
        if (cancel != null) {
          unawaited(cancel.whenCancelled.then((_) => signal()));
        }
        await wake.future;
      }
    } finally {
      _apply(node, const WaitExited());
    }
  }

  /// 任务结果写回失败（客户端断连）→ 退回 pending，避免卡在没收到它的 worker 上。
  void releaseTask(String taskId) => _taskQueue?.release(taskId);

  /// 分页读邮件（默认只读未读、不消费）。
  Future<BusMessagePage> readMessages(
    String memberId, {
    String? afterId,
    int limit = 20,
    bool unreadOnly = true,
    bool markRead = false,
  }) async {
    final node = _members[memberId];
    if (node == null) {
      return const BusMessagePage(messages: [], hasMore: false);
    }
    return node.inbox.readPage(
      afterId: afterId,
      limit: limit,
      unreadOnly: unreadOnly,
      markRead: markRead,
    );
  }

  /// 打开 session：回放每个成员的日志，重建未读集；并回放共享任务队列。
  Future<void> rehydrateUnread() async {
    await _taskQueue?.rehydrate();
    for (final node in _members.values) {
      await node.inbox.rehydrate();
      if (!node.inbox.isEmpty) _coordination.noteInboundWork(node.memberId);
      // 同步 declared 的 mailQueued/none（此时尚无 PTY，不会响门铃）。
      _apply(node, const MailArrived());
    }
  }

  Future<int> unreadCountFor(String memberId) async {
    return _members[memberId]?.inbox.unreadCount ?? 0;
  }

  int _hotUnreadCount(AgentNode node) => node.inbox.unreadCount;

  /// 纯数据投递（内存 + 日志由 inbox 自洽）；活动态 / 门铃交给 [MailArrived]，
  /// 协调上报由 [CoordinationPolicy] 记账。
  void _deliverToInbox(AgentNode node, TeamMessage message) {
    _coordination.noteInboundWork(node.memberId);
    node.inbox.deliver(message);
    _env.events.emit(MessageRouted(
      messageId: message.id,
      to: node.memberId,
      from: message.from,
    ));
  }

  /// 直投并 eager 唤醒（idle-notify / 用户命令）：即便成员在回合中也响门铃。
  void _deliverToMember(String memberId, TeamMessage message) {
    final node = _members[memberId];
    if (node == null) return;
    _deliverToInbox(node, message);
    _apply(node, const MailArrived(eager: true));
  }

  String? _teamLeadMemberId() {
    for (final node in _members.values) {
      if (node.profile.isTeamLead) return node.memberId;
    }
    return null;
  }

  /// UI 用户在成员 wait 期间提交的一行 → 信箱（`from: user`）。
  void deliverUserCommand(String memberId, String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;
    final node = _members[memberId];
    if (node == null) return;
    _deliverToMember(
      memberId,
      TeamMessage(
        id: _env.ids(),
        from: userSenderId,
        to: memberId,
        content: trimmed,
      ),
    );
  }

  /// 出站投递；按 lifecycle + activity 分流。
  Future<void> send(TeamMessage message) async {
    if (message.hop >= maxHop) {
      _env.events.emit(MessageDropped(
        messageId: message.id,
        reason: 'over-hop(${message.hop})',
        to: message.to,
      ));
      return;
    }
    final target = _members[message.to];
    if (target == null) {
      _env.events.emit(MessageDropped(
        messageId: message.id,
        reason: 'unknown-member',
        to: message.to,
      ));
      return;
    }
    switch (target.lifecycle) {
      case MemberLifecycle.declared:
        // 物化（awaited PTY 拉起）→ 投递 → 完成（running+active）+ 门铃。
        await _applyAsync(target, MaterializeStarted(message));
        _deliverToInbox(target, message);
        await _applyAsync(target, const MaterializeCompleted());
      case MemberLifecycle.materializing:
      case MemberLifecycle.running:
        _deliverToInbox(target, message);
        _apply(target, const MailArrived()); // send 路径：仅 idle-at-prompt 响门铃
    }
  }

  /// idle 边：turn 结束 → [MemberActivity.turnDoneReady]（或 doorbell → active）。
  void onMemberIdle(String memberId) {
    final node = _members[memberId];
    if (node == null) return;
    if (node.lifecycle == MemberLifecycle.declared ||
        node.lifecycle == MemberLifecycle.materializing) {
      return;
    }
    if (node.waitingForMessage) {
      return;
    }
    for (final msg in _coordination.onMemberIdle(this, memberId)) {
      _deliverToMember(msg.to, msg);
    }
    _apply(node, const TurnEnded());
  }

  Future<void> broadcast(
    TeamMessage message, {
    bool materializeDeclared = false,
  }) async {
    if (materializeDeclared) {
      for (final node in _members.values) {
        if (node.memberId == message.from) continue;
        await send(
          message.copyWith(
            id: _env.ids(),
            to: node.memberId,
            hop: message.hop + 1,
          ),
        );
      }
      return;
    }

    for (final node in _members.values) {
      if (node.memberId == message.from) continue;
      if (node.lifecycle == MemberLifecycle.declared) continue;
      _deliverToInbox(
        node,
        message.copyWith(
          id: _env.ids(),
          to: node.memberId,
          hop: message.hop + 1,
        ),
      );
      _apply(node, const MailArrived());
    }
  }

  // --- work-queue（mixed 模式专属；纯 Claude swarm 复用 Claude 原生任务表）---

  /// 是否装配了共享任务队列（仅 mixed 模式接线）。
  bool get hasTaskQueue => _taskQueue != null;

  /// leader 批量入队任务（`add_tasks` 落点）。入队会触发队列内部 waiter，统一 idle
  /// 原语 [receiveWork] 中阻塞的空闲 worker 由此被即时唤醒并自动认领（无需 nudge）。
  List<TeamTask> addTasks(String createdBy, List<TeamTaskDraft> drafts) =>
      _taskQueue?.addTasks(createdBy, drafts) ?? const [];

  /// 原子认领下一个任务（[receiveWork] 内部复用；无可认领返回 null）。
  TeamTask? claimNextTask(String memberId) => _taskQueue?.claimNext(memberId);

  /// worker 汇报任务终态（`update_task` 落点）。
  bool updateTask(
    String taskId,
    TaskStatus status, {
    String? result,
    String? byMember,
  }) =>
      _taskQueue?.update(taskId, status, result: result, byMember: byMember) ??
      false;

  /// 任务看板快照（`list_tasks` 落点）。
  List<TeamTask> listTasks({TaskStatus? status}) =>
      _taskQueue?.list(status: status) ?? const [];

  /// 租约回收：claimed 超时且认领者掉线 → 退回 pending。掉线判定复用 PTY 在线态。
  List<TeamTask> reclaimExpiredTasks({int leaseMs = 5 * 60 * 1000}) {
    final queue = _taskQueue;
    if (queue == null) return const [];
    // 回收会触发队列 waiter，唤醒 [receiveWork] 中阻塞的其它空闲 worker 接手。
    return queue.reclaimExpired(
      leaseMs: leaseMs,
      isAlive: (memberId) => _members[memberId]?.ptyRunning ?? false,
    );
  }

  /// 关闭 session：释放每个信箱的 Timer / 挂起 waiter，防泄漏。
  void dispose() {
    for (final node in _members.values) {
      node.inbox.dispose();
    }
    _taskQueue?.dispose();
  }
}

/// [TeamBus.receiveWork] 的结果：一批消息 / 一个已认领任务 / 空（取消）。统一
/// idle 原语让 worker 在单次调用里拿到“下一件该做的事”，无需在 wait / claim 间分支。
sealed class WorkBatch {
  const WorkBatch();
}

/// 取走但未标记已读的消息批（传输层 confirm / abort）。
class MessageWork extends WorkBatch {
  const MessageWork(this.messages);
  final List<TeamMessage> messages;
}

/// 已为该成员原子认领的任务（传输层断连则 [TeamBus.releaseTask] 退回 pending）。
class TaskWork extends WorkBatch {
  const TaskWork(this.task);
  final TeamTask task;
}

/// 取消 / 未知成员，无内容。
class EmptyWork extends WorkBatch {
  const EmptyWork();
}
