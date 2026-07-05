# Expert Hub (Member Discovery) design

**Date:** 2026-07-05  
**Status:** Approved (2026-07-05)

## Summary

Add an **Expert Hub** (专家中心) — a WorkBuddy Expert Center–style discovery surface for TeamPilot **members** (`TeamMemberConfig` / `DiscoverableMember`). Users browse, favorite, and summon expert personas; clone them into team rosters; and save/share local templates. Expert Hub complements the existing **Team Hub** (whole-team templates).

## Goals

| Goal | Description |
|------|-------------|
| Discover | Browse/search members by category; built-in, registry, team-extracted, and local sources |
| Summon | Workspace landing: Personal-only expert overlay for one-shot sessions |
| Clone | Main window: add expert to an existing team roster |
| Own | Favorites, local templates, export/import, future registry publish |

## Non-goals (v1)

- Leaderboard / popularity metrics (defer)
- In-app registry publish wizard (v2; document manual PR flow first)
- Expert summon in team-mode landing or multi-member partial connect
- Replacing Team Hub or merging into a single Discovery page

## Concept mapping

| WorkBuddy | TeamPilot |
|-----------|-----------|
| Expert | `DiscoverableMember` → `TeamMemberConfig` |
| Expert Team | `DiscoverableTeam` (Team Hub) |
| Summon | Session-scoped role overlay (Personal) |
| My experts | Local templates + favorites |

## Architecture

### Approach

**Independent Expert Hub page** (`HomeGlobalView.expertHub`), parallel to Team Hub. Reuses Team Hub UI patterns (grid, search, filter chips, detail overlay, favorites store). Team Hub gains cross-links to indexed members.

### Services

```
CompositeExpertHubSource
  ├─ BuiltinMemberTemplates      (client/lib/services/expert_hub/builtin_member_templates.dart)
  ├─ GitMemberHubSource          (mirror TeamHubSource → flashskyai/member-hub)
  ├─ TeamMemberIndexSource       (denormalize DiscoverableTeam.members from TeamHub fetch)
  └─ LocalMemberTemplateStore    (<teampilotRoot>/member-hub/local-templates/*.json)

ExpertHubFavoritesStore          (<teampilotRoot>/member-hub/favorites.json)
ExpertHubRecentStore             (<teampilotRoot>/member-hub/recent.json, landing picker)
MemberCloneService               (addToTeam, export, import; reuse TeamCloneService dep installers)
ExpertHubCubit                   (mirror TeamHubCubit)
```

### Model: `DiscoverableMember`

Extends the portable shape of `DiscoverableTeamMember` with catalog metadata:

```dart
DiscoverableMember {
  key              // teampilot/builtin/architect | owner/repo/slug | local/{uuid} | {teamKey}#{slug}
  name, description, category, author?, updatedAt
  tags[]           // search
  member           // prompt, playbook, capabilities, cli, provider, model, agent, replicas, extraArgs
  skillDeps[]      // optional; clone/add prompts install like Team Hub
  source           // builtin | registry | teamExtract | local
  originTeamKey?   // when source == teamExtract
}
```

**Key collision policy:** composite keys are namespaced by source prefix. Team-extracted members use `{teamKey}#{memberSlug}` and are deduped in UI when prompt+playbook hash matches a registry entry (prefer registry entry, show “also in team X” link).

### Personal summon: session overlay

Extend compose/launch pipeline without mutating `PersonalProfile`:

1. `LandingLaunchContext.expertKey` — optional; persisted in `LandingPrefsStore` per workspace.
2. `SessionCreateRequest.expertOverlay` — resolved `DiscoverableMember` snapshot at create time.
3. `SessionLifecycleService` / `MemberRoleProvision` — merge overlay `prompt` + `playbook` into the personal agent role body for **this session only** via the same path used for team members: `MemberRoleProvision.composeRolePrompt` → session-scoped `role.md` / CLI append-system-prompt file.
4. `AppSession` stores `expertKey` (optional) for display/debug; overlay text is snapshotted at create so registry changes do not affect open sessions.

Team-mode landing **does not** expose expert chip. Deep link `?expert=` on a team-profile landing shows a toast and ignores the param.

### Add to team

`MemberCloneService.addToTeam(teamId, member)`:

1. Resolve `DiscoverableMember` → `TeamMemberConfig` (new slug id from name; `joinedAt` now).
2. Optional: prompt to install skill deps (same UX as Team Hub clone partial success).
3. `LaunchProfileCubit.addMember` (or equivalent persist API).
4. Does not auto-start a session.

### Launch from main window

1. User picks workspace in dialog.
2. Navigate `/home-v2/workspace/:workspaceId?expert=:key`.
3. `WorkspaceLandingContextCubit` / landing resolver pre-selects expert; forces Simple mode.
4. User types message → `submitWorkspaceLandingMessage` with overlay.

## UI reference patterns (Team Hub, Skills, Plugins, MCP)

Expert Hub is **discovery-first** like Team Hub, not a multi-route library like Skills. The spec explicitly maps which existing shells and widgets to reuse so the feature feels native in the home workspace.

### Pattern choice: Team Hub shell (primary)

| Concern | Follow | Reference |
|---------|--------|-----------|
| Page shape | **Single-page** search + filter chips + grid + embedded detail overlay — **no** left sub-nav routes | `TeamHubPage`, `TeamHubBody`, `TeamHubDetailOverlay` |
| Title bar | `WorkspaceHubTitleBar` when list; hidden when detail overlay (back in overlay header) | `team_hub_page.dart` |
| Android embed | `useAndroidHubNavigation` → `WorkspaceSectionPage` with zero padding | `team_hub_page.dart` |
| Desktop embed | `Column` + title bar + `Expanded(pane)` inside `HomeGlobalSection` | same |
| Grid | `GridView` `maxCrossAxisExtent: 380`, `mainAxisExtent: 186`, spacing 14 | `TeamHubBody` |
| Filter bar | Inline chips: favorites toggle + category single-select | `TeamHubBody._FilterBar` |
| Empty / error | `EmptyStateBlock` + refresh action | `TeamHubBody` |
| Favorites | `ExpertHubFavoritesStore` + per-card star toggle | `TeamHubFavoritesStore`, `TeamHubCard` |
| Clone feedback | Toast helpers for partial dep failure | `team_hub_clone_feedback.dart` → `member_hub_add_feedback.dart` |
| Busy state | `cloningKeys` / `addingKeys` set on cubit | `TeamHubCubit` |

**Why not Skills’ 3-section nav** (`installed` / `discovery` / `repos`)? Skills manage **installed artifacts + registry sources**. Expert Hub’s “my templates” and favorites are lighter-weight filters on one catalog (same as Team Hub favorites), not a separate installed-inventory lifecycle. **My templates** = filter chip (`source == local`), not a `/expert-hub/installed` route.

### Pattern borrowings: Skills / Plugins / MCP (secondary)

| Concern | Follow | Reference |
|---------|--------|-----------|
| Card chrome | `workspaceCardDecoration` via shared bordered shell | `TeamHubWorkspaceCard` (documents parity with `SkillManagementCard`, `McpWorkspaceCard`) |
| Detail header | `TeamHubCardHeader` + `ManagementCardHeader` | `team_hub_cards.dart` |
| Identity tile | `TeamMonogram` (seed = member `key`) | `team_hub_visuals.dart` |
| Stat chips | `TeamStatChip` for capabilities count, skill deps | `TeamHubDetailOverlay` |
| Skill dep badges | `installedDepIds` from cubit; per-dep installed / will-install | `TeamHubDetailOverlay`, `TeamHubCubit.installedDepIdsLoader` |
| Search debounce | 400ms debounce on filter text | `SkillDiscoverySection` |
| Filter card wrapper | Optional: discovery filters inside a `SkillManagementCard` when adding source toggles later | `skill_discovery_section.dart` |
| Global embed | Registered on `HomeGlobalView.expertHub` like `teamHub`, `skills`, `mcp` | `home_workspace_global_section.dart`, sidebar `_ShortcutRow` |
| Standalone route (future) | If `/expert-hub` deep route is added later, mirror `SkillManagementPage` + `WorkspaceAdaptiveSectionPage` | `skill_management_page.dart` |

### Landing compose (workspace)

Landing was refactored into focused modules; Expert chip integrates there — **not** a full hub page.

| Concern | Follow | Reference |
|---------|--------|-----------|
| Toolbar chips | `_ToolbarMenuChip` / `SidebarActionMenuSpec` | `workspace_chat_landing_compose_card.dart` |
| Selector helpers | Shared label/resolver patterns | `workspace_landing_selectors.dart` |
| Palette tokens | `_LandingPalette` | `workspace_chat_landing_palette.dart` |
| Inline picker | Bottom sheet or anchored menu: compact list (search + favorites + recent), not full grid | lighter than `TeamHubBody` |
| “Browse all” | `onSelectGlobalView(HomeGlobalView.expertHub)` or `context.go(expertHub.homeLocation)` | `home_workspace_page.dart` global pane switch |

### Team Hub cross-links

| Concern | Follow | Reference |
|---------|--------|-----------|
| Member rows in team detail | Link row → Expert Hub detail with `originTeamKey` | `TeamHubDetailOverlay` member list |
| Expert detail origin | Back-link to Team Hub detail overlay | symmetric deep-link or cubit-held `originTeamKey` |

### Explicit non-reuse (v1)

- **No** `WorkspaceHubPage` hub chooser (Skills/Plugins use that only for `/skills` root before picking a section).
- **No** separate `repos` / registry-management section (registry URL is built-in default; custom registries defer to v2).
- **No** `WorkspaceEnumNavPanel` left rail unless v2 adds “Installed in teams” inventory.

## UI

### Main window — Expert Hub

- **Route:** `HomeGlobalView.expertHub` → `/home-v2?global=expertHub`
- **Sidebar:** new shortcut under Team Hub (“专家中心” / Expert Hub), same `_ShortcutRow` pattern as Team Hub / Skills entries
- **Page shell:** `ExpertHubPage` structurally identical to `TeamHubPage` (list ↔ detail overlay state machine)
- **Body:** `ExpertHubBody` — search + sort + filter chips (Favorites | categories | **My templates** | **From teams**) + card grid
- **Card:** `ExpertHubCard` — clone `TeamHubCard` API (`member`, `favorited`, `busy`, `onTap`, `onToggleFavorite`) + source badge chip
- **Detail:** `ExpertHubDetailOverlay` — clone `TeamHubDetailOverlay` sections (prompt/playbook preview, capabilities, skill deps with install badges, actions row)
- **Detail actions:**
  - Favorite
  - **Add to team** (team picker) — primary; uses `member_hub_add_feedback` toasts
  - **Launch in workspace** (workspace picker → deep link) — primary
  - Export (v1.5)
  - Publish (v2)
  - View origin team (if `teamExtract`)

### Workspace — landing

- New **Expert chip** on compose toolbar when Simple mode only.
- Inline picker sheet: search, favorites, recents; link “Browse all experts →” opens main Expert Hub.
- Selected expert shown on chip; clear via menu.
- Submit uses Personal summon overlay.

### Team config — member form

- **Add from Expert Hub** — fills prompt/playbook/capabilities (default: replace prompt + playbook).
- **Save as template** — writes local `DiscoverableMember` JSON.
- **Export** (v1.5).

### Team Hub cross-links

- Team detail member rows → “View in Expert Hub” when indexed.
- Expert detail → “View origin team” when `originTeamKey` set.

## Data flow

### Load Expert Hub

```
ExpertHubCubit.load()
  → CompositeExpertHubSource.fetchMembers()
      parallel: builtin, git registry, team index (from TeamHub cache or shared fetch)
  → merge + dedupe by key
  → ExpertHubFavoritesStore.load()
  → emit ready
```

### Workspace summon

```
Landing submit (Simple + expertKey)
  → resolve DiscoverableMember by key (local → registry → builtin → team extract)
  → SessionCreateRequest(expertOverlay: member)
  → SessionLaunchService.create → provision personal role with overlay
  → connect → deliverUserCommandToMember(message)
  → ExpertHubRecentStore.touch(key)
```

### Add to team (main window)

```
ExpertHubDetail → team picker → MemberCloneService.addToTeam
  → optional skill dep install
  → LaunchProfileCubit persist
  → toast success
```

## Storage layout

Under `<teampilotRoot>/member-hub/`:

| Path | Purpose |
|------|---------|
| `favorites.json` | `{ "keys": ["..."] }` |
| `recent.json` | `{ "keys": ["...", ...], max 10 }` |
| `local-templates/{id}.json` | User-saved `DiscoverableMember` |

Registry default (v1): `flashskyai/member-hub` on `main`, layout mirrors Team Hub:

- `index.json` → `{ "members": ["architect", "pm", ...] }`
- `members/<slug>/member.json` → `DiscoverableMember` JSON; canonical key stamped as `{owner}/{repo}/{slug}`
- Cache: `<teampilotRoot>/member-hub/cache/{owner}-{name}/members.json`

Built-in templates: `teampilot/builtin/*` key prefix (same convention as Team Hub).

## Phased delivery

### v1 — Core

- `DiscoverableMember` model + builtin templates (~20–30 roles, expand existing 4 presets)
- Git registry fetch + team member index
- Expert Hub page + cubit + favorites
- Landing expert chip + Personal overlay launch
- Main window: add to team + launch in workspace
- Local templates: save from member form + My templates filter
- Team Hub ↔ Expert Hub cross-links
- l10n en/zh

### v1.5 — Share

- Export/import `.teampilot-member.json`
- Share link: `teampilot://import-member?url=` or raw GitHub raw URL handler
- Import validates schema; assigns new `local/{uuid}` key

### v2 — Publish

- Document contributing to `flashskyai/member-hub` (PR template)
- In-app publish wizard (optional): export + open browser to fork/PR

## Error handling

| Case | Behavior |
|------|----------|
| Registry fetch fails | Show cached/builtin/local only; error banner + retry (mirror Team Hub) |
| Unknown `expertKey` on landing | Clear chip; toast “Expert not found” |
| `expertKey` on team landing | Toast; ignore param |
| Duplicate member id on addToTeam | Append numeric suffix to slug (`developer-2`) |
| Skill dep install partial failure | Toast warning with failed dep names (CloneResult pattern) |
| Overlay resolve at create fails | Block session create; toast error |

## Testing

| Area | Tests |
|------|-------|
| Model | `DiscoverableMember` JSON round-trip; key namespacing |
| Source | Composite merge + dedupe; team extract indexing |
| MemberCloneService | addToTeam id slugging; dep install mocked |
| Landing | expert chip visible only Simple; draft persists `expertKey` |
| Launch | overlay merged into role provision (unit test on composeRolePrompt path) |
| Widget | ExpertHubBody empty/loading/grid; detail overlay actions |
| Router | `?expert=` deep link pre-fills landing |

Run: `cd client && flutter analyze && flutter test --exclude-tags integration`

## Open questions (resolved in brainstorm)

- **Scope:** Discovery + launch (C)
- **Sources:** Built-in + registry + team extract + user local (C+D)
- **Launch context:** Workspace = Personal only; main window = add to team or workspace Personal (user confirmed)
- **User templates:** Local + export + publish path (A+B+C phased)

## Related code

| Area | Path |
|------|------|
| Team Hub (primary UI reference) | `client/lib/pages/team_hub/`, `client/lib/services/team_hub/` |
| Skills discovery (search debounce, filter card) | `client/lib/pages/skills/skill_discovery_section.dart`, `skill_management_cards.dart` |
| Plugins / MCP (section embed pattern) | `client/lib/pages/plugins/`, `client/lib/pages/mcp/` |
| Hub shell primitives | `client/lib/widgets/settings/workspace_hub_shell.dart` |
| Global home embed | `client/lib/pages/home_workspace/home_workspace_global_section.dart`, `home_workspace_sidebar.dart` |
| Landing compose | `client/lib/pages/home_workspace/workspace/workspace_chat_landing_compose_card.dart`, `workspace_landing_selectors.dart` |
| Launch context | `client/lib/models/landing_launch_context.dart` |
| Role provision | `client/lib/services/session/member_role_provision.dart` |
| Member presets | `client/lib/models/team_member_prompt_presets.dart` |
| Team clone / dep install | `client/lib/services/team/team_clone_service.dart` |
