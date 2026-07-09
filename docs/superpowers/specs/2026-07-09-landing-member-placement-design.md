# Landing-driven member placement design

**Date:** 2026-07-09  
**Status:** Ready for planning  
**Approach:** Placement-driven replicas (single Landing entry point)

## Summary

Member instance counts (`replicas`) and host assignment move out of the main window / team-config / member-settings surfaces. Both are configured only in the **Landing compose gear → team settings dialog**, using one placement UI for **local**, **remote**, and **mixed** workspaces.

Placement counts are the source of truth for `TeamMemberConfig.replicas`. Non-lead members may be `0`. Hosts may be left empty — there is **no** “every host must get a member” rule. After a normal Machines save, every expanded instance has a target by construction. **Mixed** workspaces require a per-team **first-time placement initialized** flag before team launch.

## Goals

| Goal | Description |
|------|-------------|
| Single entry | Configure replicas + host pins only from Landing team settings |
| Uniform model | local / remote / mixed share the same placement panel and persistence |
| Local defaults | Every member type defaults to `replicas = 1` on the current local host |
| Flexible counts | Non-lead `replicas` may be `0`; empty hosts are allowed |
| Mixed first-run | Mixed workspaces force one explicit Machines save before launch |
| Leader rule | When a local host exists, Leader must be on `local`; pure remote → Leader on that remote host |

## Non-goals (v1)

- Requiring every workspace host to receive at least one member
- Requiring every member type on every host
- Workspace-scoped replica overrides separate from team profile `replicas`
- Keeping replicas steppers in team-config member pages or home team tab
- Changing TeamBus / session runtime identity rules beyond roster expansion

## Current state (baseline)

- `MemberInstance` / `expandTeamRoster` fan out `TeamMemberConfig.replicas` (lead always 1; today `replicas < 1` is coerced to 1).
- `Workspace.memberTargetsByTeam[teamId]` stores `instanceId → targetId`.
- Landing team settings already has a **Machines** pane, but only when topology is **mixed**.
- Replicas are edited in `team_config_member_section.dart` (`_MemberReplicasRow`).
- Launch gates call `workspaceTopologyRequiresMemberAssignment` (mixed-only) + `memberTargetsComplete` (every instance must have a target).

## Design

### 1. Configuration ownership

| Concern | Owner | Persistence |
|---------|-------|-------------|
| Member type persona / CLI / presets | Team profile (unchanged) | `launch-profiles/{id}/profile.json` |
| Instance count per type | Derived from placement on save | `TeamMemberConfig.replicas` on team profile |
| Instance → host pins | Workspace + team | `Workspace.memberTargetsByTeam` |
| Mixed first-time confirmation | Workspace + team | `Workspace.memberPlacementInitializedByTeam` (new) |

**UI rule:** Remove replicas controls from team member settings. Landing team settings **Machines** section is the only place that edits counts/pins.

Secondary workspace settings entry (`WorkspaceTeamMemberTargetsSection`) must use the **same save path** as Landing Machines: write `replicas` + `memberTargetsByTeam` + `memberPlacementInitializedByTeam` together. No targets-only or flag-only save.

### 2. Placement model (unchanged shape, new semantics)

Keep:

```dart
typedef MemberPlacementByTarget = Map<String, Map<String, int>>;
// targetId → memberTypeId → countOnThatHost
```

On save from Landing team settings:

1. For each member type (except lead):  
   `replicas = sum(placement[target][typeId] for all targets)` (may be `0`).
2. Lead: always `replicas = 1`; placement must put that single instance on the **preferred lead host** (see §3).
3. Convert placement → `MemberTargetAssignments` via existing `memberTargetsFromMemberPlacement`.
4. Persist targets with `SessionRepository.updateWorkspaceMemberTargets`.
5. On any Machines save (all topologies), set `memberPlacementInitializedByTeam[teamId] = true`.

### 3. Defaults and Leader constraints

**Preferred lead host**

```
if folders contain localTargetId → local
else → first workspaceTargetIds(folders) entry
```

**Default placement** (when remembered targets are empty / opening Machines for the first time):

| Topology | Default |
|----------|---------|
| local | Each valid member type count `1` on `local` |
| remote (single non-local target) | Each valid member type count `1` on that target |
| mixed | Lead `1` on preferred lead host; other types start at `0` everywhere (user must place) **or** restore from remembered targets if present |

**Hard constraints (always)**

- Lead is a singleton (`replicas = 1`).
- If workspace has a local folder, lead’s target **must** be `local`.
- If workspace has no local folder, lead’s target must be a folder-backed target (the single remote, or one of the remotes in multi-remote mixed).

**Soft / allowed**

- Non-lead type total count may be `0` (type omitted from runtime roster).
- Empty hosts are allowed (no “every host must have a member” check).
- After a successful Machines save, placement → replicas → targets are consistent: every expanded instance has a pin. “Unassigned instances” are **not** a supported post-save state from the editor; they only appear as **stale drift** (roster/host changes without a new Machines save) and are handled in §5.

### 4. Mixed first-time initialized flag

Add to `Workspace`:

```dart
/// teamId → user has confirmed Machines placement at least once for mixed use.
final Map<String, bool> memberPlacementInitializedByTeam;
```

JSON key: `memberPlacementInitializedByTeam`. Omit empty map. Missing key / missing team → `false`.

**When `false` and topology is mixed**

- Landing gear shows attention affordance (`landingTeamSettingsNeedsAttention`).
- `WorkspaceLandingLaunchGate.syncBlock` returns a block (rename/repurpose today’s incomplete-targets block to “placement not initialized”).
- Opening team settings should prefer the Machines pane.
- Save is allowed when lead constraints hold; save sets the flag `true` even if non-lead counts are all `0`.

**When `true`**

- Do **not** block launch solely because non-lead `replicas` are `0` or because stale drift left some expanded instances without pins (those instances are omitted per §5.4).
- Still block if lead constraint is violated.

**local / remote**

- Do not require the flag for launch.
- **Silent default materialization** runs only when creating/opening a team session if remembered targets for that team are empty: write default placement (§3), derived replicas (no-op if already 1), targets, and optionally set the flag `true`. Opening the Machines pane alone must **not** persist defaults until the user saves (pane may *display* defaults in-memory).

**Reset flag to `false` for a team when**

- Workspace topology becomes **mixed** from non-mixed, **or**
- The set of `workspaceTargetIds(folders)` changes (host added/removed) while topology is mixed.

Rationale: structural host changes invalidate the prior “I already decided” confirmation; user must re-open Machines once.

### 5. Roster expansion and launch

Update `expandTeamRoster` / `memberTypeReplicaCount`:

- Lead → always 1 instance.
- Non-lead with `replicas <= 0` → **zero** instances (stop coercing `< 1` to `1`).
- Non-lead with `replicas = n` → `n` instances as today.
- Keep `instanceId` rules consistent when totals move `0 ↔ 1 ↔ n` after placement saves (`replicas <= 1` → bare type id; `replicas > 1` → `{typeId}-{ordinal}`).

**Chosen session-create rule (one behavior only):**

1. Expand roster with the zero-replica rule (`replicas = 0` → no instances / no bindings).
2. Resolve `memberTargets` from workspace memory (copied onto the session).
3. **Single-host** (local or remote): if an expanded instance has no target, implicitly pin it to the sole host before create (and persist back to workspace memory when materializing defaults per §4).
4. **Mixed** (and flag is `true`): **omit** any expanded instance that lacks a resolvable target for a current folder-backed host from **both** `AppSession.members` bindings **and** the TeamBus roster for that session. Do **not** create a binding and later skip connect. Do **not** invent mixed pins at launch. Stale target keys for removed hosts are dropped.
5. If lead would be omitted or land on an invalid host, block launch (`leadPlacementValid` failed) instead of creating a leaderless session.
6. Replace mixed-only `memberTargetsComplete` launch gates with: `workspaceNeedsMixedPlacementInit` + `leadPlacementValid`.

`workspaceTopologyRequiresMemberAssignment` should be replaced or narrowed to those explicit helpers — do not overload “requires assignment” to mean both “show UI” and “must be complete”.

### 6. Landing team settings UI

Dialog sections:

1. Team (unchanged)
2. Members (launch/preset knobs; **no replicas stepper**)
3. Machines — **always listed** for team mode (local / remote / mixed)

Machines pane:

- Reuse `MixedWorkspaceMemberPlacementPanel` (rename if needed to drop “Mixed-only” naming in user-facing copy).
- **Panel rewrite vs today:** current +/- is capped by profile `memberTypeReplicaCount`. Under placement-as-source-of-truth, **+ is unbounded** for non-lead types (practical UI max allowed, e.g. 99); **−** may reach 0 on a host and total replicas may reach 0. Header `placed/total` uses `total = sum of counts across hosts` (may be 0); do not read a separate profile replicas cap.
- Lead row: cannot go below 1 on preferred lead host; cannot place lead on a non-preferred host when local exists.
- Footer: Save enabled when lead constraint holds (no “all instances assigned” requirement).
- Mixed + uninitialized: subtitle / hint that first confirmation is required before launch.

Attention dot on Landing gear:

```
mixed && !memberPlacementInitializedByTeam[teamId]
  || !leadPlacementValid(...)
```

### 7. Error handling / copy

- Mixed uninitialized launch → open team settings Machines (or show block message pointing there); do not auto-save defaults silently for mixed.
- Lead not on local when local exists → inline validation on Machines + block save/launch.
- l10n: adjust strings that say “every member instance must be assigned”; introduce first-time mixed confirmation copy.

### 8. Testing

| Area | Cases |
|------|-------|
| `expandTeamRoster` | `replicas: 0` → no instances; lead still 1 |
| Workspace JSON | `memberPlacementInitializedByTeam` round-trip; omit when empty |
| Defaults | local/remote default placement; mixed default lead-on-local |
| Gate | mixed + flag false blocks; flag true + stale unpinned non-lead omits bindings and still launches; lead-on-wrong-host blocks |
| Flag reset | target set change / topology→mixed clears flag |
| Landing dialog | Machines always visible; save writes replicas + targets + flag |
| Team config UI | replicas row gone |
| Session create | zero-replica types omitted; single-host implicit pin |

## Migration

- Infer `memberPlacementInitializedByTeam[teamId] = true` on read **only when** topology is mixed, the new map lacks the team key, remembered `memberTargetsByTeam[teamId]` is **non-empty**, and every remembered target id is still in `workspaceTargetIds(folders)` (and lead constraint holds if lead is present in targets). Empty or stale maps stay uninitialized so users re-confirm.
- Prefer infer in repository load (not necessarily rewrite disk until next workspace save).
- Existing `replicas < 1` on disk: after code change, they mean “no instances”; acceptable (previously coerced to 1). No automatic bump.

## Files likely touched

- `client/lib/models/workspace.dart` — new map field
- `client/lib/models/workspace_topology.dart` — init helpers, lead validation, stop mixed-only complete gate
- `client/lib/models/member_instance.dart` — allow zero replicas
- `client/lib/pages/home_workspace/workspace/workspace_landing_team_settings_dialog.dart`
- `client/lib/pages/home_workspace/workspace/mixed_workspace_member_placement_panel.dart`
- `client/lib/pages/home_workspace/workspace/config/workspace_team_member_targets_section.dart` (+ dialog) — same save path as Landing
- `client/lib/pages/team_config/team_config_member_section.dart` — remove replicas row
- `client/lib/services/launch/workspace_landing_launch_gate.dart` (+ readiness / pipeline / session_repository gates)
- `client/lib/repositories/session_repository.dart` — persist flag; reset on folder/target changes; shared Machines save helper
- l10n `app_en.arb` / `app_zh.arb`
- tests under `client/test/models/`, `client/test/services/launch/`, landing/team settings widget tests

## Success criteria

1. User never needs team-config member page to set instance counts.
2. Local team launch works with zero Machines interaction (defaults).
3. Mixed team launch requires one Machines save the first time (or after host-set reset).
4. Non-lead members can be set to zero instances and are not launched.
5. Leader stays on local whenever the workspace has a local folder.
