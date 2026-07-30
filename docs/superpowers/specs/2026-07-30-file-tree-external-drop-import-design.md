# File Tree External Drop & Import

## Goal

Let users drop **OS files/folders** into the workspace file tree (local or
remote), and **drag nodes within the tree** to move or copy them. Writing goes
through a shared import pipeline on top of `Filesystem` (Local / SFTP / WSL),
reusing the existing `workspace_dnd` primitives without changing Compose /
Terminal drop semantics (those remain path-reference only).

## Product decisions

| Decision | Choice |
|----------|--------|
| Architecture | Extend `workspace_dnd` + new `WorkspaceImportService` (not a parallel drop stack) |
| Drop contents | Files **and** folders (recursive) |
| Name conflicts | Dialog: overwrite / skip / cancel-all; optional “apply to remaining” |
| Scope | External OS drop **and** in-tree move; modifier key → copy |
| Progress | Silent for small local; show progress + cancel when over threshold **or** target is non-local |
| Drop hit-testing | Folder → into folder; file → parent (sibling); empty/root chrome → root |
| Cross-namespace (tree) | Allowed as **copy only** (never delete source) |
| External OS → any tree | Always copy/upload into destination `Filesystem` |
| Compose / Terminal | Unchanged: path references only via existing ingest ors |
| Android OS drop | Out of scope (existing `ExternalFileDropRegion` passthrough) |
| Workload | Prefer best architecture / UX over incremental patch size |

## Architecture

```
OS Drop / in-tree Drag
        │
        ▼
┌─────────────────────────────┐
│ FileTreeDropRegion (UI)     │  hit-test · highlight · modifier key
│ ExternalFileDropRegion +    │
│ row / panel DragTargets     │
└──────────────┬──────────────┘
               ▼
┌─────────────────────────────┐
│ FileTreeDropIngestor        │  WorkspaceDropTarget
│ resolve dest · mode ·       │
│ conflict prompts            │
└──────────────┬──────────────┘
               ▼
┌─────────────────────────────┐
│ WorkspaceImportService      │  cancellable ImportJob
│ same-FS copy/move ·         │  progress threshold
│ cross-FS chunked pipe       │
└──────────────┬──────────────┘
               ▼
        Filesystem API
     (Local / SFTP / WSL)
               ▼
     FileTreeCubit refresh
```

| Layer | Responsibility | Not responsible for |
|-------|----------------|---------------------|
| `FileTreeDropRegion` UI | Hit-testing, drop highlight, reading modifier keys | Bytes IO |
| `FileTreeDropIngestor` | `WorkspaceDropTarget`: dest + mode + conflict policy | Progress chrome internals |
| `WorkspaceImportService` | Executing copy/move/upload jobs with cancel + progress events | Path reference formatting |
| `Filesystem` | Backend IO | DnD UX |
| Compose / Terminal ingest ors | Path inject / `@` refs | Writing into the workspace tree |

Existing `RejectCrossNamespaceStrategy` stays the default for **path-reference**
targets (terminal / compose). File-tree import does **not** use that reject path
for OS→tree or cross-mount tree copies; it always materializes bytes via
`WorkspaceImportService`.

## Drop hit-testing

| Hover target | `destDir` |
|--------------|-----------|
| Folder row | That folder’s path |
| File row | Parent directory (land as sibling) |
| Empty panel area / root chrome | Mounted workspace root for that panel |
| In-tree: onto self or descendant | Reject (invalid move/copy) |

Multi-root trees: dest is resolved against the hovered mount; `FileTreeCubit.fsFor(destDir)` selects the destination `Filesystem`.

## Operation modes

| Source | Same namespace | Cross-namespace |
|--------|----------------|-----------------|
| External OS paths | Always **copy** into dest FS | Always **copy/upload** (OS is always host-local) |
| In-tree drag | Default **move** (`rename` / same-FS move); modifier → **copy** | Force **copy** (do not delete source); modifier ignored for “move” |

Modifier keys:

- Windows / Linux: `Ctrl`
- macOS: `Option` (`⌥`)

Cursor / overlay should indicate copy vs move while dragging when the mode is
known (external always shows copy affordance).

## Conflict handling

Before each item is written (after dest basename is known):

1. If dest path does not exist → proceed.
2. If dest exists and types differ (file vs directory) → **cannot overwrite**;
   only skip or cancel-all for that item (and optionally apply-to-remaining for
   skip).
3. If dest exists and types match → dialog:
   - **Overwrite**
   - **Skip**
   - **Cancel all** (abort remaining; keep already-written items)
4. Checkbox: **Apply same choice to remaining conflicts**.

Overwrite of a directory means replace tree contents per importer rules
(remove existing dest tree then copy, or merge-with-overwrite of files — prefer
**replace dest entry** for predictability: delete dest path then write source).

## Progress & cancellation

Show a progress surface (item count + optional byte progress) and a Cancel
action when **any** of:

- any single file ≥ **5 MiB**, or
- total planned entries ≥ **10**, or
- destination `Filesystem` is **non-local** (SFTP / WSL)

Otherwise complete silently (toast/snack only on partial failure summary).

Cancel semantics:

- Stop scheduling further items.
- Do **not** roll back already-written items.
- In-flight single-file chunked transfer should stop appending and leave a
  partial file only if the backend cannot delete mid-write; prefer deleting
  the incomplete dest file on cancel when safe.

## Import service behavior

`WorkspaceImportService` accepts an `ImportPlan`:

- sources: list of `{ path, isDirectory }` (OS local paths or tree paths)
- `destDir`, destination `Filesystem`
- mode: `copy` | `move`
- source `Filesystem` (for in-tree; for OS drop use host `LocalFilesystem`)

Same-FS:

- file copy → `copyFile`; directory → `copyTree`
- move → `rename` when possible; else copy + delete source

Cross-FS (or OS→remote):

- walk directories; for each file: `readBytesRange` / stream → `writeBytes` /
  `appendBytes` on dest (align with chunked patterns from artifact transfer)
- after successful full copy in `move` mode **only when same-namespace** would
  apply; cross-namespace never deletes source

After success: refresh affected file-tree roots / expanded folders via
`FileTreeCubit`.

## Error handling

| Case | Behavior |
|------|----------|
| Single item IO failure | Record failure; continue remaining items |
| Permission / connection loss | Abort remaining; keep written items; surface summary |
| Invalid drop (onto self) | No-op with brief reject feedback |
| Partial batch | End summary: succeeded N / skipped M / failed K |

## UI integration points

| Location | Change |
|----------|--------|
| `file_tree_panel.dart` / node rows | Wrap with drop regions; row highlight for valid dest |
| `DraggableFileRow` | Already drag-out; ensure in-tree drops accepted by tree targets (not only compose/terminal) |
| `file_tree_cubit.dart` | Optional thin wrappers calling import service + refresh |
| New widgets | Conflict dialog; import progress dialog/banner |
| l10n | Conflict / progress / summary / reject strings (`app_en.arb` / `app_zh.arb`) |

## Testing

| Area | Coverage |
|------|----------|
| Hit-test | Folder / file / empty → `destDir`; reject self/descendant |
| Modes | External always copy; in-tree move vs modifier copy; cross-NS force copy |
| Conflicts | Overwrite / skip / apply-remaining / type mismatch |
| Import service | Same-FS copy & move; cross-FS chunked copy; cancel mid-batch |
| Progress gate | Thresholds and non-local always-on |
| Widgets | Highlight + dialog flows with mock `Filesystem` |

Prefer constructor-injected mock filesystems; no real SFTP in unit tests.

## Non-goals

- Android / mobile OS file drop into the tree
- Changing Compose or Terminal drop to write files into the workspace
- Full transactional rollback of multi-item imports
- Cross-namespace **move** (delete source after upload)
- OS clipboard “paste files into tree” (may share `WorkspaceImportService` later)

## Related

- Existing DnD: `client/lib/services/workspace_dnd/`, `client/lib/widgets/workspace_dnd/`
- Chunked IO precedent: [artifact chunked transfer](2026-07-21-artifact-chunked-transfer-design.md)
- Compose drop (path refs only): [unified compose card](2026-07-28-unified-compose-card-design.md)
