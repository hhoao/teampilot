# Personal Workspace (Independent Mode) · Hub Removal · Project-Scoped Config

Date: 2026-06-06  
Status: Approved

## Background / Motivation

TeamPilot today is team-centric: projects bind to a team (`AppProject.teamId`), skills/plugins/MCP/extensions
live on `TeamConfig`, and a parallel **Hub** route (`/chat` + `ContextSidebar`) offers a second path to the
same `ChatPage` workbench. This duplicates navigation and blocks a clean **solo / personal** workflow.

Users need an **independent mode**: a personal workspace with project-scoped resources, single-agent sessions,
and a single work entry point—the **project page** (`/home-v2/project/:projectId`).

**Team mode stays** on the dual-track model (B): team projects continue to use `TeamConfig` resources and
`config-profiles/teams/`. Personal projects use a new `ProjectProfile` and
`config-profiles/standalone/projects/`.

No backward compatibility. No legacy Hub code. Architecture-first.

## Goals

1. **Personal workspace** sidebar entry; right pane shows only personal projects (`teamId == ''`).
2. **ProjectProfile** for personal projects: single agent, all `CliTool` values, skills/plugins/MCP/extensions.
3. **Launch pipeline** for personal sessions via
   `config-profiles/standalone/projects/{projectId}/sessions/{sessionId}/`.
4. **Hard-remove Hub**: delete `/chat`, `ContextSidebar`, `WorkspaceEntryMode.hub`.
5. **Startup**: `主页` or `恢复上次打开的项目` (no “工作区” option).
6. **Project page** is the only work surface: conversations + `ChatPage` + config rail (personal) or team shortcut (team projects).

## Non-Goals

- Migrating existing user data, Hub bookmarks, or `workspaceEntryMode.hub` preferences.
- Unifying team resources onto projects (option A — rejected; team keeps `TeamConfig` resource fields).
- TeamBus / multi-member coordination changes for team projects (unchanged).
- Per-session skills/MCP (resources stay at project or team layer).

## Decision Log

| Decision | Choice | Rationale |
|----------|--------|-----------|
| v1 scope | Full stack (UI + data + launch + config UI) | User requirement |
| Hub | Hard delete | Single work entry; no redirect shells |
| Compatibility | None | User requirement |
| Resource model | **B — dual track** | Personal → `ProjectProfile`; team → `TeamConfig` |
| Personal CLI | **All `CliTool`** | claude, flashskyai, codex, opencode, cursor |
| Work entry | `/home-v2/project/:projectId` only | Project page already embeds `ChatPage` |

---

## Information Architecture

### Sidebar (`HomeWorkspaceSidebar`)

```
收藏 / 最近访问
────────────────
个人工作区          ← NEW: selects personal scope
────────────────
我的团队 (collapsible)
  · Team A, B, …
  + 新建团队
────────────────
团队广场 / Skills / Plugins / MCP / Extensions  (global install library)
────────────────
[ 供应商 ]
```

- **Personal scope**: right pane = project grid only (`teamId == ''`). No team header tabs.
- **Team scope**: unchanged (`HomeWorkspaceContent` with Projects / Members / Skills / …).
- Global Skills/Plugins/MCP/Extensions remain **install catalogs**; enable/link happens on project (personal) or team (team projects).

### Project page (`HomeWorkspaceProjectPage`)

Single work surface for all projects. Layout: title bar tabs + icon rail + conversation panel + `ChatPage`.

**Personal project rail** (`teamId.isEmpty`):

| Rail item | Content |
|-----------|---------|
| 对话 | `HomeWorkspaceConversationPanel` |
| Agent | Model, CLI, provider, prompt (`ProjectAgentSection`) |
| Skills | Project-scoped enable/link |
| 插件 | Project-scoped |
| MCP | Project-scoped |
| 扩展 | Project-scoped overrides |
| 设置 | Paths, display, danger zone |

**Team project rail** (`teamId.isNotEmpty`):

| Rail item | Content |
|-----------|---------|
| 对话 | Same conversation panel |
| 设置 | Project paths / display |
| 团队配置 | Deep-link to `/home-v2?section=…` on team home (skills, members, etc.) |

### Routes

| Route | Fate |
|-------|------|
| `/home-v2` | Keep; supports `?section=` deep links for team config |
| `/home-v2/project/:projectId` | **Primary work route** |
| `/chat`, `/chat/session/:sessionId` | **Delete** |
| Hub `ShellRoute` + `ContextSidebar` | **Delete** |

### Startup (`WorkspaceEntryMode`)

Remove `hub`. Enum becomes:

```dart
enum WorkspaceEntryMode { home, lastProject }
```

| Mode | Behavior |
|------|----------|
| `home` | Open `/home-v2` |
| `lastProject` | Open `/home-v2/project/{lastOpenedProjectId}` if known; else `/home-v2` |

Persist `lastOpenedProjectId` in `LayoutPreferences` (or dedicated field in session preferences).

---

## Data Model

### `AppProject` (`projects.json`)

Unchanged shape. Semantics:

- `teamId == ''` → **personal project** (personal workspace).
- `teamId != ''` → **team project** (bound to team).

Dedup key remains `(teamId, primaryPath)` so the same directory may exist as both a team project and a personal project.

### `ProjectProfile` (personal only)

**Path:** `{teampilotRoot}/projects/profiles/{projectId}.json`

```dart
class ProjectAgentConfig {
  String provider;
  String model;
  String agent;
  String agentType;
  String extraArgs;
  String prompt;
  bool dangerouslySkipPermissions;
}

class ProjectProfile {
  String projectId;
  CliTool cli;                    // any CliTool value
  ProjectAgentConfig agent;
  List<String> skillIds;
  List<String> pluginIds;
  List<String> mcpServerIds;
  Map<String, String> providerIdsByTool;
  int updatedAt;
}
```

- Created atomically when a personal project is created (sensible defaults: e.g. `CliTool.claude`, empty resource lists).
- Updated by `ProjectProfileRepository` + `ProjectProfileCubit`.
- **No `ProjectProfile` for team projects.**

### `TeamConfig` (team projects — unchanged)

Keeps `members`, `skillIds`, `pluginIds`, `mcpServerIds`, `teamMode`, `cli`, bus-related fields.

### `AppSession`

| Field | Personal | Team |
|-------|----------|------|
| `sessionTeam` | `''` | `teamId` |
| `cliTeamName` | `''` | `{teamId}-{seq}` |
| `members` | `[]` | `SessionMemberBinding[]` |

`createSession` already skips team counter when `sessionTeam` is empty; personal path must call `prepareProjectLaunch` instead of team launch.

### `ExtensionState`

Add:

```dart
Map<String, Map<String, bool>> projectOverrides; // projectId → extensionId → enabled
```

- Personal projects: `effectiveEnabledForProject(projectId, extensionId)`.
- Team projects: existing `teamOverrides` unchanged.

---

## Config Filesystem (`CliDataLayout`)

### New: standalone / personal project layer

Personal CLI runtime trees live under `config-profiles/standalone/` so they are
clearly separate from `config-profiles/teams/` and from TeamPilot’s session index
at `{teampilotRoot}/projects/` (UI `projects.json`, `sessions/`).

```
{teampilotRoot}/config-profiles/
├── {tool}/                          # app defaults (unchanged)
├── teams/{teamId}/…                 # team mode (unchanged)
└── standalone/
    └── projects/{projectId}/
        ├── {tool}/
        │   ├── skills/              ← ProjectSkillLinkerService
        │   ├── plugins/             ← ProjectPluginLinkerService
        │   └── mcp/servers.json
        └── sessions/{sessionId}/
            └── {tool}/              ← PTY CONFIG_DIR for personal launch
```

Inheritance (mirror team layer):

```
app/{tool}/agents|skills
  → standalone/projects/{projectId}/{tool}/
  → standalone/projects/{projectId}/sessions/{sessionId}/{tool}/
```

### Unchanged: team layer

```
config-profiles/teams/{teamId}/…
```

### `CliDataLayout` helpers (new)

Paths are relative to `config-profiles/` unless noted:

| Method | Resolves to |
|--------|-------------|
| `standaloneProjectsDir()` | `standalone/projects/` |
| `standaloneProjectDir(projectId)` | `standalone/projects/{projectId}/` |
| `standaloneProjectToolDir(projectId, tool)` | `standalone/projects/{projectId}/{tool}/` |
| `standaloneProjectSkillsDir(projectId)` | `…/{tool}/skills/` (flashskyai default) |
| `standaloneProjectSessionToolDir(projectId, sessionId, tool)` | `…/sessions/{sessionId}/{tool}/` |

`ProjectProfile` JSON remains under `{teampilotRoot}/projects/profiles/` (UI index tree, not CONFIG_DIR).

### New services

| Service | Role |
|---------|------|
| `ProjectSkillLinkerService` | Sync `ProjectProfile.skillIds` → `standalone/projects/{id}/flashskyai/skills/` |
| `ProjectPluginLinkerService` | Sync plugins into `standalone/projects/{id}/{tool}/` |
| `ProjectProfileRepository` | CRUD `projects/profiles/{id}.json` |
| `ConfigProfileService.prepareProjectLaunch` | Symmetric to `prepareTeamLaunch` |

`SessionLifecycleService.prepareLaunch` branches:

```dart
if (project.teamId.isEmpty) {
  // load ProjectProfile, prepareProjectLaunch, single agent
} else {
  // existing team + member path
}
```

### CLI coverage (all `CliTool`)

Each tool’s `ConfigProfileCapability` must accept a **project scope** launch context (projectId + sessionId) in addition to team scope. Tools:

- `claude`, `flashskyai`, `codex`, `opencode`, `cursor`

Personal launch uses the profile’s `cli` field; no TeamBus, no multi-member mixed dirs unless explicitly added later.

---

## UI & State

### `HomeWorkspacePage` scope

```dart
enum HomeWorkspaceScope { personal, team, global, library }
```

Mutually exclusive with existing `_globalView` / `_libraryView` / team selection.

### New widgets / pages

- `HomeWorkspacePersonalContent` — title + `HomeWorkspaceProjectsTab` filtered to `teamId == ''`.
- `pages/home_workspace/project/config/` — personal config sections (reuse team section UI patterns where possible; data from `ProjectProfileCubit`).
- Extend `HomeWorkspaceProjectRail` + `HomeWorkspaceProjectSection` enum for personal vs team items.

### `ChatPage` (personal)

When `team == null` and session’s project is personal:

- Do not spin on `CircularProgressIndicator`; render single-agent workbench.
- Hide team actions (`Open Team`, `launchAllMembers`, team-lead button).
- `cwd` from `project.primaryPath` (already true on project page).
- Tab model: session tabs only (no member tabs).

### `HomeWorkspaceNewProjectDialog`

When creating from personal workspace: `teamId: ''`, create `ProjectProfile` defaults, optional navigate to project page.

---

## Deletions (no legacy)

Remove entirely:

- `client/lib/widgets/context_sidebar.dart` and `context_sidebar/` parts
- `/chat` routes, `ActiveSessionChatPage`
- `WorkspaceEntryMode.hub` and appearance toggle segment for “工作区”
- Hub `ShellRoute` wrapper in `app_router.dart` that injects `ContextSidebar`
- Tests referencing `go('/chat')` — update to project routes
- Any `scopeSessionsToSelectedTeam` UX tied only to Hub sidebar (setting may remain for team home filtering)

Do **not** remove:

- `TeamConfig` resource fields
- `TeamSkillLinkerService` / `TeamPluginLinkerService`
- Team home tabs (Members, Skills, …)

---

## Error Handling

| Case | Behavior |
|------|----------|
| Personal project missing `ProjectProfile` | Create default profile on read; log warning |
| Launch with empty provider/model | Same validation as team member; surface `team_config_incomplete`-style dialog scoped to project Agent section |
| Open `/chat` (old link) | Route not registered; no redirect shim |
| `lastProject` id missing on disk | Fall back to `/home-v2` |

---

## Testing

| Area | Tests |
|------|-------|
| `ProjectProfileRepository` | round-trip JSON, default on create |
| `ProjectSkillLinkerService` | links under `standalone/projects/{id}/` |
| `prepareProjectLaunch` | `CONFIG_DIR` env per tool (at least claude + flashskyai + one mixed tool) |
| `SessionLifecycleService` | personal `prepareLaunch` without team |
| `HomeWorkspacePage` | personal scope lists only `teamId==''` |
| `ChatPage` | renders without `TeamConfig` for personal session |
| Router | no `/chat` route; `lastProject` startup |
| Delete | no imports of `context_sidebar` |

Run: `cd client && flutter analyze && flutter test --exclude-tags integration`

---

## Implementation Order (suggested)

1. **Data + layout**: `ProjectProfile`, `CliDataLayout` project paths, repositories.
2. **Launch**: `prepareProjectLaunch`, `SessionLifecycleService` branch, linker services.
3. **Hub removal**: router, delete ContextSidebar, startup mode.
4. **Home UI**: personal sidebar entry, `HomeWorkspacePersonalContent`.
5. **Project page**: personal rail + config sections; `ChatPage` personal path.
6. **Extensions**: `projectOverrides`.
7. **Tests + l10n** (`homeWorkspacePersonal`, `projectConfig`, etc.).

---

## Open Items (resolved)

| Item | Resolution |
|------|------------|
| CLI scope for personal | All `CliTool` values |
| Team project resources | Stay on `TeamConfig` (dual track B) |
| Hub | Hard delete |
