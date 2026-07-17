# Workspace-scoped root `IS_SANDBOX` opt-in

**Status:** Approved direction (2026-07-17).

## Problem

「为 root 注入 IS_SANDBOX」今天挂在 **设置 → SSH 服务器 → 服务器配置**，按 SSH target 存在 `targets.json` 的 `rootSandboxEnvOptIn` 列表。信任边界实际是「这个工作区是否信任其远程 root 启动环境」，不是「这个全局 SSH 主机永远信任」。用户希望把该开关迁到工作区设置，并去掉全局 SSH 配置项。

## Goals

- 每个工作区一个布尔开关：开启后，该工作区内以 root 走 SSH 启动 Claude 时注入 `IS_SANDBOX=1` 并保留 `--dangerously-skip-permissions`（策略逻辑仍由 `applyRemoteSshLaunchConstraints` 决定）。
- UI 放在工作区设置的独立卡片中。
- 从 SSH 服务器配置与 `TargetsRepository` 中彻底移除该选项。
- 不做迁移、不读旧 `targets.json` 字段。

## Non-goals

- 按工作区内 SSH 主机分别开关。
- 兼容或迁移已有 `rootSandboxEnvOptIn` target 列表。
- 改动 Claude 沙箱检测、`RemoteRootSkipPermissionsPolicy`、或 `applyRemoteSshLaunchConstraints` 的策略分支本身（仅改 `injectRootSandboxEnv` 的数据来源）。
- 改动 credential push 等其它 SSH target 配置。

## Decisions (locked)

| Choice | Decision |
|--------|----------|
| Scope | **整个工作区一个开关**（不按 SSH host 细分） |
| Storage | `Workspace` / `manifest.json` 字段 `rootSandboxEnvOptIn: bool`，默认 `false`；仅在为 `true` 时写出 JSON |
| Compatibility | **无**：删除 `TargetsFile.rootSandboxEnvOptIn` 及读写 API；不迁移旧值 |
| UI placement | 工作区设置（`WorkspaceInfoSection`）**独立卡片**，与基本信息分开 |
| Confirm | 关→开需确认；文案用工作区显示名，不再用 SSH host |
| Launch read | SSH connect 时按 session 的 `workspaceId` 读 `Workspace.rootSandboxEnvOptIn`；找不到 workspace 视为 `false` |
| SSH dialog | `showSshProfileTargetConfigDialog` 去掉 root sandbox 开关；保留 credential push |

## Architecture

```
Workspace settings UI
  └─ RootSandboxEnvOptInTile (workspace display name)
       └─ ChatCubit / SessionRepository
            └─ Workspace.manifest.json  (rootSandboxEnvOptIn)

SSH session connect
  └─ session_shell_connector
       └─ injectRootSandboxEnv ← Workspace.rootSandboxEnvOptIn
            └─ applyRemoteSshLaunchConstraints(...)
```

### Data model

`Workspace`:

- 新增 `rootSandboxEnvOptIn`（默认 `false`）。
- `fromJson`：缺省或非 `true` → `false`。
- `toJson`：仅当 `true` 时写入 key。
- `copyWith` / equality / hash 纳入该字段。

`TargetsFile` / `TargetsRepository`:

- 删除 `rootSandboxEnvOptIn` 列表、`isRootSandboxEnvOptIn`、`setRootSandboxEnvOptIn`。
- 读旧 JSON 时忽略未知 key（现有 fromJson 行为即可）；不再写出该 key。

### Launch path

- 将 `SessionLaunchHost.isRootSandboxEnvOptIn(String targetId)` 改为按 workspace 查询，例如 `isWorkspaceRootSandboxEnvOptIn(String workspaceId)`（或等价命名）。
- `ChatCubit` 实现：在 `state.workspaces`（或 repository）中查找 workspace，返回其 `rootSandboxEnvOptIn`；未找到 → `false`。
- `session_shell_connector`：lookup key 为当前 connect 的 **`activeSession.workspaceId`**（不是 `launchTarget.id`）。在 `launchTarget.kind == RuntimeKind.ssh` 时用该布尔值调用 `applyRemoteSshLaunchConstraints(..., injectRootSandboxEnv: …)`。

### UI

- 在 `WorkspaceInfoSection` 增加独立 `TpCard.outlined`（建议放在基本信息与 Folders 之间）。
- 复用 `RootSandboxEnvOptInTile`（或同风格 preference row）：确认文案传入 `workspace.localizedName(l10n)`（与其它工作区设置一致）。
- 持久化走现有 workspace 更新路径（`SessionRepository` 写 manifest + `ChatCubit` `_emitSnapshot`），可扩展 `updateWorkspaceMetadata` 或增加专用 `setWorkspaceRootSandboxEnvOptIn`。
- 从 `ssh_profile_target_config_dialog.dart` 移除该开关，并删除仅服务于它的 `SshProfileRootSandboxEnvOptInTile` 包装类。

### l10n

- 标题/副标题可保留现有 key。
- 确认 body：占位符从 `{host}` 改为 `{workspace}`；en/zh ARB 与生成本地化文件同步更新。

## Error handling

| Case | Behavior |
|------|----------|
| Workspace missing at launch | Treat as opt-out (`false`); do not abort connect |
| Confirm dialog cancelled | Leave switch off |
| Toggle off | Persist `false` immediately; no confirm |

## Testing

- `Workspace` JSON round-trip：缺省 `false`；`true` 写出并读回。
- 删除 `targets_repository` 中 `rootSandboxEnvOptIn` 用例（或改为断言字段已不存在）。
- `remote_ssh_launch_constraints_test`：策略仍由 `injectRootSandboxEnv` 布尔驱动，无需因存储迁移而改断言语义。
- 若有 connector / host mock 测试依赖 `isRootSandboxEnvOptIn(targetId)`，改为 workspace 签名。
- 建议在 `workspace_info_section_*` 相关测试中为新卡片加 smoke（开关可见 + 可选 confirm/persist 接线），避免仅改模型未挂 UI。

## Out of scope follow-ups

- 若日后需要 per-host 覆盖，再在 workspace 内加 map；本次不做。
