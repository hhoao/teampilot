# Naming rename: "项目/Project" → "工作区/Workspace" (UI text)

**Status:** Phase 1 ready to execute. Phase 2 deferred to the personal-identity-bundles refactor.
**Owner intent:** user finds the naming confusing — intuitively "工作区/Workspace = the directory you work in = a project". The home sidebar's identity section was already renamed back to **我的团队 / My Teams** (key `homeWorkspaceMyTeams`). This plan finishes the alignment by moving the word **工作区/Workspace** to the project/directory layer.

## Context an executing agent needs

The codebase uses the word `workspace` for **two different things**, and that is the root of the confusion:

| Layer | Code symbol | What it is |
|-------|-------------|------------|
| Directory you work in | `AppProject` | "where" you work — a folder |
| Reusable launch identity (team **or** personal) | `WorkspaceIdentity`, `HomeWorkspaceScope`, `homeWorkspace*` keys, `home_workspace_*` files, storage `workspace/projects/` | "who/how" — a config bundle |

After this rename, **user-facing 工作区/Workspace will mean the directory (`AppProject`)**, while **code still uses `workspace` for the identity layer**. This is a known, accepted temporary inversion — see Phase 2.

## Scope

### Phase 1 — IN SCOPE (this plan, mechanical, low-risk)
- **Only l10n string VALUES** in `client/lib/l10n/app_en.arb` and `client/lib/l10n/app_zh.arb`.
- Do **NOT** rename l10n keys (e.g. keep `homeWorkspaceAllProjects` as the key, change only its value). Renaming keys touches every Dart call site and belongs in Phase 2.
- The project enforces "l10n only, no hardcoded user-facing strings", so all user-visible text lives in the ARB files. As a safety net, also grep `client/lib` for stray hardcoded `项目` / `Project` in `Text(...)`/tooltips and report any found (do not silently change code literals — flag them).

### Phase 2 — DEFERRED (do NOT do here)
Fold into the `personal-identity-bundles` clean-break refactor, which already renames the identity concept toward `Identity` (`IdentityCubit`/`IdentityRepository` already exist; plan renames `TeamRepository→IdentityRepository`, etc.). At that time:
- Drop the "Workspace" prefix from the identity concept: `WorkspaceIdentity → Identity`, `HomeWorkspaceScope → ...`, rename `homeWorkspace*` keys, `home_workspace_*` files, and free `workspace`-named symbols for the directory layer.
- Rename the l10n **keys** containing `Project`/`Workspace` so keys match values again.
- Update `AGENTS.md` / `docs/*` terminology (they currently describe code where workspace = home/identity; leave untouched in Phase 1 to avoid lying about the code).

## Rename rule (apply to each string value)

Rename the word **only when it refers to `AppProject` (the working directory)**:
- zh: `项目` → `工作区`
- en: `Project` → `Workspace`, `project` → `workspace`, `projects` → `workspaces` (preserve original casing/plural)

## DO NOT TOUCH (false positives — "项目/item", or identity-layer labels)

| Key | Value | Why keep |
|-----|-------|----------|
| `fileTreeItemExists` | zh `同名项目已存在` | Here `项目` means **item/entry**, not a project. (Optional: clarify to `同名条目已存在`, but do NOT change to 工作区.) |
| `homeWorkspaceProjectTabKindPersonal` | zh `个人` / en `Personal` | This is an **identity** label, not a directory. Leave. |
| `homeWorkspaceDefaultPersonalProjectName` | zh `个人助手` / en built-in personal name | Identity label. Leave. |
| `homeWorkspaceMyTeams` | already `我的团队` / `My Teams` | Done. Do not revert. |

## REWRITE (don't blind-replace — would read awkwardly)

| Key | Current zh | Suggested zh | en note |
|-----|-----------|--------------|---------|
| `homeWorkspaceNewProjectSubtitle` | `选择项目的工作目录，并为它命名。` | `为工作区选择一个目录，并为它命名。` | en `Choose a working directory and name your project.` → `Choose a directory and name your workspace.` (avoid "workspace's working directory") |
| `homeWorkspaceNewProjectDirectoryLabel` | `项目目录` | `工作区目录` | `Project directory` → `Workspace directory` |

## Bulk INCLUDE list (apply the rename rule to the value)

zh + en, value-only. (Keys listed; the word to swap is obvious in each.)

```
visibilityFileTreeHint          # "项目文件树" → "工作区文件树" / "project file tree" → "workspace file tree"
workspaceEntryModeLastProject   # 恢复上次项目 → 恢复上次工作区 / Last project → Last workspace
projects                        # 项目 → 工作区 / Projects → Workspaces
newProject                      # 新建项目 → 新建工作区 / New Project → New Workspace
homeWorkspaceAllProjects        # 全部项目 → 全部工作区 / All projects → All workspaces
homeWorkspaceRecentlyClosedEmpty
homeWorkspaceTeamProjects       # 团队项目 → 团队工作区 / Projects → Workspaces
homeWorkspaceImportProject
homeWorkspaceEmptyProjects
homeWorkspaceEmptyProjectsHint
homeWorkspaceProjectSort
homeWorkspaceCreateProject
homeWorkspaceCloseProjectTitle
homeWorkspaceCloseProjectMessage   # both plural branches
homeWorkspaceProjectManagement
homeWorkspaceProjectList
homeWorkspaceProjectSettings
homeWorkspaceProjectId
homeWorkspaceNoConversations
homeWorkspaceFavoriteProject
homeWorkspaceRenameProject
homeWorkspaceCloneProject
homeWorkspaceCloneProjectFailed
projectAgentExtraArgsSubtitle      # 本项目 → 本工作区 / this project → this workspace
projectAdvancedSettingsSubtitle
projectAgentPromptSubtitle
projectAgentPromptPresetGeneralText  # two occurrences in the text
projectCliDefaultSubtitle
projectCliDefaultsSubtitle
projectCliEffortLevelSubtitle
projectSkillsAssignedCount
projectMcpAssignedCount
projectPluginsAssignedCount
projectPluginsEmptyHint
projectExtensionsTitle
projectExtensionsSubtitle
projectExtensionEffectiveOn
projectExtensionEffectiveOff
deleteProjectSubtitle
deleteProject
deleteProjectConfirm
newProjectTooltip
switchProjectTooltip
projectDirectoryAdded
projectDirectoryAlreadyPrimary
projectDirectoryAlreadyAdded
projectDetails
projectDetailsTitle
projectIconPickerTitle
windowsStorageBackendDescription   # "...项目..." → "...工作区..." (low priority; keep "teams/skills" wording)
windowsStorageBackendSwitchConfirmBody
```

> The agent must confirm each key exists in BOTH arb files and that values stay in sync. Source of truth is a fresh `grep -nE '项目|[Pp]roject' app_zh.arb app_en.arb` at execution time — this list reflects 2026-06-18 and may drift.

## Execution steps

1. Edit `client/lib/l10n/app_en.arb` and `client/lib/l10n/app_zh.arb` per the rule + lists above.
2. From `client/`: `flutter pub get` (regenerates `app_localizations*.dart`).
3. `dart run tool/gen_warmup_glyphs.dart` (new glyph `区`; refreshes `lib/widgets/warmup_glyphs.g.dart`). Commit the regenerated file.
4. Grep `client/lib` for stray hardcoded `项目`/`Project` user-facing strings; report (do not change code literals).
5. Verify: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`.
6. Manual golden-path check: home sidebar shows **我的团队**; project tabs / "新建工作区" / "工作区设置" / close-dialog all read "工作区"; the file-tree "同名…已存在" message is untouched.

## Acceptance
- No user-facing `项目`/`Project` referring to a directory remains (false positives in the DO-NOT-TOUCH table excluded).
- l10n keys unchanged; analyze + tests green; warmup glyphs regenerated.
- Phase 2 (code symbols, keys, docs) explicitly NOT done here.
