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

  /// PTY 已运行、跳出 wait 循环且信箱空：拉回 wait_for_message。
  static const String coordinationLoopNotice =
      '[teammate-bus] Session policy: do not stand down. Call wait_for_message '
      'now (no timeout — blocks until a teammate or user message). (From the '
      'bus, not raw stdin.)';

  /// [TeamMessage.from] when the human operator submits while the member waits.
  static const String userSenderId = 'user';

  final MemberLauncher _launcher;
  final String Function() _idGenerator;
  final BusMessageStore? _messageStore;
  final int maxHop;
  final Map<String, AgentNode> _members = {};
  final Map<String, DateTime> _lastCoordinationWake = {};
  final Map<String, DateTime> _lastIdleLeaderNotify = {};
  TeamSessionContext? _sessionContext;

  /// 空信箱 coordination 门铃最短间隔（Stop hook + 终端 watcher 会叠打）。
  static const coordinationWakeCooldown = Duration(seconds: 30);

  /// worker idle → leader mailbox：Stop + watcher 叠打防抖。
  static const idleLeaderNotifyCooldown = Duration(seconds: 10);

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
    if (node.lifecycle == MemberLifecycle.retired ||
        node.lifecycle == MemberLifecycle.dead) {
      return;
    }
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
  Future<List<TeamMessage>> receive(
    String memberId, {
    Duration? timeout,
  }) async {
    final node = _members[memberId];
    if (node == null) {
      return Future.value(const <TeamMessage>[]);
    }
    if (node.lifecycle == MemberLifecycle.running) {
      node.activity = MemberActivity.turnDoneBusWait;
    }
    _lastCoordinationWake.remove(memberId);
    try {
      final batch = await node.inbox.waitBatch(timeout: timeout);
      if (batch.isNotEmpty) {
        await _messageStore?.markRead(memberId, batch.map((m) => m.id));
      }
      return batch;
    } finally {
      if (node.lifecycle == MemberLifecycle.running &&
          node.activity == MemberActivity.turnDoneBusWait) {
        node.activity = MemberActivity.active;
      }
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
      for (final message in unread) {
        _members[memberId]?.inbox.deliver(message);
      }
      final node = _members[memberId];
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
    node.inbox.deliver(message);
    _syncDeclaredInboxActivity(node);
    final store = _messageStore;
    if (store == null) return;
    unawaited(store.append(memberId, message));
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
    final leaderId = _teamLeadMemberId();
    if (leaderId == null || leaderId == workerMemberId) return;

    final last = _lastIdleLeaderNotify[workerMemberId];
    if (last != null &&
        DateTime.now().difference(last) < idleLeaderNotifyCooldown) {
      return;
    }
    _lastIdleLeaderNotify[workerMemberId] = DateTime.now();

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
    if (node == null ||
        node.lifecycle == MemberLifecycle.retired ||
        node.lifecycle == MemberLifecycle.dead) {
      return;
    }
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
      case MemberLifecycle.retired:
      case MemberLifecycle.dead:
        appLogger.w(
          '[team-bus] dropped message ${message.id} to ${target.memberId} '
          '(lifecycle=${target.lifecycle.name})',
        );
    }
  }

  /// idle 边：turn 结束 → [MemberActivity.turnDoneReady]（或 doorbell → active）。
  void onMemberIdle(String memberId) {
    final node = _members[memberId];
    if (node == null) return;
    if (node.lifecycle == MemberLifecycle.retired ||
        node.lifecycle == MemberLifecycle.dead) {
      return;
    }
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
      final last = _lastCoordinationWake[memberId];
      if (last != null &&
          DateTime.now().difference(last) < coordinationWakeCooldown) {
        return;
      }
      _lastCoordinationWake[memberId] = DateTime.now();
      node.activity = MemberActivity.active;
      _launcher.wake(node.memberId, coordinationLoopNotice);
      return;
    }
    node.activity = MemberActivity.active;
    _launcher.wake(node.memberId, doorbellNotice);
  }

  /// → [MemberLifecycle.retired]（worker 主动收工）。
  void leave(String memberId) {
    final node = _members[memberId];
    if (node == null) return;
    node.lifecycle = MemberLifecycle.retired;
    node.activity = MemberActivity.none;
  }

  Future<void> broadcast(
    TeamMessage message, {
    bool materializeDeclared = false,
  }) async {
    if (materializeDeclared) {
      for (final node in _members.values) {
        if (node.memberId == message.from) continue;
        if (node.lifecycle == MemberLifecycle.retired ||
            node.lifecycle == MemberLifecycle.dead) {
          continue;
        }
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
      if (node.lifecycle == MemberLifecycle.declared ||
          node.lifecycle == MemberLifecycle.retired ||
          node.lifecycle == MemberLifecycle.dead) {
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

  /// 非 retired/dead → [MemberLifecycle.dead]（关 session tab）。
  void abortAll() {
    for (final node in _members.values) {
      if (node.lifecycle != MemberLifecycle.retired &&
          node.lifecycle != MemberLifecycle.dead) {
        node.lifecycle = MemberLifecycle.dead;
        node.activity = MemberActivity.none;
      }
    }
  }

  /// leader → [MemberLifecycle.retired] + 广播 stand-down。
  Future<void> finishTask(String memberId, String result) async {
    final node = _members[memberId];
    if (node == null) return;
    node.lifecycle = MemberLifecycle.retired;
    node.activity = MemberActivity.none;
    await broadcast(
      TeamMessage(
        id: _idGenerator(),
        from: memberId,
        to: '*',
        content: 'TASK COMPLETE — stand down. Result: $result',
      ),
    );
  }
}
