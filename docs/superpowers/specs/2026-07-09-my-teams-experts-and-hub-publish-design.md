# My Teams / My Experts + Hub Publish design

**Date:** 2026-07-09  
**Status:** Draft (brainstorm approved; pending spec review)  
**Approach:** Sidebar ownership pages for local configs; hubs for discovery; publish via PR

## Summary

Add two home-shell global views — **我的团队 (My Teams)** and **我的专家 (My Experts)** — as the ownership surfaces for local team and expert configuration. Local configuration **is** the template. Team Hub / Expert Hub remain discovery + clone surfaces. Users publish local configs to the corresponding git registries through an in-app upload wizard that opens a PR.

Create experts only from Expert Hub / My Experts. Remove “save as template” from member settings. Do **not** keep parallel legacy paths, compatibility shims, or deprecated APIs.

## Goals

| Goal | Description |
|------|-------------|
| Own teams | Sidebar **我的团队** lists local `TeamProfile`s for manage / open / delete / upload |
| Own experts | Sidebar **我的专家** is the CRUD home for local experts (`member-hub/local-templates`) |
| Create experts | Expert Hub + My Experts share one create/edit form; no member-settings bypass |
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
4. **One create path for experts.** Shared editor used by My Experts and Expert Hub. Member settings must not write local templates.
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
| List | Name, member count, CLI / teamMode, updated time |
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

**Create entry points (same editor)**

1. My Experts primary CTA
2. Expert Hub toolbar “新建”

**Removal (mandatory)**

- Delete member-settings overflow “保存为模板” (`team_config_member_section.dart` `_saveAsTemplate` / `save_template` menu item)
- Delete related tests and unused l10n once no callers remain
- Do not leave a hidden API that recreates the bypass

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

**Wizard steps (shared shell)**

1. Metadata: slug, display name, description, category, tags, author
2. Dependency gate (teams): every roster `expertKey` that is `local/…` must be published first or remapped to an already-published key; unresolved → cannot continue
3. Serialize:
   - Team: `TeamProfile` → `DiscoverableTeam` (roster = expertKey + overrides only)
   - Expert: local `DiscoverableMember` → `member.json`
4. Auth: GitHub token from secure store (never embedded in template JSON)
5. Publish: branch → write package file(s) → update `index.json` → open PR → show PR URL in app

**After success**

- Record publish metadata locally (registry, slug, PR URL, timestamps) for badges
- Do **not** auto-rewrite local roster keys to remote keys
- Do **not** delete the local expert/team after publish

**Security**

- Strip API keys, SSH profiles, workspace paths, and other secrets from payloads
- PR only — never push default branch in v1

**Failure modes**

- Missing token, slug collision, network errors, unresolved local expert deps → in-wizard errors; no partial `index.json` update

### 5. Components

| Component | Responsibility |
|-----------|----------------|
| `HomeGlobalView.myTeams` / `myExperts` | Route + sidebar |
| `MyTeamsPage` / `MyExpertsPage` | Ownership UI |
| Shared expert editor | Create/edit local experts |
| `HubPublishService` | Serialize → git branch → index update → PR |
| `HubPublishCredentialsStore` | Token storage |
| `HubPublishRecordStore` | Local publish badges / history |
| `TeamProfile → DiscoverableTeam` mapper | Sanitize for publish |

Reuse: `LaunchProfileCubit`, `LocalMemberTemplateStore`, `ExpertHubCubit`, existing team navigation.

### 6. Cleanup checklist (delete, do not wrap)

| Remove | Why |
|--------|-----|
| Member-settings “保存为模板” | Ownership moves to My Experts / Expert Hub create |
| `@Deprecated addMemberToTeam` | Callers must use `addExpertToTeam` only |
| Any dual “save template vs create expert” helpers introduced during AI flows that duplicate the editor | One editor, one store write path |
| Orphan l10n / tests for removed UI | No dead strings or skipped tests left behind |

Prefer deleting unused `addMember()` production dead ends if nothing outside tests needs a “default developer” shortcut; if tests need a fixture helper, put it in test support — not in the cubit public API.

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
| Upload in v1 | Yes — PR to registry |
| Approach | Sidebar ownership pages + Hub discovery + publish wizard |
| Compatibility | None — clean architecture, delete leftovers |

## Open points for implementation plan (not design blockers)

- Exact GitHub API client vs `gh` CLI for PR creation (plan should pick one injectable port)
- Whether Expert Hub “local” filter remains a chip or becomes a link to My Experts (UX detail; both keep local list readable from Hub)
)
