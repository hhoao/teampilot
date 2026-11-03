# 定时任务增加「执行命令」动作（runCommand）设计

日期：2026-11-02
状态：已评审（待实现）

## 背景

现有 automation 只有两种动作（`client/lib/models/automation.dart:7`）：

| action | 到点做什么 |
|---|---|
| `scheduledMessage` | 找到已有会话，把 `message` 当用户输入发给该会话的 lead |
| `launchPrompt` | 新建 CLI 会话（Simple/团队），把 `message` 当首条输入交给 agent |

调度侧是完整的：cron 解析、时区、`hourly/daily/weekdays/weekly/custom/once`、
`missedRunGraceMinutes`、运行历史（`automation_schedule_calculator.dart`、
`automation_repository.dart`）。缺的是执行端——`AutomationDispatcher.dispatch` 只有一条
路径 `_dispatchMessage` → `busGateway.deliverUserCommandToMember`
（`automation_dispatcher.dart:139-213`）。

因此用户无法表达「每天 2 点跑一次构建」「每小时备份一次数据库」这类需求，只能用
`launchPrompt` 让 agent 去执行：每次起一个 CLI、烧 token、结果不确定，CLI 没连上还会
`skippedUnavailable`。

## 目标

- 新增 `runCommand` 动作：到点在 workspace 所在的运行时上执行一行 shell 命令。
- 结果（exit code、输出尾部、耗时）落运行历史，在 Automations 页可查看。
- agent 可通过 `teampilot` MCP 创建/修改这类任务，并按情况决定是否直接启用。

非目标：

- 不做系统级调度（launchd / systemd / 计划任务）。应用的进程内调度语义不变。
- 不做输出投递到会话、桌面通知、失败告警。
- 不做完整日志落盘（需要时命令自己 `> log 2>&1`）。
- 不改动 `scheduledMessage` / `launchPrompt` 的既有行为。

## 决策

### 执行层：复用 `ProcessRunExecutor`，不用 `HostOneShotRunner`

`HostOneShotRunner`（`services/host/host_one_shot_runner.dart:25`）覆盖 native / WSL /
SSH，但它是缓冲式一次性返回、**无法中途杀掉进程**。超时必须能真杀：`AutomationScheduler`
的队列是严格串行的（`automation_scheduler.dart:63-67`），一条 `sleep 99999` 会堵死所有
定时任务。

`ProcessRunExecutor`（`services/run/process_run_executor.dart:57`）已经具备所需能力：

- 覆盖 local / WSL / SSH / Termux 四种 `RuntimeKind`；
- 流式输出（`onOutput` 回调）；
- 返回 `ProcessRunResult{exitCode, stop}`，`stop()` 会取消订阅并 `kill()` 子进程
  （本地 `Process.kill`、远端 `SSHSession.kill`，见 `process_run_handle.dart`）；
- `shell: true` 让 POSIX 目标走 `sh -c`、WSL 走 `sh -c`，管道与 `&&` 可用。

命令到目标的映射沿用现有链路：`Workspace.folders`（`path` + `targetId`）→
`RunTargetResolver.resolve(owner: folder, cwd: …)` → `RunTargetPlan`。

### 命令形式：一行 shell 字符串

不符合 argv 语义的场景（`npm ci && npm run build`、`dart run tool/x.dart | tee log`）
太常见，因此存 shell 字符串而不是 argv 列表。脚本文件用 `bash scripts/daily.sh` 表达，
不单开字段。

### 调度可靠性：不做系统级调度，命令类可选补跑

应用关闭时不执行，这是与 crontab 的既有差距，本次明确写入契约而不是隐藏。为缓解
「关机一整晚错过备份」这类场景，`runCommand` 增加 `catchUpPolicy`：

- `none`（默认）：超过 `missedRunGraceMinutes`（默认 15）记 `skippedMissed`，与现状一致。
- `once`：应用启动时无论错过多久都补跑一次。

默认 `none` 是因为构建/部署/推送这类操作补跑可能比不跑更危险。

### 调度与执行解耦

`_dispatchClaimed` 现在 `await _dispatcher.dispatch(...)`
（`automation_scheduler.dart:146-162`），一条长命令会占住调度队列。`runCommand` 改为：
认领阶段（写 `nextRunAtMs` / `runCount`，毫秒级）同步完成，执行交给
`AutomationCommandExecutor` 的独立队列，结果回来再写 `AutomationRun`。

## 架构与接线

### 新增文件

- `client/lib/services/automation/automation_command_runner.dart`
  `AutomationCommandRequest` / `AutomationCommandOutcome` / `AutomationCommandRunner`
  接口 + `HostAutomationCommandRunner` 生产实现（依赖 `ProcessRunExecutor`、
  `RunTargetResolver`、`Workspace? Function(String)`）。
- `client/lib/services/automation/automation_command_executor.dart`
  `AutomationCommandExecutor`：自有串行队列、按 `automationId` 防重叠、写
  `AutomationRun`、调用运行计数推进。
- `client/lib/services/automation/automation_tail_buffer.dart`
  按字节上限保留输出尾部的环形缓冲（各流 4 KB），记录是否被截断。
- `client/lib/services/automation/automation_run_accounting.dart`
  从 `AutomationDispatcher._advanceAutomationAfterRun`（`automation_dispatcher.dart:411`）
  提取的共享推进逻辑（`runCount` / `lastRunAtMs` / `nextRunAtMs` / 上限停用），
  dispatcher 与 command executor 共用。

### 既有文件改动

1. `models/automation.dart`
   - `AutomationAction` 增加 `runCommand`；`AutomationSchedulePreset` 不变。
   - `Automation` 增加 `command`、`timeoutSeconds`（默认 300）、`catchUpPolicy`（默认
     `none`）；`toJson` 仅在 `runCommand` 时写出，`fromJson` 缺省安全。
   - `AutomationRunStatus` 增加 `failed`、`timedOut`、`skippedOverlap`。
   - `AutomationRun` 增加 `exitCode`、`stdoutTail`、`stderrTail`、`outputTruncated`、
     `durationMs`；`copyWith` / `toJson` / `==` / `hashCode` 同步。
   - `validate()`：`message` 必填改为仅对两种旧动作生效；`runCommand` 校验
     `command` 非空且 ≤ 2000 字符、`timeoutSeconds` 在 30..1800、
     `sessionId` / `presetId` / `teamId` 为空、`reuseSession == false`。
2. `services/automation/automation_dispatcher.dart`
   - `dispatch` 增加 `runCommand` 分支前的显式拒绝（`ArgumentError`），保证命令只走
     `AutomationCommandExecutor`，两条路径不会同时存在。
   - `_advanceAutomationAfterRun` 改为委托 `AutomationRunAccounting`。
3. `services/automation/automation_scheduler.dart`
   - 构造参数增加可选 `AutomationCommandExecutor? commandExecutor`。
   - `_dispatchClaimed`：`runCommand` 认领后 `commandExecutor.enqueue(...)`（不 await），
     完成回调触发 `onAfterTick`。
   - `runNow`（手动试跑）是例外：`runCommand` 时等待 executor 本次执行结束再返回，
     保证 `run_automation` 拿得到 run 记录；等待上限为 `timeoutSeconds` 再加 30 秒。
   - `_processMissedRuns`：`catchUpPolicy == once` 的 `runCommand` 直接派发；
     同时把启动前遗留、已超过 `timeoutSeconds` 仍处于 `pending` / `dispatching` 的 run
     标记为 `dispatchFailed(error: interrupted)`，避免进程被杀后留下永久中间态。
4. `app/app_shell.dart`
   - 构造 `ProcessRunExecutor`（复用现有的 `sshSpawner`）、`RunTargetResolver`、
     `HostAutomationCommandRunner`、`AutomationCommandExecutor`，注入 `AutomationScheduler`。
5. `pages/automations/`
   - `AutomationEditorKind` 增加 `runCommand`（`automation_editor_dialog.dart:27`）；
     Automations 页「新建」改为三项菜单；编辑时按 `action` 反查 kind
     （`automations_list_body.dart:174-181` 的二选一改三选一）。
   - `runCommand` 表单：命令（等宽多行，必填）、工作目录（复用现有 folder 选择器，
     空 = workspace 主 folder）、超时、补跑开关，以及提示文案「应用未运行时不会执行；
     错过超过 15 分钟默认不补跑」。
   - 运行历史展开显示状态、耗时、`exitCode`、stdout/stderr 尾部；`failed` / `timedOut`
     用错误色。
6. `services/catalog/modules/automation_catalog_module.dart` 与
   `automation_catalog_tools.dart`：见「MCP 工具契约」。
7. `l10n/app_en.arb` / `app_zh.arb`：新增表单、列表、状态文案。
8. `services/catalog/managed_skills/teampilot-catalog/SKILL.md`：补充「定时执行命令」
   的用法与限制。

## 数据模型

```dart
enum AutomationAction { scheduledMessage, launchPrompt, runCommand }

enum AutomationCatchUpPolicy { none, once }

enum AutomationRunStatus {
  pending,
  dispatching,
  dispatched,
  completed,        // exitCode == 0
  failed,           // exitCode != 0
  timedOut,         // 超过 timeoutSeconds，进程被 stop()
  skippedUnavailable,
  skippedMissed,
  skippedOverlap,   // 同一条 automation 上一次仍在运行
  dispatchFailed,   // 目标解析失败 / 进程起不来 / 应用中断
}
```

`Automation` 新增字段只对 `runCommand` 有意义：

| 字段 | 类型 | 说明 |
|---|---|---|
| `command` | `String` | 一行 shell 命令，必填 |
| `timeoutSeconds` | `int` | 默认 300，范围 30–1800 |
| `catchUpPolicy` | `AutomationCatchUpPolicy` | 默认 `none` |
| `workingDirectoryPath` | `String?` | 复用现有字段；空则用 workspace 主 folder |

`AutomationRun` 新增字段：`exitCode`（`int?`）、`stdoutTail` / `stderrTail`（`String?`）、
`outputTruncated`（`bool`）、`durationMs`（`int?`）。

输出各保留最后 4 KB 并内联进 `automations.json`。`maxRunsPerWorkspace` 为 100
（`automation_repository.dart:57`），最坏约 800 KB；每次 `upsertRun` 全量重写文件的成本
仍在可接受范围。需要完整日志时由命令自身重定向到文件。

## 执行链路

```
Timer.periodic(30s)
  → AutomationScheduler._tick
  → _dispatchDueAutomations → _dispatchClaimed（同步认领：写 nextRunAtMs）
  → AutomationCommandExecutor.enqueue（独立串行队列）
      → HostAutomationCommandRunner.run
          → Workspace.folders 匹配 cwd → RunTargetResolver.resolve
          → ProcessRunExecutor.start(shell: true, onOutput: tailBuffer.add)
          → Future.any([exitCode, timeout])
              → 超时：ProcessRunResult.stop()
      → AutomationRunAccounting.advance → AutomationRun.status = completed/failed/timedOut
      → AutomationRepository.upsertRun + upsert
      → onAfterTick → AutomationCubit.reload
```

`AutomationCommandRunner` 契约：

```dart
class AutomationCommandRequest {
  final String workspaceId;
  final String command;
  final String? workingDirectoryPath;
  final int timeoutSeconds;
  final int outputTailBytes; // 默认 4096
}

class AutomationCommandOutcome {
  final int? exitCode;
  final String stdoutTail;
  final String stderrTail;
  final bool truncated;
  final bool timedOut;
  final int durationMs;
  final String? error; // workspace_unavailable / target_unreachable / spawn_failed
}

abstract interface class AutomationCommandRunner {
  Future<AutomationCommandOutcome> run(AutomationCommandRequest request);
}
```

目标解析规则：

- `workingDirectoryPath` 为空 → 用 `workspace.folders.first`。
- 非空 → 必须落在某个 folder 的路径之下（POSIX/Windows 各自规范化后比较），
  用该 folder 的 `targetId`；匹配不到 → `dispatchFailed`，
  `error: working_directory_invalid`。
- `RunTargetResolver.resolve(owner: folder, cwd: workingDirectoryPath)` 得到
  `RunTargetPlan`，其 `runtimeTarget.kind` 决定实际入口（local / wsl / ssh / termux）。

## MCP 工具契约

### `create_automation`

新增 `action: "runCommand"`：

```json
{
  "name": "夜间构建",
  "action": "runCommand",
  "command": "npm ci && npm run build",
  "working_directory": "/home/me/repo",
  "timeout_seconds": 900,
  "catch_up": "once",
  "enabled": true,
  "schedule": {"type": "daily", "time": "02:00", "timezone": "Asia/Shanghai"}
}
```

- `message` 对 `runCommand` 不再是必填；`session_id` / `team_id` / `preset_id` 忽略。
- `enabled` **仅对 `runCommand` 生效**，缺省 `false`，显式 `true` 才立即启用。
  `scheduledMessage` / `launchPrompt` 维持「创建恒为禁用」（上一版设计中已评审的安全属性）。
- `timeout_seconds` 缺省 300，越界 → `invalid_argument`。
- `catch_up` 缺省 `none`。落盘字段为 `catchUpPolicy`（值为 `"none"` / `"once"`），
  与其余字段的 camelCase 约定一致。

### `update_automation`

支持 PATCH `command` / `working_directory` / `timeout_seconds` / `catch_up`，
合并后重新 `validate()`；改动调度字段时按现有逻辑重算 `nextRunAtMs`。

### `read_automation` / `delete_automation` / `run_automation`

无需改动。`read_automation` 会通过 `AutomationRun.toJson()` 自动带出
`exit_code` / `stdout_tail` / `stderr_tail` / `duration_ms`。
`run_automation` 对手动试跑同样走 `AutomationCommandExecutor`。

## 错误处理

| 场景 | run 状态 | error |
|---|---|---|
| workspace 被删除 / folder 消失 | `dispatchFailed` | `workspace_unavailable` |
| SSH 目标离线 | `dispatchFailed` | `target_unreachable` |
| cwd 不在该 workspace 的任何 folder 下 | `dispatchFailed` | `working_directory_invalid` |
| 进程创建失败 | `dispatchFailed` | `spawn_failed` |
| 命令不存在 / shell 报错 | `failed` | 无（`exitCode` 为 127 等） |
| 超过 `timeoutSeconds` | `timedOut` | 无 |
| 应用退出导致中断 | `dispatchFailed` | `interrupted` |
| 上次运行未结束又到点 | `skippedOverlap` | 无 |

`skippedOverlap` 的 run 不计入 `runCount`，不推进 `lastRunAtMs`。

MCP 参数校验错误码：`command_invalid`（空或 > 2000 字符）、
`working_directory_invalid`（非绝对路径或不在 workspace 内）、`invalid_argument`
（`timeout_seconds` 越界）、`schedule_invalid`（沿用现有）。

## 安全

- `runCommand` 等价于本机任意代码执行，权限级别与现有的安装脚本一致，无新增远程攻击面
  （命令只从本地 UI 或本地 MCP 会话写入）。
- agent 创建 `runCommand` 默认禁用；显式传 `enabled: true` 才立即生效——这是本次确认的
  产品行为，MCP 侧不做额外拦截。
- `read_automation` 会把 `stdout_tail` 送进 agent 上下文。命令输出若含密钥会被一并读出，
  这是已知取舍，不做脱敏（无法可靠脱敏）。
- 所有 id 查询仍限定在 `CatalogRequest.workspaceId` 内。

## 测试

新增 `client/test/services/automation/automation_command_runner_test.dart`：

- 假 `ProcessSpawner` 注入：正常退出 → `exitCode`、stdout/stderr 尾部正确；
- 超时路径：`stop()` 被调用且结果 `timedOut == true`；
- 输出超过上限 → `truncated == true` 且保留的是尾部；
- cwd 不在 workspace 内 → `working_directory_invalid`；
- 不同 `RuntimeKind` 的 spawn 参数分别正确（local / wsl / ssh）。

新增 `client/test/services/automation/automation_command_executor_test.dart`：

- 同一 automation 重入 → 记 `skippedOverlap`、`runCount` 不变；
- 完成 / 失败 / 超时三种状态正确推进 `runCount` 与 `lastRunAtMs`；
- `runNow` 对 `runCommand` 等待执行结束并返回 run。

扩展现有测试：

- `automation_test.dart`：老 JSON 反序列化、`runCommand` 的 `validate()` 各分支、
  `toJson` 往返。
- `automation_scheduler_test.dart`：`catch_up: once` 补跑 vs `none` 记 `skippedMissed`；
  启动时把过期中间态 run 标记为 `interrupted`。
- `automation_dispatcher_test.dart`：`runCommand` 传入 dispatcher 时被拒绝，且不触发
  session / bus 调用。
- `automation_catalog_module_test.dart`：创建默认 disabled、显式 `enabled: true`、
  `command_invalid` / `working_directory_invalid`、`update` 支持新字段。
- `automation_editor_dialog_test.dart`：三选一入口、命令为空不放行、编辑时 kind 正确。

收尾：`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`，
`dart run tool/run_tests.dart` 跑上述文件，最后一次全量。

## 未决 / 后续

- 运行历史仍是 100 条上限的滚动窗口，命令输出的完整归档留给命令自身重定向。
- 多 folder workspace 的 cwd 目前只能按路径前缀匹配 folder；如需要「命名工作目录」，
  另开字段。
- 系统级调度（关掉应用也执行）不在本次范围，需要 headless 入口，另立设计。
