# Resource Provisioning Redesign (Phase A)

- **Date:** 2026-06-14
- **Status:** Design approved, pending implementation plan
- **Scope:** Phase A of a two-phase effort. Phase A redesigns how *linkable
  resources* (skills, plugins, MCP servers) are provisioned into a CLI's runtime
  config directory across all three session modes. Phase B (separate spec) will
  unify the launch orchestration itself (`LaunchPlan` / mode resolution). Phase A
  is designed to be a clean seam for Phase B but does not depend on it.
- **Constraints from the owner:** Optimize for the best architecture,
  reusability, readability, and performance. Do **not** preserve backward
  compatibility (consistent with AGENTS.md: "No backward compatibility" for team
  session runtime paths). Effort is not a constraint.

## 1. Problem

Skills that the user installs/enables do **not** take effect in **personal
(simple) mode** and **mixed team mode**; repeated fixes have failed to hold. The
same defect class is expected for plugins and MCP servers. The root structural
cause is not a single bug but the provisioning architecture.

### 1.1 Current architecture (push / staging-trust)

Resource provisioning today is **push-based** and split across two unrelated
trigger points, implemented as hardcoded shared logic in
`ConfigProfileService` + `CliDataLayout` (NOT a per-CLI capability), with a
separate hand-written method per (resource × mode) — 9 combinations:

| Mode | Who populates the staging layer | How it reaches the CLI's real CONFIG_DIR |
|------|----------------------------------|------------------------------------------|
| personal | UI `ProjectProfileCubit` manual sync → `standalone/projects/<id>/<tool>/skills/` (project layer) | launch copies project layer → `.../sessions/<sessionId>/<tool>/skills/` (an **extra hop**) |
| native | UI `TeamResourceSyncService` continuous sync → `teams/<teamId>/<tool>/skills/` (team layer) | launch provisions team layer → `.../members/<cliTeamName>/<tool>/skills/` |
| mixed | same as native | same as native, with an extra `<memberId>` nesting level |

Two independent problems follow:

1. **Launch is not the source of truth.** The launch path *trusts* that some UI
   cubit already populated a staging directory. If that sync never ran (or ran
   against a different layer/mode), the leaf CONFIG_DIR the CLI actually reads
   ends up empty → "installed but not effective." Personal mode is worst: it has
   an additional project-layer → session-layer copy hop, so it is doubly
   dependent on prior state.
2. **No reusable abstraction.** 3 resource kinds × 3 modes = 9 bespoke
   `provision*` methods with subtly different semantics, none of it expressed as
   a CLI capability, so every fix must be re-applied per mode and silently
   misses the others.

The canonical install location for skills/plugins is already the global library
(`<teampilotRoot>/skills/<id>`, `<teampilotRoot>/plugins/<id>`); the existing
linkers already symlink *from* there. The only thing the intermediate layers add
is fragility and an extra copy.

### 1.2 Root-cause verification is still required

The "staging layer was never populated" explanation is a **strong hypothesis,
not yet proven**. Implementation MUST begin (TDD) with a failing test that
reproduces the exact mechanism in personal mode (enable a skill → launch →
assert the leaf CONFIG_DIR contains it). We do not declare the bug fixed on the
strength of the hypothesis; we confirm the mechanism with evidence first. The
structural redesign below makes the whole class impossible regardless, but the
verification step stays.

## 2. Goals / Non-goals

**Goals**
- Skills, plugins, and MCP servers take effect identically in personal, native,
  and mixed modes.
- A single, mode-agnostic, reusable provisioning core; per-CLI differences
  expressed only as a thin capability.
- Launch is the single source of truth: correctness no longer depends on whether
  a UI cubit synced beforehand.
- Better performance than today's copy chain.
- A clean seam for Phase B.

**Non-goals (Phase A)**
- Unifying the launch orchestration / mode resolution (`session_launch_service`
  vs `session_lifecycle_service` double dispatch) — that is Phase B.
- Provider/credential/settings provisioning — stays as-is; not folded into the
  resource manifest.
- The 9 non-launch `if (cli == ...)` special cases in provider/llm_config/team
  validation code — out of scope (different domain).

## 3. Design: declarative pull-based provisioning

Invert the model: at launch, compute the **effective enabled resource set** for
the scope (from the user's stored enable lists), then **idempotently
materialize** it directly into the leaf CONFIG_DIR the CLI reads. Whether a UI
cubit synced, or a staging directory is stale, becomes irrelevant.

### 3.1 Domain model (pure data, no IO)

- `ResourceKind` = `skill | plugin | mcp`.
- `ResourceRef` — identity of one enabled resource: `id` + canonical source
  location pointing straight at the global library
  (`<teampilotRoot>/skills|plugins/<id>`). No intermediate copies.
- `ResourceScope` — unifies all three modes:
  - `personal(projectId, sessionId)`
  - `teamMember(teamId, cliTeamName, member, mixed)` — covers native and mixed;
    the `mixed` flag only changes how the leaf scope id is nested.
- `EffectiveResourceSet` — resolved `ResourceRef`s grouped by `ResourceKind`.

### 3.2 Components (one set, shared across all modes / kinds / CLIs)

**`ResourceResolver`** (pure function; unit-testable with no filesystem)
`EffectiveResourceSet resolve(ResourceScope scope, CliTool cli)`. Computes the
`app default → team/project → member override` inheritance **in memory**, reading
from the existing enable-list stores (personal: `ProjectProfile`; team: team
config + member override — the same `skillIds`/`pluginIds` lists currently passed
to the linker services' `syncForProject`/`syncForTeam`). Inheritance lives only
in memory; the disk no longer carries inheritance layers.

**`ResourceMaterializer`** (the only component that touches disk; idempotent)
`reconcile({configDir, kind, desired, strategy})`: list the current contents of
`configDir/<kind>/`, diff against `desired`, add what is missing, remove what is
stale, leave correct entries untouched. Running it twice produces zero changes on
the second run. This absorbs the "full reconcile" idea — the leaf directory is a
reconciled projection of the desired set, not an incrementally mutated pile.

**`ResourceCapability`** (per-CLI, thin; lives in the registry)
Each CLI declares only: (1) `supportedKinds`; (2) where each kind lands inside the
CONFIG_DIR (the `skills/` dir, the `plugins/` dir, or the MCP config JSON file);
(3) the representation per kind — `linkedDirectory` (skills/plugins) or
`mergedJsonEntry` (mcp). **No provisioning logic.** It composes into the existing
`CliToolDefinition`.

**`ResourceProvisioningService`** (orchestration)
`provisionForLaunch(scope, cli, configDir)` = `resolve` → for each
`supportedKind`, `materialize`. The launch path calls **only** this one entry
point, the same line for all three modes. It replaces the 9 hand-written
`provision*` methods.

### 3.3 Data flow at launch (identical for all modes)

```
launch
 └─ ResourceProvisioningService.provisionForLaunch(scope, cli, configDir)
      ├─ ResourceResolver.resolve(scope, cli)        # in-memory effective set
      └─ for kind in capability.supportedKinds:
            ResourceMaterializer.reconcile(
               configDir, kind,
               desired   = effectiveSet[kind],
               strategy  = junction → symlink → copy)
```

The mode only influences how `ResourceScope` is constructed upstream; steps
inside `provisionForLaunch` are mode-agnostic.

The UI cubits (`ProjectProfileCubit`, `TeamResourceSyncService`) are demoted to
**editing the enable lists only**. They MAY call the same service for instant
preview, but launch always re-reconciles, so they are never correctness-critical.

### 3.4 Directory model (eliminate intermediate physical layers)

On disk, each launch scope has **only the leaf CONFIG_DIR**. Skill/plugin
symlinks point **directly at the global library** (`<teampilotRoot>/skills|plugins/<id>`).
Inheritance is computed by `ResourceResolver` in memory and never materialized as
nested physical staging dirs.

`cli_data_layout.dart` deletes the staging/inheritance path helpers it no longer
needs, including `standaloneProjectSkillsDir`, `standaloneProjectPluginsDir`,
`teamSkillsDir`, `teamPluginsDir`, the resource-related parts of
`ensureMemberInheritsTeam`, and the provision methods
`provisionStandaloneSessionSkillsFromProject` / `provisionMemberSkillsFromTeam`
(and their plugin/mcp equivalents). `config_profile_service.dart` drops the
matching calls. The four linker services
(`project_skill_linker_service`, `project_plugin_linker_service`,
`team_skill_linker_service`, `team_plugin_linker_service`) collapse into the
shared resolver + materializer rather than each owning a `_syncWithFilesystem`.

### 3.5 Link strategy & performance

A single `LinkStrategy`: **junction (Windows directories, no admin) → symlink →
copy fallback**, centralized in the materializer instead of duplicated in each
linker. Performance: reconcile reads each `configDir/<kind>/` listing once, diffs
in memory, and only touches disk on the delta; directory symlinks are O(1) versus
the current O(size) copy.

### 3.6 Error handling

- Enabled but the canonical install is missing → `AppLogger` diagnostic + an
  l10n UI warning; skip that ref, **do not fail the launch**.
- Link creation fails (permissions) → fall back to copy; if copy also fails →
  diagnostic + warning, skip ref.
- MCP server name collision across levels → fixed precedence
  `member > team > app`; last writer wins per server name.
- Materialization is best-effort per ref: one bad ref never breaks the others.

## 4. Module / file layout (respects layering & file-size conventions)

```
client/lib/services/resource/
  resource_kind.dart                 # ResourceKind enum, ResourceRef, EffectiveResourceSet
  resource_scope.dart                # ResourceScope (personal | teamMember)
  resource_resolver.dart             # pure in-memory inheritance/override merge
  link_strategy.dart                 # junction → symlink → copy, centralized
  resource_materializer.dart         # idempotent reconcile of one kind into a dir
  resource_provisioning_service.dart # resolve → materialize orchestration
client/lib/services/cli/registry/resource/
  resource_capability.dart           # interface: supportedKinds, landing dir, representation
  <tool>_resource_capability.dart    # per-CLI thin declarations
(slimmed) cli_data_layout.dart, config_profile_service.dart,
          project_skill_linker_service.dart, project_plugin_linker_service.dart,
          team_skill_linker_service.dart, team_plugin_linker_service.dart
```

No `Process.run`/raw paths in UI; all IO via `AppStorage.fs` / `CliDataLayout`;
state via cubits only. Logging: diagnostics → `AppLogger`, user-facing → l10n
(`app_en.arb` + `app_zh.arb`).

## 5. Testing

- **Resolver unit tests** (no FS): inheritance + override merge across
  app/team/member; personal vs team scope resolution.
- **Materializer unit tests** (inject `AppStorage.fs` / temp FS): idempotency
  (second `reconcile` is a no-op), adds missing, removes stale, leaves correct
  entries untouched; link → copy fallback path.
- **Cross-mode parametric test (key regression lock):** one enable list ×
  {personal, native, mixed} → assert all three leaf CONFIG_DIRs end with
  identical resource landings. This directly pins the reported bug.
- **Capability tests:** MCP merge precedence (`member > team > app`).
- **Root-cause TDD anchor:** a first, currently-failing test reproducing
  "personal: enable skill → launch → skill present in leaf CONFIG_DIR" — must fail
  before the redesign and pass after.
- Mock subprocess/filesystem via constructor injection; cubit tests touching
  `AppStorage` use `setUpTestAppStorage()` / `tearDownTestAppStorage()`.
- Before done: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
  && flutter test --exclude-tags integration`.

## 6. Phase B seam

`ResourceResolver` / `ResourceMaterializer` / `ResourceProvisioningService` know
nothing about launch orchestration. When Phase B introduces a unified
`LaunchPlan`, it calls `provisionForLaunch` at a single point. No rework of the
provisioning core is anticipated.
