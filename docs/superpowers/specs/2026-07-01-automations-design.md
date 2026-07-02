# TeamPilot 自动化（Automations）设计

> 状态：**待实现** · 日期：2026-07-01  
> 决策：**方案二（App 级调度器 + 统一分发器）** · **零向后兼容** — 全新存储布局与模型，不保留 Orca 字段映射或旧数据迁移路径。

## 1. 目标

在 TeamPilot 中实现 Orca 风格的**项目级自动化管理**，并通过 Session 右键提供**定时向 lead 发消息**的快捷入口（Claude Code 按时间重置上下文）。两类能力共用同一 `Automation` 模型与调度管线，UI 分三条入口：

| 入口 | 位置 | 范围 |
|------|------|------|
| Session 右键 | `SidebarSessionTile` | 预填 `scope=session`, `action=sendToLead` |
| 工作区侧边栏顶部 | `WorkspaceSidebar` | 当前 `workspaceId` |
| 主窗口侧边栏 | `HomeSidebar` → `HomeGlobalView.automations` | 跨项目汇总 |

## 2. 非目标（v1）

- Orca 外部 provider（Hermes / OpenClaw）
- precheck 命令、token 用量统计
- SSH 远程调度 owner / bridge
- RRULE 完整语法（v1 使用 preset + 5 段 cron）
- 旧版或实验性 automation 数据迁移

## 3. 架构

```
app_shell
  AutomationRepository          ← JSON 持久化
  AutomationScheduleCalculator  ← preset/cron → nextRunAt
  AutomationScheduler           ← app 生命周期 Timer + missed run
  AutomationDispatcher          ← 按 action 投递
        ├─ sendToLead  → TeamBus / TerminalSession
        └─ launchPrompt → SessionLifecycleService + inject
  AutomationCubit               ← UI 状态

UI
  AutomationsPanel              ← 工作区侧边栏 + 全局页共用
  AutomationEditorDialog        ← 完整编辑 / Session 精简编辑
  SidebarSessionTile            ← 右键「定时消息…」
  HomeSidebar                   ← 「全部自动化」
  HomeGlobalView.automations
```

### 3.1 调度器（AutomationScheduler）

- 在 `AppShell` bootstrap 完成后 `start()`，dispose 时 `stop()`。
- 每 30s tick，扫描全部 `enabled` automation 的 `nextRunAtMs <= now`。
- App 冷启动：对 `nextRunAtMs < now` 且在 **missed run grace**（默认 15 分钟）内的条目补跑一次；超出 grace 标记 `skipped_missed` 并推进 `nextRunAtMs`。
- 手动「立即运行」绕过 schedule，写入 `trigger=manual` 的 `AutomationRun`。
- 调度与 UI 解耦：Repository 为唯一数据源，Cubit 订阅变更。

### 3.2 分发器（AutomationDispatcher）

#### `AutomationAction.sendToLead`

向绑定 Session 的 team-lead（mixed/team）或唯一 CLI member（personal）投递 operator 消息，路径与 UI 手动输入一致：

1. 解析 `sessionId` → `AppSession` + `TeamProfile`（若有）
2. `targetMemberId` 默认 `team-lead`；personal 模式解析为唯一 member
3. **Tab 已存在**（含后台保活）：`TabTeamBusCoordinator.deliverUserCommand` 或 `injectMemberStdin`（按 CLI `TerminalBehaviorCapability.usesFullScreenInput`）
4. **Tab 不存在**：`ChatCubit.openSessionTab` + `prepareLaunch` + connect → 就绪后 inject（**冷启动，v1 必做**）
5. 失败写入 `AutomationRun.status = dispatch_failed`，附 `error`

#### `AutomationAction.launchPrompt`

Orca 式：定时向 agent 发送 prompt。

1. `reuseSession == true` 且 `sessionId` 有效 → 复用 Session，否则 `SessionRepository.createSession`
2. connect member（`launchPrompt` 默认 target = team-lead / personal CLI）
3. `submitFullScreenInput(message)` 或 `writeln`
4. `AutomationRun` 记录 `sessionId`、`dispatchedAtMs`

### 3.3 调度表达式

`AutomationScheduleCalculator` 支持：

| Preset | 语义 |
|--------|------|
| `hourly` | 每小时 `:minute` |
| `daily` | 每天 `HH:mm` |
| `weekdays` | 周一至周五 `HH:mm` |
| `weekly` | 指定星期 `HH:mm` |
| `custom` | 5 段 cron（分 时 日 月 周） |

- `timezone`：IANA 字符串，默认 `DateTime.now().timeZoneName` 解析为 `timezone` 包 ID（存盘显式字段）。
- 计算 `nextRunAtMs` 时使用 timezone-aware 算法（port Orca preset 逻辑，不引入 RRULE）。

## 4. 数据模型

```dart
enum AutomationAction { sendToLead, launchPrompt }
enum AutomationScope { session, workspace }
enum AutomationSchedulePreset { hourly, daily, weekdays, weekly, custom }
enum AutomationRunStatus {
  pending, dispatching, dispatched, completed,
  skippedUnavailable, skippedMissed, dispatchFailed,
}
enum AutomationRunTrigger { scheduled, manual }

class Automation {
  String id;
  String name;
  AutomationAction action;
  AutomationScope scope;
  String workspaceId;
  String? sessionId;       // scope==session 必填；launchPrompt reuse 可选
  String targetMemberId;   // 默认 'team-lead'
  String message;
  CliTool? cli;            // launchPrompt 必填
  bool reuseSession;       // launchPrompt
  AutomationSchedulePreset preset;
  String? customCron;      // preset==custom
  int? dayOfWeek;          // preset==weekly, 1=Mon..7=Sun
  String hourMinute;       // "HH:mm" for non-hourly presets
  int minute;              // preset==hourly
  String timezone;
  int dtstartMs;
  bool enabled;
  int? nextRunAtMs;
  int? lastRunAtMs;
  int missedRunGraceMinutes; // 默认 15
  int createdAtMs;
  int updatedAtMs;
}

class AutomationRun {
  String id;
  String automationId;
  String workspaceId;
  int scheduledForMs;
  AutomationRunStatus status;
  AutomationRunTrigger trigger;
  String? sessionId;
  String? error;
  int? startedAtMs;
  int? completedAtMs;
}
```

**约束**

- `scope == session` ⇒ `sessionId` 非空，`action` 通常为 `sendToLead`（允许 `launchPrompt` 但不从 Session 右键预填）。
- `scope == workspace` ⇒ `sessionId` 为空（`launchPrompt` 创建 Session 时写入 run 记录）。
- 删除 Session 时：关联 `scope=session` 的 automation 自动 `enabled=false`（不删记录，UI 显示「Session 已删除」）。

## 5. 存储布局

```
{teampilotRoot}/
  automations/
    catalog.json                 # [{ workspaceId, path, updatedAtMs }]
  workspace/workspaces/{workspaceId}/
    automations.json             # { automations: [...], runs: [...] }
```

- **catalog.json**：全局索引，HomeSidebar 汇总用；Repository 在 workspace CRUD 时维护。
- **automations.json**：单 workspace 的原子文件；`runs` 保留最近 **100** 条（FIFO 截断）。
- 不使用 `automation_refs.json`（YAGNI：Session 右键通过 filter `sessionId` 查询）。

`WorkspaceLayout` 新增：

```dart
String workspaceAutomationsFile(String workspaceId) =>
    p.join(workspaceDir(workspaceId), 'automations.json');

String automationsCatalogFile() =>
    p.join(teampilotRoot, 'automations', 'catalog.json');
```

## 6. UI 规格

### 6.1 Session 右键（`SidebarSessionTile`）

在 rename / pin / delete 之后增加：

- **定时消息…** → `AutomationEditorDialog(compact: true)`  
  预填：`scope=session`, `action=sendToLead`, `sessionId`, `workspaceId`, `name=会话标题 + 定时消息`
- **管理定时消息**（该 Session 有 ≥1 条 automation 时显示）→ 打开过滤后的 `AutomationsPanel`

### 6.2 工作区侧边栏顶部（`WorkspaceSidebar`）

在 preset dropdown /「新建对话」**之上**：

```
[⚡ 自动化 · N]     [+]
  下次运行：14:00（若有 enabled 项）
```

点击标题 → 工作区右 pane 或 overlay 打开 `AutomationsPanel(filterWorkspaceId: …)`。

### 6.3 主窗口（`HomeSidebar` + `HomeGlobalView.automations`）

- `HomeSidebar`：在「我的收藏」上方增加 **全部自动化** 快捷行。
- 路由：`/home-v2?global=automations`
- `AutomationsPanel`：`groupByWorkspace=true`，支持按 enabled / action 筛选。

### 6.4 编辑器（`AutomationEditorDialog`）

| 模式 | 字段 |
|------|------|
| compact（Session 右键） | name, message, schedule, enabled |
| full（管理页新建） | 上述 + action, scope, cli, reuseSession, targetMemberId |

调度 UI：`AutomationSchedulePicker` — preset 下拉 + time picker + weekly 星期选择 + custom cron 文本框（校验 `isValidCron`）。

### 6.5 列表 / 详情

- 列表行：名称、action 图标、schedule 摘要、`nextRunAt` 相对时间、enabled switch
- 上下文菜单：编辑、立即运行、启用/禁用、删除
- 详情抽屉：最近 run 历史（status badge + 时间 + error）

## 7. 状态层与依赖注入

| 类型 | 路径 | 职责 |
|------|------|------|
| Model | `client/lib/models/automation.dart` | 枚举 + JSON |
| Repository | `client/lib/repositories/automation_repository.dart` | CRUD + catalog + run append |
| Service | `client/lib/services/automation/automation_schedule_calculator.dart` | nextRunAt |
| Service | `client/lib/services/automation/automation_scheduler.dart` | tick + missed run |
| Service | `client/lib/services/automation/automation_dispatcher.dart` | sendToLead / launchPrompt |
| Cubit | `client/lib/cubits/automation_cubit.dart` | UI |
| Pages | `client/lib/pages/automations/` | panel, editor, schedule picker |
| Layout | `client/lib/services/storage/workspace_layout.dart` | 路径 |

`AutomationDispatcher` 构造函数注入：

- `ChatCubit`
- `SessionRepository`
- `SessionLifecycleService`
- `TabTeamBusCoordinator`（或 `MemberMaterializer` 接口）

`app_shell.dart`：创建 Repository → Scheduler → Dispatcher → Cubit，Scheduler 在 bootstrap 完成后 start。

## 8. 错误处理

| 场景 | Run status | 用户可见 |
|------|------------|----------|
| Session 不存在 | `skippedUnavailable` | Toast + 列表标记 |
| Tab 冷启动超时（60s） | `dispatchFailed` | error 字段 |
| cron 无效 | 保存拒绝 | 编辑器 inline 错误 |
| workspace 已删除 | catalog 条目移除 | 全局列表不显示 |

## 9. 国际化

新增 `app_en.arb` / `app_zh.arb` 键：

- `automationsTitle`, `automationsNew`, `automationsSendToLead`, `automationsLaunchPrompt`
- `automationsScheduleHourly`, …, `automationsSessionContextMenu`
- `automationsNextRun`, `automationsRunNow`, `automationsRunHistory`
- `automationsSkippedUnavailable`, `automationsDispatchFailed`

完成后运行 `dart run tool/gen_warmup_glyphs.dart`。

## 10. 测试

| 层 | 文件 | 覆盖 |
|----|------|------|
| Unit | `automation_schedule_calculator_test.dart` | 各 preset、timezone、custom cron |
| Unit | `automation_repository_test.dart` | CRUD、catalog、run 截断 |
| Unit | `automation_dispatcher_test.dart` | sendToLead mock ChatCubit |
| Cubit | `automation_cubit_test.dart` | 列表、enable、runNow |
| Widget | `automation_editor_dialog_test.dart` | compact/full 字段 |
| Widget | `sidebar_session_tile_test.dart` | 右键含「定时消息」 |

完成判据：

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration
```

## 11. 实现分期（单 spec 内顺序）

虽为最优终态一次交付，任务顺序建议：

1. Model + Repository + ScheduleCalculator（可测）
2. Scheduler + Dispatcher（含冷启动）
3. AutomationCubit
4. UI：Editor → Panel → 三入口接线
5. l10n + docs/DEVELOPMENT.md 简述
