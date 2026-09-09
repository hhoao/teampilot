# Session「在右侧分栏打开」(Open to the Side) — Design

Date: 2026-09-08
Status: approved (design)
Builds on: [workbench split groups](2026-09-07-workbench-split-groups-design.md)

## Goal

Session 列表项（左侧栏 / 分组区 / worktree 区 / 搜索对话框中的
`SidebarSessionTile`）的右键与 `⋯` 溢出菜单新增 **「在右侧分栏打开」**：
VSCode "Open to the Side" 语义——该 session 的 tab 呈现在当前聚焦分组
右侧的分组中，与现有内容并排。

非目标：

- 不改左键单击行为（仍在聚焦分组打开/聚焦）。
- 不加键盘快捷键（见「可扩展性」）。
- 不动持久化：split tree 快照（`workbench-layout.json`）已按工作区保存，
  新建分组自动被覆盖。
- 不提供「在下方分栏打开」菜单项，但逻辑层参数化支持。

## Semantics

记 F = center layout 的聚焦分组，S = 目标 session 的 tab
（`WorkbenchTabId.session(id)`），G = S 当前所在分组（可能不存在）。

目标语义（2026-09-08 修订，实测反馈）：**每次调用都应新开右侧分组承载
S，且当前内容（含 preview 标签）原样保留在左侧**。

| 场景 | 行为 |
|---|---|
| S 未打开 | 先走 `openWorkspaceSessionTab`（`preview: false` 强制持久化——S 不占用、也不替换 F 的 preview 槽位），S 开进 F 后按「S 已打开」规则处理 |
| F 右侧存在相邻叶子分组 T | `moveTab(S, T)`：S 移入 T 并激活、聚焦 T；G 被掏空则按 reducer 现有规则剪枝 |
| S 已经就在 T 中 | `moveTab` 退化：仅激活 + 聚焦（它已在右侧窗口里） |
| F 是中序最后一个叶子、G 有 ≥2 tab | `splitInto(S, F, horizontal, before: false)`：F 右侧新建分组承载 S |
| F 是最后一个叶子、S 是 G 的唯一 tab、G ≠ F | 两步组合 `moveTab(S, F)` + `splitTab(S, right)`：净效果 = F 右侧新分组承载 S，G 被剪枝（要求 F 已有 tab 供 split 存活） |
| F 是最后一个叶子、S 是 F 的唯一 tab（或 F 为空 landing） | 降级：激活 + 聚焦——不可能出现有意义的并排视图 |

降级不打 toast、不记错误日志——该 tab 语义上已经是那个方向最靠边的内容。

「右侧」的定义：中序（`leafGroupIds`，`first` 在前）里 F 之后的下一个叶子，
与 `workbenchFocusNextGroup` 的序一致；对混合轴树同样退化为中序下一个叶子，
行为可预测。

## Design

### 1. 纯函数层 — `workbench_split_layout.dart`

```dart
/// 中序里 [groupId] 相邻的叶子分组：[before] 为 true 取前一个
/// （左侧），false 取后一个（右侧）；无则 null。
String? adjacentLeaf(
  WorkbenchGroupLayout layout,
  String groupId, {
  required Axis axis,
  required bool before,
})
```

`axis` 参数为将来「在下方分栏打开」（`Axis.vertical`）预留；两种 axis 的
首版实现相同（中序相邻叶子），水平/垂直差异化留待需要时再做。

### 2. Cubit — `workbench_cubit.dart`

```dart
/// 把 [tab] 呈现在聚焦分组 [axis] 方向、[before] 一侧的分组中：
/// 相邻组存在则移入，不存在则从聚焦组旁分裂新建；无法分裂时降级为
/// 激活 + 聚焦。全部组合现有 reducer 原语，无新 reducer 语义。
void revealTabBeside(
  String workspaceId,
  WorkbenchTabId tab, {
  required Axis axis,
  required bool before,
})
```

实现读取 `centerLayout(workspaceId)`，`adjacentLeaf` 找相邻组：
有 → `moveTab`；无 → `splitInto(tab, focusedGroup, axis, before)`，
reducer 拒绝（唯一 tab 捐出）时再 `moveTab(tab, G)`（源 == 目标，即激活 +
聚焦的退化路径）。tab 不存在于布局时静默 no-op。

### 3. 动作层 — `workspace_session_actions.dart`

```dart
Future<void> openWorkspaceSessionTabToSide(
  BuildContext context,
  AppSession session,
)
```

函数内部从 `ChatCubit.state.workspaces` 解析 session 所属 workspace
（单一解析点，调用方只需传 session），未找到则静默返回。随后
`await openWorkspaceSessionTab(...)`（team 同步、worktree 同同步、
`requestOpenSession` 全部不变——复用，不复制），完成后查
`workbench.centerLayout(ws)` 是否含 S：含则
`revealTabBeside(axis: horizontal, before: false)`；不含（打开被阻断或
失败，`_handleSessionOpenStatus` 已负责用户提示）则静默返回。

### 4. 菜单接线 — `sidebar_session_tile.dart`

- `_contextMenuItems()`：非 archive 模式加
  `value: 'open_to_side'`，icon `Icons.vertical_split_outlined`，
  label `l10n.sessionOpenToSide`。位置放在 rename 之前（与「打开」
  语义最近的操作置顶）。
- `⋯` 溢出菜单（`TpActionMenuItem` 列表）同步加一项，同样位置。
- `_handleContextAction` 增加 `case 'open_to_side'`：
  调 `openWorkspaceSessionTabToSide(context, session)`（workspace 解析
  在函数内部）。

副作用面：tile 被 4 处复用（主侧栏、`session_group_section`、
`worktree_group_section`、`workspace_search_dialog`），菜单在 tile 内部，
四处自动获得该功能。浮动窗口中的 tile 同样生效——目标始终是 center
workbench 布局，与现有 open 语义一致。Android 长按菜单获得同一项；
窄屏下分组布局本身退化为单分组展示，reveal 逻辑不受影响。

### 5. l10n

`app_en.arb` / `app_zh.arb` 各一个 key：

- `sessionOpenToSide`: "Open to the Side" / "在右侧分栏打开"

## Testing

1. **Reducer 纯函数**（`workbench_split_layout_test.dart`）：
   `adjacentLeaf` 在单叶、多叶水平树、混合轴树、首/尾叶子、`before`
   两个方向上的返回值。
2. **Cubit**（`workbench_cubit_test.dart`）`revealTabBeside` 四场景：
   移入相邻组（含源组剪枝断言）、已在相邻组（激活 + 聚焦）、尾部
   `splitInto` 新建、唯一 tab 降级；tab 不存在时 no-op。
3. **Widget**（sidebar session tile 菜单测试）：
   菜单项存在且非 archive 模式显示；点击后 tab 落在聚焦分组右侧的分组
   （fake chat/workbench cubit，复用现有 workbench 测试 fakes）。

## 可扩展性

- `revealTabBeside(axis, before)` 已参数化：加「在下方分栏打开」菜单项
  = 一个 l10n key + 一个菜单 case，零逻辑改动。
- 若将来要快捷键：在 `split_command_registrar.dart` 注册一个以活跃
  session 为目标的命令即可复用 `revealTabBeside`。
