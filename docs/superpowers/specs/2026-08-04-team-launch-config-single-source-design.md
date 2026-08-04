# Team launch config — single source of truth (design)

**Date:** 2026-08-04  
**Status:** Approved for planning  
**Scope:** Eliminate dual team launch defaults (`activePresetId` vs `providerIdsByTool` / `modelsByTool` / `cliEffortLevels`) that cause Claude members to miss API credentials (login screen) while UI shows “inherit team default”. No backward/forward compatibility; no legacy dual-path shims.

**Primary bug scope:** `TeamMode.native` (including replicated pods). Mixed-mode profile writes stay as today except where materialize / team-shape normalize is CLI-agnostic.

## Problem

1. **Two team-default stores coexist** on `TeamProfile`:
   - `activePresetId` — UI “team default preset” (e.g. DeepSeek).
   - `providerIdsByTool` / `modelsByTool` / `cliEffortLevels` — custom-per-CLI bindings (e.g. residual `claude-official`).
2. **`setTeamActivePreset` does not clear** custom bindings; `updateTeamCustomLaunch` clears the preset. Asymmetry leaves dirty profiles.
3. **`ExpertMemberMaterializer._applyTeamInheritance`** stamps empty `member.provider` from `providerIdsByTool` even when the member will inherit a preset (`__inherit__`).
4. **Claude settings write path** (`_loadMemberProviderSettings`) iterates raw `team.members` (stamped official) and only fully resolves the *currently launching* seat. Sibling pods / lead get settings without third-party tokens → Claude login UI.
5. **Parallel `stage-session`** rewrites all member settings; incomplete sibling maps drop tokens.
6. **`resolveTeamLaunchBundle`** falls back to custom maps when preset id is missing — silent wrong provider after normalize clears maps.

UI and intended product rule: team preset **is** the team default when set.

## Goals

1. **One team launch shape at a time:** Preset **xor** Custom — never both after normalize.
2. **One resolution pipeline** for staging and PTY: `resolveMemberLaunch` → `memberForLaunch` → `resolveTeamRosterForLaunch` for every seat (including replica pods).
3. **Claude member settings** keyed by **session pod id** with credentials from that resolved launch config.
4. **Order-independent multi-seat staging.**
5. **Tests** cover native replicated + team preset + inherit (third-party auth on disk).

## Non-goals

- Claude teammateMode / inbox / doorbell.
- Redesigning preset catalog chrome beyond mutual exclusion.
- Preserving dirty dual-state profiles.
- Compat shims or permanent “prefer X if Y” branches.
- Full redesign of mixed-mode per-seat Claude profile writes (document only; see Mixed).

**Load normalize is intentional migration**, not a dual-read shim: dirty disk is rewritten in memory (and on next save) to a single shape.

## Locked decisions

| Topic | Decision |
|-------|----------|
| Architecture | Approach C — single source of truth |
| Team shapes | `preset` \| `custom` |
| Dirty team load | If `activePresetId` non-empty → Preset (clear **all** custom launch maps); else Custom |
| Dirty inherit members | Clear persisted `provider` / `model` / `effort` on inherit seats at materialize / normalize |
| Materialize vs launch | Materialize must **not** stamp team custom maps onto inherit seats. Launch resolution **may** put concrete provider/model/effort on **in-memory** copies only |
| Settings keys | Pod / seat id after session roster (or runtime expand when no session) |
| Stale preset id | Preset shape + missing catalog entry → validation blocks launch; **no** fallback to custom maps |
| Legacy team provider bind API | **Remove** API and onboarding call sites (no redefine) |
| Compat | None |

## Mixed mode

- **In scope for this change:** team-shape normalize, materialize inherit rules, and any shared resolver cleanup (CLI-agnostic).
- **Out of scope:** changing mixed “only write launched member Claude profile” behavior; forcing a team Claude preset’s CLI onto non-Claude mixed experts (leave `memberForLaunch` mixed CLI rules as today unless a test already pins otherwise).
- **Custom shape (mixed):** `providerIdsByTool` may contain one entry per CLI tool the roster uses. **Preset shape:** clear **all** keys in the three custom maps (not only `team.cli`).

## Domain model

### Team launch shape

```dart
enum TeamLaunchShape { preset, custom }

TeamLaunchShape teamLaunchShape(TeamProfile team) {
  final id = team.activePresetId?.trim() ?? '';
  return id.isNotEmpty ? TeamLaunchShape.preset : TeamLaunchShape.custom;
}
```

**Invariant after `normalizedLaunchConfig()`:**

| Shape | Required | Forbidden |
|-------|----------|-----------|
| `preset` | non-empty `activePresetId` | any non-empty `providerIdsByTool` / `modelsByTool` / `cliEffortLevels` |
| `custom` | `providerIdsByTool` for `team.cli` when launch requires a provider | `activePresetId != null` |

Helpers on `TeamProfile` (names flexible):

- `asPresetLaunch(String presetId, {CliTool? syncCli})`
- `asCustomLaunch(...)` — clear preset + `withLaunchDefaultsForCli`
- `normalizedLaunchConfig()` — dirty → shape; also used on load

**Save:** defensive assert / normalize before persist.  
**Load:** always normalize (silent). Disk may briefly stay dirty until save.

### Member launch

Keep `MemberLaunchMode`: `inheritTeam` | `memberPreset` | `custom`.

- Empty roster `activePresetId` → default `__inherit__`.
- Inherit seats: persisted overrides for provider/model/effort must be empty after normalize/materialize.
- `memberPreset` while team is preset-shaped: member’s explicit preset wins for that seat (unchanged product rule); covered by unit test.
- Continue overrides that freeze concrete provider/model remain last-wins at finalize (existing); they clear inherit sentinel when applying concrete fields (existing).

### Resolution pipeline

```
team.normalizedLaunchConfig()
  + seats (session pods if session else runtime expand)
  + globalPresets
→ resolveTeamRosterForLaunch / memberForLaunch
→ concrete provider/model/effort per seat (in-memory)
→ resolve(providerId) per seat
→ settingsByMember[seat.id]
→ write settings/<safe(seat.id)>.json
```

### Claude API

```dart
Future<ClaudeLaunchExtras> resolveLaunchExtras({
  required TeamProfile team, // already normalized by caller
  required List<TeamMemberConfig> launchResolvedMembers, // ctx.members
  required TeamMemberConfig? launchedMember,
  required ClaudeProviderSettingsResolver resolver,
});
```

Rules:

- `_loadMemberProviderSettings` **must not** iterate `team.members`.
- Map keys are pod/seat ids from `launchResolvedMembers`.
- `ClaudeProviderSettingsResolver.resolveProviderId` / `resolveTeamClaudeSettings` / `resolveMemberClaudeSettings`:
  - Preset shape → bundle provider from `resolveTeamLaunchBundle` (preset only; **no** custom-map fallback).
  - When resolving an inherit seat, callers pass launch-resolved member; resolver must not prefer a stale raw `member.provider` left on persist (persist should be empty after normalize).

### Official OAuth vs third-party

| Provider kind | Settings env | Credentials |
|---------------|--------------|-------------|
| Third-party (e.g. DeepSeek) | Must include auth token / base URL on **every** inheriting seat file | From provider record |
| Official (`claude-official`) | No third-party token env | `_maybeLinkOfficialCredentials` for **each** Claude seat being staged in the pass (not only launched), or one shared `CLAUDE_CONFIG_DIR` link strategy documented in code — pick **per-seat link on full roster write** for native |

Acceptance splits accordingly (below).

### Stale preset id

- Shape remains `preset` if id string non-empty.
- `resolveTeamLaunchBundle`: if shape is preset and preset missing from catalog → unconfigured bundle (`provider` empty); **do not** read custom maps.
- Launch validator emits existing / aligned issue (e.g. team default provider missing) and blocks launch.

## Mutation API

| API | Behavior |
|-----|----------|
| `setTeamActivePreset(id)` | `asPresetLaunch` — clear all custom launch maps |
| `updateTeamCustomLaunch` | `asCustomLaunch` — clear preset |
| Legacy team provider bind API | **Delete** + remove onboarding / app_shell call sites |

## Claude staging

1. `ConfigProfileService` already resolves roster via `_resolveTeamLaunchRoster` into `ctx.members` — pass that list into `resolveLaunchExtras`.
2. Session present → seats = `cliTeamRosterMembers` (pods). Preview / no session → same expand used for launch preview (`runtimeRosterMembers` / equivalent), then `memberForLaunch`.
3. Each `contributeLaunch` rewrite uses the **full** resolved settings map (order-independent).
4. Native: write profiles for all seats in `launchResolvedMembers`. Mixed: keep current “launched only” write policy.

## Data flow

**Before:** dual team fields → stamp official on inherit → settings map keyed by types / partial pods → login.

**After:** normalize to Preset → inherit seats empty provider → `memberForLaunch` DeepSeek for lead + all pods → every `settings/<pod>.json` has auth env (third-party).

## Testing plan

1. Dirty disk JSON (`activePresetId` + `providerIdsByTool`) → load/normalize → preset shape only; inherit members have empty provider.
2. `asPresetLaunch` / `asCustomLaunch` exclusivity.
3. `setTeamActivePreset` clears custom maps (cubit/helper).
4. Materialize inherit under preset team: no stamped provider.
5. `resolveTeamLaunchBundle` preset shape + missing preset → empty provider (no custom fallback).
6. `contributeLaunch` / resolveLaunchExtras: fixture third-party team preset + inherit + replicas=2 → `team-lead`, `developer-0`, `developer-1` settings all contain auth env keys.
7. Sequential contributeLaunch for `developer-0` then `developer-1` — all three files still have tokens.
8. Member explicit `memberPreset` not overwritten by team preset.
9. Official fixture: native inherit seats get official-shaped settings + credential link for each seat dir (or shared dir assertion).
10. No remaining call sites for legacy team provider bind API.
11. Cross-link: matrix `claude × native × replicated` L2 remains green after fix (manual/CI when PTY available); unit chain is the merge gate.

## Acceptance

1. After load/save normalize, a team never has both non-empty `activePresetId` and non-empty custom launch maps.
2a. Third-party team preset + inherit + replicas=2 → every seat settings file has provider auth env.
2b. Official team preset + inherit + replicas=2 → official-shaped settings per seat; credentials linked per seat on full roster write.
3. Preset ↔ Custom switches clear the other side.
4. Inherit members never **persist** non-empty provider/model/effort overrides.
5. No dual-prefer / custom-fallback-in-preset-shape branches; deleted obsolete tests.

### No-compat checklist (done when all true)

- [ ] No read path uses `providerIdsByTool` when shape is preset.
- [ ] No legacy team provider bind API.
- [ ] `resolveTeamLaunchBundle` does not fall back to custom maps in preset shape.
- [ ] Inherit roster overrides never persist non-empty `provider`.
- [ ] Tests asserting dirty dual-state as valid behavior are removed/replaced.

## Implementation notes

- Call `normalizedLaunchConfig()` from launch-profile load / `updateSelected` / hub import — one function, no missed paths.
- `resolveLaunchExtras` consumes `ctx.members`; do not re-read `team.members` inside capability.
- Align `ClaudeProviderSettingsResolver` three entry points with shape rules.
- Materialize fix is CLI-agnostic (all tools).
- Files (expected): `team_config.dart` / helpers, `preset_resolver.dart`, `expert_member_materializer.dart`, `launch_profile_cubit.dart`, `claude_config_profile_capability.dart`, `claude_provider_settings_resolver.dart`, `config_profile_service.dart`, onboarding/app_shell bind call sites, tests under `client/test/services/...`.
