# TeamPilot 事件架构 — 接续说明（新 Session 从这里开始）

> 写给下一个 session 的交接文档。目标：让新 session 在**不读历史对话**的情况下，知道做过什么、现在在哪、下一步做什么。

最后更新：2026-09-12

---

## 一句话现状

**期 1（中央事件发布层）与期 2（agent presence 事件化）均已完成并合入 `main`。** 期 3 第一刀（Event Transport）spec 已写，待审：`docs/superpowers/specs/2026-09-12-event-transport-design.md`。

---

## 背景：为什么要做这件事

2026-08-28 你提了一个问题：「怎么才能让移动端看到桌面端正在运行的 session，并及时更新聊天记录」。

当时（在另一个 session 里）它被做成了 `feat-host-session-runtime` 分支——一个「runtime 守护进程接管一切」的大重写：一天生成 28 个提交、~15,600 行，从未真机运行过，基线就有 ~120 个测试失败。之后 9 天里反复修复，问题始终存在，最后判定做崩。

**复盘结论**（重要，决定了后续做法）：

1. 崩溃的根因不是架构方向错，而是**一次性大爆炸重写 + 零运行验证 + 零测试地基**三者叠加；
2. 真正被缺的是一层**事件发布/解耦**架构——服务之间通过事件联系，而不是互相直接调用；
3. 因此重启为**分阶段、每步可验证、行为等价**的路线。

**那个失败的 worktree 从未被合并**（`services/runtime/` 目录在 main 上不存在），继续冻结，不要在上面继续修。其中有 salvage 价值的部分（PTY 环境修复、framing 协议、虚拟 CLI 测试框架）留到期 4 再挑。

---

## 已完成：期 1 — 中央事件发布层

**设计**：`docs/superpowers/specs/2026-09-10-central-event-dispatcher-design.md`
**计划**：`docs/superpowers/plans/2026-09-10-central-event-dispatcher.md`

仿 Hadoop YARN 的 `org.apache.hadoop.yarn.event` 包，落在 `client/lib/services/event/`：

| YARN | 本项目 |
|---|---|
| `Event<TYPE>` | `DispatcherEvent<K>`（getter 名为 **`eventKind`**，非 `kind`） |
| `EventHandler<T>` | `EventHandler<T>` |
| `Dispatcher` | `Dispatcher`（`dispatch` / **`registerFamily<K>(Type kindType, EventHandler)`** / `unregister`） |
| `AsyncDispatcher` | `AsyncDispatcher`：无界队列 + 单消费循环 + 按族路由 + 自动多播 |

**有意偏离 YARN 的三处**（写在 `services/event/README.md`）：
1. handler 抛异常 → log + 继续（YARN 是进程退出）；
2. 无界队列 + 深度 >1000 告警（YARN 用有界阻塞队列）；
3. 接口 getter 叫 `eventKind`（`kind` 会与业务字段撞名）；`registerFamily` 显式传 `Type`（Dart 泛型不 reify）。

**首批接入的事件源**：`CatalogMutationBus`、`WorkspaceFsWatcher`（均为行为等价迁移——对外 API 不变，背靠 dispatcher，现有订阅方零改动）。另外新增了 Session 生命周期事件族。

---

## 已完成：期 2 — Agent presence 事件化

**设计**：`docs/superpowers/specs/2026-09-11-agent-presence-events-design.md`（结尾有 *Implementation notes*，逐条记录实际交付与 spec 的偏离）
**计划**：`docs/superpowers/plans/2026-09-11-agent-presence-events.md`

把 agent 工作状态（booting / working / idle）从**轮询快照**改为**事件推送**，并让 `MemberPresenceCubit` 成为中央 dispatcher 的**第一个真实消费方**。

### 实际数据流（务必按这个理解，不要按 spec 的初稿）

```
推送触发（只有两条锁存边）
  ① TerminalSession.markUserTurnStarted / markUserTurnIdle   → onPresenceInputsChanged
  ② TerminalActivityTracker boot latch 翻转（一次性定时器）  → onPresenceInputsChanged
                    │
                    ▼
  MemberPresenceCubit._requestPresenceRecompute() → tickFromIdleWatch()
                    │
                    ▼
  既有权威求值：MemberPresenceService.compute() → MemberCoordination.availability()
                    │
                    ▼
  PresenceEventBridge.reportAvailability(seat, 计算值)   ← 注意：喂的是【计算值】
                    │
                    ▼
  AsyncDispatcher → AgentPresenceProjection（Map<seat, kind>，变化才广播 changes）
                    │
                    ▼
  cubit 读 projection.availabilityFor(seat) 并 emit  ← UI 看到的是【投影值】
```

### 三个必须知道的坑（都已在代码注释里记录）

1. **发布边喂计算值，不是投影值。** 若把投影值喂回发布边，会形成自指环路——投影只在值变化时广播，于是循环冻结在第一个值。这是本期最微妙的设计决策，`README.md` 与 spec 均有记录。
2. **一跳延迟是正常的。** 生产环境的 sink 只**入队**，投影在消费循环的下一轮才观察到；因此某次 tick 会读到上一轮的投影值并 emit，随后由 `changes` 监听触发重算收敛。这是有界延迟，不是卡死。
3. **`TerminalActivityTracker.isWorking` 确实驱动 presence**——但只对 `usesShellActivity`（nativeShellActivity）与 `mixed` 两条策略；原生单 CLI 走回合锁存 `userTurnActive`，Claude roster 走 roster 标志。**这条最初被写错了**（spec 初稿与 README 都说它不驱动），已在 Task 9 的 review 后修正。改这块前先读 `client/lib/services/team/member_coordination.dart`。

### 可用性维度的完整策略表

`MemberCoordination.resolve` 每个 seat 选一种策略，全部经 `_bootingOr`（由 `isBootFrameReady` 决定是否降级为 booting）：

| 策略 | working/idle 来源 | 本期是否推送 |
|---|---|---|
| personal / native 单 CLI | `shell.userTurnActive`（回合锁存） | ✅ 推送 |
| nativeClaudeRoster | `claudeRosterWorking`（roster） | ❌ 仍轮询 |
| nativeShellActivity | `activityTracker.isWorking`（PTY 启发式） | ❌ 仍轮询 |
| mixed | bus 回合/等待状态，否则退回 `isWorking` | ❌ 仍轮询 |

本期推送只覆盖两条锁存边；**roster 标志、`isWorking` 与 connection 仍是轮询输入**。

### 关键文件

| 文件 | 角色 |
|---|---|
| `client/lib/services/event/agent_presence_event.dart` | 事件族类型（`AgentPresenceKind` + `PresenceSeatKey` + `AgentPresenceEvent`） |
| `client/lib/services/event/agent_presence_sink.dart` | 窄发布接口（含 no-op 实现，未接线时零行为） |
| `client/lib/services/event/presence_event_bridge.dart` | 去重发布边 |
| `client/lib/services/event/agent_presence_projection.dart` | 投影（`availabilityFor` / `snapshot` / `changes` / `removeSeat`） |
| `client/lib/services/team/terminal_activity_tracker.dart` | boot 推送（`setBootFrameListener` 可复活 + 一次性定时器） |
| `client/lib/services/terminal/terminal_session.dart` | 回合锁存触发 + `presenceSeat` + `onPresenceInputsChanged` |
| `client/lib/cubits/member_presence_cubit.dart` | 消费迁移（读投影 + 触发重算 + 生命周期） |
| `client/lib/app/app_shell.dart` | 接线（app 生命周期 dispatcher + projection；**每 bootstrap 一个** bridge） |

### 期 2 的验收与质量记录

- 全套测试：**+9146 通过 / 2 跳过 / 0 失败**（`70d78e643` 树；之后仅新增两个 markdown 文件）
- `flutter analyze`：零新增问题
- 既有测试**未被修改**地通过（行为等价的证据）
- 9 个任务，每个都过独立 review；共 4 轮 fix loop，修掉的真问题包括：一次性 dispose 标志会导致重连后推送静默失效、构造函数在 seat 未绑定时挂载监听、测试绕过了 dispatcher 的异步跳数而断言了生产不会有的行为

---

## 下一步：期 3 — 移动端同步（原始需求的交付点）

**目标**：手机看到桌面端会话列表 + 聊天记录实时更新。

**第一刀设计（已定稿，待你审 spec）**：`docs/superpowers/specs/2026-09-12-event-transport-design.md`

- 组件名是 **Event Transport**（不是 Hub / Relay）：dispatcher 的过线方式，不是新总线。
- 桌面 local home 开 `EventTransportServer`（`127.0.0.1` + `<teampilotRoot>/event-transport.json`）；手机 ssh home 经现有 SSH `forwardLocal` 开 Client。
- 本期 family：`agentPresence`（snapshot + `op:clear` 墓碑）与 `sessionLifecycle`（只直播；手机无新 UI 消费者）。聊天仍走 `TranscriptChangeSignal`；下一刀在同一通道加 `transcriptInvalidated`。
- 期 2 墓碑遗留变为负载：`AgentPresenceKind.cleared` 进 dispatcher；投影 `removeSeat` 且广播。

**仍有效的背景判断**：

- **不需要 daemon**。用现有 SSH / Connect 通道即可。
- 聊天记录同步推荐「失效事件 + 现有 softReload」，不在第一刀。

**已知待处理项**：

1. ~~投影断连基线~~ → 已纳入第一刀 spec（`cleared` + `clearAll`）。
2. `TerminalActivityTracker.isWorking` 驱动的两条策略仍轮询——第一刀不事件化。
3. 若干代码整洁类 minor（`_knownSeats` 无界增长等）——第一刀不顺手清理。

---

## 工作方式约定（沿用，已被验证有效）

1. **流程**：brainstorm（含探索与澄清）→ 写 spec → 自审 → 你审 → writing-plans 出计划 → 新 worktree + subagent-driven-development 逐任务实施（每任务独立 review + fix loop）→ 整分支 final review → 合并。
2. **每步可验证**：验收标准固定为「全套测试绿 + 行为等价（既有测试未被修改地通过）」。期 1 与期 2 各靠这条安全网抓到真实回归。
3. **小步**：宁可多切一个任务，不要一次改多层。失败的 runtime 分支就是反例。
4. **注意 agent 的越界修改**：本期多次出现「实施者做了 brief 未列的改动」——有时正确（如 bridge 每 bootstrap 重建），有时是缺陷（如测试绕过异步跳数）。派发时明确边界，review 时逐条裁决，不要照单全收。
5. **agent 可能中途掉线**（API 配额/网络）。若工作已落盘但未提交，controller 核验后可代为提交，并在报告里注明「controller 未编写代码」。

### 已知环境事项

- 新 worktree 需要：`git submodule update --init --recursive` + `cd client && dart run tool/sync_bundled_google_fonts.dart`（否则字体测试红）。
- **绝不直接 `flutter test`**：一律 `cd client && dart run tool/run_tests.dart <paths>`。
- 测试 runner 有 bug：即使「Some tests failed」，退出码仍为 0 —— **读摘要行，不要信退出码**。
- `docs/ARCHITECTURE.md` 是 AGENTS.md 的**悬空引用**（该文件从未被提交过），值得补或修链接。

### 跑全套时会看到的失败（已知、与本路线无关）

`client/test/pages/floating_workspace/floating_workspace_panel_gestures_test.dart`
→ `overflow keeps + after strip and chrome flush-right`

确定性失败，文件不在期 1/期 2 的改动范围内，来自另一条工作线（sidebar / floating panel）。跑全套时看到它不必慌，但也别顺手"修"到别的东西。

### 如果新增的测试要等定时器

`TerminalActivityTracker` 的推送测试驱动的是**真实一次性 `Timer` + 真实墙钟**。固定 `Future.delayed` 会被负载打穿（期 2 合并后就是这么抖起来的，见 `c74df8ec0` 的去抖动提交）。写这类测试请用「轮询到截止时间」的等待（`_waitFor(predicate, timeout)`），并把时长取到抖动占比可忽略；负向用例（取消/解绑后不该触发）则要固定等待**数倍于** `bootMaxWait`，让漏掉的定时器有机会暴露。

---

## 失败分支的处置

`feat-host-session-runtime`（worktree 路径 `.worktrees/feat-host-session-runtime`）**冻结、未合并**。期 4 接入 Runtime daemon 时，从中挑已验证的件：PTY 环境清理修复、`runtime_framing` 协议、虚拟 CLI 测试框架、peer-sync 集成测试。**判决：不要在上面继续开发。**
