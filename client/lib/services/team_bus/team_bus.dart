import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../utils/logger.dart';
import 'agent_node.dart';
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

  /// Stop hook / idle 边：禁止收工，立刻回到 wait_for_message（无限阻塞）。
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
  final Set<String> _waitingForMessage = {};
  final Map<String, DateTime> _lastCoordinationWake = {};
  TeamSessionContext? _sessionContext;

  /// 空信箱 coordination 门铃最短间隔（Stop hook + 终端 watcher 会叠打）。
  static const coordinationWakeCooldown = Duration(seconds: 30);

  void installSessionContext(TeamSessionContext context) {
    _sessionContext = context;
  }

  TeamSessionContext? get sessionContext => _sessionContext;

  static bool ptyRunningForState(MemberState state) => switch (state) {
    MemberState.declared || MemberState.retired || MemberState.dead => false,
    MemberState.materializing ||
    MemberState.busy ||
    MemberState.idle => true,
  };

  void declareMember(AgentNode node) {
    _members[node.memberId] = node;
  }

  AgentNode? memberById(String memberId) => _members[memberId];

  /// PTY 已 spawn（用户 connect 或 mailbox 物化后）。
  void markMemberRunning(String memberId) {
    final node = _members[memberId];
    if (node == null) return;
    if (node.state == MemberState.retired || node.state == MemberState.dead) {
      return;
    }
    node.state = MemberState.busy;
  }

  /// 成员是否正 park 在 MCP `wait_for_message`（UI 用户输入应进 bus 而非 PTY）。
  bool isWaitingForMessage(String memberId) =>
      _waitingForMessage.contains(memberId);

  /// 全队 roster（MCP `list_teammates`）；leader 在前，其余按 member id 排序。
  TeamRosterSnapshot rosterSnapshot() {
    final snapshots = _members.values
        .map(
          (node) => TeammateSnapshot(
            profile: node.profile,
            state: node.state,
            unreadCount: _hotUnreadCount(node),
            waitingForMessage: _waitingForMessage.contains(node.memberId),
            ptyRunning: ptyRunningForState(node.state),
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
    _waitingForMessage.add(memberId);
    _lastCoordinationWake.remove(memberId);
    try {
      final batch = await node.inbox.waitBatch(timeout: timeout);
      if (batch.isNotEmpty) {
        await _messageStore?.markRead(memberId, batch.map((m) => m.id));
      }
      return batch;
    } finally {
      _waitingForMessage.remove(memberId);
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
    _members[memberId]?.inbox.deliver(message);
    final store = _messageStore;
    if (store == null) return;
    unawaited(store.append(memberId, message));
  }

  /// UI 用户在成员 wait 期间提交的一行 → 信箱（`from: user`）。
  void deliverUserCommand(String memberId, String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;
    final node = _members[memberId];
    if (node == null ||
        node.state == MemberState.retired ||
        node.state == MemberState.dead) {
      return;
    }
    _deliverToInbox(
      memberId,
      TeamMessage(
        id: _idGenerator(),
        from: userSenderId,
        to: memberId,
        content: trimmed,
      ),
    );
    if (_waitingForMessage.contains(memberId)) {
      return; // in-loop: mailbox debounce 唤醒 waiter
    }
    if (node.state == MemberState.idle) {
      node.state = MemberState.busy;
      _launcher.wake(memberId, doorbellNotice);
    }
  }

  /// 出站（来自成员的 send_message）。按目标状态分流投递。
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
    switch (target.state) {
      case MemberState.declared:
        target.state = MemberState.materializing;
        await _launcher.materialize(target.memberId, message);
        target.state = MemberState.busy;
        _deliverToInbox(target.memberId, message);
        _launcher.wake(target.memberId, doorbellNotice);
      case MemberState.materializing:
      case MemberState.busy:
        _deliverToInbox(target.memberId, message);
      case MemberState.idle:
        _deliverToInbox(target.memberId, message);
        target.state = MemberState.busy;
        _launcher.wake(target.memberId, doorbellNotice);
      case MemberState.retired:
      case MemberState.dead:
        appLogger.w(
          '[team-bus] dropped message ${message.id} to ${target.memberId} '
          '(state=${target.state.name})',
        );
    }
  }

  /// idle 边（Stop hook / 终端 watcher）：不收工，门铃拉回 wait_for_message 循环。
  void onMemberIdle(String memberId) {
    final node = _members[memberId];
    if (node == null) return;
    if (node.state == MemberState.retired || node.state == MemberState.dead) {
      return;
    }
    // 尚未 spawn PTY（仅 declared / 物化中）— 不能 doorbell。
    if (node.state == MemberState.declared ||
        node.state == MemberState.materializing) {
      return;
    }
    // 已在 MCP wait_for_message：信箱 debounce 会唤醒，勿再 writeln 污染 PTY 输入框。
    if (_waitingForMessage.contains(memberId)) {
      return;
    }
    node.state = MemberState.busy;
    if (node.inbox.isEmpty) {
      final last = _lastCoordinationWake[memberId];
      if (last != null &&
          DateTime.now().difference(last) < coordinationWakeCooldown) {
        return;
      }
      _lastCoordinationWake[memberId] = DateTime.now();
      _launcher.wake(node.memberId, coordinationLoopNotice);
      return;
    }
    _launcher.wake(node.memberId, doorbellNotice);
  }

  /// worker 自我退出循环。
  void leave(String memberId) {
    final node = _members[memberId];
    if (node == null) return;
    node.state = MemberState.retired;
  }

  /// 向除发送方外的所有成员投递；[materializeDeclared] 为 true 时对
  /// `declared` 成员惰性物化（`send_message(to="*")`），否则跳过（如 stand-down）。
  Future<void> broadcast(
    TeamMessage message, {
    bool materializeDeclared = false,
  }) async {
    if (materializeDeclared) {
      for (final node in _members.values) {
        if (node.memberId == message.from) continue;
        if (node.state == MemberState.retired || node.state == MemberState.dead) {
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
      if (node.state == MemberState.declared ||
          node.state == MemberState.retired ||
          node.state == MemberState.dead) {
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
      if (node.state == MemberState.idle) {
        node.state = MemberState.busy;
        _launcher.wake(node.memberId, doorbellNotice);
      }
    }
  }

  /// 会话 tab 关闭：所有未 retired/dead 的成员置为 dead。
  void abortAll() {
    for (final node in _members.values) {
      if (node.state != MemberState.retired &&
          node.state != MemberState.dead) {
        node.state = MemberState.dead;
      }
    }
  }

  /// leader 完成：置 retired + 广播 stand-down。
  Future<void> finishTask(String memberId, String result) async {
    final node = _members[memberId];
    if (node == null) return;
    node.state = MemberState.retired;
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
