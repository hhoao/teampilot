# Progress Activity System

## Goal

Introduce a single **runtime progress activity** bus so long-running transfers
and installs (file-tree import, app update, hub clone, skill/plugin/extension
acquire, CLI/remote provision) share one progress surface across:

1. **Notification center** (bell) — ongoing rows with progress + cancel  
2. **Workspace status bar** — compact activity pill(s)  
3. **Optional detail dialog** — dismissible without cancelling  

Runtime activities are the source of truth. History notifications are a
projection written only on terminal outcomes.

**Out of scope:** TeamBus artifact transfer member-visible progress (keep
existing artifact design).

## Product decisions

| Decision | Choice |
|----------|--------|
| Architecture | Dedicated `ProgressActivityCubit` (not stuffing progress into toast history) |
| Surfaces | Notification center **and** workspace status bar (both) |
| Dialog | Optional detail dialog; **close ≠ cancel**; cancel from dialog / notification / status list |
| Scope (v1 producers) | fileTreeImport, appUpdate, hubClone, packAcquire, cliProvision |
| Artifact | Excluded |
| Compatibility | **No backward compatibility** — redesign notification list model/UI as needed; remove producer-local progress UIs that duplicate this system |
| Workload | Prefer best architecture / extensibility |
| Persistence | Ongoing activities are **in-memory only**; completed outcomes may persist as normal history `AppNotification`s |
| Conflict UI | File-tree conflict dialogs stay separate modal flows (not progress activities) |

## Architecture

```
Producers
  (import / update / hub clone / pack acquire / CLI provision)
        │  start / update / complete / requestCancel
        ▼
┌─────────────────────────────────┐
│ ProgressActivityCubit           │  sole runtime truth (no disk)
│ List<ProgressActivity>          │
└────────────────┬────────────────┘
                 │ project
         ┌───────┴────────┐
         ▼                ▼
 Notification center   Workspace status bar
 (ongoing + history)   (progress-activities segment)
         │
         ▼  on terminal phase
 History AppNotification (optional persist)
```

| Layer | Responsibility | Not responsible for |
|-------|----------------|---------------------|
| `ProgressActivityCubit` | Activity lifecycle, cancel requests, multi-activity ordering | Persisting ongoing rows |
| Notification center UI | Ongoing section + history; progress bar; cancel affordance | Owning transfer IO |
| Status bar segment | Compact progress / “N activities”; open list | Detailed error recovery |
| Detail dialog | Optional expanded view; close sets `detailOpen=false` only | Being the only progress channel |
| Producer adapters | Map domain progress → activity updates | Private progress chrome |

## Activity model

```dart
enum ProgressActivityKind {
  fileTreeImport,
  appUpdate,
  hubClone,
  packAcquire, // skill / plugin / extension
  cliProvision,
}

enum ProgressActivityPhase {
  queued,
  running,
  cancelling,
  succeeded,
  failed,
  cancelled,
}

class ProgressActivity {
  final String id;
  final ProgressActivityKind kind;
  final String title;
  final String? subtitle;
  final ProgressActivityPhase phase;
  final double? fraction; // null = indeterminate
  final int? completedItems;
  final int? totalItems;
  final int? bytesDone;
  final int? bytesTotal;
  final bool cancellable;
  final bool detailOpen;
  final String? errorMessage;
  final DateTime createdAt;
  final DateTime updatedAt;
}
```

### Cubit API (conceptual)

| Method | Behavior |
|--------|----------|
| `start(activity, {FutureOr<void> Function()? onCancelRequested})` | Insert/replace by `id`; phase typically `running`; store cancel hook with the activity |
| `update(id, …)` | Patch progress fields; bump `updatedAt` |
| `requestCancel(id)` | If `cancellable`, set `cancelling` and invoke the hook from `start` |
| `setDetailOpen(id, bool)` | Dialog visibility only |
| `complete(id, outcome)` | Remove from active list; emit history notification; optional toast |

**Cancel registration:** The cancel callback is passed at `start` (not a separate
registry). Adapters own domain tokens/flags and close over them in
`onCancelRequested`. Missing hook + `cancellable: true` is a programming error
(assert in debug; treat as non-cancellable in release).

**Ordering:** Active list is FIFO by `createdAt`. Same `id` on `start` replaces
in place (keeps position).

**Progress display priority** (UI): `fraction` if non-null → else
`completedItems/totalItems` → else `bytesDone/bytesTotal` → else indeterminate.

**History mapping on `complete`:** `succeeded` → success notification;
`failed` → error; `cancelled` → warning (kind-specific copy allowed). Cubit
calls `NotificationCubit` / `NotificationRecorder` for history only.

Producers **must not** treat local UI widgets as the source of truth for
progress. They report through the cubit (directly or via a thin adapter).

Cancel semantics:

- `requestCancel` is idempotent while `cancelling`.
- Producer stops further work; already-written side effects follow each domain’s
  existing rules (e.g. file-tree import keeps written items; no full rollback).
- On acknowledge: `phase = cancelled` then `complete`.

## Producer adapters

| Kind | Progress source | Cancel |
|------|-----------------|--------|
| `fileTreeImport` | `WorkspaceImportService.progress` | Existing cancel flag / `isCancelled` |
| `appUpdate` | Download fraction; then installing phase | Cancel while downloading if supported; `cancellable: false` while installing |
| `hubClone` | `CloneProgress(done, total)` → fraction or items | Wire cancel when underlying clone supports it; else indeterminate + non-cancellable |
| `packAcquire` | Skill / plugin / extension acquisition steps | Cancel when engine supports; else step items / indeterminate |
| `cliProvision` | `CliInstallProgress` | Same pattern as pack/CLI install |

Replace or delete producer-specific progress chrome that only mirrored the same
job (dialogs that cannot be dismissed without cancel, ad-hoc banners that
duplicate the status pill). Domain-specific **blocking** UIs that are not
progress (e.g. conflict overwrite dialogs, update release notes confirm) remain.

## Notification center UX

- Split UI into **Ongoing** (top) and **History**.
- Ongoing row: title, progress bar or indeterminate indicator, subtitle
  (current file / step), **Cancel** when `cancellable`.
- Tap ongoing row → optional `setDetailOpen(true)`.
- Bell badge: unread history count and/or ongoing count (distinct visual for
  ongoing preferred — e.g. subtle pulse / separate badge).
- On terminal outcome: drop from ongoing; append history `AppNotification`
  (success / warning / error) with stable copy.

**Bulk actions (mark all read / clear all):** Apply to **history only**. Never
remove, cancel, or mark “read” on ongoing activities. Clear-all must not imply
cancel; expose cancel only via per-row Cancel / `requestCancel`.

**Model change (allowed to break):** notification list is no longer “only
persisted toast echoes.” Prefer **view-model merge**:
`ProgressActivityCubit` ongoing + repository history. Disk schema stays
history-only.

## Status bar UX

- New `WorkspaceStatusBar` segment id: `progress-activities`.
- One activity: icon + short title + percent (or spinner).
- Many: `N activities in progress` → click opens popover/list of ongoing
  (same data as notification ongoing section).
- Coexists with resource-manager and SSH segments.
- **Desktop only** for the status-bar segment (align with
  `GlobalResourceManagerHost` `!isMobile`). Mobile relies on the notification
  center ongoing section.

## Detail dialog UX

- May auto-open for some kinds (e.g. file-tree import when progress gate trips).
- Actions: **Close** (dismiss UI) and **Cancel** (requestCancel) when allowed.
- Closing never cancels.
- Re-open from notification or status list via `detailOpen`.

## Error handling

| Case | Behavior |
|------|----------|
| Producer failure | `phase=failed`, `errorMessage`, then history error notification |
| Cancel mid-flight | `cancelling` → `cancelled`; history notes cancelled |
| Unknown / lost producer | Complete as failed with diagnostic message; never leave stuck `running` forever (timeout policy optional per kind) |

## Testing

| Area | Coverage |
|------|----------|
| Cubit | start/update/cancel/complete; multi-activity; idempotent cancel |
| Projection | Ongoing + history merge; badge counts |
| Status bar | Single vs multi collapse |
| Dialog | Close keeps activity; cancel completes cancelled |
| Adapters | Each kind maps progress at least once (unit / fake producer) |

## Non-goals

- OS desktop notification progress bars for these activities (may reuse
  `DesktopSystemNotifier` later for idle-style alerts only)
- Artifact transfer progress
- Persisting in-flight activities across app restart
- Transactional rollback of multi-file imports

## Related

- File-tree import: [2026-07-30-file-tree-external-drop-import-design.md](2026-07-30-file-tree-external-drop-import-design.md)
  — **Supersedes** that doc’s “import progress dialog/banner as sole surface”
  for progress UX. Keep conflict dialogs; migrate progress to this activity
  system (dismissible detail dialog + notification + status bar). Update the
  file-tree UI integration table when implementing the `fileTreeImport`
  adapter.
- Status bar shell: [2026-07-23-workspace-status-bar-resource-manager-design.md](2026-07-23-workspace-status-bar-resource-manager-design.md)
- Artifact (excluded): [2026-07-21-artifact-chunked-transfer-design.md](2026-07-21-artifact-chunked-transfer-design.md)
