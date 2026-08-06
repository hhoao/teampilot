# Clone team — shadow-clone missing experts into My Experts (design)

**Date:** 2026-08-06 (rev. 2026-08-07: redesign to shadow-clone model)
**Status:** Design approved — implementation rework in progress
**Scope:** When a user clones a TeamHub team, roster-referenced experts that are not already cloned locally are cloned into My Experts. A clone is stored **under the catalog key itself** and **shadows** the catalog entry at resolution, so team rosters stay unchanged and the team is self-contained. Built-in experts and already-present clones are not re-cloned; unresolvable keys fail non-blockingly and are reported. No backward compatibility with the initial uuid-clone implementation.

## Problem

Today `TeamCloneService.clone` (`client/lib/services/team/team_clone_service.dart`):

1. Installs the team's `skillDeps` / `pluginDeps` / `mcpDeps` into the app-global library.
2. Copies the roster slots verbatim — each `TeamRosterSlot.expertKey` keeps referencing a **catalog** expert.
3. Writes **no expert persona** to My Experts. `addClonedTeam` → `_materializeTeam` only resolves keys against the catalog to materialize in-memory `TeamMemberConfig`s.

Consequences:

- The cloned team's members are **not self-contained**: they keep depending on the live catalog (or built-ins) for resolution.
- An `expertKey` that resolves neither from the catalog nor locally is **silently dropped** by `ExpertMemberMaterializer.materializeRosterAsync` (`expert == null → continue`) — the team launches without that member, no warning.

The user expectation: cloning a team should bring the experts it references into My Experts when missing, so the team works offline and members are never silently lost.

## Goals

1. Cloning a team clones any referenced expert that is not already cloned locally into My Experts.
2. **Shadow model:** a clone is stored under its catalog key (`local-templates/{owner}/{repo}/{slug}.json`); resolution prefers the local clone, shadowing the catalog. Team rosters are **unchanged** (key stays the catalog key).
3. **O(1) dedup:** the same catalog expert is cloned at most once and shared across all teams (key existence is the dedup).
4. Built-in experts (`teampilot/builtin/...`) are never cloned — always available.
5. Unresolvable expert keys fail **non-blockingly** (team still created) and are reported — no silent member loss.
6. **One-time legacy cleanup:** purge the initial uuid-clone files (they carry a `catalogKey` field) while preserving user-created experts.

## Non-goals

- Reinstalling per-expert skill/plugin/MCP deps at clone time (team template declares the union; the cloned persona keeps its dep refs).
- Auto-refreshing clones against upstream catalog changes (a future feature; `clonedAt` is the seed).
- Backward compatibility with the initial uuid-clone layout beyond the one-time purge.
- A wrapper record model — provenance lives on `DiscoverableMember` (key = provenance; `originTeamKey`, `clonedAt`, `source`).

## Locked decisions

| Topic | Decision |
|-------|----------|
| Clone storage | Stored under the **catalog key** (`local-templates/{key}.json`), nested paths |
| Resolution | Local store wins for **any key** (shadow); catalog/builtin fallback otherwise |
| Roster after clone | **Unchanged** — slot keeps the catalog key |
| Dedup | O(1) key existence check in the store |
| Built-in experts | Never cloned — always resolvable |
| Already-cloned expert | Reuse existing clone (`cloned: false`) |
| Unresolvable key | Non-blocking failure, reported; slot unchanged |
| Provenance | `ExpertMemberSource.clone` + `clonedAt` (int) + `originTeamKey`; **no** `catalogKey` field (key is provenance) |
| Legacy cleanup | `migrateLegacyLayout()`: delete files carrying `catalogKey` (old clones); relocate root-level user-custom into `local/` |
| Clone service | Stateless singleton — no per-run factory/memo |
| Copy model | Pure `copyWith` (no `update*` flags) |

## Design

### 1. `DiscoverableMember` model

- **Remove** `catalogKey` field (key itself is provenance for clones) and its `copyWith`/`update*` plumbing.
- **Add** `ExpertMemberSource.clone` enum value and optional `clonedAt` (int, epoch ms) — provenance + refresh seed.
- `copyWith` simplified to pure `??` overrides (no `update*` flags).

### 2. `LocalExpertStore` (replaces `LocalMemberTemplateStore`)

- Layout under `member-hub/local-templates/`:
  - `{owner}/{repo}/{slug}.json` — clones (key = catalog key).
  - `local/{uuid}.json` — user-created experts.
- Nested paths: `ensureDir` parent before write; `loadAll()` lists recursively.
- API:
  - `getByKey(key)` — reads `{key}.json` for **any** key (shadow lookup); null if absent.
  - `save(member)` — user-custom: forces `local/{uuid}`, stamps `source: local`.
  - `putClone(member)` — stores under `member.key` verbatim (idempotent upsert).
  - `delete(key)` / `loadAll()`.
  - `migrateLegacyLayout()` — scan legacy root files: delete those whose raw JSON has a non-empty `catalogKey` (old uuid clones); relocate the rest (old user-custom) into `local/` so `getByKey` still finds them.

### 3. Resolution shadow

- `ExpertMemberResolver.resolveMember` checks `store.getByKey(key)` for **any** key first; a hit (clone or custom) wins over catalog/builtin.
- `CompositeExpertHubSource.fetchMembers` dedups by key so a local clone/custom **shadows** the catalog entry in listings (no duplicate entries).

### 4. `ExpertCloneService` (stateless singleton)

- `ExpertCloneOutcome clone({required String expertKey, String? originTeamKey})`:
  - Empty key → failure.
  - Builtin prefix → keep (`cloned: false`).
  - `store.getByKey(key)` hit → reuse (`cloned: false`).
  - Catalog resolvable → `store.putClone(expert.copyWith(source: clone, originTeamKey: originTeamKey, clonedAt: now))` → `cloned: true`.
  - Unresolvable → failure (`null`).
- No per-run memo or factory.

### 5. `TeamCloneService`

- Constructor takes a plain `ExpertSlotCloner` (tear-off of `ExpertCloneService.clone`), **no factory**.
- Roster passes through unchanged (only `joinedAt` stamping); tracks cloned count and records `DependencyKind.expert` failures.
- `CloneDepInstallSummary` keeps `expertKeys` / `expertCount`; `DependencyKind` keeps `expert`.

### 6. Wiring (`app_shell.dart`)

- Construct singleton `LocalExpertStore` + `ExpertCloneService`; run `migrateLegacyLayout()` once at bootstrap.
- `TeamCloneService(expertCloner: expertCloneService.clone, ...)`.

### 7. UI / l10n

- Source label for `ExpertMemberSource.clone` in `expert_hub_cards.dart` (+ detail overlay if it switches on source); en/zh arb + regenerate.
- Clone toast already reports expert counts (`teamHubClone*` from the initial implementation).

### 8. Tests

- Model: clone source / `clonedAt` round-trip; `copyWith` pure override.
- Store: nested put/get/delete/loadAll; `save` user-custom under `local/`; `migrateLegacyLayout` purges old clones and relocates user-custom.
- Resolver: local clone shadows catalog; builtin fallback.
- Clone service: shadow clone; reuse; builtin keep; failure; O(1) dedup across calls.
- Team clone: no repoint, counts, `DependencyKind.expert` failure.
- Hub source: clone shadows catalog in merged listing.
