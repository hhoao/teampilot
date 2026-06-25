# Mixed 团队 Claude 互通信 · ChatCubit 全链路集成测试设计

> 状态：**已实现（L0–L1 验证通过；L2 需本地 claude + PTY golden path）** · 日期：2026-06-25  
> 决策：**方案一（ChatCubit 全栈）** + **最佳架构（零兼容包袱）** — 独立 `tools/mock_anthropic` 包、共享 Scenario DSL、双层集成测（fast bus / full ChatCubit）、集成环境强制 HTTP teammate-bus。

## 1. 目标

验证 mixed 团队在 **生产代码路径** 下，两个 Claude 成员能完成一次确定性互发消息：

1. `team-lead` → `worker-1`：`ping`
2. `worker-1` → `team-lead`：`pong`

**覆盖范围（方案一特有）**

| 层 | 验证点 |
|----|--------|
| ChatCubit | `openSessionTab`、`autoLaunchAllMembersOnConnect`、post-frame connect |
| TabTeamBusCoordinator | `installBusForTab`、loopback `TeammateBusMcpServer` |
| SessionLifecycleService | per-member `prepareLaunch`、MCP config 写入、`CLAUDE_CONFIG_DIR` 隔离 |
| TerminalSession | 真实 PTY spawn（非 `FakeTerminalSession`） |
| Claude Code | 真实进程读 settings.env + MCP → 调 bus 工具 |
| Mock Anthropic | `ANTHROPIC_BASE_URL` 指向 loopback，scripted `tool_use` |

**不在范围**

- 4 CLI mixed（codex/cursor/opencode）
- doorbell retry、task queue 等 bus 语义细节（由现有 L1 单测覆盖）
- CI 默认跑（`integration` tag，本地 golden path）
- 远程成员 / SSH tunnel（后续可扩展）

## 2. 架构（最佳终态）

### 2.0 三层测试金字塔（共享 Scenario DSL）

| 层 | Tag | 文件 | 验证 |
|----|-----|------|------|
| **L0** | 无 | `tools/mock_anthropic/test/` | SSE 编码、scenario 状态机 |
| **L1-fast** | `integration` | `mixed_team_bus_ping_pong_integration_test.dart` | 同 ping/pong 剧本，HTTP MCP 客户端假成员（秒级，无 claude） |
| **L2-full** | `integration` | `mixed_team_claude_bus_integration_test.dart` | ChatCubit 全栈 + 真实 claude PTY |

L1 与 L2 **共用** `tools/mock_anthropic/lib/scenarios/ping_pong_mixed_claude.dart` 中的剧本定义；L2 额外走 ChatCubit launch path。

### 2.1 独立 mock 包

`tools/mock_anthropic/`（与 `tools/teammate_bus_bridge/` 同级）：

- `lib/sse/` — Anthropic Messages API streaming 编码器（完整 event 类型，非最小 stub）
- `lib/scenario.dart` — 声明式 `MockScenario` / `MockTurn` DSL
- `lib/server.dart` — `MockAnthropicServer`（path 自动探测、request log、failure dump）
- `bin/mock_anthropic.dart` — 独立运行供手动调试 Claude Code 对接

`client/pubspec.yaml` **dev_dependency** path 引用（仅 test 编译链，不进 release）。

### 2.2 集成环境强制 HTTP teammate-bus

集成测在成员 `extraEnvironment` 注入 `TEAMPILOT_BUS_BRIDGE=/dev/null/teampilot-it-no-bridge`，使 `BusBridgeLocator.resolve()` 回落 HTTP MCP（消除 stdio bridge 环境差异）。断言 **仅** 看 bus mail jsonl，不假设 Claude 传输层。

### 2.3 ChatCubit 全栈路径

```
mixed_team_claude_bus_integration_test.dart
  │
  ├─ MixedTeamClaudeIntegrationHarness (orchestrator)
  ├─ MockAnthropicServer @ tools/mock_anthropic
  ├─ setUpTestAppStorage + AppProviderRepository + SessionRepository()
  └─ ChatCubit (真实 TerminalSessionFactory)
        │
        openSessionTab(session, team, member: team-lead, connectImmediately: true)
        │
        ├─ installBusForTab → TeammateBusMcpServer @127.0.0.1:<busPort>
        ├─ post-frame: _connectShell (leader PTY → claude)
        └─ autoLaunchAllMembersOnConnect → _launchRemainingMembersForTab
              └─ _scheduleMemberConnect (worker PTY → claude)

  claude (leader)                          claude (worker)
  settings: ANTHROPIC_API_KEY=lead-script    settings: ANTHROPIC_API_KEY=worker-script
  MCP X-Member: team-lead                    MCP X-Member: worker-1
        │                                         │
        └──────── teammate-bus MCP ───────────────┘
              (HTTP 或 stdio→teammate_bus_bridge→HTTP，取决于环境)
```

### 2.1 与方案二的差异

方案二跳过 ChatCubit，直接 `prepareLaunch` + `TerminalSession.connect`。方案一 **必须** 使用：

- `ChatCubit` + `PostFrameTestHarness` 驱动 post-frame connect
- `autoLaunchAllMembersOnConnect: () => true` 触发 worker 自动 connect
- `openSessionTab` 以 **team-lead** 为初始 member（mixed 模式仅 lead 首连）

## 3. Mock Anthropic Server

**包：** `tools/mock_anthropic/`（`client/test` 通过 path dev_dependency 引用）

### 3.1 路由

- 单 `HttpServer` 绑定 loopback 随机端口
- `POST /v1/messages`（若 Claude Code 实际路径不同，首次运行 probe 后固化；常见变体：`/v1/messages`、`/anthropic/v1/messages`）
- 按 `x-api-key` 或 `Authorization: Bearer …` 区分 **lead-script** / **worker-script**

### 3.2 剧本（状态机，按请求序号）

**Leader（`lead-script`）**

| Turn | SSE 返回 | 后续 |
|------|----------|------|
| 1 | `tool_use: list_teammates` | claude 调 bus MCP |
| 2 | `tool_use: send_message(to:"worker-1", content:"ping")` | claude 调 bus MCP |
| 3 | （无新 API 请求） | claude 阻塞在 bus `wait_for_message` |
| 4 | `text: "done"` | worker pong 到达后 |

**Worker（`worker-script`）**

| Turn | SSE 返回 | 后续 |
|------|----------|------|
| 1 | `tool_use: wait_for_message` | 阻塞直到 leader ping |
| 2 | `tool_use: send_message(to:"team-lead", content:"pong")` | 回复 leader |

### 3.3 SSE 最小实现

仅实现 scripted 响应所需事件：`message_start` → `content_block_start`（tool_use）→ `content_block_delta` → `content_block_stop` → `message_delta` → `message_stop`。第一版不 stream 长文本。

### 3.4 诊断

- 记录 `(apiKey, turnIndex, timestamp)` 请求 log
- 失败时 dump log + bus mail jsonl

## 4. Test Providers & Team 配置

写入 `providers/claude/providers.json`（测试 harness，`setUpTestAppStorage` 后）：

```dart
AppProviderConfig(
  id: 'mock-leader',
  cli: CliTool.claude,
  name: 'Mock Leader',
  baseUrl: 'http://127.0.0.1:$mockPort',
  apiKey: 'lead-script',
  defaultModel: 'mock-model',
),
AppProviderConfig(
  id: 'mock-worker',
  cli: CliTool.claude,
  name: 'Mock Worker',
  baseUrl: 'http://127.0.0.1:$mockPort',
  apiKey: 'worker-script',
  defaultModel: 'mock-model',
),
```

Team：

```dart
const team = TeamProfile(
  id: 'it-mixed-claude',
  name: 'IT Mixed Claude',
  cli: CliTool.claude,
  teamMode: TeamMode.mixed,
  members: [
    TeamMemberConfig(
      id: 'team-lead',
      name: 'team-lead',
      provider: 'mock-leader',
    ),
    TeamMemberConfig(
      id: 'worker-1',
      name: 'developer',
      provider: 'mock-worker',
    ),
  ],
);
```

## 5. ChatCubit Harness

**文件：** `client/test/integration/mixed_team_claude_bus_integration_test.dart`

### 5.1 构造

```dart
@Tags(['integration'])
library;

// Skip: claude not on PATH
// Skip: libflutter_pty.so unavailable (Linux PTY)

final postFrame = PostFrameTestHarness();

final repo = SessionRepository(); // 无 custom rootDir — 与 AppStorage.paths.basePath 一致

// providers 写入 AppProviderRepository(basePath: AppStorage.paths.basePath)

final cubit = ChatCubit(
  executableResolver: () => resolvedClaudePath,
  cliExecutableResolver: (_) => resolvedClaudePath,
  postFrameScheduler: postFrame.scheduler,
  autoLaunchAllMembersOnConnect: () => true,
  sessionRepository: repo,
  lifecycleService: SessionLifecycleService(
    appDataBasePath: AppStorage.paths.basePath,
  ),
);
```

不使用 `_FakeTerminalSession`；使用默认 `defaultTerminalSessionFactory`。`setUp` 中设 `HttpOverrides.global = null`（同 `chat_cubit_team_bus_test.dart`）。

### 5.2 执行流程

1. `mockServer.start()` → `AppProviderRepository.saveProviders(...)` 写 mock providers
2. `repo.createWorkspace([WorkspaceFolder(path: AppStorage.cwd)])` + `repo.createSession`（roster = team.members）
3. `await cubit.openSessionTab(session, team: team, member: teamLead, repo: repo, connectImmediately: true)`
4. `await postFrame.flush()` — 排空 post-frame **调度**（leader connect + `_launchRemainingMembersForTab`）；**不**等于 PTY 已 ready（`TerminalSession.connect()` 是 void）
5. Poll 直到 `cubit.isMemberRunning('team-lead')` 且 `cubit.isMemberRunning('worker-1')`（interleave `drainPendingAsyncWork()`，超时 30s）
6. **Kickoff 全屏输入**（Claude 用 `usesFullScreenInput`；须 `submitFullScreenInput`，不能用 raw `write()`）：
   - `cubit.selectMember('worker-1')` → `await cubit.currentSession?.submitFullScreenInput('Start idle loop.')`
   - `cubit.selectMember('team-lead')` → `await cubit.currentSession?.submitFullScreenInput('Coordinate the team.')`
   - `_launchRemainingMembersForTab` 会把 selection 重置回 team-lead，故 worker kickoff **必须**先 `selectMember('worker-1')`
7. `await waitForExchange(timeout: 90s)` — poll bus mail jsonl（见 §6）
8. `cubit.closeTab(0)`；`mockServer.stop()`

### 5.3 Post-frame 与 async

沿用 `post_frame_test_harness.dart` 模式：

- `postFrame.flush()` 排空 connect 队列
- `drainPendingAsyncWork()` 在 tearDown
- 测试总 timeout：`@Timeout(Duration(minutes: 2))`

### 5.4 Mixed 启动语义（代码依据）

- `openSessionTab` mixed 模式：`installBusForTab` 在首 tab 创建时执行（`session_launch_service.dart:208-214`）
- 仅 team-lead 首连 PTY（`:217-220`）
- `autoLaunchAllMembersOnConnect` → `_launchRemainingMembersForTab` → worker `_scheduleMemberConnect`（`:236-238`）

## 6. 断言

**主断言（必须通过真实 claude MCP，非直接 HTTP 注入 bus）**

Poll `WorkspaceLayout(teampilotRoot: AppStorage.paths.basePath).busMailFile(workspaceId, sessionId, memberId)`：

1. `.../worker-1.jsonl`（safe segment 以 `ClaudeTeamRosterService.safeClaudePathSegment` 为准）含 JSONL 行：`"t":"msg"`, `"from":"team-lead"`, `"content":"ping"`
2. `.../team-lead.jsonl` 含：`"from":"worker-1"`, `"content":"pong"`

**辅助断言**

- `cubit.hasTeamBusResources(sessionId)` 在 exchange 前为 true
- `cubit.teammateBusMcpEndpointForSession(sessionId)` 可达（已有 `_mcpEndpointAcceptsHttp` 模式）
- `cubit.isMemberRunning('team-lead')` 且 `cubit.isMemberRunning('worker-1')`（exchange 完成时）

**失败诊断**

- Dump mock server request log
- Dump 两个成员的 `settings.json` env 段（确认 `ANTHROPIC_BASE_URL` / key）
- Dump teammate-bus MCP config snapshot（member config inspection 或 provisioned files）

## 7. 前置条件与 Skip

| 条件 | 行为 |
|------|------|
| `claude` 不在 PATH | `markTestSkipped('claude not found')` |
| Linux 无 `libflutter_pty.so` | skip（同 `pty_spawn_harness_test.dart`） |
| Mock server 绑定失败 | `fail` |

Launch args 经 `CliToolAdapter` 在 `member.dangerouslySkipPermissions == true`（`TeamMemberConfig` 默认 true）时含 `--dangerously-skip-permissions`，避免 MCP 审批阻塞。Harness 中显式保持默认或设为 true。

## 8. 文件清单

| 文件 | 职责 |
|------|------|
| `tools/mock_anthropic/pubspec.yaml` | 独立包 |
| `tools/mock_anthropic/lib/sse/anthropic_sse_encoder.dart` | SSE 事件编码 |
| `tools/mock_anthropic/lib/scenario.dart` | Scenario DSL |
| `tools/mock_anthropic/lib/scenarios/ping_pong_mixed_claude.dart` | 共享 ping/pong 剧本 |
| `tools/mock_anthropic/lib/server.dart` | HTTP server |
| `tools/mock_anthropic/bin/mock_anthropic.dart` | CLI 调试入口 |
| `tools/mock_anthropic/test/` | L0 单测 |
| `client/test/integration/support/mixed_team_integration_harness.dart` | Harness：providers、bus mail poll、kickoff、failure artifact |
| `client/test/integration/support/bus_mail_assertions.dart` | jsonl poll 断言 |
| `client/test/integration/mixed_team_bus_ping_pong_integration_test.dart` | L1-fast |
| `client/test/integration/mixed_team_claude_bus_integration_test.dart` | L2-full |
| `client/pubspec.yaml` | path dev_dependency |
| `docs/DEVELOPMENT.md` | 运行命令 |

## 9. 运行命令

```bash
cd client
flutter build linux --debug
LD_LIBRARY_PATH=build/linux/x64/debug/bundle/lib \
  flutter test test/integration/mixed_team_claude_bus_integration_test.dart --tags integration
```

macOS/Windows：需本机 PTY 库 + `claude` on PATH；文档注明平台差异，首版以实现 Linux 路径为主。

## 10. 风险与缓解

| 风险 | 缓解 |
|------|------|
| Claude Code 升级改 API 路径/format | mock 单测 + 首跑 probe；失败 log 请求 path |
| Post-frame 时序 race | `postFrame.flush()` + poll `isMemberRunning` + `drainPendingAsyncWork()` |
| Worker 晚于 leader 启动 | mock worker turn-1 即 `wait_for_message`；leader send 触发 delivery |
| 90s 仍 flaky | 不进 CI；确定性剧本；失败 dump |
| ChatCubit 测试复杂 | harness 提取 helpers；单测 mock server 隔离 SSE |
| 并行 PTY spawn 挂起（Linux） | 串行 connect 已由 launch service 保证；参考 `pty_spawn_harness_test.dart` |
| stdio bridge vs HTTP MCP | 断言只看 bus mail，不假设 Claude 直连 HTTP 端口 |

## 11. 与现有测试的分工

| 现有 | 本测试 |
|------|--------|
| `chat_cubit_team_bus_test.dart` | bus 创建/销毁（FakeTerminalSession） |
| `teammate_bus_mcp_server_test.dart` | bus MCP 语义（HTTP client 假成员） |
| `member_remote_bus_loopback_test.dart` | 远程 tunnel |
| **本测试** | **ChatCubit + 真实 PTY + 真实 claude + mock API 互发消息** |

## 12. 后续扩展

- L2 + Docker SSH 远程成员（复用 `docker_ssh_server.dart`）
- GitHub Actions `workflow_dispatch` nightly integration job
- 3+ 成员 / task queue scenario 插件化（新文件 `scenarios/*.dart`）
- Codex/OpenAI mock 变体（同 `MockAnthropicServer` 接口，不同 path/format adapter）
