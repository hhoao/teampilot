# CLI Configuration Presets (全局 CLI 配置预设)

**Date:** 2026-06-15
**Status:** approved
**Scope:** Simple mode (personal projects) — 全局跨项目共享的 CLI 配置预设

## Motivation

当前简单模式下，每个 CLI 只有一套固定的 provider/model/effort 映射（`providerIdsByTool` / `modelsByTool` / `effortsByTool`）。用户不能为同一个 CLI 保存多套配置（如 "Claude 工作" vs "Claude 快速"），切换不便。

需求：用户可增删命名的 CLI 配置预设（CLI + Provider + Model + Effort），全局跨项目共享，侧边栏直接列预设名称供切换。完全替代现有 per-CLI 映射机制，不做向后兼容。

## Data Model

### `CliPreset` (new)

```dart
// client/lib/models/cli_preset.dart
class CliPreset {
  final String id;        // UUID
  final String name;      // 用户命名，如 "Claude 工作"
  final CliTool cli;      // CLI 工具
  final String provider;  // provider ID
  final String model;     // model ID
  final String effort;    // effort level（可选）
  final int createdAt;
  final int updatedAt;
}
```

### `ProjectProfile` changes (simplified)

Remove:
- `cli` — replaced by activePreset → .cli
- `agent.provider`, `agent.model`, `agent.effort` — resolved from preset at session launch
- `providerIdsByTool`, `modelsByTool`, `effortsByTool` — no longer needed

Add:
- `activePresetId` (String?, nullable) — points to a `CliPreset.id`

Keep:
- `agent.prompt`, `agent.extraArgs`, `agent.agent`, `agent.agentType`, `agent.dangerouslySkipPermissions` — these are CLI-independent agent config
- `skillIds`, `pluginIds`, `mcpServerIds`

## Storage

- **Preset list:** `<teampilotRoot>/cli-presets.json` — global single file, JSON array
- **Active preset:** `projects/{projectId}/profile.json` → `activePresetId` field
- **No migration:** old fields silently ignored; users create presets fresh

## New Components

| Component | Role |
|-----------|------|
| `CliPresetsRepository` | Read/write `cli-presets.json` |
| `CliPresetsCubit` | Global cubit for preset CRUD; exposed via `RepositoryProvider` in `app_shell.dart` |
| `CliPresetsManageDialog` | Full preset list with add/edit/delete actions |
| `CliPresetEditDialog` | Create or edit a single preset (name, CLI, provider, model, effort) |

## `ProjectProfileCubit` Changes

**Remove:**
- `setCli(CliTool cli)`
- `setCliDefaults(CliTool cli, {provider, model, effort})`

**Add:**
- `setActivePreset(String presetId)` — resolve preset from `CliPresetsCubit` → update `agent` fields that remain + save `activePresetId` to profile
- On `load()`: if `activePresetId` is set, accept it as-is (preset resolution happens at launch time, not load time)

**New dependency:** `ProjectProfileCubit` does NOT directly depend on `CliPresetsCubit`. The cubit only stores `activePresetId`. Preset resolution (CLI, provider, model, effort) happens at **session launch time** and in the **config profile generation** path — not in the cubit.

## Session Launch & Config Profile Resolution

These paths currently read `profile.cli`, `profile.providerIdsByTool`, `profile.modelsByTool`, `profile.effortsByTool`, and `profile.agent.provider/model/effort`. They must instead resolve from the active preset.

### Files to update

| File | Current reads | Change |
|------|--------------|--------|
| `config_profile_context.dart` | `standaloneProviderId()`, `standaloneModelId()`, `standaloneTeamFromProfile()`, `standaloneMemberFromProfile()` — all read from `profile` | Accept `CliPreset?` parameter; resolve CLI/provider/model/effort from preset |
| `session_launch_service.dart` | `_personalProfileForSession()` reads `providerIdsByTool`/`modelsByTool` | Resolve from preset by `activePresetId` |
| `config_profile_service.dart` | Reads `profile.cli` at L303 | Get CLI from active preset |
| `codex_config_profile_capability.dart` | Reads `profile.agent.effort` + `profile.effortsByTool` | Read effort from preset |
| `claude_config_profile_capability.dart` | Reads `profile.agent.model` + `profile.agent.effort` + `profile.effortsByTool` | Read model/effort from preset |
| `project_agent_section.dart` | Reads `profile.cli` for agent preset display | Get CLI from active preset via `CliPresetsCubit` |

## UI Changes

### Sidebar (`_DefaultCliDropdown` → `_PresetDropdown`)

- Dropdown lists all preset names
- Selected = preset matching `profile.activePresetId`
- Gear button → opens `CliPresetsManageDialog`
- Empty state: "No presets — create one" guidance

### Agent config page (`ProjectAgentSection`)

**Remove:**
- `ProjectCliDefaultsSection` (CLI picker + per-CLI config list)
- `ProjectCliConfigList` and all related helpers

**Keep:**
- Agent prompt, extraArgs, agent type, dangerouslySkipPermissions fields

**Add:**
- A small row showing current preset name + "Manage Presets" button → opens `CliPresetsManageDialog`

### `CliPresetsManageDialog` (new)

- Full preset list with: name, CLI icon, provider brand icon, model, effort
- Each row: edit + delete actions
- Delete warns if any project references the preset
- "Add Preset" button at bottom

### `CliPresetEditDialog` (new)

- Name text field
- CLI dropdown (all launchable CLIs from registry)
- Provider dropdown (filtered by selected CLI)
- Model dropdown (filtered by selected provider)
- Effort dropdown (shown when CLI/provider/model support it)
- Save / Cancel

## Edge Cases

| Case | Handling |
|------|----------|
| Preset deleted while referenced by project(s) | Sidebar shows warning state; "Select a preset" prompt |
| Preset list empty | Sidebar shows "Create your first preset" CTA |
| Provider removed from system | Preset keeps the ID; shown as "Unavailable" in lists |
| CLI removed from system | Same — preset preserved but marked |
| No active preset (activePresetId = null) | Sidebar shows hint + gear button to manage presets |

## Removed Code

### Models
- `ProjectProfile.cli`, `ProjectProfile._providerIdsByTool`, `ProjectProfile._modelsByTool`, `ProjectProfile._effortsByTool` (and related getters/constructor params/copyWith/toJson/==/hashCode)
- `ProjectAgentConfig.provider`, `ProjectAgentConfig.model`, `ProjectAgentConfig.effort` (and related copyWith/toJson/==/hashCode)

### Cubit
- `ProjectProfileCubit.setCli()`, `ProjectProfileCubit.setCliDefaults()`

### UI / Helpers
- `project_cli_defaults_section.dart` — entire file
- `project_cli_config_list.dart` — entire file
- `project_cli_config_helpers.dart` — functions no longer needed
- `project_cli_effort_helpers.dart` — functions no longer needed
- Parts of `project_agent_section.dart` referencing `ProjectCliDefaultsSection`

### Pages
- `home_workspace_project_config_workspace.dart` — still renders `ProjectAgentSection`, but the section's content changes (no more CLI picker)
