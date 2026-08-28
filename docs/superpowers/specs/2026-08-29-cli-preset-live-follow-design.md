# CLI 预设热绑定与编辑锁定 CLI

日期：2026-08-29

状态：待确认

## 问题

全局 CLI 预设是创建时的模板：session 把当时的 `provider` / `model` / `effort` 钉在自己身上。之后改预设（例如换官方账户）只影响新建 session；恢复旧 session 仍走钉死值。用户把预设当成「这个账户 + 这套模型」，期望还挂着该预设、且没在继续条单独改过的 session 下次恢复跟上。

范围是全部可 launch 的 CLI（`claude` / `flashskyai` / `codex` / `opencode` / `cursor`）：跟随判定、编辑锁 CLI、connect 展开、脏检查写回都走同一套，不按 CLI 分支。Cursor 隔离 HOME / `--resume` 只是该 CLI 上的后果，不是本功能的范围限制。

同时，编辑已有预设时仍可改 CLI。换 CLI 等于换工具，会让 `--resume` 对不上。产品要求：**创建时可设 CLI；编辑时锁定 CLI。Provider / model / effort / 名称在编辑时仍可改。**

## 决策

采用**明确跟随**，不用 `session.updatedAt` 与 `preset.updatedAt` 比新旧。

| 规则 | 行为 |
|------|------|
| 跟随 | 还挂着该 `presetId`、且未在继续条走自定义四元组 → 每次 connect 按**当前预设**展开 `provider` / `model` / `effort` |
| 脱离 | 继续条选 Custom（清掉 `presetId`）→ 钉死当前四元组，预设再改也不动 |
| 再跟随 | 继续条再选某个预设 → 改挂到那个预设，之后跟它走 |
| 编辑预设 | CLI 锁定；可改名称 / provider / model / effort |
| 创建预设 | CLI + provider + model + effort 都可设 |
| 脏检查 | 跟随中且 launch 字段与预设不一致时才写回 session 行；只比字段内容，不比时间戳 |
| 运行中 | 改预设不热替换正在跑的 PTY；下次恢复 / 用户重启后生效（与继续条换身份后需重启同一类） |

不在 v1 做：改预设时弹窗重启所有跟随中的 session、按时间戳 last-write-wins、Cursor 跨账户 resume 失败的专门提示。

## 跟随判定

不新增字段。现有 `presetId` 就是跟随开关。

**Simple**

- `session.presetId` 非空 → 跟随该预设。
- `setSessionContinueCustom` / `patchCustom` 把 `presetId` 写成 `''` → 脱离。
- `setSessionContinuePreset` / `patchPreset` 写入新的 `presetId` → 跟随新预设。

**Team**

- `continueOverrides.memberOverrides[memberId].presetId` 非空 → 该成员跟随该预设。
- 创建时 `snapshotTeamSessionContinueOverrides` 仍可写入快照（UI / 预设被删时的回退），但 connect 时若仍能解析到该预设，**快照里的 provider/model/effort 不得盖掉 live 预设**。
- 成员从未挂预设（自定义四元组、无 `sourcePreset`）→ 仍用钉死 / 快照字段，行为与今天一致。
- Team 继续条目前没有 Simple 那种 Custom 四元组；成员换预设走 `patchPreset`，即换跟随目标。

**CLI 失配（防御）**

若 live 预设的 `cli` 与 session 锁定 CLI 不同（历史脏数据或手改 JSON），不跟随 launch 字段，保留 session 已钉值，也不改 CLI。编辑路径锁 CLI 后，正常 UI 不会再制造这种行。

**预设已删**

`presetById` 找不到 → 保留 session / 成员覆盖上最后钉死的 provider/model/effort。`presetId` 可留着（出处记录）；下次若同 id 的预设被重建则重新跟随。

## 架构

```text
编辑预设
  CliPresetEditDialog（编辑时 CLI dropdown disabled）
  CliPresetsCubit.updatePreset（忽略传入的 cli，保留原 cli）

Connect / 恢复
  Simple: enrichSimpleLaunchIdentityFromPreset 在跟随且预设存在时始终展开 live
  Team:   presetForSessionConnect 已按 override.presetId 取 live 预设
          applySessionContinueOverrides 在跟随且 live 预设存在时不再用快照盖 provider/model/effort
  脏检查: 展开后的 provider/model/effort 与 session 行不同 → persist
  Launch: 用展开后的 identity / member（各 CLI 既有物化：Cursor HOME、Codex/Claude 凭证等）
```

| 单元 | 位置 | 职责 |
|------|------|------|
| 编辑锁 CLI | `cli_preset_edit_dialog.dart` | `isEditing` 时 CLI `TpSelect.enabled: false`（`lockCli != null` 时本来已锁）。Provider 行保持可改。 |
| Cubit 锁 CLI | `cli_presets_cubit.dart` | `updatePreset` 不写 `cli`。名称 / provider / model / effort / `updatedAt` 照常。 |
| Simple 展开 | `landing_draft_resolver.dart` `enrichSimpleLaunchIdentityFromPreset` | 跟随 + 预设存在 + CLI 一致 → 用预设的 provider/model/effort；CLI 仍用 session 已锁定的 `identity.cli`。预设缺失或 CLI 失配 → 原样返回。 |
| Team 覆盖合并 | `session_continue_overrides_apply.dart` | `finalizeSessionLaunchMember` 把已解析的 live `preset` 传进 `applySessionContinueOverrides`。跟随（override.presetId 非空）且 live 预设存在 → 只合并 security policy，**不要**用快照盖 provider/model/effort，**不要**清 `activePresetId`。预设缺失 → 维持今天的快照盖写（回退到最后钉死值）。无 presetId → 仍按今天的脱离逻辑盖 concrete 字段。 |
| 脏检查写回 | `session_shell_connector.dart`（已有 `SessionRepository` 的 connect 落盘点） | 展开后的 provider/model/effort 与 session 行不同才 `updateSimpleLaunchIdentity` / `updateContinueOverrides`。继续条 UI 与下次启动读到同一份。不扫全库、不在保存预设时遍历所有 session。`SessionConnectOrchestrator` 只负责展开，不写盘。 |
| 文档注释 | `simple_launch_identity.dart` 等 | 改掉「reconnect must not re-fetch preset」；写明跟随 / 脱离。 |

`presetForSessionConnect` 已按 `override.presetId` 查全局预设；`finalizeSessionLaunchMember` 先 `withPreset` 再 `applySessionContinueOverrides`。今天的 bug 是后者用创建时快照盖掉 live。改合并规则即可，不必重做 snapshot 写入。

## 数据流

### 编辑已有预设

1. 打开 `CliPresetEditDialog(existing: preset)`。
2. CLI 下拉禁用，值保持 `existing.cli`。
3. 用户改 provider / model / effort / 名称，保存。
4. `updatePreset` 写入新字段，**cli 仍为原值**。
5. 已打开且正在跑的 PTY 不变。已停止的跟随 session 下次 connect 展开新值。

### Simple 恢复

1. `prepareSimpleConnect` 读 `session.simpleIdentity`。
2. `enrichSimpleLaunchIdentityFromPreset`：有 `presetId` 且预设还在且 `preset.cli == identity.cli` → provider/model/effort 取预设。
3. `finalizeSessionLaunchMember(isSimple: true)` 仍只合并 security policy（Simple 本来就不从 memberOverrides 盖 provider）。
4. `SessionShellConnector`：若展开后的 provider/model/effort 与 session 行不同 → persist。
5. 各 CLI 按展开后的 provider 走既有物化（Cursor 隔离 HOME / auth，其它 CLI 各自的凭证与 config）。

### Team 成员恢复

1. `presetForSessionConnect` 用 override.presetId 取 live 预设。
2. `withPreset` 把 live provider/model/effort 铺到 member。
3. `applySessionContinueOverrides` 接收该 live `preset`：仅当 override.presetId 非空且 live 预设存在时，才不用快照盖这三项。
4. `SessionShellConnector`：快照与 live 不一致 → persist memberOverride 的 provider/model/effort（presetId 不变）。
5. 预设已删：走现有快照盖写，CLI 仍受 session binding lock 约束。

### 继续条

- 选预设：与今天相同，写入 `presetId` + 当时的四元组；之后该 session 跟随**新**预设。
- Simple 选 Custom：清 `presetId`，钉死四元组。
- 继续条换身份后若 PTY 还在跑，仍用现有「是否立即重启」对话框。

## 错误与边界

| 情况 | 行为 |
|------|------|
| 预设删除 | 保留最后钉死的 launch 字段；不改 CLI |
| 预设 CLI 与 session 锁定 CLI 不同 | 不跟随；保留钉死值 |
| 只改预设名称 | launch 字段相同 → 不写 session |
| 跟随中改预设 provider | 下次 connect 用新 provider。换官方账户可能导致该 CLI 的 `--resume` / 云端会话对不上（Cursor 尤其明显；与继续条手动换账户相同）。v1 不按 CLI 做专门提示 |
| 运行中的 session | 本次 PTY 仍用启动时配置；停止后再开才用新预设 |
| Onboarding `updatePreset` | 与编辑同一 cubit 规则：不能借更新改 CLI |

## 测试

| 用例 | 文件 |
|------|------|
| 跟随且已钉 provider/model 时仍展开 live 预设 | `landing_draft_resolver_test.dart`（改掉今天的 `keeps session-pinned provider and model when already set`） |
| 预设缺失时保留钉死值 | 同上 |
| 预设 CLI ≠ session CLI 时不展开 | 同上 |
| Team：override 有 presetId 且 live 预设存在时，快照 provider 不能盖掉 live | `session_continue_overrides_apply_test.dart`（今天「concrete fields clear activePresetId」仅适用于**无 presetId 的脱离**；有 presetId 时应保留 activePresetId、不盖 live） |
| Team：预设缺失时仍用快照 concrete 字段 | 同上 |
| `updatePreset` 不能改 cli | `cli_presets_cubit_test.dart`（现有用例会把 claude 改成 flashskyai，改为 expect cli 不变） |
| 编辑对话框 CLI 下拉 disabled；创建时 enabled | `cli_preset_edit_dialog_test.dart` |
| Simple connect 跟随写回不同的 provider/model | `session_shell_connector` / connect 落盘相关测试附近补一条 |

不改继续条 cascade 菜单结构。不改 landing 新建 session（创建时已经按当时预设解析一次）。

## 非目标

- 用时间戳决定跟不跟随。
- 保存预设时批量改写所有历史 session（connect 时惰性同步即可）。
- 编辑时锁定 provider。
- 为任一 CLI 跨账户 resume 失败做专门 UX。
- Team 成员新增 Simple 式 Custom 四元组。
- 改正在运行的 PTY 的 env / HOME。
