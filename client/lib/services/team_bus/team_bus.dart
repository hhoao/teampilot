import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../utils/logger.dart';
import 'agent_node.dart';
import 'idle_notification.dart';
import 'member_launcher.dart';
import 'persistence/bus_message_page.dart';
import 'persistence/bus_message_store.dart';
import 'team_message.dart';
import 'teammate_roster_profile.dart';
import 'teammate_snapshot.dart';

/// 进程内消息总线：路由 + 每成员信箱 + 状态机 + 惰性物化 + 边触发唤醒。
class TeamBus {
  TeamBus({
    required MemberLauncher launcher,
    String Function()? idGenerator,
    BusMessageStore? messageStore,
    this.maxHop = 8,
  }) : _launcher = launcher,
       _idGenerator = idGenerator ?? (() => const Uuid().v4()),
       _messageStore = messageStore;

  /// 门铃：信箱有积压时提示 pull。
  static const String doorbellNotice =
      '[teammate-bus] You have unread teammate messages — call '
      'wait_for_message to read them. (From the bus, not your operator.)';

  /// [TeamMessage.from] when the human operator submits while the member waits.
  static const String userSenderId = 'user';

  final MemberLauncher _launcher;
  final String Function() _idGenerator;
  final BusMessageStore? _messageStore;
  final int maxHop;
  final Map<String, AgentNode> _members = {};
  TeamSessionContext? _sessionContext;

  void installSessionContext(TeamSessionContext context) {
    _sessionContext = context;
  }

  TeamSessionContext? get sessionContext => _sessionContext;

  /// 注册成员 → [MemberLifecycle.declared]。
  void declareMember(AgentNode node) {
    _members[node.memberId] = node;
  }

  AgentNode? memberById(String memberId) => _members[memberId];

  /// PTY 已 spawn → [MemberLifecycle.running] + [MemberActivity.turnDoneReady]。
  void markMemberRunning(String memberId) {
    final node = _members[memberId];
    if (node == null) return;
    node.lifecycle = MemberLifecycle.running;
    node.activity = MemberActivity.turnDoneReady;
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
  /// 抽干热信箱 **并立即** 把这批标记已读 —— 仅当传输层确保能把结果送达 CLI 时
  /// 才该用它（例如非流式调用 / 测试）。流式 SSE 路径请改用
  /// [receivePending] + [acknowledgeDelivery] / [redeliver]，否则客户端中途断连
  /// 会「已读但未投递」丢消息。
  Future<List<TeamMessage>> receive(
    String memberId, {
    Duration? timeout,
  }) async {
    final batch = await receivePending(memberId, timeout: timeout);
    if (batch.isNotEmpty) {
      await acknowledgeDelivery(memberId, batch.map((m) => m.id));
    }
    return batch;
  }

  /// 抽干热信箱但 **不** 标记已读（冷层仍为未读）。流式传输层在结果写回成功后
  /// 调 [acknowledgeDelivery]，失败（客户端断连）则调 [redeliver] 回滚。
  Future<List<TeamMessage>> receivePending(
    String memberId, {
    Duration? timeout,
  }) async {
    final node = _members[memberId];
    if (node == null) {
      return const <TeamMessage>[];
    }
    if (node.ptyRunning) {
      node.activity = MemberActivity.turnDoneBusWait;
    }
    try {
      return await node.inbox.waitBatch(timeout: timeout);
    } finally {
      if (node.ptyRunning &&
          node.activity == MemberActivity.turnDoneBusWait) {
        node.activity = MemberActivity.active;
      }
    }
  }

  /// 结果已成功送达 CLI → 冷层标记已读（热层抽干已发生在 [receivePending]）。
  Future<void> acknowledgeDelivery(
    String memberId,
    Iterable<String> messageIds,
  ) async {
    final ids = messageIds.toList(growable: false);
    if (ids.isEmpty) return;
    await _messageStore?.markRead(memberId, ids);
  }

  /// 结果写回失败（SSE 断连）→ 把抽干的批次放回热信箱，避免「已读但未投递」丢失。
  /// 冷层从未标记已读，故无需回滚冷层；[Mailbox.deliver] 按 id 去重，重连安全。
  void redeliver(String memberId, List<TeamMessage> batch) {
    if (batch.isEmpty) return;
    final node = _members[memberId];
    if (node == null) return;
    for (final message in batch) {
      node.inbox.deliver(message);
    }
  }

  /// 分页读邮件（冷层 + 可选 mark read）；默认只读未读。
  Future<BusMessagePage> readMessages(
    String memberId, {
    String? afterId,
    int limit = 20,
    bool unreadOnly = true,
    bool markRead = false,
  }) async {
    final store = _messageStore;
    if (store == null) {
      final node = _members[memberId];
      final hot = node?.inbox.peekAll() ?? const <TeamMessage>[];
      return BusMessagePage(
        messages: hot,
        hasMore: false,
        totalUnread: hot.length,
      );
    }
    final page = await store.readPage(
      memberId,
      afterId: afterId,
      limit: limit,
      unreadOnly: unreadOnly,
      markRead: markRead,
    );
    if (markRead && page.messages.isNotEmpty) {
      _members[memberId]?.inbox.removeByIds(
        page.messages.map((m) => m.id).toSet(),
      );
    }
    return page;
  }

  /// 打开 session：冷层未读 → 热层信箱（dedupe）。
  Future<void> rehydrateUnread() async {
    final store = _messageStore;
    if (store == null) return;
    for (final memberId in _members.keys) {
      final unread = await store.loadUnread(memberId);
      final node = _members[memberId];
      if (unread.isNotEmpty) node?.hasUnreportedWork = true;
      for (final message in unread) {
        node?.inbox.deliver(message);
      }
      if (node != null) _syncDeclaredInboxActivity(node);
    }
  }

  Future<int> unreadCountFor(String memberId) async {
    final store = _messageStore;
    if (store != null) {
      return store.unreadCount(memberId);
    }
    return _members[memberId]?.inbox.unreadCount ?? 0;
  }

  int _hotUnreadCount(AgentNode node) => node.inbox.unreadCount;

  void _deliverToInbox(String memberId, TeamMessage message) {
    final node = _members[memberId];
    if (node == null) return;
    node.hasUnreportedWork = true;
    node.inbox.deliver(message);
    _syncDeclaredInboxActivity(node);
    final store = _messageStore;
    if (store == null) return;
    // fire-and-forget 持久化：吞掉 IO 失败为日志，避免变成未捕获的异步错误。
    unawaited(
      store.append(memberId, message).catchError((Object e) {
        appLogger.w(
          '[team-bus] cold-store append failed member=$memberId '
          'msg=${message.id}: $e',
        );
      }),
    );
  }

  /// declared 且无 PTY：有信 → [MemberActivity.mailQueued]。
  void _syncDeclaredInboxActivity(AgentNode node) {
    if (node.lifecycle != MemberLifecycle.declared) return;
    node.activity = node.inbox.isEmpty
        ? MemberActivity.none
        : MemberActivity.mailQueued;
  }

  void _deliverToMember(String memberId, TeamMessage message) {
    final node = _members[memberId];
    if (node == null) return;
    _deliverToInbox(memberId, message);
    _wakeMemberForMail(memberId);
  }

  void _wakeMemberForMail(String memberId) {
    final node = _members[memberId];
    if (node == null) return;
    if (node.waitingForMessage) return;
    if (!node.ptyRunning) return;
    if (node.inbox.isEmpty) return;
    node.activity = MemberActivity.active;
    _launcher.wake(memberId, doorbellNotice);
  }

  String? _teamLeadMemberId() {
    for (final node in _members.values) {
      if (node.profile.isTeamLead) return node.memberId;
    }
    return null;
  }

  void _notifyLeaderOnMemberIdle(String workerMemberId) {
    final worker = _members[workerMemberId];
    if (worker == null || worker.profile.isTeamLead) return;
    // A worker only reports to the leader when it has unreported work: never
    // when it just booted and went idle, and at most once per dispatched batch.
    if (!worker.hasUnreportedWork) return;
    final leaderId = _teamLeadMemberId();
    if (leaderId == null || leaderId == workerMemberId) return;

    worker.hasUnreportedWork = false;

    final body = IdleNotification.fromWorker(
      memberId: workerMemberId,
      displayName: worker.profile.effectiveDisplayName,
    ).encode();

    _deliverToMember(
      leaderId,
      TeamMessage(
        id: _idGenerator(),
        from: workerMemberId,
        to: leaderId,
        content: body,
      ),
    );
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
        id: _idGenerator(),
        from: userSenderId,
        to: memberId,
        content: trimmed,
      ),
    );
  }

  /// 出站投递；按 lifecycle + activity 分流。
  Future<void> send(TeamMessage message) async {
    if (message.hop >= maxHop) {
      appLogger.w(
        '[team-bus] dropped over-hop message ${message.id} (hop=${message.hop})',
      );
      return;
    }
    final target = _members[message.to];
    if (target == null) {
      appLogger.w(
        '[team-bus] dropped message ${message.id} to unknown member '
        '"${message.to}"',
      );
      return;
    }
    switch (target.lifecycle) {
      case MemberLifecycle.declared:
        target.lifecycle = MemberLifecycle.materializing;
        await _launcher.materialize(target.memberId, message);
        target.lifecycle = MemberLifecycle.running;
        target.activity = MemberActivity.active;
        _deliverToInbox(target.memberId, message);
        _launcher.wake(target.memberId, doorbellNotice);
      case MemberLifecycle.materializing:
      case MemberLifecycle.running:
        _deliverToInbox(target.memberId, message);
        if (target.acceptsImmediateDoorbell) {
          target.activity = MemberActivity.active;
          _launcher.wake(target.memberId, doorbellNotice);
        }
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

    _notifyLeaderOnMemberIdle(memberId);

    node.activity = MemberActivity.turnDoneReady;
    if (node.inbox.isEmpty) {
      return;
    }
    node.activity = MemberActivity.active;
    _launcher.wake(node.memberId, doorbellNotice);
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
            id: _idGenerator(),
            to: node.memberId,
            hop: message.hop + 1,
          ),
        );
      }
      return;
    }

    for (final node in _members.values) {
      if (node.memberId == message.from) continue;
      if (node.lifecycle == MemberLifecycle.declared) {
        continue;
      }
      _deliverToInbox(
        node.memberId,
        message.copyWith(
          id: _idGenerator(),
          to: node.memberId,
          hop: message.hop + 1,
        ),
      );
      if (node.acceptsImmediateDoorbell) {
        node.activity = MemberActivity.active;
        _launcher.wake(node.memberId, doorbellNotice);
      }
    }
  }

  /// 关闭 session：释放每个信箱的 Timer / 挂起 waiter，防泄漏。
  void dispose() {
    for (final node in _members.values) {
      node.inbox.dispose();
    }
  }
}
