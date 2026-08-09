# TeamBus 门铃投递自愈化 + 诚实工作状态 — 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 消除 mixed 团队中成员因门铃投递失败而永久 stuck `active` + 未读 + 不响铃的整类问题——门铃投递改为等 TUI boot 就绪、失败永不封死、看门狗持续驱动直到消费或 park。

**Architecture:** 三个协调改动。(1) `MaterializeCompleted` 不再乐观置 `active`,改为 `turnDoneReady`,`active` 只由真实回合开始(`TurnStarted`)置位,门铃投递成功确认(`noteMailDeliverySubmitted`)触发 `TurnStarted`。(2) 门铃投递义务 = `running && !parked && 邮箱有未读 && 未确认`,`deliveryPhase.failed` 不再是终态(`MailDeliveryStarted` 遇到 failed 自动重置预算)。(3) 门铃注入等 `activityTracker.isBootFrameReady` 再粘,未就绪走 PTY 自动化重试队列推迟(不耗 attempts)。

**Tech Stack:** Dart / Flutter,`flutter_bloc`。改动集中在 `client/lib/services/team_bus/`、`client/lib/cubits/chat/`、`client/lib/services/terminal/`。

## Global Constraints

- 遵循仓库 `AGENTS.md`/`docs/CODE_QUALITY.md`:层位清晰、状态只走 `flutter_bloc`、日志用 `appLogger`(无 print)、提交前 `flutter analyze` + `flutter test --exclude-tags integration`。
- 不改动消费侧:`receiveWork`/`wait_for_message`/消息路由。
- 不改 `ensureMemberInputReady`(正常首条输入路径,已等 boot)。
- 复用现有 `PtyAutomationRetryQueue` 与 `doorbellRetryMs`(5s)节流,不新增重试参数。
- 单测沿用现有 helper:`FakeMemberLauncher`(`test/services/team_bus/support/fake_member_launcher.dart`)、`AgentNode.test`(`lib/services/team_bus/agent_node.dart`)。

---

### Task 1: PresenceReducer — 诚实置位(MaterializeCompleted → turnDoneReady)

**Files:**
- Modify: `client/lib/services/team_bus/state/presence_reducer.dart:61-68`
- Test: `client/test/services/team_bus/state/presence_reducer_test.dart:70-79`

**Interfaces:**
- Consumes: `PresenceReducer.reduce(Presence, BusEvent, PresenceContext)` 现有签名。
- Produces: `MaterializeCompleted` 跃迁产出 `Presence(lifecycle: running, activity: turnDoneReady)` + `[DoorbellEffect(memberId)]`。后续任务依赖:`turnDoneReady` 成员落入看门狗 atPrompt 覆盖范围;`MailDeliverySubmitted` 后 `noteMailDeliverySubmitted` 触发 `TurnStarted` → `active`(已有逻辑,不新增)。

- [ ] **Step 1: 改现有测试(红)**

在 `client/test/services/team_bus/state/presence_reducer_test.dart` 找到 `test('MaterializeCompleted → running + active + Doorbell', ...)`,把断言 `activity` 从 `MemberActivity.active` 改为 `MemberActivity.turnDoneReady`,并改测试名为 `'MaterializeCompleted → running + turnDoneReady + Doorbell (honest: active only on real turn)'`:

```dart
test('MaterializeCompleted → running + turnDoneReady + Doorbell (honest: active only on real turn)', () {
  const presence = Presence(MemberLifecycle.materializing, MemberActivity.none);
  final result = PresenceReducer.reduce(
    presence,
    const MaterializeCompleted(),
    const PresenceContext(memberId: 'w', hasUnread: true),
  );
  expect(result.presence.lifecycle, MemberLifecycle.running);
  expect(result.presence.activity, MemberActivity.turnDoneReady);
  expect(result.effects, [const DoorbellEffect('w')]);
});
```

- [ ] **Step 2: 运行确认红**

Run: `cd client && flutter test test/services/team_bus/state/presence_reducer_test.dart`
Expected: FAIL — 断言 `turnDoneReady` 但实际 `active`。

- [ ] **Step 3: 改实现**

`client/lib/services/team_bus/state/presence_reducer.dart` 中 `MaterializeCompleted` 分支:

```dart
case MaterializeCompleted():
  // 诚实状态:active 只等于真实回合进行中。门铃投递成功确认后由
  // noteMailDeliverySubmitted → TurnStarted 置 active;投递失败则停在
  // turnDoneReady(at-prompt),看门狗可持续重试门铃。
  return PresenceTransition(
    s.copyWith(
      lifecycle: MemberLifecycle.running,
      activity: MemberActivity.turnDoneReady,
    ),
    [DoorbellEffect(ctx.memberId)],
  );
```

- [ ] **Step 4: 运行确认绿**

Run: `cd client && flutter test test/services/team_bus/state/presence_reducer_test.dart`
Expected: PASS。

- [ ] **Step 5: 跑相关回归**

Run: `cd client && flutter test test/services/team_bus/`
Expected: 若有断言 `MaterializeCompleted → active` 的测试失败,按 Step 1 同样改为 `turnDoneReady`(见 `team_bus_lifecycle_test.dart` 等,逐处改断言与命名)。

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/team_bus/state/presence_reducer.dart client/test/services/team_bus/
git commit -m "fix(team-bus): MaterializeCompleted no longer optimistic-active — turnDoneReady until doorbell lands"
```

---

### Task 2: MailboxDeliveryReducer — 次数去双计 + failed 自动重臂

**Files:**
- Modify: `client/lib/services/team_bus/mailbox_delivery_reducer.dart`
- Test: `client/test/services/team_bus/mailbox_delivery_reducer_test.dart`

**Interfaces:**
- Consumes: `MailboxDeliveryReducer.reduce(MailboxDeliverySnapshot, MailboxDeliveryEvent, {hasUnread, maxAttempts})` 现有签名;事件 `MailDeliveryStarted`/`MailDeliveryFailed`。
- Produces: 语义变化——`attempts` 只随 `MailDeliveryStarted` 递增(每个投递尝试 1 次,不再 Started+Failed 双计);`MailDeliveryStarted` 在 `phase == failed` 时把 attempts 重置为 0 重新开一轮(失败可重臂);`MailDeliveryFailed` 只回报结果不叠次数。Task 3 依赖:看门狗无需显式 rearm,重试注入时 `MailDeliveryStarted` 自动重置。

- [ ] **Step 1: 写失败测试**

在 `client/test/services/team_bus/mailbox_delivery_reducer_test.dart` 的 `group('MailboxDeliveryReducer')` 内新增:

```dart
test('MailDeliveryFailed does not double-count attempts', () {
  const state = MailboxDeliverySnapshot(
    phase: MailboxDeliveryPhase.inFlight,
    attempts: 3,
  );
  final next = MailboxDeliveryReducer.reduce(
    state,
    const MailDeliveryFailed(MailboxDeliveryError.pasteNotFound),
    hasUnread: true,
    maxAttempts: 6,
  );
  expect(next.attempts, 3);          // 不再 +1
  expect(next.phase, MailboxDeliveryPhase.pending);
});

test('MailDeliveryStarted on failed phase re-arms a fresh budget', () {
  const state = MailboxDeliverySnapshot(
    phase: MailboxDeliveryPhase.failed,
    attempts: 6,
  );
  final next = MailboxDeliveryReducer.reduce(
    state,
    const MailDeliveryStarted(),
    hasUnread: true,
    maxAttempts: 6,
  );
  expect(next.phase, MailboxDeliveryPhase.inFlight);
  expect(next.attempts, 1);          // 重置后第一轮
});
```

- [ ] **Step 2: 运行确认红**

Run: `cd client && flutter test test/services/team_bus/mailbox_delivery_reducer_test.dart`
Expected: FAIL — 双计让 attempts=4;failed 态 `MailDeliveryStarted` 仍保持 failed。

- [ ] **Step 3: 改实现**

`client/lib/services/team_bus/mailbox_delivery_reducer.dart` 的两个分支:

```dart
case MailDeliveryStarted():
  final attempts = (state.phase == MailboxDeliveryPhase.failed)
      ? 0          // failed 非终态:重臂一轮新预算
      : state.attempts;
  final nextAttempts = attempts + 1;
  if (nextAttempts > maxAttempts) {
    return MailboxDeliverySnapshot(
      phase: MailboxDeliveryPhase.failed,
      attempts: nextAttempts,
      lastError: state.lastError ?? MailboxDeliveryError.crStuck,
    );
  }
  return state.copyWith(
    phase: MailboxDeliveryPhase.inFlight,
    attempts: nextAttempts,
  );

case MailDeliveryFailed(:final error):
  // 只回报结果,不叠加次数(次数由 Started 计),避免一次尝试双计快速耗竭预算。
  if (state.attempts >= maxAttempts) {
    return MailboxDeliverySnapshot(
      phase: MailboxDeliveryPhase.failed,
      attempts: state.attempts,
      lastError: error,
    );
  }
  return MailboxDeliverySnapshot(
    phase: MailboxDeliveryPhase.pending,
    attempts: state.attempts,
    lastError: error,
  );
```

- [ ] **Step 4: 更新旧断言**

`MailDeliveryFailed at budget → failed` 旧测试断言 `attempts: 6`(从 attempts=5 双计)。改为只断言 `phase == failed`,`attempts` 保持 5:

```dart
expect(next.phase, MailboxDeliveryPhase.failed);
expect(next.attempts, 5);   // Failed 不叠加
```

- [ ] **Step 5: 运行确认绿 + 回归**

Run: `cd client && flutter test test/services/team_bus/mailbox_delivery_reducer_test.dart`
Expected: PASS。

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/team_bus/mailbox_delivery_reducer.dart client/test/services/team_bus/mailbox_delivery_reducer_test.dart
git commit -m "fix(team-bus): delivery attempts de-double-count; failed phase re-arms on next start"
```

---

### Task 3: TeamBus — failed 非终态 + 看门狗覆盖 running+未 park+欠门铃

**Files:**
- Modify: `client/lib/services/team_bus/team_bus.dart`(`pendingDoorbellNoticeFor` :136-148、`_ringDoorbell` :875-890、`reengageIdleWorkers` :1028-1068、`shouldDeferPtyIdleEnd` :255-261)
- Test: `client/test/services/team_bus/team_bus_mailbox_delivery_test.dart`、`client/test/services/team_bus/team_bus_idle_doorbell_test.dart`

**Interfaces:**
- Consumes: Task 2 的 `MailDeliveryStarted` 自动重臂;`pendingDoorbellNoticeFor` 成为"义务是否成立"的唯一判据。
- Produces: `pendingDoorbellNoticeFor(memberId)` 语义变为 `running && !parked && (未读 || 有可认领任务) → 返回 notice`,`failed` 不再返回 null;`reengageIdleWorkers` 对任何 `running && !parked && pendingDoorbellNoticeFor != null` 的成员重试门铃。

- [ ] **Step 1: 写失败测试(义务判定 + 看门狗重试)**

在 `client/test/services/team_bus/team_bus_mailbox_delivery_test.dart` 里,把 `markMailDeliveryFailed stops pendingDoorbellNoticeFor` 与 `reengageIdleWorkers skips failed delivery` 两个测试改为断言新语义(红→绿):

```dart
test('failed delivery still owes doorbell while unread', () {
  final launcher = FakeMemberLauncher();
  final bus = TeamBus(launcher: launcher);
  final node = AgentNode.test(
    memberId: 'worker',
    lifecycle: MemberLifecycle.running,
    activity: MemberActivity.turnDoneReady,
  )..doorbelled = true;
  bus.declareMember(node);
  node.inbox.deliver(
    TeamMessage(id: 'm1', from: 'lead', to: 'worker', content: 'ping'),
  );
  bus.markMailDeliveryFailed('worker', error: MailboxDeliveryError.crStuck);

  expect(node.deliveryPhase, MailboxDeliveryPhase.failed);
  expect(bus.pendingDoorbellNoticeFor('worker'), TeamBus.doorbellNotice);
});

test('reengageIdleWorkers retries failed delivery (never terminal)', () {
  final launcher = FakeMemberLauncher();
  final bus = TeamBus(launcher: launcher);
  final node = AgentNode.test(
    memberId: 'worker',
    lifecycle: MemberLifecycle.running,
    activity: MemberActivity.turnDoneReady,
  );
  bus.declareMember(node);
  node.inbox.deliver(
    TeamMessage(id: 'm1', from: 'lead', to: 'worker', content: 'ping'),
  );
  bus.markMailDeliveryFailed('worker', error: MailboxDeliveryError.crStuck);

  bus.reengageIdleWorkers();

  // 已响过门铃 → retryDelivery,而非直接 wake
  expect(launcher.retried, isNotEmpty);
  expect(launcher.retried.first.memberId, 'worker');
});

test('parked member with unread owes no doorbell', () {
  final launcher = FakeMemberLauncher();
  final bus = TeamBus(launcher: launcher);
  bus.declareMember(
    AgentNode.test(
      memberId: 'worker',
      lifecycle: MemberLifecycle.running,
      activity: MemberActivity.turnDoneBusWait,
    ),
  );
  bus.memberById('worker')!.inbox.deliver(
    TeamMessage(id: 'm1', from: 'lead', to: 'worker', content: 'ping'),
  );
  expect(bus.pendingDoorbellNoticeFor('worker'), isNull);
});
```

- [ ] **Step 2: 运行确认红**

Run: `cd client && flutter test test/services/team_bus/team_bus_mailbox_delivery_test.dart`
Expected: FAIL — `pendingDoorbellNoticeFor` 仍因 failed 返回 null、看门狗跳过。

- [ ] **Step 3: 改实现**

`client/lib/services/team_bus/team_bus.dart`:

```dart
String? pendingDoorbellNoticeFor(String memberId) {
  final node = _members[memberId];
  if (node == null || node.lifecycle != MemberLifecycle.running) return null;
  if (node.waitingForMessage) return null; // parked:waiter 直收,不欠门铃
  if (!node.inbox.isEmpty) {
    return doorbellNotice; // failed 非终态:未读即欠
  }
  final queue = _taskQueue;
  if (queue != null && _hasEligiblePendingTask(node, queue)) {
    return taskDoorbellNotice;
  }
  return null;
}

void _ringDoorbell(AgentNode node, String notice) {
  // 不再因 deliveryPhase.failed 短路——投递义务由 running+未读+未 park 决定。
  if (notice == taskDoorbellNotice &&
      node.lifecycle == MemberLifecycle.running &&
      !node.waitingForMessage) {
    _apply(node, const TurnStarted());
  }
  node.doorbelled = true;
  node.doorbelledAt = _env.clock();
  _env.events.emit(MemberDoorbelled(node.memberId));
  _launcher.wake(node.memberId, notice);
}

void reengageIdleWorkers() {
  final queue = _taskQueue;
  for (final node in _members.values) {
    if (node.profile.isTeamLead) continue;
    if (node.lifecycle != MemberLifecycle.running) continue;
    if (node.waitingForMessage) continue; // parked 直收,不重敲门铃
    final notice = pendingDoorbellNoticeFor(node.memberId);
    if (notice == null) continue; // 不欠门铃
    if (_recentlyDoorbelled(node)) continue;
    if (node.doorbelled || node.doorbelledAt != null) {
      appLogger.d(
        '[team-bus] reengage retry-delivery member=${node.memberId}',
      );
      _launcher.retryDelivery(node.memberId, notice);
    } else {
      appLogger.d(
        '[team-bus] reengage wake member=${node.memberId} '
        'unread=${!node.inbox.isEmpty} '
        'queuedTask=${queue != null && _hasEligiblePendingTask(node, queue)}',
      );
      _ringDoorbell(node, notice);
    }
    node.doorbelledAt = _env.clock();
  }
}
```

`shouldDeferPtyIdleEnd`(:255-261)移除 failed 短路(门铃仍欠着,PTY 安静不该提前结束回合):

```dart
bool shouldDeferPtyIdleEnd(String memberId) {
  final node = _members[memberId];
  if (node == null) return false;
  if (node.deliveryPhase == MailboxDeliveryPhase.inFlight) return false;
  return node.doorbelled && !node.inbox.isEmpty;
}
```

同步更新 `team_bus_mailbox_delivery_test.dart` 的 `shouldDeferPtyIdleEnd is false when delivery failed` 测试为断言 `isTrue`(failed 时门铃仍欠着,应 defer)。

- [ ] **Step 4: 运行确认绿 + 回归**

Run: `cd client && flutter test test/services/team_bus/`
Expected: PASS。若 `team_bus_idle_doorbell_test.dart` 有断言旧语义失败的用例,按其意图改写(看门狗现在覆盖更广:不再漏掉 failed/active 成员)。

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/team_bus/team_bus.dart client/test/services/team_bus/
git commit -m "fix(team-bus): doorbell owed while unread — failed phase not terminal; watchdog re-engages running non-parked members"
```

---

### Task 4: 门铃注入等 TUI boot 就绪(推迟,不耗 attempts)

**Files:**
- Modify: `client/lib/services/terminal/pty_automation_retry_queue.dart`(新增 `defer`)、`client/lib/services/terminal/member_pty_inject_service.dart`(新增 `deferForBoot`)、`client/lib/cubits/chat/tab_member_pty_delivery.dart`(boot 门控)
- Test: `client/test/services/terminal/member_pty_inject_service_test.dart`、`client/test/cubits/chat_cubit_team_bus_test.dart`(若需要)

**Interfaces:**
- Consumes: `shell.activityTracker.isBootFrameReady`(`TerminalSession.activityTracker`);现有 `PtyAutomationRetryQueue.schedule`/`due`/`isPending`/`clear`。
- Produces:
  - `PtyAutomationRetryQueue.defer({required String key, required String sessionId, required String memberId, required String text}) → bool` — 重新定时且**不**递增 attempt(与失败重试 `schedule` 区分)。
  - `MemberPtyInjectService.deferForBoot(String sessionId, String memberId, String text)` — 调 `_retryQueue.defer`。
  - `TabMemberPtyDelivery` 在初始注入与重试 tick 前检查 boot 就绪,未就绪则 `deferForBoot` 后 return(不粘贴)。

- [ ] **Step 1: 写失败测试(retry queue defer 不耗 attempts)**

在 `client/test/services/terminal/member_pty_inject_service_test.dart` 内新增:

```dart
test('deferForBoot re-times without consuming retry attempts', () {
  final service = MemberPtyInjectService(
    retryQueue: PtyAutomationRetryQueue(
      retryIntervalMs: 0,
      maxAttempts: 1,
    ),
  );
  service.deferForBoot('s', 'w', TeamBus.doorbellNotice);
  service.deferForBoot('s', 'w', TeamBus.doorbellNotice);
  // 若 defer 像 schedule 一样递增 attempt,第二次会因 attempt(2)>max(1) 被
  // clear → hasPendingRetry 变 false。defer 不耗预算 → 两次后仍 pending。
  expect(service.hasPendingRetry('s', 'w'), isTrue);
});
```

(若 `MemberPtyInjectService` 构造要求注入 retryQueue,则用 `MemberPtyInjectService(retryQueue: PtyAutomationRetryQueue(retryIntervalMs: 0, maxAttempts: 1))` 并在两次 `deferForBoot` 后断言 `hasPendingRetry` 仍为 true——旧 `schedule` 第二次会因 attempt>max 而 clear。)

- [ ] **Step 2: 运行确认红**

Run: `cd client && flutter test test/services/terminal/member_pty_inject_service_test.dart`
Expected: FAIL — `deferForBoot` 不存在。

- [ ] **Step 3: 改实现(三处)**

`client/lib/services/terminal/pty_automation_retry_queue.dart` 新增:

```dart
/// 门铃 boot 推迟:重新定时且不消耗 attempts(与失败重试 [schedule] 区分)。
bool defer({
  required String key,
  required String sessionId,
  required String memberId,
  required String text,
}) {
  final prev = _pending[key];
  final attempt = prev?.attempt ?? 0;
  if (attempt > maxAttempts) return false;
  _pending[key] = _PendingRetry(
    sessionId: sessionId,
    memberId: memberId,
    text: text,
    nextRetryAtMs: _nowMs() + retryIntervalMs,
    attempt: attempt,
  );
  return true;
}
```

`client/lib/services/terminal/member_pty_inject_service.dart` 新增:

```dart
/// 门铃在 TUI boot 未就绪时推迟:排入重试队列,就绪后由重试 tick 落地。
void deferForBoot(String sessionId, String memberId, String text) {
  _retryQueue.defer(
    key: PtyAutomationSessionLock.key(sessionId, memberId),
    sessionId: sessionId,
    memberId: memberId,
    text: text,
  );
}
```

`client/lib/cubits/chat/tab_member_pty_delivery.dart`:`deliverMemberStdin` 在 `_deliverFullScreen` 之前、`retryMemberDelivery` 与 `retryAutomationTick` 在 `_ptyInject.retry` 之前,加 boot 门控:

```dart
/// 门铃投递的 boot 门控:全屏 TUI 未就绪时推迟到重试 tick,避免盲粘启动屏。
/// 返回 true 表示已推迟(调用方应 return)。
bool _deferMailDoorbellIfBooting(
  String sessionId,
  String memberId,
  TerminalSession shell,
  String text,
) {
  if (!_isMailDoorbellText(text)) return false;
  if (shell.activityTracker.isBootFrameReady) return false;
  appLogger.d(
    '[session-runtime] doorbell deferred (boot) member=$memberId session=$sessionId',
  );
  _ptyInject.deferForBoot(sessionId, memberId, text);
  return true;
}
```

在 `deliverMemberStdin` 内、`usesFullScreen` 为真时:

```dart
if (usesFullScreen &&
    _deferMailDoorbellIfBooting(sessionId, memberId, shell, trimmed)) {
  return;
}
```

在 `retryMemberDelivery` 与 `retryAutomationTick` 内、调用 `_ptyInject.retry` 前,同样插入:

```dart
if (_deferMailDoorbellIfBooting(tick.sessionId, tick.memberId, shell, tick.text)) {
  return;
}
```

- [ ] **Step 4: 运行确认绿 + 回归**

Run: `cd client && flutter test test/services/terminal/ test/services/cubits/chat_cubit_team_bus_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/terminal/pty_automation_retry_queue.dart client/lib/services/terminal/member_pty_inject_service.dart client/lib/cubits/chat/tab_member_pty_delivery.dart client/test/services/terminal/
git commit -m "fix(team-bus): doorbell inject defers until TUI boot frame ready (no blind paste into boot screen)"
```

---

### Task 5: 集成测试 — 广播 + 惰性连接后全员消费并 park

**Files:**
- Create: `client/test/integration/mixed_team_bus_doorbell_self_healing_integration_test.dart`
- Test: 同一文件

**Interfaces:**
- Consumes: Task 1-4 的产物。沿用 `test/integration/mixed_team_bus_ping_pong_integration_test.dart` 的模式(`TeamBus` + `FakeMemberLauncher` + `InMemoryBusMessageLog`),不拉真实 PTY。
- Produces: 回归证明——5 个成员(1 lead + 4 worker)在 lead 广播后,所有 worker 最终消费消息并进入 `wait_for_message`(park),无人 stuck `active` 且未读>0。

- [ ] **Step 1: 写集成测试**

`@Tags(['integration', 'cross-platform'])`,setUp 建 1 个 lead(running/active)与 4 个 worker(全部 `declared`,模拟惰性连接):

```dart
test('broadcast to lazily-declared workers: all consume and park, none stuck active', () async {
  // 1. lead 广播
  await bus.broadcast(
    TeamMessage(
      id: 'greet',
      from: 'team-lead',
      to: '*',
      content: 'hello team',
    ),
    materializeDeclared: true,
  );
  // 物化漏斗把 4 个 worker 拉起 → running + turnDoneReady,邮箱各 1 条未读。

  // 2. 走几轮看门狗(真实环境由 1s idle watch 驱动;这里受 5s doorbellRetryMs
  //    节流约束,可能不触发重投,但核心不变量与本步骤无关)。门铃驱动的健壮性
  //    由 Task 3 单测覆盖;这里验证状态机端到端。
  for (var i = 0; i < 3; i++) {
    bus.reengageIdleWorkers();
  }

  // 3. 每个 worker:消费未读 → 进 wait_for_message(receiveWork park)。
  for (final w in ['architect', 'builder-0', 'builder-1', 'reviewer']) {
    final node = bus.memberById(w)!;
    expect(node.inbox.isEmpty, isFalse, reason: '$w should have unread before consuming');
    final batch = await bus.receiveWork(w);
    expect(batch, isA<MessageWork>(), reason: '$w consumes the greeting');
    expect(node.inbox.isEmpty, isTrue, reason: '$w consumed all mail');
    // 已 park:后续不再欠门铃
    expect(bus.pendingDoorbellNoticeFor(w), isNull);
  }

  // 4. 没有任何 worker 被假标为 in-turn(诚实状态:turnDoneReady/已 park)。
  for (final w in ['architect', 'builder-0', 'builder-1', 'reviewer']) {
    expect(bus.isMemberInTurn(w), isFalse, reason: '$w not falsely working');
  }
});
```

(用 `fakeMemberLauncher` 的 `woken`/`retried` 断言门铃被持续驱动;若断言与实现细节冲突,以"全员消费 + park + 无 stuck active"为核心不变量。)

- [ ] **Step 2: 运行确认通过**

Run: `cd client && flutter test --tags integration test/integration/mixed_team_bus_doorbell_self_healing_integration_test.dart`
Expected: PASS。

- [ ] **Step 3: 全量回归**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`
Expected: 无 analyze 错误;单测全绿。

- [ ] **Step 4: Commit**

```bash
git add client/test/integration/mixed_team_bus_doorbell_self_healing_integration_test.dart
git commit -m "test(team-bus): broadcast to lazily-declared workers — all consume, park, none stuck active"
```
