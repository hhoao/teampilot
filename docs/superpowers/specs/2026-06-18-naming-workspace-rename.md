# Naming model: Workspace → Projects → Teams (orthogonal)

**Status:** Phase 1 superseded. UI realigned 2026-06-18 to the three-layer model below.
**Previous plan** (Project→Workspace for directories) is **reverted** — it contradicted the intended product vocabulary.

## Target vocabulary (user intent)

| Layer | zh | en | Code (current → target) | What it is |
|-------|----|----|---------------------------|------------|
| **Workspace** | 工作区 | Workspace | `HomeWorkspacePage`, `WorkspaceLayout.workspaceDir`, disk `{root}/workspace/` | Container holding **multiple** projects (Apifox-style home). Not a team. |
| **Project** | 项目 | Project | `AppProject`, `projectId`, `workspace/projects/{id}/` | **One** working directory (+ optional additional dirs). Where files and sessions live. |
| **Team / Personal** | 团队 / 个人 | Team / Personal | `TeamIdentity`, `PersonalIdentity`, `WorkspaceIdentity` → **`Identity`** | Launch identity (who/how). **Orthogonal** to workspace — not “inside” or “owned by” workspace. |

Relationships:

```
Workspace (工作区)          Team (团队) — separate axis
  ├── Project A (目录)        └── used when launching a project (?as=teamId)
  ├── Project B
  └── Project C
```

- Opening a **project** tab = one directory workbench.
- **Team** picks roster/CLI bundle for a session; teams are listed in the sidebar, not nested under workspace in the data model.
- Disk layout already matches: `{teampilotRoot}/workspace/projects/{projectId}/`.

## UI string rules (l10n values)

### Use **项目 / Project** when referring to `AppProject`

Examples: 新建项目, 项目设置, 本项目, 关闭项目, 项目目录, project file tree, delete project.

### Use **工作区 / Workspace** only for the **container / home**

Examples: title-bar home chip (`homeWorkspaceMainWindow`), app-level “workspace home”, storage area that holds many projects (if mentioned in copy). **Do not** label a single directory as 工作区.

### Use **团队 / Team** (or **个人 / Personal**) for identities

Examples: 我的团队, 创建团队, 团队设置, 团队代理. **Never** “工作区团队” or “solo workspace” — use 单人团队 / solo team.

### False positives (keep)

| Key | zh | Why |
|-----|-----|-----|
| `fileTreeItemExists` | 同名项目已存在 | 项目 = list item, not `AppProject` |
| `sshDefaultWorkingDirectoryTitle` | SSH 默认**工作目录** | 远端 cwd，不是 AppProject |

## Phase 1 (done) — l10n realignment

- Reverted directory strings from erroneous 工作区 back to **项目**.
- Fixed team/solo/session strings that mixed workspace + team.
- `homeWorkspaceMainWindow`: **工作区 / Workspace** (container home tab).
- Kept `homeWorkspaceMyTeams`: **我的团队 / My Teams**.

## Phase 2 — code symbols (deferred, `personal-identity-bundles`)

Priority order:

### P0 — Free “workspace” for the container; keep “project” for directory

| Current | Target | Notes |
|---------|--------|-------|
| `AppProject` | **keep** (or `AppProject` alias until disk migration) | Already matches 项目 |
| `WorkspaceIdentity` | `Identity` | Team/personal; drop Workspace prefix |
| `HomeWorkspacePage/Shell/Sidebar` | `WorkspaceHome*` or `HomePage` | Container UI |
| `home_workspace/project/*` | `workspace_home/project/*` or `project/*` | Directory workbench |

### P0 — Stop calling teams “workspace”

| Current | Target |
|---------|--------|
| `homeWorkspaceNewSoloNameHint` key | rename to `…TeamNameHint` |
| Comments “workspace identity” | “launch identity” / “team or personal” |

### P1 — Layout scaffold disambiguation

| Current | Target |
|---------|--------|
| `WorkspaceShell` (per-project workbench chrome) | `ProjectWorkbenchShell` |
| `WorkspaceHub*` (settings layout kit) | `SettingsHub*` |
| `SessionConfigWorkspace` | `SessionConfigPage` |

### P2 — l10n keys

Rename keys so `homeWorkspace*Project*` values say Project and `*Workspace*` keys mean container only.

### P2 — docs

Update `AGENTS.md` terminology table to match this spec.

## Acceptance (Phase 1)

- User-facing: single directory = 项目; home/container tab = 工作区; team = 团队.
- No user-facing 工作区 referring to one directory.
- No “工作区团队” / “solo workspace”.
- `flutter analyze` + unit tests green.

## Manual check

- Title bar: home chip **工作区**; project tabs show project names.
- Sidebar: **全部项目**, **我的团队**.
- New project dialog: **项目目录**, 创建项目.
- Team settings subtitle: **团队代理**, not 工作区团队.
