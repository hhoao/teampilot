# Expert Hub (Member Discovery) design

**Date:** 2026-07-05  
**Status:** Approved; **canonical architecture revised 2026-07-09** (reference-only rosters, no embedded member copies, no backward compatibility)

## Summary

Add an **Expert Hub** (专家中心) — discovery for reusable **experts** (`DiscoverableMember`). A **team is an ordered collection of expert references** plus team-level coordination (`TeamMode`, shared skills/plugins/MCP, default CLI). Persona text lives in the catalog; rosters store **`expertKey` + per-slot overrides only**.

Expert Hub complements **Team Hub** (curated team templates that are themselves lists of expert keys). There is **no** copy-on-add, **no** embedded prompt/playbook on team rosters, and **no** migration path for legacy inline members — refactor replaces the old shape entirely.

## Goals

| Goal | Description |
|------|-------------|
| Discover | Browse/search experts: builtin, registry, local; “from teams” = keys referenced by Team Hub templates |
| Summon | Workspace landing (Simple): `expertKey` on session → materialize at connect |
| Clone | Add **expert reference** to team roster (`expertKey` + overrides) |
| Own | Favorites, local templates, export/import, future registry publish |

## Non-goals (v1)

- Leaderboard / popularity metrics (defer)
- In-app registry publish wizard (v2; document manual PR flow first)
- Expert summon in team-mode landing or multi-member partial connect
- Replacing Team Hub or merging into a single Discovery page

## Concept mapping

| WorkBuddy | TeamPilot |
|-----------|-----------|
| Expert | `DiscoverableMember` (catalog atom; canonical `key`) |
| Expert Team | `DiscoverableTeam` = metadata + `roster[]` of expert keys |
| User team | `TeamProfile` = metadata + `roster[]` of expert keys |
| Summon (Personal) | `AppSession.expertKey` → resolve at connect (same pipeline as team slots) |
| My experts | Local templates + favorites under `member-hub/` |

## Teams as expert collections (canonical architecture)

**团队 = 多个专家的集合.** This is the only roster model — not a future phase. **No backward compatibility:** remove embedded member copies and copy-on-add code paths entirely.

### Primitives

| Primitive | Persisted shape | Resolved at connect |
|-----------|-----------------|---------------------|
| **Expert** | `DiscoverableMember` in builtin / registry / `member-hub/local-templates/` | — |
| **Roster slot** | `TeamRosterSlot { id, expertKey, overrides?, joinedAt }` | → `TeamMemberConfig` (runtime only) |
| **Team** | `TeamProfile { …team bundle…, roster: TeamRosterSlot[] }` | per slot |
| **Team template** | `DiscoverableTeam { …meta…, roster: TeamRosterSlot[] }` | clone → new `TeamProfile` |
| **Personal session** | optional `AppSession.expertKey` | → materialized member for Simple launch |

**Rule:** `prompt`, `playbook`, and display `name` for a roster seat come **only** from the resolved expert (plus optional slot `overrides` for provider/model/cli/effort/replicas — never duplicate persona prose on the team).

### `TeamRosterSlot` (persisted)

```dart
TeamRosterSlot {
  id              // roster seat: team-lead | developer | … (TeamMemberNaming)
  expertKey       // required — teampilot/builtin/architect | owner/repo/slug | local/{uuid}
  overrides? {    // per-team/per-slot only — no prompt/playbook fields
    provider, model, cli, effort, replicas, capabilities?, extraArgs?
  }
  joinedAt
}
```

`TeamProfile.roster` replaces `TeamProfile.members` (`TeamMemberConfig[]` with inline prompts is **deleted**).

### Materialization (single code path)

```
materializeRosterSlot(expertKey, overrides?, presetInheritance?) → TeamMemberConfig
```

Used by team connect, Personal connect (`AppSession.expertKey`), and preview UI. Always live-resolve from catalog on connect.

```
ExpertMemberResolver.resolve(expertKey)
  → DiscoverableMember → base TeamMemberConfig
  → apply TeamRosterSlot.overrides
  → apply preset / team CLI inheritance
  → MemberRoleProvision.syncRolePromptFile + append-system-prompt
```

### Expert Hub vs Team Hub

| Surface | Responsibility |
|---------|----------------|
| **Expert Hub** | Browse atomic experts; favorite; add expert **reference** to team; Personal launch; save local template |
| **Team Hub** | Browse team templates (`DiscoverableTeam.roster[]`); clone → new `TeamProfile` with same keys |
| **Team config** | Reorder roster; pick `expertKey` per slot; edit **overrides** only; edit persona in Expert Hub |

**Delete:** inline prompt editor on team member form; `MemberCloneService` copy semantics; `DiscoverableTeam.members[]` embedded bodies; `teamExtract` hash-dedup of copied prose; persisted `ExpertSessionOverlay` on sessions.

### `DiscoverableTeam` (team templates)

```dart
DiscoverableTeam {
  key, name, description, category, skillDeps[], …
  roster: TeamRosterSlot[]   // not members[] with inline prompts
}
```

### Code to remove (refactor checklist)

| Remove | Replace with |
|--------|----------------|
| `TeamProfile.members: TeamMemberConfig[]` | `TeamProfile.roster: TeamRosterSlot[]` |
| `MemberCloneService.addToTeam` + `toMemberConfig()` copy | `MemberRosterService.addExpertToTeam(teamId, expertKey, …)` |
| `DiscoverableTeam.members` | `DiscoverableTeam.roster` |
| `indexMembersFromTeams()` | Optional: flatten template `roster[].expertKey` for “from teams” filter |
| `ExpertSessionOverlay` on `AppSession` | `AppSession.expertKey` only |
| `applyExpertOverlay` as parallel Personal path | `materializeRosterSlot` |

`TeamMemberConfig` remains **runtime-only** after materialization.

### Implementation map

| Concern | Path |
|---------|------|
| Persisted slot model | `client/lib/models/team_roster_slot.dart` (new) |
| Materialize | `client/lib/services/expert_hub/expert_member_materializer.dart` |
| Add to team | `MemberRosterService` |
| Resolve key | `ExpertMemberResolver` |
| Connect | `session_lifecycle_service`, config-profile capabilities |
| Role files | `MemberRoleProvision` |

## Architecture

### Approach

**Independent Expert Hub page** (`HomeGlobalView.expertHub`), parallel to Team Hub. Reuses Team Hub UI patterns (grid, search, filter chips, detail overlay, favorites store). Team Hub gains cross-links to indexed members.

### Services

```
CompositeExpertHubSource
  ├─ BuiltinMemberTemplates
  ├─ GitRegistryExpertHubSource     (hhoao/teampilot/member-hub)
  ├─ TeamTemplateExpertIndex        (flatten DiscoverableTeam.roster[].expertKey)
  └─ LocalMemberTemplateStore

ExpertHubFavoritesStore / ExpertHubRecentStore
MemberRosterService                 (addExpertToTeam — reference only)
ExpertMemberMaterializer            (materializeRosterSlot)
ExpertHubCubit
```

### Model: `DiscoverableMember`

Extends the portable shape of `DiscoverableTeamMember` with catalog metadata:

```dart
DiscoverableMember {
  key              // teampilot/builtin/architect | owner/repo/slug | local/{uuid}
  name, description, category, author?, updatedAt
  tags[]
  member           // DiscoverableTeamMember body: prompt, playbook, capabilities, cli hints, …
  skillDeps[]
  source           // builtin | registry | local | teamTemplateRef
  originTeamKey?   // when listed because a team template references this key
}
```

**Keys are global** in the catalog. Team templates and user teams reference the same keys in `roster[]`.

### Personal summon

Simple-mode landing only; does not mutate `PersonalProfile`:

1. `LandingLaunchContext.expertKey` — optional; persisted in `LandingPrefsStore`.
2. `AppSession.expertKey` — set at session create (no separate overlay blob).
3. Connect: `materializeRosterSlot(session.expertKey)` merged with personal preset base → `MemberRoleProvision`.

Team-mode landing has no expert chip. `?expert=` on team landing → toast + ignore.

### Add to team

`MemberRosterService.addExpertToTeam(teamId, expertKey, slotId?, overrides?)`:

1. Append or update `TeamRosterSlot` on `TeamProfile.roster` (reference only).
2. Optional skill dep install for the expert (non-blocking failures → toast).
3. Persist via `LaunchProfileCubit`; does not start a session.

### Launch from main window

1. User picks workspace in dialog.
2. Navigate `/home-v2/workspace/:workspaceId?expert=:key`.
3. `WorkspaceLandingContextCubit` / landing resolver pre-selects expert; forces Simple mode.
4. User types message → create session with `expertKey` → materialize at connect.

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
  - View origin team template (if `originTeamKey`)

### Workspace — landing

- New **Expert chip** on compose toolbar when Simple mode only.
- Inline picker sheet: search, favorites, recents; link “Browse all experts →” opens main Expert Hub.
- Selected expert shown on chip; clear via menu.
- Submit persists `expertKey` on session; materialize at connect.

### Team config — roster editor

- Each row is a **`TeamRosterSlot`**: expert picker + overrides (provider/model/cli/effort/replicas).
- **No** inline prompt/playbook fields — “Edit expert” opens Expert Hub or local template editor.
- **Add from Expert Hub** appends a slot with `expertKey` set.
- **Save as template** writes `DiscoverableMember` to `member-hub/local-templates/`.

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
  → validate key resolves (toast + abort if not)
  → create AppSession with expertKey
  → connect: materializeRosterSlot + personal preset base
  → deliverUserCommandToMember(message)
  → ExpertHubRecentStore.touch(key)
```

### Team session connect

```
For each TeamProfile.roster slot:
  → materializeRosterSlot(slot.expertKey, slot.overrides, team preset inheritance)
  → prepareTeamLaunch / MemberRoleProvision (same as today, runtime TeamMemberConfig)
```

### Add to team (main window)

```
ExpertHubDetail → team picker → MemberRosterService.addExpertToTeam
  → optional skill dep install
  → persist TeamProfile.roster
  → toast success
```

## Storage layout

Under `<teampilotRoot>/member-hub/` (see also [workspace-storage-layout.md](../../workspace-storage-layout.md)):

| Path | Purpose |
|------|---------|
| `favorites.json` | `{ "keys": ["..."] }` |
| `recent.json` | `{ "keys": ["...", ...], max 10 }` |
| `local-templates/{id}.json` | User-saved `DiscoverableMember` |
| `cache/{owner}-{repo}/members.json` | Git registry fetch cache |

**Team rosters** — `launch-profiles/{teamId}/profile.json`:

```json
{
  "kind": "team",
  "id": "my-squad",
  "name": "My Squad",
  "teamMode": "native",
  "cli": "claude",
  "skillIds": ["..."],
  "roster": [
    {
      "id": "team-lead",
      "expertKey": "teampilot/builtin/lead",
      "overrides": { "model": "opus" },
      "joinedAt": 1710000000000
    }
  ]
}
```

**Personal session** — optional `expertKey` on `session.json` (no `expertOverlay` object).

**Team Hub registry** — `team-hub/…/team.json` uses the same `roster[]` shape (not `members[]` with inline prompts).

Registry default (v1): `hhoao/teampilot/member-hub` on `main`, layout mirrors Team Hub:

- `index.json` → `{ "members": ["architect", "pm", ...] }`
- `members/<slug>/member.json` → `DiscoverableMember` JSON; canonical key stamped as `{owner}/{repo}/{slug}`

Built-in templates: `teampilot/builtin/*` key prefix (same convention as Team Hub).

## Delivery scope

Single refactor — no parallel legacy paths:

1. **Models:** `TeamRosterSlot`; `TeamProfile.roster`; `DiscoverableTeam.roster`; drop embedded roster copies.
2. **Materialization:** `ExpertMemberMaterializer.materializeRosterSlot` at all connect entry points.
3. **Expert Hub UI:** discovery, favorites, add reference to team, Personal launch, local templates.
4. **Team Hub:** template JSON + clone → roster of keys; registry schema update.
5. **Team config UI:** roster editor (expert picker + overrides only).
6. **Remove:** `MemberCloneService`, `ExpertSessionOverlay`, `indexMembersFromTeams`, inline prompt copy flows.

### Later (separate specs)

| Phase | Scope |
|-------|--------|
| Share | Export/import `.teampilot-member.json`, share URL handler |
| Publish | `hhoao/teampilot/member-hub` PR docs + in-app publish wizard |

## Error handling

| Case | Behavior |
|------|----------|
| Registry fetch fails | Show cached/builtin/local only; error banner + retry (mirror Team Hub) |
| Unknown `expertKey` (landing / connect / roster slot) | Toast `expertHubNotFound`; block create/connect for that path |
| Duplicate slot `id` on add | Append numeric suffix (`developer-2`) |
| Skill dep install partial failure | Toast warning with failed dep names |
| `expertKey` on team landing | Toast; ignore param |
| Expert missing at team connect | Toast; block member connect for that slot |

## Testing

| Area | Tests |
|------|-------|
| Model | `TeamRosterSlot`, `DiscoverableMember` JSON round-trip |
| Materializer | `materializeRosterSlot` applies overrides + expert body |
| MemberRosterService | addExpertToTeam persists reference; dep install mocked |
| Team connect | each roster slot resolves to role prompt at launch |
| Landing | expert chip Simple-only; session stores `expertKey` only |
| Widget / router | ExpertHubBody; `?expert=` deep link |

Run: `cd client && flutter analyze && flutter test --exclude-tags integration`

## Open questions (resolved in brainstorm)

- **Scope:** Discovery + launch (C)
- **Sources:** Built-in + registry + team extract + user local (C+D)
- **Launch context:** Workspace = Personal only; main window = add to team or workspace Personal (user confirmed)
- **User templates:** Local + export + publish path (A+B+C phased)
- **Team = expert collection:** reference-only `TeamProfile.roster[]`; no embedded copies (2026-07-09)

## Related code

| Area | Path |
|------|------|
| Roster slot model | `client/lib/models/team_roster_slot.dart` (new) |
| Materializer | `client/lib/services/expert_hub/expert_member_materializer.dart` (new) |
| Add to team | `client/lib/services/expert_hub/member_roster_service.dart` (replaces clone service) |
| Catalog | `client/lib/services/expert_hub/composite_expert_hub_source.dart` |
| Resolve key | `client/lib/services/expert_hub/expert_member_resolver.dart` |
| Connect | `client/lib/services/session/session_lifecycle_service.dart` |
| Role provision | `client/lib/services/session/member_role_provision.dart` |
| Team Hub templates | `client/lib/models/discoverable_team.dart`, `client/lib/services/team_hub/` |
| Expert Hub UI | `client/lib/pages/expert_hub/` |
| Landing | `client/lib/pages/home_workspace/workspace/workspace_chat_landing*.dart` |
