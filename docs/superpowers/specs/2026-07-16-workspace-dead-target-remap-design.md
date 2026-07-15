# Workspace dead-target remap

## Problem

Mixed workspaces pin folder hosts via `WorkspaceFolder.targetId` (e.g. `ssh:{profileId}`). The folders editor **locks** target changes when topology is mixed (`WorkspaceFoldersEditor._targetsLocked`). Member Machines UI only redistributes roster counts across **existing** folder hosts.

If an SSH profile is deleted or rebuilt with a new id, folders and `memberTargetsByTeam` keep the dead `ssh:…` id. Launch then fails with `No SSH profile for target "ssh:…"`, and the UI cannot repair it without recreating the workspace.

## Goals

- Recover mixed (and any multi-host) workspaces when a pinned runtime target is **dead**.
- Keep healthy mixed topology locked: remap is a **remediation**, not free retargeting.
- One repository API that rewrites folders, workspace member pins, and session snapshots together (logical transaction — not filesystem ACID).
- Kind-agnostic liveness so WSL (or future kinds) can plug in later.

## Non-goals

- Allow arbitrary folder machine changes on healthy mixed workspaces.
- Silently auto-remap by host/user heuristics.
- Rewrite remote filesystem paths as part of remap.
- Change team `roster.overrides.replicas` counts (those are placement counts, not machine ids).

## Concepts

| Term | Meaning |
|------|---------|
| **Target id** | `RuntimeTarget.id` (`local`, `wsl:…`, `ssh:{profileId}`) |
| **Dead target** | An id that fails liveness for its kind (SSH: profile missing from `SshProfileRepository`) |
| **Remap** | Replace every persisted use of `fromTargetId` with `toTargetId` inside one workspace |

## Architecture

```
UI (Folders / Machines / connect error)
        │
        ▼
WorkspaceTargetRemapDialog  ──selects──►  listSelectable() candidates
        │
        ▼
SessionRepository.remapWorkspaceTarget(...)
        │
        ├── pure: WorkspaceTargetRemap.apply(...)   // folders + pins + sessions
        ├── write workspace manifest
        ├── write affected session manifests
        └── side effects: invalidate provision, dispose RuntimeContext(from)
```

### 1. Pure transform — `WorkspaceTargetRemap`

Path: `client/lib/services/workspace/workspace_target_remap.dart` (name may follow repo conventions).

```dart
class WorkspaceTargetRemapResult {
  final List<WorkspaceFolder> folders;
  final Map<String, MemberTargetAssignments> memberTargetsByTeam;
  final List<AppSession> sessions; // only those that changed
}

WorkspaceTargetRemapResult apply({
  required List<WorkspaceFolder> folders,
  required Map<String, MemberTargetAssignments> memberTargetsByTeam,
  required List<AppSession> sessions,
  required String fromTargetId,
  required String toTargetId,
});
```

Rules:

- Every folder with `targetId == from` → `to`.
- Every pin value `== from` in every team map → `to`.
- Every session whose `memberTargets` values or `folders[].targetId` contain `from` → rewritten copy.
- No-op if `from == to`.
- Throw / assert if `from`/`to` empty.

Keep `memberPlacementInitializedByTeam` **unchanged** when remap preserves pin completeness (same instance keys, only host id changes). Callers may still invalidate provision.

Unit-test this module thoroughly (folders only, pins only, both, multi-team, session snapshot divergence).

### 2. Liveness — `TargetLiveness`

Path: `client/lib/services/workspace/target_liveness.dart`.

```dart
abstract class TargetLiveness {
  Future<bool> isAlive(String targetId);
}

class DefaultTargetLiveness implements TargetLiveness {
  // local → always alive
  // ssh: → SshProfileRepository.findById(sshProfileIdOfId)
  // wsl: → optional probe later; until then treat as alive if listed by registry
}
```

UI lists dead ids from `workspaceTargetIds(folders)` (and optionally pin values not in folder set) via `isAlive == false`.

### 3. Repository transaction — `SessionRepository.remapWorkspaceTarget`

```dart
Future<Workspace> remapWorkspaceTarget(
  String workspaceId, {
  required String fromTargetId,
  required String toTargetId,
});
```

Steps:

1. Load workspace + sessions; reject if `from` unused in **folders ∪ memberTargetsByTeam ∪ session snapshots** (so session-only stale ids still remap).
2. Validate `to` is alive (`TargetLiveness`) and, for UI-driven calls, in selectable catalog.
3. `apply(...)`.
4. Persist workspace (folders + `memberTargetsByTeam`) in one write path — **do not** call `updateWorkspaceFolders` alone (that resets placement init without rewriting pins).
5. Persist each changed session.
6. Return updated workspace.

After return, app shell / cubit:

- Reload workspace data (`loadWorkspaceData` or equivalent) so UI and provision see new ids.
- `ChatCubit.invalidateWorkspaceProvision` (and any target-scoped caches for `from` / `to`).
- `RuntimeContextRegistry.dispose(fromTargetId)` only when no active transports still hold that context.

### 4. UI surfaces (same dialog)

**`showWorkspaceDeadTargetRemapDialog`**

Inputs: `workspace`, `fromTargetId` (optional: if null, dialog lists all dead targets first), `TargetLiveness`, selectable targets.

Confirm copy: warn that directory paths are unchanged and must exist on the new machine.

Entrypoints:

| Surface | Behavior |
|---------|----------|
| **Workspace Folders** | Dead host group shows error chip + “Remap…” even when mixed-locked |
| **Team Settings → Machines** | Left host list marks dead hosts; same dialog |
| **Connect / provision failure** | If error matches missing SSH profile for `ssh:…`, offer “Remap machine…” action that opens the dialog with that id |

Healthy mixed rows stay locked (`allowRowTargetChange: false`).

## Data flow

```
Dead ssh:old-id on folders + memberTargetsByTeam + session pins
        │ user confirms remap → ssh:new-id
        ▼
apply() rewrites all three
        ▼
disk: workspace.json (+ sessions/*.json)
        ▼
UI reload / loadWorkspaceData
        ▼
provision + connect use live profile
```

## Error handling

| Case | Behavior |
|------|----------|
| `from` not present | No-op error to UI (“nothing to remap”) |
| `to` dead / missing | Reject before write |
| `to` already used as another host in same workspace | **Allowed** (merge hosts); document that two folder groups become one target id |
| Persist fails mid-session writes | Prefer workspace-first then sessions; on session failure log and surface partial success — ideal is single transactional writer if filesystem layout allows; otherwise document best-effort session follow-up + retry |

Merging two folder groups onto one target id is intentional and useful when replacing a deleted profile with an existing machine already in the workspace.

## Testing

- Pure `apply` matrix (see above).
- Repository test with in-memory / temp FS: folders + pins + one session rewritten; placement init flags unchanged when pins stay complete.
- Widget/dialog test optional; at least pump remap dialog candidate filtering (exclude `from`, exclude other dead ids).
- Liveness: missing SSH profile → dead; present → alive.

## Success criteria

- Mixed workspace with deleted SSH profile can be repaired without recreating the workspace.
- Healthy mixed folder targets remain non-editable.
- Launch after remap no longer throws `No SSH profile for target` for the old id.
- Remap logic is unit-tested without Flutter UI.

## Follow-ups (out of scope)

- Path existence check on destination host after remap.
- Auto-suggest replacement profile by host:port:user.
- Bulk remap across workspaces when a profile is deleted.
