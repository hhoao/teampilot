# 侧栏「已打开」按分栏分组 — Design

Date: 2026-09-08
Status: approved (design)
Builds on: [session open-to-the-side](2026-09-08-session-open-to-side-design.md)、[workbench split groups](2026-09-07-workbench-split-groups-design.md)

## Goal

Workbench 开分栏后，侧栏「已打开」区块从平铺列表改为按分栏分组：
每栏一个小节，头部「分栏 N」（N = 中序位置，1 起）、聚焦栏高亮、
点击头部聚焦该栏。单分栏布局维持现状平铺（无头部）。

非目标：

- 分组不做折叠（分栏组内 tab 数由分栏自身决定，不会过长；worktree
  组有折叠是因为组可能容纳几十个 session）。
- 不做分组拖拽 / 重排（布局归 workbench split tree 管理）。
- 序号不持久化——位置描述不是身份；分栏增删时自然重排。
- 不动手动分组 / worktree 分组区块。

## Design

### 1. 数据层 — `workbench_cubit.dart`

```dart
/// Per-split-group session tile data, in leaf (中序) order:
/// (groupId, non-preview session tab ids of that group's strip).
/// Empty list for a single-group layout — callers keep the flat path.
List<(String groupId, List<String> sessionIds)> centerSessionGroups(
  String workspaceId,
)
```

过滤规则沿用 `OpenSessionTabIds.fromCenterBarOrder`（排除 preview、
`local-` 前缀 id），但按组保留。只有 file/diff tab 的分组过滤后为空，
不产生 entry（调用方据此省略整节）。

### 2. UI 层 — `workspace_sidebar.dart`（_RunningSessionsHost / _RunningSessionsSection）

- **单分栏**：`centerSessionGroups` 返回空 → 走现有平铺路径，零改动。
- **多分栏**：每 entry 渲染小节 = 头部 + 该组 `SidebarSessionTile` 列表：
  - 头部「`l10n.sidebarSplitGroupLabel(n)`」，N 为中序序号（1 起）。
  - 聚焦分栏的头部高亮：主题 primary 前景色（对齐
    `SplitGroupFocusFrame` 的视觉语言），非聚焦用 `onSurfaceVariant`。
  - 头部整行可点：`workbench.focusGroup(workspaceId, groupId)`——与
    分栏内点击聚焦同语义。
  - tiles 复用现有 `_RunningSessionsSection` 的渲染参数（`onTap` =
    `openWorkspaceSessionTab`，行为不变：激活该 tab 并聚焦其组）。
- 头部与 tiles 数据均经 `context.select`（Equatable 值对象），沿用
  现有重建边界。

### 3. l10n

- `sidebarSplitGroupLabel`: `"Column {n}"` / `"分栏 {n}"`（参数 N）。

## Testing

1. **Cubit**（`workbench_cubit_test.dart`）：`centerSessionGroups` 的
   多分栏分组序、单分栏返回空、preview 排除、仅文件 tab 的组不出现。
2. **Widget**（`workspace_sidebar` 既有测试文件或就近新建）：
   多分栏渲染「分栏 1 / 分栏 2」两组 tiles；头部点击调用 focusGroup；
   聚焦组头部高亮；单分栏无头部（现状回归）。

## 可扩展性

将来若浮动静侧栏需要同样分组，`centerSessionGroups` 的模式可镜像一个
`floatingSessionGroups`；序号语义与 `workbenchFocusNextGroup` 的中序
一致，无新顺序概念。
