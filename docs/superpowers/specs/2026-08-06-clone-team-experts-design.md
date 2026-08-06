# Clone team — clone missing experts into My Experts (design)

**Date:** 2026-08-06
**Status:** Design approved — awaiting implementation
**Scope:** When a user clones a TeamHub team, referenced experts that are not already present locally are cloned (saved) into **My Experts** (`LocalMemberTemplateStore`), and the cloned team's roster is repointed at those local copies so the team is self-contained. Built-in experts and already-present local experts are not re-cloned; unresolvable expert keys fail non-blockingly and are reported.

## Problem

Today `TeamCloneService.clone` (`client/lib/services/team/team_clone_service.dart`):

1. Installs the team's `skillDeps` / `pluginDeps` / `mcpDeps` into the app-global library.
2. Copies the roster slots verbatim — each `TeamRosterSlot.expertKey` keeps referencing a **catalog** expert (`owner/name/slug`, `teampilot/builtin/...`, or a dangling `local/...`).
3. Writes **no expert persona** to My Experts (`LocalMemberTemplateStore`). `addClonedTeam` → `_materializeTeam` only resolves keys against the catalog to materialize in-memory `TeamMemberConfig`s.

Consequences:

- The cloned team's members are **not self-contained**: they keep depending on the live catalog (or built-ins) for resolution at materialize time.
- An `expertKey` that resolves neither from the catalog nor locally is **silently dropped** by `ExpertMemberMaterializer.materializeRosterAsync` (`expert == null → continue`) — the team is created but launches without that member, with no warning.

The user expectation: cloning a team should also bring the experts it references into My Experts when they are missing, so the team works offline and members are never silently lost.

## Goals

1. Cloning a team clones any referenced expert that is not already available locally into My Experts.
2. The cloned team's roster slots **repoint** to the new local copies (`local/...`), making the team self-contained and offline-usable.
3. No duplicate local copies across repeated clones or teams sharing an expert: provenance (`catalogKey`) is recorded and reused.
4. Built-in experts (`teampilot/builtin/...`) are never cloned — they are always available; their slots keep the built-in key.
5. Unresolvable expert keys fail **non-blockingly** (team still created, deps still installed) and are reported in the clone result/toast — no more silent member loss.

## Non-goals

- Reinstalling per-expert skill/plugin/MCP deps at clone time. The team template declares the union at team level and `TeamCloneService` already installs it; the saved local expert preserves its own dep refs for standalone use later.
- Auto-tracking upstream catalog updates for cloned experts. A local clone is a snapshot; refreshing is a future manual action.
- Purging existing My Experts entries or migrating legacy uuid-keyed local experts.
- Changing the local key convention from `local/{uuid}`.

## Locked decisions

| Topic | Decision |
|-------|----------|
| Roster reference after clone | Repoint slot to the cloned `local/{uuid}` key |
| Built-in experts | Keep original `teampilot/builtin/...` key — always resolvable, never cloned |
| Already-local expert | Keep reference, no re-clone |
| Unresolvable expert key | Non-blocking failure, reported in `CloneResult` / toast; slot keeps original key |
| Cross-clone dedup | Record `catalogKey` on local members; reuse existing local copy with matching `catalogKey` |
| Per-clone dedup | One memoized cloner per `clone()` run (`catalogKey → localKey`) |

## Design

### 1. `DiscoverableMember.catalogKey` (provenance)

Add an optional `String? catalogKey` field to `DiscoverableMember` (`client/lib/models/discoverable_member.dart`):

- Records which catalog key a local clone came from (used for cross-clone dedup).
- Updated in `fromJson` / `toJson` / `==` / `hashCode`, and carried through `forLocale` and `LocalMemberTemplateStore.save` (it reconstructs the member explicitly, so it must thread the new field).
- Optional (defaults `null`) — no existing call sites break.

### 2. `ExpertCloneService` (`client/lib/services/expert_hub/expert_clone_service.dart`)

New service injected with `CompositeExpertHubSource` (resolution) and `LocalMemberTemplateStore` (persistence). One instance per `clone()` run — it holds the run-scoped `Map<String, String> _memo` (`catalogKey → localKey`) so a catalog expert referenced by multiple slots is cloned exactly once.

```
Future<ExpertCloneOutcome?> clone({required String expertKey, String? originTeamKey})
```

`ExpertCloneOutcome { final String key; final bool cloned; }` — `key` is what the slot should reference; `cloned` true when a new local copy was created. `null` = failure.

| Input | Behavior |
|-------|----------|
| empty key | failure |
| `local/...` and file exists | keep (same key, `cloned: false`) |
| `local/...` but file missing (dangling) | failure |
| `teampilot/builtin/...` | keep (same key, `cloned: false`) |
| catalog key already in `_memo` | reuse memoized local key |
| catalog key with an existing local member whose `catalogKey` matches | reuse that member's local key (cross-clone dedup; never overwrites user edits) |
| catalog key resolvable | `store.save(resolved.copyWith(catalogKey: key, originTeamKey: originTeamKey))` → new `local/{uuid}`, memoized |
| catalog key unresolvable | failure |

Resolution reuses `ExpertMemberResolver.resolveMember(key, source: ..., localStore: ...)` (local → hub cache → built-in → git source), consistent with existing materialization.

### 3. `TeamCloneService` integration

- Define `typedef ExpertSlotCloner = Future<ExpertCloneOutcome?> Function({required String expertKey, String? originTeamKey});`.
- Add required constructor param `expertClonerFactory` — `ExpertSlotCloner Function()` producing a per-run cloner closure (so `_memo` is scoped to one clone).
- `clone()` flow becomes:
  1. Install skill / plugin / MCP deps (unchanged).
  2. For each roster slot with a non-empty `expertKey`, call the cloner; repoint `slot.expertKey` to `outcome.key` on success; on failure record `DependencyFailure(DependencyKind.expert, key)` and keep the original key.
  3. `createTeam` receives the repointed roster.
- `CloneDepInstallSummary` gains `expertKeys` / `expertCount`; `DependencyKind` gains an `expert` value.
- Progress total counts expert slots alongside skill/plugin/MCP deps.

### 4. Wiring (`client/lib/app/app_shell.dart`)

- Move `compositeExpertHubSource` construction (currently ~line 1005) ahead of `TeamCloneService` (line 951); it only depends on `teamHubSource` (line 947).
- Pass `expertClonerFactory` to `TeamCloneService`, building `ExpertCloneService` per run with `compositeExpertHubSource` and `LocalMemberTemplateStore()`.

### 5. UI / l10n

- `teamHubCloneToastMessage` (`client/lib/pages/team_hub/team_hub_clone_feedback.dart`): include cloned-expert count and expert failures in the success/partial copy.
- Update `client/lib/l10n/app_en.arb` and `app_zh.arb` only; regenerate `app_localizations*.dart`.
- `hubCloneActivityAdapter` history messages in `app_shell.dart` keep working off `CloneResult` (expert failures are `failedDeps`).

### 6. Tests

- `TeamCloneService`: injected fake cloner — repointing, failure recording, counts, progress, memoized-per-run.
- `ExpertCloneService`: catalog expert → saved with `local/{uuid}` + `catalogKey`; already-local → keep; built-in → keep; unresolvable → failure; cross-clone reuse; `_memo` reuse.
- `LocalMemberTemplateStore`: `catalogKey` persists through `save` / `loadAll`.

## Data flow (clone of team T referencing catalog expert X)

```
TeamCloneService.clone(T)
  ├─ install T.skillDeps / pluginDeps / mcpDeps
  ├─ for each slot: cloneExpert(X)
  │    ├─ dedup: existing local member with catalogKey == X.key → reuse it
  │    ├─ resolve X via catalog → DiscoverableMember
  │    ├─ store.save(X.copyWith(catalogKey: X.key, originTeamKey: T.key))
  │    │    → local/{uuid} (memoized in _memo for sibling slots)
  │    └─ slot.expertKey = local/{uuid}
  ├─ createTeam(roster with local keys) → addClonedTeam
  │    └─ _materializeTeam resolves local/... from My Experts → members
  └─ CloneResult { teamId, installed(+experts), failedDeps(+expert) }
```
