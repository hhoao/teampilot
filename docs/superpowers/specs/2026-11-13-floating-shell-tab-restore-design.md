# 浮动工作区 shell tab 持久化与懒恢复设计

日期：2026-11-13

## 背景与问题

浮动工作区（Floating Workspace）的终端 tab id 是内存中 `WorkspaceTerminalEntry` 的 UUID
（`WorkspaceTerminalRegistry`）。`workbench-layout.json` 把这个 id 原样持久化，重启后：

- PTY 注册表为空，tab 仍被恢复 → chip 标题回退成原始 UUID；
- `TerminalFloatingSurface.build` 找不到 entry，把失效 id 作为 `activeEntryId` 传给
  `WorkspaceTerminalPanel` → 永远渲染"新建终端"空态；
- 点击按钮会新建一个带新 UUID 的 entry，但 body 仍被旧失效 id 锁定 → 界面无变化，
  且每次点击都会 spawn 一个不可见的 PTY（资源泄漏）。

因此需要两件事：

1. 恢复时剪掉无法恢复的 shell tab（默认行为，修掉幽灵 tab）。
2. 可选地把 shell tab 持久化成 `cwd + spec`，重启后**首次激活该 tab 时**才懒重建 PTY。

## 目标与非目标

**目标**

- 默认关闭时：重启后失效的 shell tab 被剪掉，浮动面板落到可用的空面板 launcher。
- 开启"恢复终端会话"时：shell tab 的标题、顺序、分组、预览/固定位跨重启保留；
  只有 tab 被激活时才创建 PTY / 连接 SSH。
- SSH profile 已被删除或连接失败：保留 tab，终端内展示连接错误，可重试。
- 不改变 session / file / diff / run 等其它 tab kind 的恢复语义。

**非目标**

- 不恢复 PTY 进程本身（不可能），只恢复"如何重新打开"的描述。
- 不在开机或面板渲染时批量重建终端；不自动连接从未被激活的 tab。
- 不处理 run tab 的持久化（沿用现状）。

## 决策

| 决策点 | 结论 |
|---|---|
| 开关默认值 | 默认关闭 |
| 懒重建触发 | tab 被激活时 |
| SSH 失败处理 | 保留 tab，终端内显示连接失败，可重试 |
| 重建后的 id 衔接 | 重绑 tab id（方案 A）：布局层原位替换旧 entry id → 新 entry id |

## 数据格式

`workbench-layout.json` 升级到 v2，顶层新增 `shellSessions`：

```json
{
  "version": 2,
  "center": { "...": "..." },
  "floating": { "...": "..." },
  "shellSessions": {
    "<tabId>": {
      "cwd": "/path/to/dir",
      "spec": { "type": "sshProfile", "profileId": "..." }
    }
  }
}
```

`spec` 三种形态，由 `WorkspaceTerminalSessionSpec` 上的 `toJson` / `fromJson` 编解码：

- `{ "type": "local", "shellPath": "..." }`
- `{ "type": "target", "targetId": "..." }`
- `{ "type": "sshProfile", "profileId": "..." }`

单条描述符损坏（缺字段、未知 type）只影响对应 tab：该描述符丢弃，tab 按"无描述符"处理。

快照仓库的版本校验接受 `1` 与 `2`：v1 视为 `shellSessions` 为空；其余版本仍按现有
"不支持版本 → 保留当前布局"处理。

## 恢复剪枝

`WorkbenchLayoutPersistence._tabResolves` 对 `shell` 的规则：

1. `workspaceTerminalRegistry` 中存在活 entry → 保留（同进程内重开 workspace）。
2. 否则若开关开启且存在有效描述符 → 保留。
3. 否则（开关关闭 / v1 快照 / 描述符缺失或损坏）→ 剪掉。

session 维持现有逻辑；其余 kind 维持"一律 true"。v1 快照没有 `shellSessions`，
shell tab 全部剪掉，正好清理历史幽灵 tab。剪枝后空组按现有 `layoutFromSnapshot`
规则回滚合并。

## 保存时的描述符来源

保存由 `WorkbenchLayoutPersistence._flush` 统一合成 `shellSessions`，避免未激活 tab
在二次重启时丢失：

- 布局中的 shell tab 有活 entry → 现场从 entry 派生 `cwd + spec`。
- 尚未激活重建 → 沿用恢复时载入的描述符缓存。
- 布局中已不存在的 tab → 丢弃。
- 开关关闭 → 写入空 `shellSessions`（不保留缓存）。

描述符缓存只服务于"已恢复、尚未重建"的 tab，不参与运行期权威状态。

## 懒重建时序

`TerminalFloatingSurface.build`：

- registry 无该 entry 且存在描述符 → 渲染占位（居中 loading + "正在恢复终端…"），
  并 post-frame 调度一次重建；按 tab id 去重，避免多帧重复触发。
- 无描述符 → 维持空白占位（正常恢复剪枝后不应出现）。

`WorkbenchShellLauncher.restorePersistedShell(workspaceId, tabId, descriptor)`：

1. `_sessionOps.createEntry`（描述符的 `cwd + spec`，`select: true`，
   `followWorkspace: false`），tab 立即有内容。
2. post-frame 调 `connectEntry`（与 `openAndSelect` 相同的"先出 tab 再连"节奏）；
   SSH 失败走现有 `sshConnectFailedMessage` 展示。
3. `WorkbenchCubit.replaceFloatingTabId(workspaceId, oldId, entry.id)` 重绑 tab；
   `registry.groupFor(workspaceId).activeId = entry.id`。
4. 不调用 `openShell`（tab 已存在），不调用 `_floating.ensureOpen()`（面板已打开）。

创建阶段抛错（如 spec 数据异常）：捕获并 `AppLogger` 记录，保留 tab 与占位，
释放去重标记使下次激活可重试；删除 tab 的动作仍由用户显式完成。

不会自动连接的场景：面板隐藏、后台分屏中的 tab、从未被激活的 tab。

## 重绑 API

`workbench_split_layout.dart` 新增纯函数 reducer：

```dart
WorkbenchGroupLayout replaceTab(
  WorkbenchGroupLayout layout,
  WorkbenchTabId from,
  WorkbenchTabId to,
);
```

- 遍历所有 group，对 `order / previewIds / pinnedIds / activeId` 原位替换，保持位置与标志。
- `from == to`、`from` 不存在、`to` 已存在 → 返回原布局（no-op）。
- 不触碰 `root`、`focusedGroupId`、`maximizedGroupId`、`lockedGroupIds`。

`WorkbenchCubit.replaceFloatingTabId` 仅替换 floating 布局；不发 `onTabRemoved`
（不是关闭，不该触发领域 teardown）。

## 偏好开关

- `LayoutPreferences.restoreTerminalSessions`，默认 `false`；补齐构造参数、
  `fromJson`（缺省 false）、`copyWith`、`==/hashCode`、`toJson`。
- `LayoutCubit.setRestoreTerminalSessions(bool)`，与 `setFloatingPreviewTabs` 同模式。
- 设置 UI：`layout_appearance_in_layout_section.dart` 浮动预览开关旁新增 Switch，
  标题「恢复终端会话」，副标题说明"重启后保留终端标签，首次打开时才重新连接"。
- l10n：`floating_en.i18n.json` / `floating_zh.i18n.json`，重新执行 `dart run slang`。
- 开关只影响下一次恢复；当前已加载布局不立即增删 tab。

## 接线

- `app_shell.dart` 构造 `WorkbenchLayoutPersistence` 时注入
  `workspaceTerminalRegistry`（已先构建）与
  `() => layoutCubit.state.preferences.restoreTerminalSessions`。
- 描述符查询通过 `WorkbenchLayoutPersistence.descriptorFor(workspaceId, tabId)` 暴露。
- `TerminalFloatingSurface` 注入描述符查询与 `WorkbenchShellLauncher`
  （launcher 先于 surface registry 构建）。

## 错误处理

- 快照读写/解码失败：维持现有"记录日志、保留当前布局"策略。
- 描述符单条损坏：丢弃该描述符并剪掉对应 tab。
- 重建失败：保留 tab 与占位，记录日志，可重试。
- SSH profile 删除：不预校验；重建时按普通连接失败展示，用户可关闭 tab。
- 工作区删除：沿用现有整目录删除，`workbench-layout.json` 一并清理。

## 测试计划

1. reducer：`replaceTab` 原位替换 order/preview/pinned/active、跨 group、三种 no-op 守卫。
2. cubit：`replaceFloatingTabId` 只改 floating，不触碰 center / focused group。
3. 快照仓库：v2 描述符往返；v1 剪掉 shell tab；单条描述符损坏只剪该 tab。
4. 持久化协调器：开关关闭剪枝、开启保留；保存时活 entry 派生 + 未激活 tab 沿用缓存；
   不在布局中的描述符被清理。
5. launcher：`restorePersistedShell` 创建 entry、post-frame 连接、重绑 tab id；
   创建抛错时释放去重标记可重试。
6. surface widget 测试：无 entry + 有描述符 → 占位且只触发一次重建；无描述符 → 空白。

验证：`flutter analyze` + `dart run tool/run_tests.dart <相关路径>`（遵循仓库测试规则）。
