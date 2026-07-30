# File Tree External Drop & Import Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Support OS file/folder drops into the workspace file tree (local and remote) and in-tree move/copy, via a shared `WorkspaceImportService` on top of `Filesystem`.

**Architecture:** Pure hit-test + progress-gate helpers; cancellable `WorkspaceImportService` (same-FS copy/move, cross-FS chunked pipe); `FileTreeDropIngestor` for conflicts/mode; panel UI wraps `ExternalFileDropRegion` with pointer-resolved `destDir` plus per-row in-app `DragTarget`s. Compose/Terminal path-reference drops stay unchanged.

**Tech Stack:** Flutter / `flutter_bloc`; existing `workspace_dnd` (`ExternalFileDropRegion`, `DraggableFileRow`, `WorkspaceDragPayload`); `Filesystem` + `InMemoryFilesystem`; `desktop_drop`; l10n ARBs.

**Spec:** `docs/superpowers/specs/2026-07-30-file-tree-external-drop-import-design.md`

## Global Constraints

- Prefer best architecture/UX; do **not** ship a local-only half measure that cannot upload to SSH/WSL.
- Compose / Terminal continue path-reference only (`RejectCrossNamespaceStrategy` unchanged there).
- Cross-FS / cross-mount tree ops are **copy only** (never delete source).
- Progress when: any file ≥ 5 MiB, **or** flattened file count ≥ 10, **or** dest FS is non-local.
- Same/cross FS decided by `FileTreeCubit.fsFor` / `workContextFor`, not global `PathNamespace.ofCurrentStorage()`.
- `destIsLocal`: `cubit.workContextFor(destDir)?.mode` is native/local only; **WSL and SFTP are non-local** (always show progress).
- `destDir` resolved at drop time (hit-test), not constructed into a panel-global ingestor.
- Before claiming done: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings` and the test commands in the final task.
- Tests use `InMemoryFilesystem` from `client/test/support/in_memory_filesystem.dart`.

---

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/services/file_tree_import/file_tree_drop_hit_test.dart` | Pure: row/empty → `destDir`; reject self/descendant; multi-root nearest-Y |
| `client/lib/services/file_tree_import/import_models.dart` | `ImportMode`, `ImportSource`, `ImportPlan`, `ImportProgress`, `ConflictChoice`, `ImportSummary` |
| `client/lib/services/file_tree_import/import_progress_gate.dart` | Whether to show progress UI from plan stats + dest locality |
| `client/lib/services/file_tree_import/workspace_import_service.dart` | Execute plan: same-FS / cross-FS, cancel, progress stream |
| `client/lib/services/file_tree_import/file_tree_drop_ingestor.dart` | Mode resolution, conflict prompts, calls import service, refresh cubit |
| `client/lib/widgets/file_tree/file_tree_drop_region.dart` | Panel drop chrome: OS drop + hover highlight + dest resolution |
| `client/lib/widgets/file_tree/file_tree_import_dialogs.dart` | Conflict dialog + progress dialog |
| `client/lib/widgets/right_tools/file_tree_panel.dart` | Wire drop region + pass hit-test inputs |
| `client/lib/widgets/file_tree_node.dart` | Row drop target + highlight; feed drag payload |
| `client/lib/widgets/workspace_dnd/external_file_drop_region.dart` | Optional `onDropWithDetails` / position callback for dest hit-test (keep existing API working) |
| `client/lib/l10n/app_en.arb` / `app_zh.arb` | Conflict / progress / summary / reject strings |
| Tests under `client/test/services/file_tree_import/` and widget tests under `client/test/widgets/file_tree/` |

---

### Task 1: Drop hit-test (pure)

**Files:**
- Create: `client/lib/services/file_tree_import/file_tree_drop_hit_test.dart`
- Test: `client/test/services/file_tree_import/file_tree_drop_hit_test_test.dart`

**Interfaces:**

```dart
enum FileTreeDropRowKind { folder, file, rootChrome, empty }

class FileTreeDropHit {
  const FileTreeDropHit({required this.destDir, this.rejectedReason});
  final String? destDir;
  final String? rejectedReason; // e.g. 'ontoSelf'
  bool get isValid => destDir != null && rejectedReason == null;
}

/// [pathContext] from dest mount. [sourcePaths] non-empty for in-tree reject checks.
FileTreeDropHit resolveFileTreeDropDest({
  required FileTreeDropRowKind kind,
  required String rowPath, // folder/file path, or root path for rootChrome
  required p.Context pathContext,
  List<String> sourcePaths = const [],
});

/// Multi-root empty/gap: pick root whose [Rect] contains [localY], else nearest centerY.
String resolveNearestRootDest({
  required double localY,
  required List<({String rootPath, double top, double bottom})> rootBands,
});
```

- [ ] **Step 1: Write the failing tests**

Cover: folder → that path; file → parent; rootChrome → root; onto self / descendant → rejected; nearest-root by Y (inside band + gap).

- [ ] **Step 2: Run tests — expect FAIL**

Run: `cd client && flutter test test/services/file_tree_import/file_tree_drop_hit_test_test.dart`

Expected: FAIL — library not found.

- [ ] **Step 3: Implement hit-test**

Use `pathContext.dirname` / `isWithin` / normalize. No Flutter imports.

- [ ] **Step 4: Run tests — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/file_tree_import/file_tree_drop_hit_test.dart \
  client/test/services/file_tree_import/file_tree_drop_hit_test_test.dart
git commit -m "feat(file_tree): add pure drop dest hit-test helpers"
```

---

### Task 2: Import models + progress gate

**Files:**
- Create: `client/lib/services/file_tree_import/import_models.dart`
- Create: `client/lib/services/file_tree_import/import_progress_gate.dart`
- Test: `client/test/services/file_tree_import/import_progress_gate_test.dart`

**Interfaces:**

```dart
enum ImportMode { copy, move }

class ImportSource {
  const ImportSource({required this.path, required this.isDirectory});
  final String path;
  final bool isDirectory;
}

class ImportPlan {
  const ImportPlan({
    required this.sources,
    required this.destDir,
    required this.mode,
    required this.sourceFs,
    required this.destFs,
    required this.flattenedFileCount,
    required this.maxFileBytes,
    required this.destIsLocal,
  });
  // fields as named
}

enum ConflictChoice { overwrite, skip, cancelAll }

class ImportProgress {
  const ImportProgress({
    required this.completedItems,
    required this.totalItems,
    this.bytesDone = 0,
    this.bytesTotal = 0,
    this.currentName = '',
  });
}

class ImportSummary {
  const ImportSummary({
    this.succeeded = 0,
    this.skipped = 0,
    this.failed = 0,
    this.cancelled = false,
  });
}

bool shouldShowImportProgress({
  required int flattenedFileCount,
  required int maxFileBytes,
  required bool destIsLocal,
  int fileCountThreshold = 10,
  int byteThreshold = 5 * 1024 * 1024,
});
```

- [ ] **Step 1: Write failing gate tests**

Cases: small local silent; ≥10 files show; ≥5MiB show; non-local always show.

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement models + gate**

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/file_tree_import/import_models.dart \
  client/lib/services/file_tree_import/import_progress_gate.dart \
  client/test/services/file_tree_import/import_progress_gate_test.dart
git commit -m "feat(file_tree): add import models and progress gate"
```

---

### Task 3: `WorkspaceImportService` — same-FS copy/move

**Files:**
- Create: `client/lib/services/file_tree_import/workspace_import_service.dart`
- Test: `client/test/services/file_tree_import/workspace_import_service_same_fs_test.dart`

**Interfaces:**

```dart
typedef ConflictResolver = Future<ConflictChoice> Function({
  required String destPath,
  required bool sourceIsDirectory,
  required bool destIsDirectory,
  required bool typeMismatch,
  required int remainingConflicts,
});

class WorkspaceImportService {
  WorkspaceImportService({this.chunkSize = 256 * 1024});

  final int chunkSize;

  /// Walk sources on [sourceFs], return flattened file paths + max size.
  Future<({List<String> files, int maxBytes, List<ImportSource> topLevel})>
      planSources(Filesystem sourceFs, List<ImportSource> sources);

  Stream<ImportProgress> get progress; // or callback on run

  Future<ImportSummary> run(
    ImportPlan plan, {
    required ConflictResolver onConflict,
    required bool Function() isCancelled,
  });
}
```

Same-FS behavior (identical `sourceFs` and `destFs` instances **or** same `workContext` — caller sets mode; service trusts plan):

- copy file → `copyFile`; dir → `copyTree`
- move → prefer `rename`; if fails, copy then `removeRecursive` source
- conflict overwrite → `removeRecursive(dest)` then copy/rename
- type mismatch → only skip / cancelAll (resolver must not return overwrite)

- [ ] **Step 1: Write failing tests with `InMemoryFilesystem`**

Copy file into dest; copy tree; move via rename; overwrite; skip; cancel mid-batch keeps prior writes; type mismatch skips without deleting.

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement same-FS path in `run`** (cross-FS can throw `UnimplementedError` until Task 4)

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/file_tree_import/workspace_import_service.dart \
  client/test/services/file_tree_import/workspace_import_service_same_fs_test.dart
git commit -m "feat(file_tree): same-FS workspace import service"
```

---

### Task 4: Cross-FS chunked copy

**Files:**
- Modify: `client/lib/services/file_tree_import/workspace_import_service.dart`
- Test: `client/test/services/file_tree_import/workspace_import_service_cross_fs_test.dart`

**Approach:** Mirror `ArtifactTransferService` chunk loop (`readBytesRange` → `appendBytes`), without TeamBus resume sidecars. For each file:

1. `ensureDir` parent on dest
2. Write to `destPath + '.partial'` or direct path; on success rename/finalize; on cancel delete incomplete dest when safe
3. Directories: `ensureDir` then recurse files from `planSources` flatten list
4. **Never** delete source when `sourceFs != destFs` (even if plan.mode was move — caller must pass `ImportMode.copy` for cross-FS; assert or coerce)

Use two distinct `InMemoryFilesystem` instances as source/dest in tests.

- [ ] **Step 1: Write failing cross-FS tests**

File copy; nested dir; cancel mid-file cleans partial; move mode on cross-FS does not delete source.

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement cross-FS branch**

- [ ] **Step 4: Run same-FS + cross-FS tests — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/file_tree_import/workspace_import_service.dart \
  client/test/services/file_tree_import/workspace_import_service_cross_fs_test.dart
git commit -m "feat(file_tree): cross-FS chunked import copy"
```

---

### Task 5: `FileTreeDropIngestor` (mode + conflict + refresh)

**Files:**
- Create: `client/lib/services/file_tree_import/file_tree_drop_ingestor.dart`
- Test: `client/test/services/file_tree_import/file_tree_drop_ingestor_test.dart`

**Interfaces:**

```dart
class FileTreeDropIngestor {
  FileTreeDropIngestor({
    required this.cubit,
    required this.importService,
    required this.hostLocalFs, // LocalFilesystem / InMemory for tests
    required this.onConflict,  // UI-injected
    required this.isCopyModifierPressed, // () => bool
  });

  final FileTreeCubit cubit;
  final WorkspaceImportService importService;
  final Filesystem hostLocalFs;
  final ConflictResolver onConflict;
  final bool Function() isCopyModifierPressed;

  /// External OS drop or in-tree drop with explicit dest.
  Future<ImportSummary> consumeAt({
    required String destDir,
    required WorkspaceDragPayload payload,
    required bool fromExternalOs,
  });
}
```

Mode rules (implement exactly):

| fromExternalOs | same FS (`identical` fs or same workContext id) | mode |
|----------------|--------------------------------------------------|------|
| true | any | copy; sourceFs = `hostLocalFs` |
| false | same | move, unless `isCopyModifierPressed()` → copy |
| false | different | copy; sourceFs = `cubit.fsFor(source)` |

**`consumeAt` pipeline (required order):**

1. Resolve mode via `resolveFileTreeImportMode` / same-FS check.
2. Call `importService.planSources(sourceFs, sources)` → flattened files + `maxFileBytes`.
3. Build `ImportPlan` including `flattenedFileCount`, `maxFileBytes`, `destIsLocal`.
4. Caller/UI uses `shouldShowImportProgress(...)` **before** `run` (ingestor may expose the plan or a `prepare` method so UI can open the progress dialog). Minimum: `consumeAt` always plans first internally; never call `run` without a fully populated plan.
5. `importService.run(plan, onConflict:, isCancelled:)`.
6. `cubit.refreshPaths` for `destDir` (and source parent on move).

Map `ImportSummary` into a `DropOutcome`-like result if UI needs it (`delivered` = succeeded).

- [ ] **Step 1: Write failing tests** with fake cubit/fs or minimal `FileTreeCubit` if cheap; otherwise test mode selection via a package-visible helper `resolveImportMode(...)` extracted in the same file. Include a test that `consumeAt` invokes `planSources` before `run` (mock service).

Prefer extracting:

```dart
ImportMode resolveFileTreeImportMode({
  required bool fromExternalOs,
  required bool sameFs,
  required bool copyModifier,
});
```

Test that pure function thoroughly; one integration test that `consumeAt` copies a file via `InMemoryFilesystem` + stub refresh callback if cubit is heavy.

- [ ] **Step 2–4: TDD implement**

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/file_tree_import/file_tree_drop_ingestor.dart \
  client/test/services/file_tree_import/file_tree_drop_ingestor_test.dart
git commit -m "feat(file_tree): drop ingestor mode and conflict orchestration"
```

---

### Task 6: Conflict + progress dialogs + l10n

**Files:**
- Create: `client/lib/widgets/file_tree/file_tree_import_dialogs.dart`
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`
- Test: `client/test/widgets/file_tree/file_tree_import_dialogs_test.dart`

**UI:**

Conflict `showDialog`:

- Title/body with basename + remaining count
- Actions: Overwrite (disabled if typeMismatch), Skip, Cancel all
- Checkbox: apply to remaining → when set, return choice with a side-channel `applyToRemaining: true` (extend resolver signature or wrap in a stateful `ConflictSession` class held by the panel)

Progress dialog:

- Listen to import progress stream / `ValueNotifier`
- Cancel button sets cancel flag
- Non-dismissible barrier while running

Strings (examples — use Tp/l10n style already in ARBs):

- `fileTreeImportConflictTitle`, `fileTreeImportOverwrite`, `fileTreeImportSkip`, `fileTreeImportCancelAll`, `fileTreeImportApplyRemaining`
- `fileTreeImportProgressTitle`, `fileTreeImportProgressCancel`
- `fileTreeImportSummary` (succeeded/skipped/failed) — used for **both** progress completion and silent partial-failure toast
- `fileTreeImportRejectSelf`
- `fileTreeImportDropCopy`, `fileTreeImportDropMove` (drag affordance)

After ARB edits, run codegen if the project requires it (follow existing pattern in repo — usually `flutter gen-l10n` via `flutter test` / analyze). Also run `dart run tool/gen_warmup_glyphs.dart` if ARB glyph set changes per AGENTS.md.

- [ ] **Step 1: Add ARB keys + failing widget test that pumps conflict dialog and taps Skip**

- [ ] **Step 2–4: Implement dialogs**

- [ ] **Step 5: Commit**

```bash
git add client/lib/widgets/file_tree/file_tree_import_dialogs.dart \
  client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb \
  client/test/widgets/file_tree/file_tree_import_dialogs_test.dart
git commit -m "feat(file_tree): import conflict and progress dialogs"
```

---

### Task 7: Panel + row drop UI wiring

**Files:**
- Create: `client/lib/widgets/file_tree/file_tree_drop_region.dart`
- Modify: `client/lib/widgets/workspace_dnd/external_file_drop_region.dart` (add optional `ValueChanged<DropDoneDetails>? onDropDetails` **or** `Future<void> Function(WorkspaceDragPayload, Offset?)?` — keep backward compatible defaults so Compose/Terminal unchanged)
- Modify: `client/lib/widgets/right_tools/file_tree_panel.dart`
- Modify: `client/lib/widgets/file_tree_node.dart`
- Test: `client/test/widgets/file_tree/file_tree_drop_region_test.dart` (logic-focused; may test hit-test integration with fake bands)

**Wiring rules:**

1. **OS drop:** Panel-level `ExternalFileDropRegion`. On drop, use last pointer position (track via `Listener` / `MouseRegion` / desktop_drop `onDragUpdated` if available) to:
   - find hovered visible row → `resolveFileTreeDropDest`
   - else multi-root bands → `resolveNearestRootDest`
2. **In-tree drop:** Each `FileTreeNode` wraps content in `DragTarget<WorkspaceDragPayload>` (or `WorkspaceFileDropRegion` if it can pass dest). On accept, read modifier via `HardwareKeyboard.instance.logicalKeysPressed` (`LogicalKeyboardKey.control` / `LogicalKeyboardKey.alt` on macOS — use `defaultTargetPlatform == TargetPlatform.macOS` for Option).
3. Highlight hovered valid dest row (border/background using theme primary, mirror ExternalFileDropRegion alpha).
4. **Copy vs move affordance (spec):** While dragging over a valid dest, show an overlay/badge or cursor hint — external OS drag always “copy”; in-tree shows “move” or “copy” based on modifier + same-FS (cross-FS always “copy”). Implement as a small label in the highlight overlay (l10n: `fileTreeImportDropCopy` / `fileTreeImportDropMove`).
5. Filter mode: only **visible** rows are valid hover targets; empty area still resolves to root by Y. Prefer `visibleRows` + `kFileTreeRowExtent` + list scroll offset for row/root band geometry (`file_tree_visible_rows.dart`).
6. Build `FileTreeDropIngestor` once per panel state; pass dialog `ConflictResolver` that shows Task 6 dialogs.
7. **Progress + silent summary:** After `planSources` / plan build, if `shouldShowImportProgress` → show progress dialog wrapping `run` with cancel flag; else run silently. When summary has `failed > 0` or `skipped > 0` (or cancelled), always show toast/snack with `fileTreeImportSummary` — **including the silent path**.
8. **`ExternalFileDropRegion` API:** If adding `onDropDetails` / custom handler, document: when custom handler is non-null, **do not** also call `target.consume` (avoid double ingest). Keep `target` required for Compose/Terminal unchanged call sites (they omit the new optional callback).

Modifier copy detection helper (put next to ingestor or in drop region):

```dart
bool fileTreeCopyModifierPressed() {
  final keys = HardwareKeyboard.instance.logicalKeysPressed;
  if (defaultTargetPlatform == TargetPlatform.macOS) {
    return keys.contains(LogicalKeyboardKey.altLeft) ||
        keys.contains(LogicalKeyboardKey.altRight);
  }
  return keys.contains(LogicalKeyboardKey.controlLeft) ||
      keys.contains(LogicalKeyboardKey.controlRight);
}
```

- [ ] **Step 1: Write a widget/unit test for copy-modifier helper + dest injection path (mock ingestor)**

- [ ] **Step 2–4: Implement region + wire panel/node; verify Compose still compiles (no API break)**

- [ ] **Step 5: Commit**

```bash
git add client/lib/widgets/file_tree/file_tree_drop_region.dart \
  client/lib/widgets/workspace_dnd/external_file_drop_region.dart \
  client/lib/widgets/right_tools/file_tree_panel.dart \
  client/lib/widgets/file_tree_node.dart \
  client/test/widgets/file_tree/file_tree_drop_region_test.dart
git commit -m "feat(file_tree): wire OS and in-tree drop regions"
```

---

### Task 8: End-to-end verification

**Files:** none new (fix + analyze)

- [ ] **Step 1: Run focused tests**

```bash
cd client && flutter test test/services/file_tree_import test/widgets/file_tree
```

Expected: PASS

- [ ] **Step 2: Run broader unit suite (optional but preferred)**

```bash
cd client && flutter test --exclude-tags integration
```

Expected: PASS (or only pre-existing failures unrelated to this feature)

- [ ] **Step 3: Run analyze**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: no errors related to new code

- [ ] **Step 4: Manual smoke (desktop)**

1. Local workspace: drag files + folder from OS into folder / onto file / empty → correct dest
2. Conflict dialog overwrite/skip/apply remaining
3. In-tree move; Ctrl/⌥ copy
4. SSH or WSL workspace: OS drop uploads with progress; cancel leaves prior files
5. Compose/Terminal drop still inserts paths only (regression)

- [ ] **Step 5: Commit any leftover fixes**

```bash
git add -A  # only intentional leftovers from this feature
git commit -m "fix(file_tree): polish drop import after verification"
```

---

## Execution notes

- Reuse `InMemoryFilesystem` from existing test support (search `class InMemoryFilesystem`).
- Do not change `TerminalDropIngestor` / `ComposeFileDropIngestor` semantics.
- Symlinks: follow existing `Filesystem.copyFile` / `copyTree` behavior; no special-case in v1.
- Keep new service files under ~600 lines; split if `workspace_import_service.dart` grows past that.
