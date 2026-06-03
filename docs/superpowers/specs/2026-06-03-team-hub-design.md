# TeamHub Design

**Date:** 2026-06-03
**Status:** Approved (design); pending implementation plan

## Summary

TeamHub is a discovery surface for **public teams**, modeled on Apifox's "API Hub". From a
dedicated highlighted entry in the workspace-home sidebar, the user browses public team
templates (search + category filter + sort + favorites), opens a detail view to preview a
team's members and dependencies, then **clones** it into their local teams. Cloning
**auto-pulls** the team's referenced skill/plugin/MCP dependencies.

The feature reuses the existing Skills discovery/install architecture and is built behind a
`TeamHubSource` interface so the v1 git-registry data source can later be swapped for a
remote backend with no changes to the cubit or UI.

## Goals (v1)

- Sidebar entry that opens a TeamHub discovery view in the workspace-home right pane.
- Browse public teams with **search**, **category filter** (counts), **sort by name/time**.
- **Favorites** (local) — mark and filter favorite public teams.
- **Detail view** (embedded overlay in the right pane) previewing members + dependencies.
- **Clone** a public team into local `teams/`, auto-pulling its skill/plugin/MCP deps.

## Non-Goals (v1)

- No remote backend (designed for it via the source interface; not implemented).
- No view-count / star metrics (git source has no such data; interface reserves an
  optional `stats` field for a future backend).
- No user-facing "manage registries/repos" sub-section (a single built-in default
  registry is hardcoded, mirroring Skills' default repos).
- No publishing/sharing of the user's own teams (browse + clone only).

## Decisions (from brainstorming)

| Question | Decision |
|----------|----------|
| Data source | Reuse existing git-registry pattern now; **must stay extensible** to a remote backend later (→ `TeamHubSource` interface). |
| Core interaction | Browse → open **detail** → **clone**. |
| v1 features | Search, category filter, sort (name/time), favorites. |
| Sidebar placement | **Standalone highlighted entry** below "My Teams", above the divider (like Apifox API Hub). |
| Dependency handling on clone | **Auto-pull** referenced skills/plugins/MCP. |
| Partial dependency failure | **Non-blocking** — still create the team, report failed deps. |
| Detail page presentation | **Embedded overlay** in the right pane (no route push). |

## Architecture

```
Sidebar standalone entry (home_workspace_sidebar.dart)
  -> HomeWorkspaceGlobalView.teamHub  (new enum value)
  -> HomeWorkspaceGlobalSection renders TeamHubPage(section, onSelectSection)
      |- TeamHubSection { discovery, favorites }   (WorkspaceSectionDescriptor)
      |- Discovery view: search + category filter + sort + card grid
      |- Favorites view: locally-favorited public teams
      \- Detail overlay: members + dependency preview + "Clone" action

Data layer:
  TeamHubCubit  --watch-->  UI
     |- TeamHubSource (interface)            <- extensibility point
     |     \- GitRegistryTeamHubSource (v1)  -- reuses Skills git cache mechanism
     |- TeamHubFavoritesStore                -- team-hub/favorites.json
     \- TeamCloneService                     -- auto-pull orchestration
            |- SkillInstallService.installFromDiscovery()
            |- PluginInstallService.installFromDiscovery()
            |- McpRepository.add()  (inline config)
            \- TeamCubit.addTeam(name, cli, teamMode, members)
```

### Clone data flow

1. `TeamCloneService.clone(DiscoverableTeam, onProgress)` starts, emits progress.
2. Pre-scan dependencies: mark which skills/plugins are already installed locally (skip),
   which must be pulled; dedupe MCP deps by server id.
3. Pull each missing dependency via the matching install service; collect successes and
   `failedDeps`. **A single dependency failure does not abort the clone.**
4. MCP deps written inline to `McpRepository`, yielding `mcpServerId`s.
5. Build `TeamConfig` from resolved local ids + template members; call
   `TeamCubit.addTeam` (name collisions auto-resolved by `uniqueTeamId`).
6. On success, `TeamCubit.selectTeam` switches to the new team; close the detail overlay.
   Report `CloneResult { teamId, installedDeps[], failedDeps[] }` (snackbar / detail page:
   "Cloned; N dependencies could not be installed automatically").

## Data model

```dart
// Built-in default registry (v1 exposes no management UI)
class TeamHubRegistry { final String owner, name, branch; }

// One public team in a registry manifest (teams/<slug>/team.json)
class DiscoverableTeam {
  final String key;                 // unique discovery key = owner/name/slug
  final String name, description;
  final String category;            // drives left-side category filter
  final String? author;             // source attribution
  final int updatedAt;              // for "sort by time"
  final List<DiscoverableTeamMember> members;
  final TeamCli cli;
  final TeamMode teamMode;
  // ...other portable TeamConfig fields (extraArgs, loop, claude* etc.)
  final List<SkillDependencyRef> skillDeps;    // {repoOwner,repoName,branch,directory,name}
  final List<PluginDependencyRef> pluginDeps;  // same shape
  final List<McpDependencyRef> mcpDeps;        // inline MCP server config
  // final TeamHubStats? stats;     // reserved for future backend (views/stars)
}

// Portable subset of TeamMemberConfig (no local id/joinedAt)
class DiscoverableTeamMember {
  final String name, provider, model, agent, agentType, prompt, extraArgs;
}
```

**Key principle:** the template stores **dependency source descriptors**, not local ids.
Local ids only exist after `clone` resolves each descriptor via the install services. This
is what makes auto-pull work across machines.

### Registry / manifest layout

One git repo = one TeamHub registry. Repo structure:

```
index.json                  # lists teams: [{ slug, name, category, updatedAt }, ...]
teams/<slug>/team.json      # full DiscoverableTeam payload
```

## Data source & caching

```dart
abstract interface class TeamHubSource {
  Future<List<DiscoverableTeam>> fetchTeams({bool forceRefresh = false});
  Future<List<String>> categories();   // derived/deduped from teams' category
}

class GitRegistryTeamHubSource implements TeamHubSource {
  // Reuses the Skills git download + local cache approach
  // (mirrors SkillRepoDiskCacheService).
  // Cache dir: <teampilotRoot>/team-hub/cache/<owner>-<name>/
  // Reads index.json, then teams/<slug>/team.json.
}
```

- v1 hardcodes a default `TeamHubRegistry` (mirrors Skills' default repos); no
  registry-management UI.
- Cache lives at `<teampilotRoot>/team-hub/cache/`. Fetch on first load / manual refresh;
  otherwise read cache. Cached content is browsable offline.
- Switching to a backend later = add `RemoteApiTeamHubSource implements TeamHubSource`;
  cubit and UI unchanged.

## Clone service & error handling

```dart
class TeamCloneService {
  Future<CloneResult> clone(
    DiscoverableTeam team, {
    void Function(CloneProgress)? onProgress,
  });
}

class CloneResult {
  final String teamId;
  final List<String> installedDeps;
  final List<DependencyFailure> failedDeps;
}
```

- **Pre-check:** classify each dependency as already-installed (skip) vs to-pull; dedupe
  MCP by server id.
- **Pull:** install each dependency; a single failure is collected into `failedDeps` and
  does not abort — the team is still created.
- **Build:** construct `TeamConfig` from resolved local ids + template members → `addTeam`.
- **Feedback:** `CloneResult` surfaced to the detail page / snackbar.

**Error classes:**
- Network / registry fetch failure → l10n error message + retry affordance; diagnostics via
  `AppLogger`.
- Partial dependency failure → non-blocking; team created; failed items listed.
- Name collision → silently auto-renamed (`uniqueTeamId`); no interruption.

## UI

### Sidebar entry

In `home_workspace_sidebar.dart`, below the "My Teams" list and above the divider: a new
`_TeamHubEntry` widget — a standalone highlighted card with `Icons.travel_explore_outlined`,
title "TeamHub", and a subtitle ("Discover more public teams"), using the active-highlight
colors of `_ShortcutRow`. `HomeWorkspaceGlobalView` gains `teamHub`; the existing
`onSelectGlobalView` flow in `home_workspace_page.dart` is reused unchanged.

```
| My Teams (list)        |
|   + New Team           |
| +--------------------+ |
| | ◈ TeamHub          | |   <- standalone highlighted entry
| |   Discover teams   | |
| +--------------------+ |
| ----- divider -------- |
|  ⊕ Skills              |
|  ▣ Plugins             |
|  ⌗ MCP                 |
|  ⏻ Extensions          |
```

### TeamHubPage

Embedded in the right pane, reusing `WorkspaceAdaptiveSectionPage` +
`WorkspaceEnumNavPanel<TeamHubSection>`.

```
+----------+--------------------------------------------+
| Discovery|  [search public teams...]      [Sort: Name]|
| Favorites| +------+ +------+ +------+                  |
|          | | card | | card | | card |  <- card grid   |
| -Categs- | +------+ +------+ +------+                  |
|  All  12 | +------+ +------+                           |
|  AI    5 | | card | | card |                           |
+----------+--------------------------------------------+
```

- Left secondary nav: category list with counts (derived from `categories()`).
- Top bar: search box + sort (name / time).
- Cards reuse `SkillManagementCard` / `SkillCardHeader` styling: team name, description,
  member-count / skill-count chips, favorite star toggle. Tapping a card opens the detail
  overlay.
- Empty state uses `SkillEmptyBlock` (prompts refresh when no cache).

### Detail overlay

`TeamHubDetailPage` rendered as an **embedded overlay** in the right pane (with a back
affordance; no route push):

- Header: team name + description + source/category + favorite toggle.
- Preview sections: members (name/provider/model/agent), skill deps (marked local ✓
  installed / ⬇ to-pull), plugin deps, MCP deps.
- Primary action: **"Clone to my teams"** → triggers `TeamCloneService.clone`, shows
  progress, switches to the new team on completion.

## Favorites storage

`TeamHubFavoritesStore` persists `<teampilotRoot>/team-hub/favorites.json` (a list of
`DiscoverableTeam.key`). The Favorites view filters the discovery list by these keys.

## Testing

- `TeamHubCubit`: search / category / sort / favorite-toggle behavior with an injected fake
  `TeamHubSource`.
- `TeamCloneService`: injected fake install services + fake `TeamCubit`/repository; assert
  local-id mapping, partial-failure tolerance, and name-collision auto-rename.
- Tests touching `AppStorage` use `setUpTestAppStorage()` / `tearDownTestAppStorage()`.

## l10n

New keys in `app_en.arb` + `app_zh.arb`: `teamHubNav`, `teamHubSubtitle`,
`teamHubDiscovery`, `teamHubFavorites`, `teamHubClone`, `teamHubCloneSuccess`,
`teamHubClonePartial`, plus error strings. All user-visible text via l10n; diagnostics via
`AppLogger`.

## File-size / layering

- Thin page shell: `pages/team_hub/team_hub_page.dart`.
- Split Discovery / Favorites / Detail into separate section files under `pages/team_hub/`.
- `TeamHubCubit` target < 500 lines; clone orchestration lives in `TeamCloneService`.
- No `Process.run` or raw paths in UI; state via `flutter_bloc`; paths via `AppStorage` /
  `RuntimeStorageContext`.

## Affected / new files (indicative)

- New: `lib/models/discoverable_team.dart`, `lib/services/team_hub/team_hub_source.dart`,
  `git_registry_team_hub_source.dart`, `team_hub_favorites_store.dart`,
  `lib/services/team/team_clone_service.dart`, `lib/cubits/team_hub_cubit.dart`,
  `lib/pages/team_hub/team_hub_page.dart` (+ section/detail files),
  `lib/pages/team_hub/team_hub_section.dart`.
- Modified: `home_workspace_sidebar.dart` (entry), `home_workspace_global_section.dart`
  (enum + render), `app_shell.dart` (DI wiring), `app_en.arb` / `app_zh.arb`.
```
