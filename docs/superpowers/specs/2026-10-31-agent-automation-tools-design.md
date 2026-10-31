# Agent 定时任务工具（automation catalog kind）设计

日期：2026-10-31
状态：已评审（待实现）

## 背景

TeamPilot 的定时任务（automation）目前只有 UI 入口：`pages/automations/` 的编辑弹窗 →
`AutomationCubit.save` → `AutomationRepository.upsert`，落盘在
`<teampilotRoot>/workspaces/<workspaceId>/automations/automations.json`。

供 agent 使用的 MCP 只有 `teampilot` catalog 一个，固定注册 skill / plugin / mcp 三个
kind（`services/catalog/catalog_runtime.dart:81-118`），没有 automation。因此用户在会话里说
"每天 9 点提醒我……"时，agent 没有任何工具可用。

文件级变通（agent 直接写 `automations.json`）不可行：整份 store 是原子覆盖，会和 UI 抢写；
`nextRunAtMs` 需要按 `AutomationScheduleCalculator` 计算；`validate()` 失败只剩日志；远端 /
移动端拿不到 app data 目录。

## 目标

让 agent 通过 `teampilot` MCP 管理定时任务：查看、创建、修改、删除、启停、立即试跑。

非目标：

- 不新增独立 MCP server、不改 transport / gateway / CLI 配置。
- 不提供运行历史的分页/清理工具（只读返回最近一次运行）。
- 不支持 `projectFolderPath` / `workingDirectoryPath` / `expertKey` 覆盖。
- 不改 Automations 页面 UI。

## 决策

三个候选：

1. **给 catalog 加第 4 个 kind `automation`**（采纳）。
   复用 transport、gateway、CLI 配置注入、Claude/Cursor allow-list 与测试脚手架；
   代价是需要给 `CatalogOp` 加一个 `run`，且 `restart_required` 对它只能恒为 false。
2. 独立 MCP server `teampilot-automation`：工具命名更自由、权限可独立开关，但要动
   gateway path/字段/delegate/port、CLI 配置注入、两套 policy 与独立测试，工作量约 3–4 倍，
   功能与方案 1 完全重合。
3. skill 教 agent 直接改 `automations.json`：否决，理由见“背景”。

## 架构与接线

### 新增文件

- `client/lib/services/catalog/modules/automation_catalog_tools.dart`
  纯 `const List<CatalogToolSpec>`。
- `client/lib/services/catalog/modules/automation_catalog_module.dart`
  `AutomationCatalogModule implements CatalogKindModule`，`kind: 'automation'`，
  `supportsCreate: true`，`supportsImport: false`，`supportsInstall: false`。

### 既有文件改动

1. `services/catalog/catalog_kind.dart`：`CatalogOp` 增加 `run`。既有 skill / plugin / mcp
   三个 module 的 `switch (op)` 是穷尽式，需要各补一个 `CatalogOp.run =>` 抛
   `CatalogException('unsupported_op', ...)` 的分支，否则编译失败。
2. `services/catalog/catalog_kind_registry.dart`：`_opPrefixes` 增加 `'run_': CatalogOp.run`。
   `catalogGenerationAcquisitionOps` 不包含 `run`，Team Builder 会话调用 `run_automation`
   会被 `generation_mutation_forbidden` 拒绝。
3. `services/catalog/catalog_mcp_policy.dart`：`advertisedRegistry()` 静态登记
   `_AdvertisedKind('automation', automationCatalogTools)`；`_AdvertisedKind` 增加
   `supportsImport` / `supportsInstall` 可选参数（allow-list 只读 `advertise()`，加参数只为语义准确）。
4. `app/app_shell.dart`：
   - `CatalogRuntime.assemble`（`:2164`）保持不动。`CatalogKindRegistry._advertisedRoutes()`
     每次调用现算、handler 每次从 registry 取，因此在 `automationScheduler` 构造之后
     （`:2582`）执行 `catalogRuntime!.registry.register(AutomationCatalogModule(...))`
     即可对 `tools/list` 与 `tools/call` 立即生效。
   - 注入：`AutomationRepository`、`AutomationScheduleCalculator`、
     `runNow = automationScheduler.runNow`、`CatalogMutationBus`、`nowMs`、`newId`（默认真
     uuid，测试注入）、`defaultTimezone = resolveDeviceTimezoneIdentifier`
     （`services/automation/automation_schedule_defaults.dart:19`）、可选校验器
     `teamById` / `resolveCliPreset` / `sessionById`。
   - 刷新：订阅 `catalogRuntime.bus.listen()`，过滤 `kind == 'automation'` 后调用
     `automationCubit.reloadPreservingScope()`；订阅存字段，在 shell `dispose()`（`:3500`）
     cancel。页面因此无需等 30 秒的 scheduler tick（`automation_scheduler.dart:18`）。
5. `services/catalog/managed_skills/teampilot-catalog/SKILL.md`：description 与 workflow
   补充定时任务，保证 agent 能发现这组工具。

### 依赖边界

module 只依赖 repository、schedule calculator、三个回调与若干校验器，不引用 cubit、不引用
Flutter，`handle(op, req)` 可直接用假 repository 单测。transport、gateway、CLI 配置零改动。

## 工具契约

工具名必须满足 `catalog_kind_registry.dart:16-25` 的前缀约束。

| 工具 | op | mutating | 说明 |
|---|---|---|---|
| `read_automation` | read | 否 | 无 `id` 返回本工作区清单；有 `id` 返回详情 + 最近一次运行 |
| `create_automation` | create | 是 | 新建，恒为 `enabled: false` |
| `update_automation` | update | 是 | PATCH 语义，含 `enabled` 启停 |
| `delete_automation` | delete | 是 | 删除规则及其运行历史 |
| `run_automation` | run | 是 | 立即派发一次，不受 `enabled` 限制 |

### `create_automation`

```json
{
  "name": "每日站会提醒",
  "message": "汇总昨天的提交并给出今日计划",
  "action": "scheduledMessage",
  "session_id": "…",
  "schedule": {
    "type": "daily",
    "time": "09:00",
    "minute": 0,
    "day_of_week": 1,
    "cron": "*/5 * * * *",
    "at": "2026-11-01T09:00:00+08:00",
    "timezone": "Asia/Shanghai"
  },
  "max_run_count": 0,
  "missed_run_grace_minutes": 15,
  "reuse_session": false,
  "team_id": "…",
  "target_member_id": "team-lead",
  "preset_id": "…"
}
```

必填：`name`、`message`、`schedule`。

- `action` 缺省 `scheduledMessage`。
- `scheduledMessage`：`session_id` 缺省 `CatalogRequest.sessionId`；显式传入时必须属于
  同一 workspace 且存在（`sessionById` 或 `SessionRepository` 校验）。
- `launchPrompt`：`preset_id` 与 `team_id` 二选一。给了 `team_id` 走团队模式
  （`target_member_id` 缺省 `team-lead`，必须存在于该团队且 `isValid`）；只给 `preset_id`
  走 Simple 模式（`resolveCliPreset` 能解析）。`isPersonal` 由是否给 `team_id` 推导。
- `reuse_session` 仅 `launchPrompt` 生效。

`schedule` 到模型字段的映射：

| `type` | 模型字段 |
|---|---|
| `hourly` | `preset=hourly`、`minute`（缺省 0） |
| `daily` | `preset=daily`、`hourMinute=time`（缺省 `09:00`） |
| `weekdays` | `preset=weekdays`、`hourMinute=time` |
| `weekly` | `preset=weekly`、`hourMinute=time`、`dayOfWeek`（缺省 1，1=周一..7=周日） |
| `custom` | `preset=custom`、`customCron=cron`（必须过 `isValidCron`） |
| `once` | `preset=once`、`runAtMs=at`（ISO-8601 字符串或 epoch ms，必须晚于 now） |

`timezone` 缺省 `resolveDeviceTimezoneIdentifier()`；`dtstartMs` 缺省 now；
`missed_run_grace_minutes` 缺省 15；`max_run_count` 缺省不设上限，设置时必须 ≥ 1。

### `update_automation`

入参为 `id` 加上述任意可写字段（含 `schedule` 与 `enabled`）。合并后重新
`validate()`；改动 `schedule` 或显式 `enabled: true` 时用 `computeNextRunAtMs` 重算，
显式 `enabled: false` 时清空 `nextRunAtMs`。未传字段保持原值。

`enabled` 只在显式传参时改变，因此“建好即开跑”需要第二次显式调用。

### `read_automation`

- 无 `id`：`data.automation.items` 为 `Automation.toJson()` + `summary`
  （`formatScheduleSummary`）+ `last_run`（最近一次 `AutomationRun.toJson()`，无则 null）。
- 有 `id`：`data.automation` 为单个对象，额外带 `recent_runs`（最近 5 条）。

### `delete_automation`

调用 `repository.delete`，连带清除该 automation 的 run 记录。

### `run_automation`

先确认 id 属于本工作区且未达运行上限（`isRunLimitReached`），再调用注入的 `runNow`
（`AutomationScheduler.runNow` 内部已串行化并等待派发完成）。返回
`data.run` = 该 automation 最新一条 `AutomationRun`。未启用的任务同样允许试跑。

### 返回

统一 `CatalogResult`：`kind: "automation"`、`restartRequired: false`、
`boundTo: workspace`。

```json
{
  "ok": true,
  "kind": "automation",
  "ids": ["<uuid>"],
  "workspace_id": "…",
  "restart_required": false,
  "bound_to": "workspace",
  "data": {
    "automation": { },
    "summary": "Daily at 09:00",
    "enabled": false,
    "next_run_at_ms": 1762900000000
  },
  "message": "Created disabled. Enable it in Automations, or call update_automation with enabled:true."
}
```

`next_run_at_ms` 对未启用草稿也会计算并返回（不落盘），便于向用户复述首次触发时间。

## 数据流

```
CLI agent → catalog MCP tools/call
  → CatalogMcpHandler._callTool（解析 CatalogRequest：workspaceId/sessionId 均来自会话）
  → CatalogKindRegistry.dispatch → AutomationCatalogModule.handle
  → 校验 + 归一化 → AutomationScheduleCalculator.computeNextRunAtMs
  → AutomationRepository.upsert / delete
  → CatalogMutationBus.emit(kind: 'automation')
  → AutomationCubit.reloadPreservingScope()（页面即时刷新）
```

`workspace_id` 一律取 `CatalogRequest.workspaceId`，不接受模型传参。

## 错误处理

| code | 触发 |
|---|---|
| `not_found` | `id` 不存在，或属于其他 workspace（合并处理，避免探测） |
| `invalid_argument` | 缺必填字段、类型不符、`session_id` 不在本工作区 |
| `schedule_invalid` | cron 非法、`HH:mm` 越界、`day_of_week` 不在 1..7、`once` 的 `at` 已过期 |
| `target_invalid` | `launchPrompt` 的 `team_id`/`preset_id`/`target_member_id` 无法解析 |
| `run_limit_reached` | `run_automation` 命中 `isRunLimitReached` |
| `write_failed` | repository 落盘异常，消息过 `CatalogErrorSanitizer.sanitize` |

写入顺序固定：构造 `Automation` → `validate()` → `computeNextRunAtMs()` →
`repository.upsert()`，任一步失败都不落盘。成功后才发 `CatalogMutationEvent`。
module 内部用一条 `Future` 链串行化自己的写操作，避免连续调用时 read-modify-write 交错；
与 UI 的窗口仍然存在，但 `atomicWrite` 保证文件不损坏，最坏是后写覆盖。

## 安全

- `create_automation` 恒写 `enabled: false`，用户到 UI 启用，或由 agent 再发一次显式
  `update_automation {enabled: true}`。`run_automation` 允许试跑，不算启用。
- 所有写工具 `mutating: true`。Claude / Cursor 只有读工具在 allow-list
  （`catalog_mcp_policy.dart:33-47`），写工具每次弹确认；Codex / OpenCode 无 per-tool
  allow-list（同文件 `:8-14` 已有说明），启用 server 后自动放行——这一点不隐藏、不假装有闸。
- 所有 id 查询限定在 `CatalogRequest.workspaceId` 内。

## 测试

新增 `client/test/services/catalog/automation_catalog_module_test.dart`（假 repository +
假 runNow + 固定 `nowMs`）：

- create 强制 `enabled=false`，返回 `next_run_at_ms`，消息包含启用提示；
- `launchPrompt` 缺 `preset_id` / `team_id` → `target_invalid`；
- 非法 cron → `schedule_invalid`；`once` 过期 → `schedule_invalid`；
- update 未传字段保持原值；`enabled=false` 清空 next run；`enabled=true` 重算；
- delete 连带清除 run；
- `run_automation` 调用注入的 `runNow`，并返回最新 run；达到上限 → `run_limit_reached`；
- 跨工作区 id → `not_found`；
- list / detail 的返回形状。

扩展现有测试：

- `catalog_kind_registry_test.dart`：`run_automation` 路由到 `('automation', run)`。
- `catalog_mcp_handler_test.dart`：`tools/list` 含 5 个新工具名；`tools/call` 成功结果
  `restart_required: false`。
- `catalog_mcp_policy_test`（若不存在则并入 handler 测试）：读工具含 `read_automation`，
  写工具含 create/update/delete/run。

收尾：`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`，
`dart run tool/run_tests.dart` 跑上述文件，最后一次全量。

## 未决 / 后续

- UI 目前不提示“本次任务由 agent 创建”；如需来源标记，另开 `createdBy` 字段的迁移。
- 运行历史只暴露最近一次 / 最近 5 条，历史清理仍走 UI 的 100 条上限
  （`AutomationRepository.maxRunsPerWorkspace`）。
