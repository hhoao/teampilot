# My Teams / My Experts + Hub Publish design

**Date:** 2026-07-09  
**Status:** Draft (brainstorm approved; pending spec review)  
**Approach:** Sidebar ownership pages for local configs; hubs for discovery; publish via fork PR  
**Supersedes (for this scope):** Expert Hub design notes that deferred in-app publish and kept team-config “Save as template” — those are replaced here.

## Summary

Add two home-shell global views — **我的团队 (My Teams)** and **我的专家 (My Experts)** — as the ownership surfaces for local team and expert configuration. Local configuration **is** the template. Team Hub / Expert Hub remain discovery + clone surfaces. Users publish local configs to the corresponding git registries through an in-app upload wizard that opens a **fork-based PR** into the upstream registry.

Local experts are written only through one service used by My Experts, Expert Hub create, and AI New Team. Remove “save as template” from member settings. Do **not** keep parallel legacy paths, compatibility shims, or deprecated APIs.

## Goals

| Goal | Description |
|------|-------------|
| Own teams | Sidebar **我的团队** lists local `TeamProfile`s for manage / open / delete / upload |
| Own experts | Sidebar **我的专家** is the CRUD home for local experts (`member-hub/local-templates`) |
| Create experts | One local-expert writer; UI editor (Hub + My Experts) + AI New Team; no member-settings bypass |
| Publish | Upload local team or expert to registry as a PR (`team-hub` / `member-hub`) |
| Clean cut | No backward/downward compatibility; delete superseded UI and APIs in the same change |

## Non-goals (v1)

- Multi-registry marketplace UI beyond one configurable default owner/repo
- Direct push to `main` / default branch
- Auto-rewriting team roster `expertKey`s from `local/…` to published remote keys after upload
- Merging Hub and “My …” into a single page
- Publishing skills/plugins/MCP packages as part of this feature
- Keeping “save as template” anywhere outside the expert ownership flow

## Hard constraints (architecture)

1. **No backward / downward compatibility.** Replace superseded flows; do not dual-write, feature-flag old UI, or keep deprecated wrappers “for callers.”
2. **No leftover code.** When a path is replaced, delete call sites, tests, l10n keys, and dead helpers in the same work — including already-deprecated APIs such as `LaunchProfileCubit.addMemberToTeam`.
3. **One ownership model.** Local `TeamProfile` = team template. Local `DiscoverableMember` under `member-hub/local-templates` = expert template. Do not introduce a second “saved template copy” store for teams.
4. **One write path for local experts.** Shared persistence writer used by My Experts UI, Expert Hub create UI, and AI New Team. Member settings must not write local templates.
5. **Reference-only rosters stay canonical.** Teams remain ordered expert references + overrides; persona text lives only on experts (aligned with Expert Hub design).

## Current state (baseline)

| Area | Today |
|------|--------|
| Team create | Sidebar “New Team” + AI draft → `LaunchProfileCubit.addTeam` / clone from Team Hub |
| Team templates | Builtin + git registry (`index.json` + `teams/<slug>/team.json`); clone only; no local team publish |
| Expert create | No first-class create UI; AI team gen and member-settings “保存为模板” write `LocalMemberTemplateStore` |
| Expert Hub | Discover builtin / registry / local / team-extracted; add-to-team / summon |
| Sidebar globals | Team Hub, Expert Hub, Skills, Plugins, MCP, Extensions, … |
| Legacy | `addMemberToTeam` marked `@Deprecated`; `addMember()` unused by production UI |

## Design

### 1. Navigation and information architecture

**Layers**

| Layer | Meaning | Entry |
|-------|---------|-------|
| My Teams | Local launchable `TeamProfile` (local config = template) | New sidebar item |
| My Experts | Local reusable experts | New sidebar item |
| Team Hub / Expert Hub | Discover + clone remote/builtin | Existing items |
| Upload | Publish local config to registry | From My Teams / My Experts |

**Sidebar order (hub block)**

```
我的团队
我的专家
────────
Team Hub
Expert Hub
────────
Skills / Plugins / MCP / Extensions
```

**Routing**

- Add `HomeGlobalView.myTeams` and `HomeGlobalView.myExperts`
- Deep links: `/home-v2?global=myTeams`, `/home-v2?global=myExperts`
- Optional detail query: `?team=<profileId>` / `?member=<localKey>` (same pattern as hubs)

**Boundary with sidebar Teams list**

- Upper Teams list: switch current identity / open team config (workflow)
- My Teams page: management + upload; selecting a row may select that team and open config, without replacing the upper list

### 2. My Teams

**Source of truth:** all local `TeamProfile`s via `LaunchProfileCubit` / `LaunchProfileRepository`. No separate team-template store.

| Action | Behavior |
|--------|----------|
| List | Name, member count, CLI / teamMode, `createdAt` (no separate `updatedAt` on `TeamProfile` in v1) |
| Open | Navigate into existing team config (home team tab / team-config) |
| New | Reuse existing New Team dialog (blank / AI); no second creator |
| Delete | Same confirmation + delete path as today |
| Upload | Open publish wizard → Team Hub registry PR |

**Out of page scope:** inline roster editing (stays in existing member config).

### 3. My Experts

**Source of truth:** `LocalMemberTemplateStore` (`member-hub/local-templates/*.json`). Builtin and registry experts stay in Expert Hub only.

| Action | Behavior |
|--------|----------|
| List | Name, description, skillDeps, local badge |
| Create | Shared expert editor → `local/{uuid}` |
| Edit | Update persona; teams referencing the key pick up changes on next materialize |
| Delete | Confirm; if any team roster still references the key → block with clear message (must reassign first) |
| Upload | Publish wizard → Expert Hub registry PR |
| Add to team | Reuse existing Expert Hub team picker |

**Single write path for local experts**

All local expert persistence goes through one injectable writer (thin facade over `LocalMemberTemplateStore.save` / `delete` / `loadAll`). Callers:

| Caller | How |
|--------|-----|
| My Experts / Expert Hub UI | Shared expert editor → writer |
| AI New Team (`rosterSlotsFromTeamDraft`) | Programmatic create via the **same writer** (no UI form); must not invent a second JSON shape or store |

“One create path” means **one persistence API**, not “AI must open the editor dialog.” Member settings must not call the writer.

**Create UI entry points (shared editor)**

1. My Experts primary CTA
2. Expert Hub toolbar “新建”

**Removal (mandatory)**

- Delete member-settings overflow “保存为模板” (`team_config_member_section.dart` `_saveAsTemplate` / `save_template` menu item)
- Delete related tests and unused l10n once no callers remain
- Refactor AI draft mapper to use the shared writer; delete any duplicate save helpers

**Expert Hub relationship**

- Expert Hub continues to list local experts so discovery / add-to-team still works
- My Experts is the only surface for local CRUD + upload ownership UX

### 4. Hub publish

**Registry layout (existing read path)**

| Hub | Files | Canonical key |
|-----|-------|---------------|
| Team | `index.json` + `teams/<slug>/team.json` | `{owner}/{repo}/{slug}` |
| Expert | `index.json` + `members/<slug>/member.json` | `{owner}/{repo}/{slug}` |

Defaults: `flashskyai/team-hub`, `flashskyai/member-hub` (configurable owner/repo).

**Publish transport (v1 rule)**

End users are not assumed to have write access to `flashskyai/*`. v1 always:

1. Ensure a **user fork** of the target registry exists (create fork via API if missing)
2. Commit on a new branch **on the fork**
3. Open a **PR from the fork into upstream** `owner/repo` default branch
4. Show the PR URL

Do not implement “push branch on upstream” as a parallel mode. Collaborator-only shortcuts are out of scope.

**Wizard steps (shared shell)**

1. Metadata: slug, display name, description, category, author; **tags only for experts** (`DiscoverableMember.tags`; teams have no tags field)
2. Dependency gates:
   - **Experts on team roster:** every `local/…` `expertKey` must be published first **or** remapped via an in-wizard picker to an already-published / builtin / registry expert key; unresolved → cannot continue
   - **Bundle deps:** map local `skillIds` / `pluginIds` / `mcpServerIds` → portable `skillDeps` / `pluginDeps` / `mcpDeps` by reverse-looking up install provenance (repo owner/name/branch/directory or marketplace refs). IDs with **no portable provenance** (ad-hoc local-only installs) are listed in the wizard; user must remove them from the team bundle or cancel — v1 does **not** publish opaque local ids
3. Serialize:
   - Team: `TeamProfile` → `DiscoverableTeam` with roster (`expertKey` + overrides only), `cli`, `teamMode`, `extraArgs`, description/name, and resolved `*Deps` only
   - Expert: local `DiscoverableMember` → `member.json` (including its `skillDeps` if already portable)
4. Auth: GitHub token from secure store (never embedded in template JSON)
5. Publish: fork → branch on fork → write package file(s) → update fork `index.json` → open upstream PR → show PR URL

**After success**

- Record publish metadata locally (registry, slug, PR URL, timestamps) for badges
- Do **not** auto-rewrite local roster keys to remote keys
- Do **not** delete the local expert/team after publish

**Security**

- Strip API keys, SSH profiles, workspace paths, and other secrets from payloads
- Fork PR only — never push upstream default branch in v1

**Failure modes**

- Missing token, fork/PR API errors, slug collision on upstream index, network errors, unresolved local expert keys, non-portable bundle deps → in-wizard errors; no half-applied upstream state (fork branch may exist; PR creation is the success criterion)

### 5. Components

| Component | Responsibility |
|-----------|----------------|
| `HomeGlobalView.myTeams` / `myExperts` | Route + sidebar |
| `MyTeamsPage` / `MyExpertsPage` | Ownership UI |
| Shared expert editor | Create/edit local experts (UI) |
| Local expert writer | Sole persistence API for local experts (UI + AI) |
| `HubPublishService` | Serialize → fork branch → index update → upstream PR |
| `HubPublishCredentialsStore` | Token storage |
| `HubPublishRecordStore` | Local publish badges / history |
| `TeamProfile → DiscoverableTeam` mapper | Sanitize + reverse-map portable `*Deps` |
| Bundle provenance lookup | Resolve local skill/plugin/MCP ids → dependency refs |

Reuse: `LaunchProfileCubit`, `LocalMemberTemplateStore` (behind writer), `ExpertHubCubit`, existing team navigation.

### 6. Cleanup checklist (delete, do not wrap)

| Remove | Why |
|--------|-----|
| Member-settings “保存为模板” | Ownership moves to My Experts / Expert Hub create |
| `@Deprecated addMemberToTeam` | Callers must use `addExpertToTeam` only |
| Duplicate AI save helpers that bypass the shared writer | One persistence API |
| Orphan l10n / tests for removed UI | No dead strings or skipped tests left behind |

Delete unused `addMember()` from the cubit public API if production UI does not call it; test fixtures that need a default developer slot live in test support, not the cubit.

### 7. Testing

- Deep links for `myTeams` / `myExperts`
- Local expert CRUD; delete blocked when referenced
- Member settings no longer exposes save-as-template
- Publish: unresolved local deps blocked; payload has no secrets; PR success path with mocked git/HTTP
- Team upload dependency gate
- Regression: Team Hub clone and Expert Hub add-to-team still work

### 8. Implementation sequencing (for planning)

1. Navigation + empty My Teams / My Experts shells
2. My Teams list wired to existing profiles + open/delete
3. Shared expert editor + My Experts CRUD; Expert Hub “新建”
4. Remove member-settings save-as-template + deprecated APIs
5. Publish credentials + record stores
6. Expert publish wizard
7. Team publish wizard + local-expert dependency gate
8. Badges / polish / l10n

## Decisions log

| Decision | Choice |
|----------|--------|
| Team templates | Local `TeamProfile` is the template; upload publishes it |
| Expert create | Expert Hub + My Experts; remove member-settings save-as-template |
| My pages | New sidebar items (not Hub filters) |
| My Teams content | Local launch identities (`TeamProfile`), not a separate template copy |
| Upload in v1 | Yes — fork-based PR into upstream registry |
| Publish deps | Only portable `*Deps`; non-portable local ids block until removed |
| Local expert writes | One writer: UI editor + AI New Team; no member-settings path |
| Approach | Sidebar ownership pages + Hub discovery + publish wizard |
| Compatibility | None — clean architecture, delete leftovers |

## Open points for implementation plan (not design blockers)

- Exact GitHub API client vs `gh` CLI behind the publish port (plan picks one injectable implementation)
- Whether Expert Hub “local” filter remains a chip or becomes a link to My Experts (UX detail; both keep local list readable from Hub)
- Where skill/plugin/MCP install provenance is already stored on disk (plan locates existing metadata vs adds a minimal provenance index if missing)
)
