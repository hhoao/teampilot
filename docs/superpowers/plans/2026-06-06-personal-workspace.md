# Personal Workspace (Independent Mode) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add personal workspace with project-scoped `ProjectProfile`, standalone CLI config under `config-profiles/standalone/projects/`, and remove Hub (`/chat` + `ContextSidebar`) so the project page is the sole work entry.

**Architecture:** Dual-track (B): personal projects (`teamId == ''`) use `ProjectProfile` + standalone config paths; team projects keep `TeamConfig` + `config-profiles/teams/`. `SessionLifecycleService.prepareLaunch` branches on `project.teamId.isEmpty`. Hub code deleted; startup becomes `home | lastProject`.

**Tech Stack:** Flutter/Dart (`client/`), `flutter_bloc`, `go_router`, existing `CliDataLayout` / `ConfigProfileService` / `TeamSkillLinkerService` patterns.

**Spec:** `docs/superpowers/specs/2026-06-06-personal-workspace-design.md`

---

## File map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `client/lib/models/project_profile.dart` | `ProjectProfile`, `ProjectAgentConfig` |
| Create | `client/lib/repositories/project_profile_repository.dart` | CRUD `projects/profiles/{id}.json` |
| Create | `client/lib/cubits/project_profile_cubit.dart` | Profile state + linker sync triggers |
| Create | `client/lib/services/skill/project_skill_linker_service.dart` | Standalone skills symlinks |
| Create | `client/lib/services/plugin/project_plugin_linker_service.dart` | Standalone plugins materialization |
| Create | `client/lib/services/cli/standalone_project_inherit_service.dart` | app → standalone project → session inheritance |
| Modify | `client/lib/services/cli/cli_data_layout.dart` | `standalone/projects/` path helpers |
| Modify | `client/lib/services/provider/config_profile_service.dart` | `prepareProjectLaunch` |
| Modify | `client/lib/services/cli/registry/config_profile/config_profile_scope.dart` | `StandaloneLaunchProfileScope` |
| Modify | `client/lib/services/cli/registry/config_profile/*_config_profile_capability.dart` | All 5 `CliTool` personal launch branches |
| Modify | `client/lib/services/session/session_lifecycle_service.dart` | Personal `prepareLaunch` branch |
| Modify | `client/lib/models/extension_state.dart` | `projectOverrides` |
| Modify | `client/lib/models/layout_preferences.dart` | `lastProject` entry mode + `lastOpenedProjectId` |
| Modify | `client/lib/router/app_router.dart` | Remove Hub shell; config-only shell for `/config` |
| Delete | `client/lib/widgets/context_sidebar.dart` + `context_sidebar/*` | Hub sidebar |
| Modify | `client/lib/pages/chat_page.dart` | Personal mode without `TeamConfig` |
| Create | `client/lib/pages/home_workspace/home_workspace_personal_content.dart` | Personal project grid pane |
| Modify | `client/lib/pages/home_workspace/home_workspace_page.dart` | `HomeWorkspaceScope.personal` |
| Modify | `client/lib/pages/home_workspace/home_workspace_sidebar.dart` | Personal workspace row |
| Modify | `client/lib/pages/home_workspace/project/home_workspace_project_section.dart` | Personal rail sections |
| Modify | `client/lib/pages/home_workspace/project/home_workspace_project_rail.dart` | Personal vs team items |
| Modify | `client/lib/pages/home_workspace/project/home_workspace_project_page.dart` | Rail section bodies |
| Create | `client/lib/pages/home_workspace/project/config/*.dart` | Agent, skills, plugins, MCP, extensions sections |
| Modify | `client/lib/pages/home_workspace/home_workspace_new_project_dialog.dart` | Personal create + profile |
| Modify | `client/lib/cubits/chat/session_launch_service.dart` | Pass `ProjectProfile` for personal tabs |
| Modify | `client/lib/app/app_shell.dart` | Register `ProjectProfileCubit` / repository |
| Modify | `client/lib/l10n/app_en.arb`, `app_zh.arb` | New strings |
| Tests | `client/test/**` | See tasks below |

---

### Task 1: `ProjectProfile` model + repository

**Files:**
- Create: `client/lib/models/project_profile.dart`
- Create: `client/lib/repositories/project_profile_repository.dart`
- Create: `client/test/repositories/project_profile_repository_test.dart`
- Modify: `client/test/support/post_frame_test_harness.dart` (if temp dirs needed)

- [ ] **Step 1: Write failing repository test**

```dart
// client/test/repositories/project_profile_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/project_profile.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/project_profile_repository.dart';

void main() {
  test('save and load round-trip', () async {
    final repo = ProjectProfileRepository(rootDir: tempDir);
    const profile = ProjectProfile(
      projectId: 'p1',
      cli: CliTool.claude,
      agent: ProjectAgentConfig(model: 'sonnet'),
      updatedAt: 1,
    );
    await repo.save(profile);
    final loaded = await repo.load('p1');
    expect(loaded?.cli, CliTool.claude);
    expect(loaded?.agent.model, 'sonnet');
  });

  test('createDefault seeds claude and empty resource lists', () async {
    final repo = ProjectProfileRepository(rootDir: tempDir);
    final profile = await repo.createDefault('p-new');
    expect(profile.skillIds, isEmpty);
    expect(profile.cli, CliTool.claude);
  });
}
```

- [ ] **Step 2: Run test — expect FAIL**

```bash
cd client && flutter test test/repositories/project_profile_repository_test.dart
```

- [ ] **Step 3: Implement model + repository**

`ProjectProfile` fields per spec. Store at `{appProjectsDir}/profiles/{projectId}.json`.

- [ ] **Step 4: Run test — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/project_profile.dart client/lib/repositories/project_profile_repository.dart client/test/repositories/project_profile_repository_test.dart
git commit -m "feat: add ProjectProfile model and repository"
```

---

### Task 2: `CliDataLayout` standalone paths

**Files:**
- Modify: `client/lib/services/cli/cli_data_layout.dart`
- Create: `client/test/services/cli/cli_data_layout_standalone_test.dart`

- [ ] **Step 1: Write failing path tests**

```dart
test('standaloneProjectSessionToolDir', () {
  final layout = CliDataLayout(teampilotRoot: '/tp');
  expect(
    layout.standaloneProjectSessionToolDir('proj', 'sess', 'claude'),
    '/tp/config-profiles/standalone/projects/proj/sessions/sess/claude',
  );
});
```

- [ ] **Step 2: Run — FAIL**

- [ ] **Step 3: Add helpers**

Implement per spec table: `standaloneProjectsDir`, `standaloneProjectDir`, `standaloneProjectToolDir`, `standaloneProjectSkillsDir`, `standaloneProjectPluginsDir`, `standaloneProjectMcpDir`, `standaloneProjectSessionToolDir`.

Update module doc comment tree to include `standalone/projects/`.

- [ ] **Step 4: Run — PASS**

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(cli): add standalone project paths to CliDataLayout"
```

---

### Task 3: Standalone inheritance + linkers

**Files:**
- Create: `client/lib/services/cli/standalone_project_inherit_service.dart`
- Create: `client/lib/services/skill/project_skill_linker_service.dart`
- Create: `client/lib/services/plugin/project_plugin_linker_service.dart`
- Create: `client/test/services/skill/project_skill_linker_service_test.dart`

- [ ] **Step 1: Test skill linker writes under standalone/projects/{id}/flashskyai/skills/**

Mirror `TeamSkillLinkerService` but target `layout.standaloneProjectSkillsDir(projectId)`.

- [ ] **Step 2: Implement `StandaloneProjectInheritService`**

`ensureStandaloneProjectInheritsApp(projectId, tool)` — symlink/copy `app/{tool}/agents|skills` → `standalone/projects/{projectId}/{tool}/`.

`ensureStandaloneSessionInheritsProject(projectId, sessionId, tool)` — project → `sessions/{sessionId}/{tool}/`.

- [ ] **Step 3: Implement plugin linker** (flashskyai tool dir; mirror team plugin linker paths)

- [ ] **Step 4: Run linker tests — PASS**

- [ ] **Step 5: Commit**

```bash
git commit -m "feat: standalone project skill/plugin linkers and inheritance"
```

---

### Task 4: `prepareProjectLaunch` + launch scope

**Files:**
- Modify: `client/lib/services/cli/registry/config_profile/config_profile_scope.dart`
- Modify: `client/lib/services/provider/config_profile_service.dart`
- Create: `client/test/services/provider/config_profile_service_standalone_test.dart`

- [ ] **Step 1: Add `StandaloneLaunchProfileScope`**

```dart
class StandaloneLaunchProfileScope {
  const StandaloneLaunchProfileScope({
    required this.projectId,
    required this.sessionId,
  });
  final String projectId;
  final String sessionId;
}
```

- [ ] **Step 2: Write failing test for `prepareProjectLaunch`**

Assert `CLAUDE_CONFIG_DIR` (or tool-specific env) points to `standalone/projects/{projectId}/sessions/{sessionId}/claude`.

- [ ] **Step 3: Implement `prepareProjectLaunch`**

Parallel to `prepareTeamLaunch`:
1. `ensureStandaloneSessionInheritsProject`
2. `ensureSessionProfile` variant keyed by `(projectId, sessionId)` not teamId
3. Delegate to `cap.contributeLaunch` with standalone scope

Add `ensureStandaloneProjectProfile(projectId, sessionId, cli, profile, extraMcpServers)`.

- [ ] **Step 4: Run test — PASS**

- [ ] **Step 5: Commit**

```bash
git commit -m "feat: ConfigProfileService.prepareProjectLaunch for standalone projects"
```

---

### Task 5: All `CliTool` capabilities — standalone branch

**Files:**
- Modify: `client/lib/services/cli/registry/config_profile/claude_config_profile_capability.dart`
- Modify: `client/lib/services/cli/registry/config_profile/flashskyai_config_profile_capability.dart`
- Modify: `client/lib/services/cli/registry/config_profile/codex_config_profile_capability.dart`
- Modify: `client/lib/services/cli/registry/config_profile/cursor_config_profile_capability.dart`
- Modify: `client/lib/services/cli/registry/config_profile/opencode_config_profile_capability.dart` (if exists)
- Modify: `client/lib/services/cli/registry/config_profile/config_profile_context.dart` — add `standaloneSessionToolDir`
- Extend tests per tool (at minimum: claude, flashskyai, cursor)

- [ ] **Step 1: Extend `ConfigProfileLaunchContext` with optional `standaloneScope` + `ProjectProfile`**

When `standaloneScope != null`, resolve paths via `layout.standaloneProjectSessionToolDir` and use `profile.agent` as the single member stand-in.

- [ ] **Step 2: Implement standalone branch in each capability**

No TeamBus, no mixed member nesting, no `teamId` requirement.

- [ ] **Step 3: Run targeted tests**

```bash
cd client && flutter test test/services/cli/config_profile/ test/services/provider/config_profile_service_standalone_test.dart
```

- [ ] **Step 4: Commit**

```bash
git commit -m "feat: standalone launch support for all CliTool capabilities"
```

---

### Task 6: `SessionLifecycleService` personal branch

**Files:**
- Modify: `client/lib/services/session/session_lifecycle_service.dart`
- Modify: `client/lib/cubits/chat/session_launch_service.dart`
- Create: `client/test/services/session/session_lifecycle_standalone_test.dart`

- [ ] **Step 1: Write failing test**

Personal `AppSession` (`sessionTeam == ''`) + personal `AppProject` → `prepareLaunch` returns non-empty env without `TeamConfig`.

- [ ] **Step 2: Branch in `prepareLaunch`**

```dart
final project = await resolveProject(session.projectId);
if (project.teamId.isEmpty) {
  final profile = await projectProfileRepository.loadOrCreate(project.projectId);
  // prepareProjectLaunch(profile.cli, profile.agent, ...)
  return LaunchPlan(...);
}
// existing team path
```

- [ ] **Step 3: Update `session_launch_service` / `openSessionTab`**

Personal sessions: no `team` / `member` required; synthesize a `TeamMemberConfig` from `profile.agent` + `profile.cli` for workbench only.

- [ ] **Step 4: Run tests — PASS**

- [ ] **Step 5: Commit**

```bash
git commit -m "feat: personal session launch via prepareProjectLaunch"
```

---

### Task 7: `ExtensionState.projectOverrides`

**Files:**
- Modify: `client/lib/models/extension_state.dart`
- Modify: `client/lib/services/provider/config_profile_infrastructure.dart` (extension hooks: accept `projectId`)
- Create: `client/test/models/extension_state_test.dart` (extend or create)

- [ ] **Step 1: Add `projectOverrides` JSON + `effectiveEnabledForProject`**

- [ ] **Step 2: Wire `loadEnabledExtensionIds(projectId: ...)` in lifecycle for personal launch**

- [ ] **Step 3: Test round-trip + precedence (project override > global)**

- [ ] **Step 4: Commit**

```bash
git commit -m "feat: extension projectOverrides for personal projects"
```

---

### Task 8: Remove Hub — router + delete `ContextSidebar`

**Files:**
- Delete: `client/lib/widgets/context_sidebar.dart`, `client/lib/widgets/context_sidebar/*`
- Modify: `client/lib/router/app_router.dart`
- Modify: `client/lib/pages/chat_page.dart` (remove `ActiveSessionChatPage` or relocate)
- Modify: `client/test/widget_test.dart`, `client/test/router/onboarding_gate_routing_test.dart`

- [ ] **Step 1: Remove `/chat` routes and Hub `ShellRoute`**

Keep a minimal shell for `/config`, `/team-config`, `/providers`, etc. without `ContextSidebar`. Project work only under `/home-v2/project/:id`.

- [ ] **Step 2: Delete all `context_sidebar` files**

`rg context_sidebar client` must return zero imports.

- [ ] **Step 3: Fix tests that `go('/chat')`**

Use `/home-v2/project/{fixtureProjectId}` with test harness project.

- [ ] **Step 4: Run analyzer**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

- [ ] **Step 5: Commit**

```bash
git commit -m "refactor: remove Hub /chat route and ContextSidebar"
```

---

### Task 9: Startup `WorkspaceEntryMode.lastProject`

**Files:**
- Modify: `client/lib/models/layout_preferences.dart`
- Modify: `client/lib/cubits/layout_cubit.dart`
- Modify: `client/lib/router/app_router.dart` (`applyWorkspaceEntryMode`)
- Modify: `client/lib/pages/config/appearance_config_section.dart`
- Modify: `client/lib/app/app_shell.dart`
- Modify: `client/lib/pages/home_workspace/home_workspace_shell.dart` (record `lastOpenedProjectId` on project visit)

- [ ] **Step 1: Replace `hub` with `lastProject` in enum + JSON**

Unknown persisted `hub` → treat as `home` (no migration UI).

- [ ] **Step 2: Add `lastOpenedProjectId` to `LayoutPreferences`**

Update when navigating to `/home-v2/project/:id`.

- [ ] **Step 3: Update appearance toggle** — labels: 主页 / 恢复上次项目

- [ ] **Step 4: l10n** `workspaceEntryModeLastProject`

- [ ] **Step 5: Test router initial location**

- [ ] **Step 6: Commit**

```bash
git commit -m "feat: replace hub startup with lastProject entry mode"
```

---

### Task 10: `ProjectProfileCubit` + app shell DI

**Files:**
- Create: `client/lib/cubits/project_profile_cubit.dart`
- Modify: `client/lib/app/app_shell.dart`
- Create: `client/test/cubits/project_profile_cubit_test.dart`

- [ ] **Step 1: Cubit loads/saves profile, calls linkers on skillIds/pluginIds change**

- [ ] **Step 2: Register in `app_shell` alongside `TeamCubit`**

- [ ] **Step 3: Tests — PASS**

- [ ] **Step 4: Commit**

---

### Task 11: Home UI — personal workspace

**Files:**
- Create: `client/lib/pages/home_workspace/home_workspace_personal_content.dart`
- Modify: `client/lib/pages/home_workspace/home_workspace_page.dart`
- Modify: `client/lib/pages/home_workspace/home_workspace_sidebar.dart`
- Modify: `client/lib/l10n/app_en.arb`, `app_zh.arb`

- [ ] **Step 1: Add `HomeWorkspaceScope.personal` state to `HomeWorkspacePage`**

- [ ] **Step 2: Sidebar row「个人工作区」** — selects personal scope, clears team/global/library selection

- [ ] **Step 3: `HomeWorkspacePersonalContent`** — heading + `HomeWorkspaceProjectsTab` filtered `teamId.isEmpty`

- [ ] **Step 4: Widget test or cubit-level filter test**

- [ ] **Step 5: Commit**

```bash
git commit -m "feat: personal workspace sidebar and project grid"
```

---

### Task 12: Personal project creation

**Files:**
- Modify: `client/lib/pages/home_workspace/home_workspace_new_project_dialog.dart`
- Modify: `client/lib/cubits/chat/session_data_store.dart` (`createProjectWithFirstSession`)
- Modify: `client/lib/repositories/session_repository.dart` (optional: hook profile create)

- [ ] **Step 1: When `sessionTeamId == ''`, call `projectProfileRepository.createDefault(projectId)`**

- [ ] **Step 2: Personal workspace toolbar passes `teamId: ''`**

- [ ] **Step 3: Integration test: create personal project → profile file exists**

- [ ] **Step 4: Commit**

---

### Task 13: Project page — personal rail + config sections

**Files:**
- Modify: `client/lib/pages/home_workspace/project/home_workspace_project_section.dart`
- Modify: `client/lib/pages/home_workspace/project/home_workspace_project_rail.dart`
- Modify: `client/lib/pages/home_workspace/project/home_workspace_project_page.dart`
- Create: `client/lib/pages/home_workspace/project/config/project_agent_section.dart`
- Create: `client/lib/pages/home_workspace/project/config/project_skills_section.dart`
- Create: `client/lib/pages/home_workspace/project/config/project_plugins_section.dart`
- Create: `client/lib/pages/home_workspace/project/config/project_mcp_section.dart`
- Create: `client/lib/pages/home_workspace/project/config/project_extensions_section.dart`

- [ ] **Step 1: Extend `HomeWorkspaceProjectSection` enum** — agent, skills, plugins, mcp, extensions (personal only visibility)

- [ ] **Step 2: Team project rail** — conversations, settings, teamConfig shortcut (`go('/home-v2?section=skills')` etc.)

- [ ] **Step 3: Personal sections** — reuse patterns from `team_config_*_section.dart` but bind `ProjectProfileCubit`

- [ ] **Step 4: `HomeWorkspaceConversationPanel._addConversation`** — personal: `sessionTeamId: ''`, `rosterMembers: []`

- [ ] **Step 5: Commit**

```bash
git commit -m "feat: personal project rail and config sections"
```

---

### Task 14: `ChatPage` personal mode

**Files:**
- Modify: `client/lib/pages/chat_page.dart`
- Modify: `client/lib/pages/home_workspace/project/home_workspace_conversation_panel.dart`

- [ ] **Step 1: Accept personal context** — `team == null` + personal project → render workbench

- [ ] **Step 2: Hide `_chatActions` team buttons when personal**

- [ ] **Step 3: `openSessionTab` without team for personal sessions**

- [ ] **Step 4: Widget test: personal project page builds without `TeamCubit.selectedTeam` blocking**

- [ ] **Step 5: Commit**

```bash
git commit -m "feat: ChatPage personal mode without TeamConfig"
```

---

### Task 15: Final verification + docs

**Files:**
- Modify: `docs/DEVELOPMENT.md` or `AGENTS.md` (brief note on standalone layout) — optional one paragraph
- Modify: `client/lib/services/cli/cli_data_layout.dart` doc (done in Task 2)

- [ ] **Step 1: Full test suite**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration
```

- [ ] **Step 2: Grep sanity**

```bash
rg "context_sidebar|WorkspaceEntryMode\.hub|go\\('/chat" client
```

Expected: no matches (except changelog if any).

- [ ] **Step 3: Manual smoke**

1. Open app → 个人工作区 → 新建项目 → 打开 → 新建对话 → terminal starts  
2. Agent tab: change model → relaunch works  
3. Skills tab: enable skill → config dir contains symlink  
4. Team project unchanged: team home tabs + team launch still works  

- [ ] **Step 4: Commit any remaining l10n / doc tweaks**

```bash
git commit -m "chore: personal workspace l10n and verification"
```

---

## Dependency graph

```
Task 1 → Task 10 → Task 11, 12, 13
Task 2 → Task 3 → Task 4 → Task 5 → Task 6
Task 7 → Task 5 (extensions at launch)
Task 8, 9 — can parallelize after Task 6 (router needs project routes working)
Task 14 — after Task 6 + 13
Task 15 — last
```

## Risk notes

| Risk | Mitigation |
|------|------------|
| Large `app_router.dart` refactor breaks config routes | Extract config `ShellRoute` without sidebar before deleting Hub shell |
| `ChatPage` tightly coupled to team | Pass `isPersonalProject` from project page; minimal surface change |
| Five CLI capabilities diverge | Implement claude + flashskyai first in Task 5, then codex/opencode/cursor in same task before merge |
| Android drawer used Hub sidebar | Use project page navigation from home; verify `AndroidShellChrome` paths |
