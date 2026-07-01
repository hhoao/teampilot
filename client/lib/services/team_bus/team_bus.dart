import 'dart:async';

import 'agent_node.dart';
import 'bus_feed_entry.dart';
import 'cancellation.dart';
import 'coordination/coordination_policy.dart';
import 'coordination/leader_star_coordination_policy.dart';
import 'env/bus_environment.dart';
import 'env/bus_observation.dart';
import 'idle_notification.dart';
import 'member_launcher.dart';
import 'persistence/bus_message_log.dart';
import 'persistence/bus_message_page.dart';
import 'send_outcome.dart';
import 'state/bus_effect.dart';
import 'state/bus_effect_dispatcher.dart';
import 'state/bus_event.dart';
import 'state/presence.dart';
import 'state/presence_reducer.dart';
import 'tasks/task_queue.dart';
import 'tasks/task_router.dart';
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
    bool Function(String memberId)? reportsIdleViaReceiveWork,
  }) : _env = environment ?? BusEnvironment(ids: idGenerator, clock: clock),
       _reportsIdleViaReceiveWork = reportsIdleViaReceiveWork,
       _messageLog = messageLog,
       _taskQueue = taskQueue,
       _launcher = launcher,
       _dispatcher = BusEffectDispatcher(
         launcher: launcher,
         doorbellNotice: doorbellNotice,
       ) {
    _coordination = coordination ??
        LeaderStarCoordinationPolicy(environment: _env);
    if (_taskQueue != null) {
      _reconcileTimer = Timer.periodic(
        const Duration(seconds: 15),
        (_) => reconcileTasks(),
      );
    }
  }

  /// 定时推进任务路由阶段（仅在装配了任务队列时启动）。
  Timer? _reconcileTimer;

  /// 新消息 id(MCP handler 复用,统一 id 源)。
  String newMessageId() => _env.ids();

  /// 门铃：信箱有积压时提示 pull。只对 idle-at-prompt 成员注入(parked 成员直收，
  /// 永不响门铃)，故用**非阻塞**的 read_messages —— cursor 等 push 成员被唤醒后
  /// 不能去调会超时的 wait_for_message；read_messages 秒回并抽干信箱。
  static const String doorbellNotice =
      '[teammate-bus] You have unread teammate messages — call '
      'read_messages(mark_read: true) to read them now, then handle them. '
      '(From the bus, not your operator.)';

  /// 队列有可认领任务、要敲一个 idle-at-prompt 的 worker 开工时注入的提示。与
  /// [doorbellNotice]（邮件→read_messages）区分：这里要 worker 去 `wait_for_message`，
  /// 它会原子认领下一个队列任务。
  static const String taskDoorbellNotice =
      '[teammate-bus] Queued work is available — call wait_for_message now to '
      'claim and start your next task. (From the bus, not your operator.)';

  /// [TeamMessage.from] when the human operator submits while the member waits.
  static const String userSenderId = 'user';

  /// 门铃重敲间隔（ms）。worker 被敲后仍停在 prompt、仍欠一记门铃（有未读 / 队列有
  /// 可认领）超过这么久，看门狗 [reengageIdleWorkers] 就补敲一次——补上全屏 TUI
  /// 输入框偶发吞掉首个回车导致的「永久卡在 prompt」。
  static const int doorbellRetryMs = 5 * 1000;

  final BusEnvironment _env;
  final BusMessageLog? _messageLog;
  final TaskQueue? _taskQueue;
  final MemberLauncher _launcher;
  final BusEffectDispatcher _dispatcher;

  /// 成员 idle 是否由 [receiveWork] 内 [_announceWorkerIdleToLead] 上报（forceWait
  /// CLI）。为真时 [onMemberIdle] 跳过协调策略 idle，避免与 receiveWork 双投递。
  final bool Function(String memberId)? _reportsIdleViaReceiveWork;
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
      PresenceContext(
        memberId: node.memberId,
        hasUnread: !node.inbox.isEmpty,
        doorbelled: node.doorbelled,
      ),
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
        // 置幂等闸：同一未读的后续 idle 边不再重复响门铃，直到成员进 wait 消费。
        node.doorbelled = true;
        node.doorbelledAt = _env.clock(); // 看门狗按此节流重敲（治回车被吞）。
        _env.events.emit(MemberDoorbelled(e.memberId));
      }
    }
    return effects;
  }

  /// 成员是否正 park 在 MCP `wait_for_message`。
  bool isWaitingForMessage(String memberId) =>
      _members[memberId]?.waitingForMessage ?? false;

  /// 成员是否正处于 bus 已知的回合中(Claude `isActive`;PTY 未起为否)。
  bool isMemberInTurn(String memberId) =>
      _members[memberId]?.claudeIsActive ?? false;

  /// 队里是否**任一**成员在回合中。会话级 working 指示器(tab / 列表项 spinner)用。
  bool get anyMemberInTurn =>
      _members.values.any((n) => n.claudeIsActive ?? false);

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
    node.doorbelled = false; // 进 wait = 响应了门铃并开始消费 → 解闸，读完后新邮件再响。
    node.doorbelledAt = null; // 已开工，看门狗停止重敲。
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
    node.doorbelled = false; // 进 wait = 响应了门铃并开始消费 → 解闸，读完后新邮件再响。
    node.doorbelledAt = null; // 已开工，看门狗停止重敲。
    _apply(node, const WaitEntered());
    // 本次 wait 是否已向 leader 上报过「我空闲了」（每个真正阻塞的 wait 期上报一次，
    // spurious wake 后重判不重复上报）。
    var announcedIdle = false;
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
          final task = queue.claimNext(memberId, node.profile.capabilities);
          if (task != null) return TaskWork(task);
        }
        // 3) 两者皆空 → 真正空闲。对齐 Claude Code「转 idle → 通知 leader → 再等待」：
        // 这是 bus 里精确的「worker 现在没活干」时刻，比被 parked 守卫挡掉的外部
        // onMemberIdle 可靠。随后 race 信箱到达 / 队列可认领 / 取消，醒来重判。
        if (!announcedIdle) {
          announcedIdle = true;
          _announceWorkerIdleToLead(node);
        }
        final wake = Completer<void>();
        void signal() {
          if (!wake.isCompleted) wake.complete();
        }

        unawaited(node.inbox.waitForArrival(cancel: cancel).then((_) => signal()));
        if (queue != null) {
          unawaited(queue
              .waitForClaimable(memberId, node.profile.capabilities)
              .then((_) => signal()));
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

  /// worker 进入 `wait_for_message` 且确无可干（消息空 + 队列无可认领）→ 真正空闲时，
  /// 向 team-lead 推一条 idle/available 通知。**对齐 Claude Code**「转 idle → 通知
  /// leader → 再等待」（inProcessRunner 在 isIdle 转换处 sendIdleNotification）。
  ///
  /// 替代被两道门焊死的旧路径：外部 [onMemberIdle] 对 parked worker 有 `waitingForMessage`
  /// 守卫、星型策略又有 `_unreported` 闸（仅消息投递置位，队列认领从不置位）——故纯队列
  /// worker 完成后回到 wait 永不上报、对 leader 隐形。这里在 bus 精确知晓「现在没活干」
  /// 的一刻直接上报，绕开二者。与 [send] 相同走非 eager 投递：leader 在
  /// `wait_for_message` 时由 waiter 直接收，不停在 prompt 才响门铃。
  void _announceWorkerIdleToLead(AgentNode node) {
    if (node.profile.isTeamLead) return;
    final leaderId = teamLeadId;
    if (leaderId == null || leaderId == node.memberId) return;
    _coordination.markIdleReported(node.memberId);
    final notice = IdleNotification.fromWorker(
      memberId: node.memberId,
      displayName: node.profile.effectiveDisplayName,
      timestampMs: _env.clock(),
    ).encode();
    _routeMail(
      leaderId,
      TeamMessage(
        id: _env.ids(),
        from: node.memberId,
        to: leaderId,
        content: notice,
      ),
    );
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
    final page = await node.inbox.readPage(
      afterId: afterId,
      limit: limit,
      unreadOnly: unreadOnly,
      markRead: markRead,
    );
    // push CLI（cursor 等永不进 wait）靠 read_messages 消费未读。抽干后解闸，
    // 否则 _onMail 的「已响过就不重发」抑制会把它后续的邮件门铃也压住（饿死）。
    if (markRead && node.inbox.isEmpty) {
      node.doorbelled = false;
      node.doorbelledAt = null;
    }
    return page;
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

  /// Read-only full-team feed: unions every member inbox's records, dedups by
  /// message id (broadcasts land in multiple inboxes), and sorts by time.
  Future<List<BusFeedEntry>> messagesSnapshot() async {
    final byId = <String, BusFeedEntry>{};
    for (final node in _members.values) {
      final records = await node.inbox.snapshotRecords();
      for (final r in records) {
        final existing = byId[r.message.id];
        if (existing == null) {
          byId[r.message.id] = BusFeedEntry(
            from: r.message.from,
            to: r.message.to,
            content: r.message.content,
            createdAt: r.createdAt,
            isUnread: r.isUnread,
          );
        } else {
          byId[r.message.id] = BusFeedEntry(
            from: existing.from,
            to: existing.to,
            content: existing.content,
            createdAt: existing.createdAt < r.createdAt
                ? existing.createdAt
                : r.createdAt,
            isUnread: existing.isUnread || r.isUnread,
          );
        }
      }
    }
    final entries = byId.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return entries;
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

  /// 直投并 eager 唤醒（用户命令）：即便成员在回合中也响门铃。
  void _deliverToMember(String memberId, TeamMessage message) {
    _routeMail(memberId, message, eager: true);
  }

  /// 投递邮件并按 [eager] 决定是否响门铃（与 [send] 路径一致）。
  void _routeMail(String memberId, TeamMessage message, {bool eager = false}) {
    final node = _members[memberId];
    if (node == null) return;
    _deliverToInbox(node, message);
    _apply(node, MailArrived(eager: eager));
  }

  String? _teamLeadMemberId() {
    for (final node in _members.values) {
      if (node.profile.isTeamLead) return node.memberId;
    }
    return null;
  }

  /// UI 用户在成员 wait 期间提交的一行 → 信箱（`from: user`）。返回新建消息 id，
  /// 空行 / 未知成员返回空串。
  String deliverUserCommand(String memberId, String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return '';
    final node = _members[memberId];
    if (node == null) return '';
    final id = _env.ids();
    _deliverToMember(
      memberId,
      TeamMessage(
        id: id,
        from: userSenderId,
        to: memberId,
        content: trimmed,
      ),
    );
    return id;
  }

  /// 该成员信箱里 [id] 是否仍未读（未被取走 / 未读）。
  bool isUnread(String memberId, String id) =>
      _members[memberId]?.inbox.containsUnread(id) ?? false;

  /// Resolves [address] to a registered [memberId].
  ///
  /// Accepts roster member id (`developer`) or CLI
  /// [TeammateRosterProfile.agentId] (`developer@my-team-1`).
  String? resolveMemberId(String address) {
    final trimmed = address.trim();
    if (trimmed.isEmpty) return null;
    if (_members.containsKey(trimmed)) return trimmed;
    for (final node in _members.values) {
      final agentId = node.profile.agentId.trim();
      if (agentId.isNotEmpty && agentId == trimmed) {
        return node.memberId;
      }
    }
    final at = trimmed.lastIndexOf('@');
    if (at <= 0) return null;
    final name = trimmed.substring(0, at);
    final teamSuffix = trimmed.substring(at + 1);
    final node = _members[name];
    if (node == null) return null;
    final cliTeam = _sessionContext?.cliTeamName.trim() ?? '';
    if (cliTeam.isNotEmpty && teamSuffix == cliTeam) return name;
    return null;
  }

  /// 出站投递；按 lifecycle + activity 分流。
  Future<SendOutcome> send(TeamMessage message) async {
    if (message.hop >= maxHop) {
      _env.events.emit(MessageDropped(
        messageId: message.id,
        reason: 'over-hop(${message.hop})',
        to: message.to,
      ));
      return SendOutcome.dropped(
        reason: 'over-hop(${message.hop})',
        to: message.to,
      );
    }
    final resolved = resolveMemberId(message.to);
    if (resolved == null) {
      _env.events.emit(MessageDropped(
        messageId: message.id,
        reason: 'unknown-member',
        to: message.to,
      ));
      return SendOutcome.dropped(reason: 'unknown-member', to: message.to);
    }
    final target = _members[resolved]!;
    final routed = message.to == resolved ? message : message.copyWith(to: resolved);
    switch (target.lifecycle) {
      case MemberLifecycle.declared:
        // 物化（awaited PTY 拉起）→ 投递 → 完成（running+active）+ 门铃。
        await _bringOnline(target, routed);
        _deliverToInbox(target, routed);
        await _applyAsync(target, const MaterializeCompleted());
      case MemberLifecycle.materializing:
      case MemberLifecycle.running:
        _deliverToInbox(target, routed);
        _apply(target, const MailArrived()); // send 路径：仅 idle-at-prompt 响门铃
    }
    return SendOutcome.delivered(resolved);
  }

  /// **物化漏斗（唯一入口）**：把一个 declared 成员拉起上线（declared → materializing
  /// → PTY running）。消息路径（[send]）与任务队列路径（[addTasks]）共用此处——任何
  /// 「产生需求、需要成员上线」的地方都必须经由它，结构上杜绝某条投递路径漏接生命
  /// 周期（历史 bug：`add_tasks` 漏接 → leader 派任务但 declared worker 不启动、无人
  /// 认领）。物化后由 [PtySpawned]（扩展侧 `markMemberRunning`）转 running；本方法不
  /// 调 [MaterializeCompleted]，调用方按需自行决定后续（send 要 active+门铃，队列则让
  /// worker 自然进 `wait_for_message` 拉取）。[bootstrap] 内容仅供 launcher 调度连接。
  Future<void> _bringOnline(AgentNode node, TeamMessage bootstrap) async {
    if (node.lifecycle != MemberLifecycle.declared) return;
    await _applyAsync(node, MaterializeStarted(bootstrap));
  }

  /// working 边：用户在成员自己的 prompt 直接提交一行(未 parked)→ 标记回合开始。
  /// presence 据此判 working,不必再靠 PTY 字节(被 spinner 污染)猜。守卫见
  /// [PresenceReducer] 的 [TurnStarted](declared/materializing/parked 不处理)。
  void markTurnStarted(String memberId) {
    final node = _members[memberId];
    if (node == null) return;
    _apply(node, const TurnStarted());
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
    final reportsViaReceiveWork =
        _reportsIdleViaReceiveWork?.call(memberId) ?? false;
    if (!reportsViaReceiveWork) {
      for (final msg in _coordination.onMemberIdle(this, memberId)) {
        _deliverToMember(msg.to, msg);
      }
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

  /// leader 批量入队任务（`add_tasks` 落点）。入队后两条认领来源汇合：
  /// ① 已 running 且 parked 的空闲 worker —— 由 [TaskQueue] 内部 waiter（`_wake` →
  ///    `waitForClaimable`）即时唤醒，在统一 idle 原语 [receiveWork] 里自动认领；
  /// ② declared（尚未启动）的 worker —— 经 [_materializeWorkersForQueue] 按需拉起
  ///    上线，进入 `wait_for_message` 后认领。②与 [send] 共用 [_bringOnline] 物化
  ///    漏斗，修复「leader 派任务但 declared worker 不启动、无人认领」。
  List<TeamTask> addTasks(String createdBy, List<TeamTaskDraft> drafts) {
    final queue = _taskQueue;
    if (queue == null) return const [];
    final created = queue.addTasks(createdBy, drafts);
    if (created.isNotEmpty) {
      // fire-and-forget：入队即返回（MCP 响应无需等 worker 就绪），engage 在后台进行，
      // 语义同 [_apply] 的 unawaited dispatch。
      unawaited(_engageWorkersForQueue(createdBy));
    }
    return created;
  }

  /// 入队后按需「叫醒」非 leader worker 去认领，覆盖其全部生命周期状态——这是
  /// `add_tasks` 真正让成员开工的关键（[TaskQueue] 的 `_wake` 只能唤醒**已 parked**
  /// 在 `receiveWork` 的 worker，够不到刚启动、停在 prompt 从未进过 wait 的 worker）：
  ///
  /// - **parked**（`waitingForMessage`）→ 已被 `queue._wake` 即时唤醒认领，不在此处理；
  /// - **running 且 atPrompt**（启动后没人给初始 prompt → 停在 prompt，从未进 wait）→
  ///   响门铃（注入 stdin）催它调 `wait_for_message`，与 [send] 对 atPrompt 的处理对齐；
  /// - **declared**（尚未启动）→ 物化拉起上线。
  ///
  /// 引擎成员上限 = 可认领任务数 − 已 parked 数，避免给少量任务过度供给。**优先**敲
  /// 已在跑的 atPrompt worker（几乎零成本）再冷启动 declared（有 token/延迟代价）。
  Future<void> _engageWorkersForQueue(String createdBy) async {
    final queue = _taskQueue;
    if (queue == null) return;
    final workers =
        _members.values.where((n) => !n.profile.isTeamLead).toList();
    for (final task in queue.list(status: TaskStatus.pending)) {
      if (_hasParkedEligibleWorker(workers, task)) continue;

      // 第一轮：敲已在跑、停在 prompt 的合格 worker（便宜，无冷启动）。
      AgentNode? running;
      for (final n in workers) {
        if (n.lifecycle != MemberLifecycle.running) continue;
        if (n.activity != MemberActivity.turnDoneReady) continue; // atPrompt
        if (n.doorbelledAt != null) continue; // 本轮已敲过；重试交给看门狗（只补回车）
        if (!TaskRouter.eligible(n.memberId, n.profile.capabilities, task)) {
          continue;
        }
        running = n;
        break;
      }
      if (running != null) {
        running.doorbelledAt = _env.clock();
        _launcher.wake(running.memberId, taskDoorbellNotice);
        continue;
      }

      // 第二轮：冷启动尚未上线、合格的 declared worker。
      AgentNode? declared;
      for (final n in workers) {
        if (n.lifecycle != MemberLifecycle.declared) continue;
        if (!TaskRouter.eligible(n.memberId, n.profile.capabilities, task)) {
          continue;
        }
        declared = n;
        break;
      }
      if (declared != null) {
        await _bringOnline(
          declared,
          TeamMessage(
            id: _env.ids(),
            from: createdBy,
            to: declared.memberId,
            content: taskDoorbellNotice,
          ),
        );
      }
      // 否则：无合格成员可上线 → 留给 [reconcileTasks] 最终降级。
    }
  }

  /// 距上次门铃是否还在重敲窗口内（[doorbellRetryMs] 节流，避免每个 tick 轰炸）。
  bool _recentlyDoorbelled(AgentNode node) {
    final at = node.doorbelledAt;
    return at != null && _env.clock() - at < doorbellRetryMs;
  }

  /// **门铃看门狗**（1s idle watcher 周期调用）：重敲仍停在 prompt、却还欠一记门铃的
  /// running worker。邮件门铃靠「每来一条新消息重响」白拿这种重试，队列门铃没有 ——
  /// 全屏 TUI 输入框偶发把注入的首个回车吞成换行时，worker 永远进不了
  /// `wait_for_message`、`doorbelledAt` 也永不清零，文字就此卡在输入框。这里按
  /// [doorbellRetryMs] 节流补敲，直到 worker 真正消费（进 wait / 抽干未读）后
  /// `doorbelledAt` 清零、条件不再满足自然停。消息优先于队列任务（与 [receiveWork]
  /// 一致）。只管已 running 的 worker —— declared 的冷启动由 [addTasks] / [reconcileTasks]
  /// 负责。
  void reengageIdleWorkers() {
    final queue = _taskQueue;
    for (final node in _members.values) {
      if (node.profile.isTeamLead) continue;
      if (node.lifecycle != MemberLifecycle.running) continue;
      if (node.activity != MemberActivity.turnDoneReady) continue; // atPrompt
      if (_recentlyDoorbelled(node)) continue;
      final String notice;
      if (!node.inbox.isEmpty) {
        notice = doorbellNotice;
      } else if (queue != null && _hasEligiblePendingTask(node, queue)) {
        notice = taskDoorbellNotice;
      } else {
        continue; // 没有欠它的门铃。
      }
      // 首次响铃才注入提示全文；之后只补回车提交已卡在框里的那条——重打全文会让同一
      // 条提示在输入框里叠成好几份（用户看到的「短时间发好几条」）。
      if (node.doorbelledAt == null) {
        _launcher.wake(node.memberId, notice);
      } else {
        _launcher.nudgeSubmit(node.memberId);
      }
      node.doorbelledAt = _env.clock();
    }
  }

  bool _hasEligiblePendingTask(AgentNode node, TaskQueue queue) {
    for (final task in queue.list(status: TaskStatus.pending)) {
      if (TaskRouter.eligible(node.memberId, node.profile.capabilities, task)) {
        return true;
      }
    }
    return false;
  }

  bool _hasParkedEligibleWorker(List<AgentNode> workers, TeamTask task) {
    for (final n in workers) {
      if (!n.waitingForMessage) continue;
      if (TaskRouter.eligible(n.memberId, n.profile.capabilities, task)) {
        return true;
      }
    }
    return false;
  }

  /// 推进任务路由阶段（定时 + 事件驱动）。降级后重新尝试 engage。
  List<TeamTask> reconcileTasks() {
    final queue = _taskQueue;
    if (queue == null) return const [];
    final changed = queue.reconcile(_env.clock(), _hasEligibleLiveMember);
    if (changed.isNotEmpty) {
      unawaited(_engageWorkersForQueue(_teamLeadMemberId() ?? ''));
    }
    return changed;
  }

  /// 是否存在能领该任务的**在线**（running/materializing）非 leader 成员。declared
  /// 不算「在线」——它要靠 engage 拉起；拉不起来才该降级。
  bool _hasEligibleLiveMember(TeamTask task) {
    for (final n in _members.values) {
      if (n.profile.isTeamLead) continue;
      if (!n.ptyRunning) continue;
      if (TaskRouter.eligible(n.memberId, n.profile.capabilities, task)) {
        return true;
      }
    }
    return false;
  }

  /// 原子认领下一个对该成员合格的任务（[receiveWork] 内部复用；无可认领返回 null）。
  TeamTask? claimNextTask(String memberId) =>
      _taskQueue?.claimNext(memberId, _capsOf(memberId));

  /// pull 式自取：worker 主动认领指定任务（MCP `claim_task` 落点）。
  TeamTask? claimSpecificTask(String taskId, String memberId) =>
      _taskQueue?.claimSpecific(taskId, memberId, _capsOf(memberId));

  /// 成员能力（MCP `list_tasks` 标注 eligible_for_you / match_score 用）。
  Set<String> capabilitiesOf(String memberId) => _capsOf(memberId);

  Set<String> _capsOf(String memberId) =>
      _members[memberId]?.profile.capabilities ?? const {};

  /// worker 汇报任务终态（`update_task` 落点）。leader 经由 worker 进入 wait_for_message
  /// 时的 idle 通知（[_announceWorkerIdleToLead]）感知进度，对齐 Claude Code——
  /// `update_task` 本身只落库，不单独通知（CC 同样不自动把结果推给 leader）。
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
    _reconcileTimer?.cancel();
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
