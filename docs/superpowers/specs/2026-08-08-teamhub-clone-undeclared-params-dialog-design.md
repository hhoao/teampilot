# Team Hub 克隆时补选未声明启动参数

- **Date:** 2026-08-08
- **Status:** Approved design
- **Author:** hhoao

## Problem

Team Hub 的 `team.json` 里 `teamMode` 和 `cli` 目前有静默缺省（`native` / `claude`）。
这会带来两个问题：

1. 作者不写 `teamMode` / `cli` 时，克隆出来的团队被**钉死**成缺省模式，用户没有选择机会。
2. `mixed`（跨 CLI / TeamBus）这种关键架构选择无法被缺省推断出来，只能靠作者显式写 `"teamMode": "mixed"`。

目标：`team.json` 可以**不写** `teamMode` / `cli`；克隆时若该字段未声明，则弹对话框让用户补选，
取消则中止克隆。已声明的字段直接使用，不打扰。

## Scope

- 仅影响 **Team Hub 克隆链路**（团队中心页 Clone + 落地选择器 Confirm）。
- `TeamProfile`（本地团队）不变——本地团队始终有具体的 `cli` / `teamMode`。
- 发布链路（`TeamProfilePublishMapper`）不变——本地团队总是显式传值。

## Design

### 1. 模型：`DiscoverableTeam` 区分「声明 / 未声明」

`client/lib/models/discoverable_team.dart`：

```dart
final CliTool? _cli;
final TeamMode? _teamMode;

CliTool get cli => _cli ?? CliTool.claude;
TeamMode get teamMode => _teamMode ?? TeamMode.native;

bool get cliDeclared => _cli != null;
bool get teamModeDeclared => _teamMode != null;
```

- 构造函数参数名不变（`cli` / `teamMode`，类型改为可空），现有构造点
  （`builtin_team_templates.dart`、`team_profile_publish_mapper.dart`）零改动。
- `fromJson`：改用 `CliTool.tryParse(...)` / `TeamMode.tryParse(...)`——
  缺 key 或非法值 → null → 视为「未声明」。
- `toJson`：未声明则不输出该 key，保证缓存往返不丢信息。
- equality / hashCode 基于可空字段。
- 既有 `team.cli` / `team.teamMode` 读取点继续拿到**生效值**，行为不变。

### 2. 克隆链透传覆盖

可选覆盖参数，优先于 `team.teamMode` / `team.cli`：

- `TeamCloneService.clone(team, {onProgress, TeamMode? teamMode, CliTool? cli})`
  → `createTeam(cli: cli ?? team.cli, teamMode: teamMode ?? team.teamMode, ...)`。
- `TeamHubCubit.clone(team, {TeamMode? teamMode, CliTool? cli})` → 透传。
- `TeamLandingSelection.resolveHub(team, teams, {TeamMode? teamMode, CliTool? cli})`
  及其 `cloneTeam` 回调签名同步增加这两个可选参数。

### 3. 新对话框组件

新文件 `client/lib/pages/team_hub/team_hub_clone_options_dialog.dart`：

- `Future<TeamHubCloneOptions?> resolveTeamHubCloneOptions(BuildContext, DiscoverableTeam)`
  - 两个字段都已声明 → 直接返回生效值（不弹框）。
  - 存在未声明字段 → 弹 `TpDialog`，只渲染未声明字段：
    - 模式：`native` / `mixed`（未声明时）；缺省选 `native`。
    - CLI：5 个 `CliTool` 值（未声明时）；缺省选 `claude`。
  - 取消 → 返回 `null`。
- 返回 `TeamHubCloneOptions { teamMode, cli }`（解析后的生效值）。
- 用 Tp 设计系统组件，与 `pages/team_hub/` 现有视觉一致。

### 4. 两个入口接线

- **团队中心页** `team_hub_page.dart:_clone`：
  `resolveTeamHubCloneOptions` → null 直接 return（取消）；否则 `cubit.clone(team, teamMode:, cli:)`。
- **落地选择器** `team_landing_picker_sheet.dart:_confirmHub`：
  同样先 resolve 再 `_selection.resolveHub(..., teamMode:, cli:)`。
  在 `_confirming` 状态下弹框，取消时恢复 `_confirming = false`。

### 5. 内置模板

`builtin_team_templates.dart` 的 Superpowers Quartet 补 `cli: CliTool.claude`，
避免每次克隆都弹 CLI 选择（其 base CLI 明确是 claude）。

## Error handling

- 对话框取消 → 中止克隆，不产生任何本地副作用（不触发依赖安装）。
- 落地选择器入口：`_confirmHub` 先置 `_confirming = true`（防并发重复弹框），
  resolve 返回 null（取消）时恢复 `_confirming = false`。
- 团队中心页入口：`_clone` 在 `cubit.clone` 前 resolve，取消直接 return。
- 解析或克隆异常沿用现有 toast 路径（`teamHubCloneFailed`）。

## Testing

- `discoverable_team_test.dart`：新增「未声明 → 生效 native/claude + declared=false +
  toJson 省略 key」用例；既有 round-trip 用例保持通过。
- `team_clone_service_test.dart`：覆盖值优先于 `team.teamMode` / `team.cli`。
- `team_hub_cubit_test.dart` / `team_landing_selection_test.dart`：覆盖参数透传。
- `team_hub_clone_options_dialog_test.dart`（如有 widget 测试先例）：两个都声明不弹框 /
  未声明弹框 / 取消返回 null。

## Files touched

- `client/lib/models/discoverable_team.dart`（模型声明/生效拆分）
- `client/lib/services/team/team_clone_service.dart`（覆盖参数）
- `client/lib/cubits/team_hub_cubit.dart`（透传）
- `client/lib/services/team/team_landing_selection.dart`（resolveHub + 回调签名）
- `client/lib/pages/team_hub/team_hub_page.dart`（团队中心页接线）
- `client/lib/pages/team_hub/team_landing_picker_sheet.dart`（落地选择器接线）
- `client/lib/services/team_hub/builtin_team_templates.dart`（补 cli 声明）
- `client/lib/pages/team_hub/team_hub_clone_options_dialog.dart`（新增对话框）
- 对应测试文件

## Non-goals

- 不给本地 `TeamProfile` 加「未声明」概念。
- 不做自动推断（根据 roster 猜 native/mixed）——用户要的是显式补选。
- 不改发布链路。
