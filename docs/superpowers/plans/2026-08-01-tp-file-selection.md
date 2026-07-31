# TpFileSelection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract huji’s mobile file/gallery/directory picker into `shared_ui` as `TpFileSelection`, with all IO behind injected Ports so huji and TeamPilot can reuse it without hard deps on `photo_manager` / `permission_handler` / `file_picker`.

**Architecture:** Layered package API — models → ports → selection controller → UI tabs/page → `showTpFileSelection`. Apps supply adapters + optional `FileSystemEntity` facades. Gallery/desktop/preview ports are optional and degrade safely.

**Tech Stack:** Flutter/Dart, `shared_ui` (`TpTheme`, `TpHover`, `TpDialog`, `TpToast`, `TpEmptyState`), app-side `photo_manager` / `permission_handler` / `file_picker` (adapters only).

**Spec:** `docs/superpowers/specs/2026-08-01-tp-file-selection-design.md`

**Source of truth (behavior):** `huji/huji-app/lib/widgets/file_picker/` (`file_selection_page.dart`, `filesystem_tab.dart`, `photo_gallery_tab.dart`, `desktop_file_picker.dart`)

---

## File map

### shared_ui (repo: `https://github.com/hhoao/shared_ui.git`, path in apps: `**/packages/shared_ui`)

| File | Responsibility |
|------|----------------|
| `lib/src/components/file_selection/models/tp_picked_entry.dart` | `TpPickedEntry`, `TpPickedKind` |
| `lib/src/components/file_selection/models/tp_fs_entry.dart` | `TpFsEntry`, `TpFsEntryKind`, `TpFilesystemRoot` |
| `lib/src/components/file_selection/models/tp_gallery_models.dart` | `TpGalleryAlbum`, `TpGalleryAsset` |
| `lib/src/components/file_selection/models/tp_file_selection_options.dart` | `TpSelectionMode`, `TpFileSelectionTab`, `TpFileSelectionOptions` |
| `lib/src/components/file_selection/ports/tp_filesystem_port.dart` | List/search/roots |
| `lib/src/components/file_selection/ports/tp_permission_port.dart` | Storage/gallery access + optional settings |
| `lib/src/components/file_selection/ports/tp_gallery_port.dart` | Albums/assets/thumbnails/resolve |
| `lib/src/components/file_selection/ports/tp_desktop_picker_port.dart` | Native desktop pick |
| `lib/src/components/file_selection/ports/tp_media_preview_port.dart` | Image/video preview |
| `lib/src/components/file_selection/ports/tp_file_selection_deps.dart` | Deps aggregate |
| `lib/src/components/file_selection/ui/tp_file_selection_strings.dart` | Injected labels |
| `lib/src/components/file_selection/controller/tp_file_selection_filters.dart` | Extension/hidden/in-list filter + sort + media-kind |
| `lib/src/components/file_selection/controller/tp_file_selection_controller.dart` | Selection set, max count, tab-switch gate |
| `lib/src/components/file_selection/controller/tp_file_selection_tab_api.dart` | Tab interface (clear/selectAll/count) |
| `lib/src/components/file_selection/show_tp_file_selection.dart` | Entry + desktop routing |
| `lib/src/components/file_selection/ui/tp_file_selection_page.dart` | Page chrome + tabs + bottom bars |
| `lib/src/components/file_selection/ui/tp_filesystem_tab.dart` | Filesystem browser UI |
| `lib/src/components/file_selection/ui/widgets/tp_full_disk_search_dialog.dart` | Full-disk search dialog (huji `GlobalSearchDialog` parity) |
| `lib/src/components/file_selection/ui/tp_gallery_tab.dart` | Gallery UI |
| `lib/src/components/file_selection/ui/widgets/` | Rows, thumbnails, sort sheet (internal) |
| `lib/shared_ui.dart` | Barrel exports |
| `README.md` | File Selection section |
| `test/components/file_selection/*` | Controller + widget tests with fakes |

### huji app

| File | Responsibility |
|------|----------------|
| `huji-app/lib/widgets/file_picker/adapters/*.dart` | Concrete ports |
| `huji-app/lib/widgets/file_picker/huji_file_selection_deps.dart` | Wire deps + strings from l10n |
| `huji-app/lib/widgets/file_picker/file_selection.dart` | Legacy facade (`FileSelection.show` → `FileSystemEntity`) |
| Delete after cutover | Old `filesystem_tab.dart`, `photo_gallery_tab.dart`, `file_selection_page.dart`, `desktop_file_picker.dart` (logic moved) |

### TeamPilot app (optional v1 consumer)

| File | Responsibility |
|------|----------------|
| `client/lib/services/file_selection/` or `client/lib/widgets/file_selection/` | Local FS + desktop adapters; **no gallery** |
| Call sites (later) | Prefer for local picks; keep `RemoteDirectoryBrowserDialog` for SSH |

**Locked implementer rules:**

1. **Do not** add `photo_manager`, `permission_handler`, or `file_picker` to shared_ui `pubspec.yaml`.
2. **Do not** export `dart:io` `File`/`Directory` from shared_ui public API — only `TpPickedEntry`.
3. **Behavior parity** with huji sources listed above (search, sort, bottom bar, initialPath, maxCount toast, tab clear dialog).
4. **No `as dynamic` GlobalKey** tab APIs — use `TpFileSelectionTabApi`.
5. shared_ui work lands in the **shared_ui git repo** (submodule). Bump submodule pointers in teampilot/huji separately.
6. **Do not commit** unless the user explicitly asks (skip commit steps or stop before them).
7. UI porting: prefer extracting logic into controllers first; keep widgets thin. Split files if any exceeds ~600 lines soft limit.
8. Theme via `TpTheme` / `ColorScheme` — no `Colors.grey[900]` hard-codes.

---

### Task 1: Models + options enums

**Files:**
- Create: `client/packages/shared_ui/lib/src/components/file_selection/models/tp_picked_entry.dart`
- Create: `client/packages/shared_ui/lib/src/components/file_selection/models/tp_fs_entry.dart`
- Create: `client/packages/shared_ui/lib/src/components/file_selection/models/tp_gallery_models.dart`
- Create: `client/packages/shared_ui/lib/src/components/file_selection/models/tp_file_selection_options.dart`
- Create: `client/packages/shared_ui/test/components/file_selection/tp_picked_entry_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

void main() {
  test('TpPickedEntry equality by path+kind', () {
    const a = TpPickedEntry(path: '/a', kind: TpPickedKind.file);
    const b = TpPickedEntry(path: '/a', kind: TpPickedKind.file);
    expect(a, equals(b));
  });

  test('TpFileSelectionOptions defaults match huji FileSelection', () {
    const o = TpFileSelectionOptions();
    expect(o.allowMultiple, isFalse);
    expect(o.selectionMode, TpSelectionMode.files);
    expect(o.showHiddenFiles, isFalse);
    expect(o.initialTab, isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run (from `client/packages/shared_ui`):

```bash
flutter test test/components/file_selection/tp_picked_entry_test.dart
```

Expected: FAIL (library/export missing)

- [ ] **Step 3: Implement models**

`tp_picked_entry.dart`:

```dart
import 'package:equatable/equatable.dart';

enum TpPickedKind { file, directory }

class TpPickedEntry extends Equatable {
  const TpPickedEntry({
    required this.path,
    required this.kind,
    this.displayName,
    this.mimeType,
  });

  final String path;
  final TpPickedKind kind;
  final String? displayName;
  final String? mimeType;

  @override
  List<Object?> get props => [path, kind, displayName, mimeType];
}
```

`tp_fs_entry.dart`:

```dart
enum TpFsEntryKind { file, directory, other }

class TpFsEntry {
  const TpFsEntry({
    required this.path,
    required this.name,
    required this.kind,
    this.modifiedAt,
    this.sizeBytes,
  });

  final String path;
  final String name;
  final TpFsEntryKind kind;
  final DateTime? modifiedAt;
  final int? sizeBytes;
}

class TpFilesystemRoot {
  const TpFilesystemRoot({
    required this.id,
    required this.label,
    required this.path,
  });

  final String id;
  final String label;
  final String path;
}
```

`tp_gallery_models.dart` — as in spec (`TpGalleryAlbum`, `TpGalleryAsset`).

`tp_file_selection_options.dart`:

```dart
enum TpSelectionMode { files, directories, both }

enum TpFileSelectionTab { filesystem, gallery }

class TpFileSelectionOptions {
  const TpFileSelectionOptions({
    this.allowMultiple = false,
    this.allowedExtensions,
    this.title,
    this.maxSelectionCount,
    this.initialTab,
    this.initialPath,
    this.selectionMode = TpSelectionMode.files,
    this.showHiddenFiles = false,
  });

  final bool allowMultiple;
  final List<String>? allowedExtensions;
  final String? title;
  final int? maxSelectionCount;
  final TpFileSelectionTab? initialTab;
  final String? initialPath;
  final TpSelectionMode selectionMode;
  final bool showHiddenFiles;
}
```

- [ ] **Step 4: Export from `lib/shared_ui.dart` and re-run test**

Expected: PASS

- [ ] **Step 5: Commit** (only if user asked)

```bash
cd client/packages/shared_ui
git add lib/src/components/file_selection/models lib/shared_ui.dart test/components/file_selection/tp_picked_entry_test.dart
git commit -m "feat(file_selection): add TpPickedEntry and options models"
```

---

### Task 2: Port interfaces + deps + strings

**Files:**
- Create: `lib/src/components/file_selection/ports/tp_filesystem_port.dart`
- Create: `lib/src/components/file_selection/ports/tp_permission_port.dart`
- Create: `lib/src/components/file_selection/ports/tp_gallery_port.dart`
- Create: `lib/src/components/file_selection/ports/tp_desktop_picker_port.dart`
- Create: `lib/src/components/file_selection/ports/tp_media_preview_port.dart`
- Create: `lib/src/components/file_selection/ports/tp_file_selection_deps.dart`
- Create: `lib/src/components/file_selection/ui/tp_file_selection_strings.dart`
- Create: `test/components/file_selection/fake_file_selection_ports.dart` (test helpers)
- Modify: `lib/shared_ui.dart` (export public ports/deps/strings)

- [ ] **Step 1: Define ports (no test required beyond analyze)**

`TpFilesystemPort`:

```dart
abstract class TpFilesystemPort {
  List<TpFilesystemRoot> defaultRoots();

  /// Platform default browse root when [TpFileSelectionOptions.initialPath] is null.
  String defaultBrowsePath();

  Future<List<TpFsEntry>> listDir(String path);

  /// When null, UI hides the full-disk-search sub-tab.
  Future<List<TpFsEntry>>? Function(String rootPath, String query)? get searchFiles => null;

  Future<bool> exists(String path);

  Future<TpFsEntryKind> kindOf(String path);
}
```

`TpPermissionPort`:

```dart
abstract class TpPermissionPort {
  Future<bool> ensureStorageAccess();
  Future<bool> ensureGalleryAccess();
  Future<void> openAppSettings(); // no-op OK
}
```

`TpGalleryPort`:

```dart
abstract class TpGalleryPort {
  Future<List<TpGalleryAlbum>> listAlbums({required bool includeVideos, required bool includeImages});
  Future<List<TpGalleryAsset>> listAssets({
    required String albumId,
    required int page,
    required int pageSize,
    required bool includeVideos,
    required bool includeImages,
  });
  Future<Uint8List?> thumbnail(String assetId, {int size = 200});
  Future<String?> resolveToPath(String assetId);
}
```

`TpDesktopPickerPort` / `TpMediaPreviewPort` — match spec.

`TpFileSelectionDeps` — match spec (`filesystem`, `permission`, optional `gallery`/`desktop`/`preview`, `strings`, `isDesktop`).

`TpFileSelectionStrings` — plain Dart class with required `String` fields. Seed from **all** huji file-picker l10n keys used by the four source files (not a partial list). At minimum include the keys named in the design discussion plus: `enterSearchKeyword`, `searchResultsAdded`, `sortOptionsTitle`, `noItemsSelected`, selection summary labels, `currentDirectoryLabel`, and any other string literal currently read via `context.hujiL10n` in those files. Provide `TpFileSelectionStrings.english()` for tests.

- [ ] **Step 2: Add `FakeFilesystemPort` / `FakePermissionPort` / `FakeGalleryPort` in test helpers**

In-memory map of path → entries; permission always granted; gallery returns canned albums/assets.

- [ ] **Step 3: `flutter analyze` on package**

```bash
cd client/packages/shared_ui && flutter analyze --no-fatal-infos
```

Expected: no errors in new files

- [ ] **Step 4: Commit** (only if user asked)

---

### Task 3: Filter / sort / media-kind helpers (TDD)

**Files:**
- Create: `lib/src/components/file_selection/controller/tp_file_selection_filters.dart`
- Create: `test/components/file_selection/tp_file_selection_filters_test.dart`

- [ ] **Step 1: Write failing tests**

Cover:

1. Extension filter (case-insensitive, with/without leading `.`)
2. Hidden files (`name.startsWith('.')`) when `showHiddenFiles == false`
3. In-list query filters by name substring
4. Sort by name/date/size/type ascending/descending
5. `resolveGalleryMediaFilter(allowedExtensions)` → image-only / video-only / all (use common image/video extension sets **passed in** or defined as small shared const lists in the helper — do not import huji `FileExtensions`)

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement pure functions until PASS**

- [ ] **Step 4: Commit** (only if user asked)

---

### Task 4: Selection controller + tab API (TDD)

**Files:**
- Create: `lib/src/components/file_selection/controller/tp_file_selection_tab_api.dart`
- Create: `lib/src/components/file_selection/controller/tp_file_selection_controller.dart`
- Create: `test/components/file_selection/tp_file_selection_controller_test.dart`

- [ ] **Step 1: Write failing tests**

```dart
void main() {
  test('rejects incremental select beyond maxSelectionCount', () {
    final c = TpFileSelectionController(
      options: const TpFileSelectionOptions(allowMultiple: true, maxSelectionCount: 2),
      onMaxSelectionReached: (n) => lastToast = n,
    );
    c.replaceSelection([
      const TpPickedEntry(path: '/1', kind: TpPickedKind.file),
      const TpPickedEntry(path: '/2', kind: TpPickedKind.file),
    ]);
    final ok = c.trySelect(const TpPickedEntry(path: '/3', kind: TpPickedKind.file));
    expect(ok, isFalse);
    expect(c.selection, hasLength(2));
    expect(lastToast, 2);
  });

  test('selectAll caps to max and reports first-N toast', () { /* ... */ });

  test('requestTabChange asks confirm when selection non-empty', () { /* ... */ });

  test('directory mode confirm builds entry from currentPath', () { /* ... */ });
}
```

Also test: `clearSelection` notifies registered tab APIs; single-select replaces prior entry.

- [ ] **Step 2: Run — FAIL**

- [ ] **Step 3: Implement controller**

Key API sketch:

```dart
abstract class TpFileSelectionTabApi {
  void clearSelection();
  Future<void> selectAll();
  int get selectableCount;

  /// Filesystem tab only; gallery may no-op. Page app-bar sort calls this.
  void applySorting(String sortType, {required bool ascending});
}

class TpFileSelectionController extends ChangeNotifier {
  // selection, currentPath, activeTab
  // trySelect / deselect / replaceSelection / clear
  // selectAllFrom(List<TpPickedEntry> candidates) with max cap
  // bool shouldConfirmTabChange(TpFileSelectionTab target)
  // void confirmTabChange(...)
}
```

- [ ] **Step 4: PASS + Commit** (if asked)

---

### Task 5: `showTpFileSelection` entry + desktop routing (TDD)

**Files:**
- Create: `lib/src/components/file_selection/show_tp_file_selection.dart`
- Create: `test/components/file_selection/show_tp_file_selection_test.dart`
- Modify: `lib/shared_ui.dart`

- [ ] **Step 1: Failing test with fake desktop port**

Cases:

1. `isDesktop: () => true` + desktop port + `directories` → calls `pickDirectory` only
2. `files` / `both` → calls `pickFiles` with options
3. `isDesktop: () => false` → pushes page route (pump widget; expect page present) — page can be a stub `TpFileSelectionPage` placeholder until Task 6

- [ ] **Step 2: Implement `showTpFileSelection`**

```dart
Future<List<TpPickedEntry>?> showTpFileSelection({
  required BuildContext context,
  required TpFileSelectionDeps deps,
  TpFileSelectionOptions options = const TpFileSelectionOptions(),
}) async {
  if (deps.isDesktop() && deps.desktop != null) {
    final desktop = deps.desktop!;
    switch (options.selectionMode) {
      case TpSelectionMode.directories:
        return desktop.pickDirectory(
          dialogTitle: options.title,
          initialDirectory: options.initialPath,
        );
      case TpSelectionMode.files:
      case TpSelectionMode.both:
        return desktop.pickFiles(
          allowMultiple: options.allowMultiple,
          allowedExtensions: options.allowedExtensions,
          dialogTitle: options.title,
          initialDirectory: options.initialPath,
          maxSelectionCount: options.maxSelectionCount,
        );
    }
  }
  return Navigator.of(context).push<List<TpPickedEntry>>(
    MaterialPageRoute(
      builder: (_) => TpFileSelectionPage(deps: deps, options: options),
    ),
  );
}
```

- [ ] **Step 3: PASS + Commit** (if asked)

---

### Task 6: Filesystem tab UI

**Files:**
- Create: `lib/src/components/file_selection/ui/tp_filesystem_tab.dart`
- Create: `lib/src/components/file_selection/ui/widgets/tp_fs_entry_tile.dart`
- Create: `lib/src/components/file_selection/ui/widgets/tp_file_sort_sheet.dart`
- Create: `lib/src/components/file_selection/ui/widgets/tp_full_disk_search_dialog.dart`
- Create: `test/components/file_selection/tp_filesystem_tab_test.dart`

**Port from:** `huji-app/lib/widgets/file_picker/filesystem_tab.dart` (including nested `GlobalSearchDialog`)

- [ ] **Step 1: Widget test with FakeFilesystemPort**

1. Lists root entries after permission grant
2. Tapping directory calls `listDir` for child
3. In-list search filters visible names
4. Hidden file omitted when `showHiddenFiles: false`
5. Full-disk-search sub-tab hidden when `searchFiles == null`
6. Full-disk-search dialog uses `searchFiles` and can merge results into selection
7. Implements `TpFileSelectionTabApi` including `applySorting`

- [ ] **Step 2: Implement tab + full-disk search dialog**

Checklist vs huji:

- [ ] Sub-tabs: phone storage / app folders / full-disk search (labels from strings + roots from port)
- [ ] Full-disk search dialog parity with `GlobalSearchDialog` (query, results list, multi-select, merge into controller)
- [ ] Permission gate → empty state + open settings
- [ ] `initialPath` resolution: null → `defaultBrowsePath()`; file → parent; not found → callback to page to dialog+pop
- [ ] Sort via `applySorting` (page app bar calls active filesystem tab API — no `as dynamic`)
- [ ] Multi/single select wiring into controller
- [ ] No `dart:io` imports in this file — only `TpFsEntry`

- [ ] **Step 3: PASS tests + Commit** (if asked)

---

### Task 7: Gallery tab UI

**Files:**
- Create: `lib/src/components/file_selection/ui/tp_gallery_tab.dart`
- Create: `lib/src/components/file_selection/ui/widgets/tp_gallery_asset_tile.dart`
- Create: `test/components/file_selection/tp_gallery_tab_test.dart`

**Port from:** `huji-app/lib/widgets/file_picker/photo_gallery_tab.dart`

- [ ] **Step 1: Widget tests with FakeGalleryPort**

1. Shows albums then assets
2. Pagination loads page 2
3. In-list search filters
4. Preview button absent when `preview == null`
5. Selecting asset calls `resolveToPath` and updates controller
6. `TpFileSelectionTabApi` works

- [ ] **Step 2: Implement tab**

Checklist:

- [ ] `ensureGalleryAccess` before load
- [ ] Media kind from `resolveGalleryMediaFilter`
- [ ] Thumbnail cache via port
- [ ] Select-all respects maxCount + first-N toast
- [ ] No `photo_manager` / `AssetEntity` types

- [ ] **Step 3: PASS + Commit** (if asked)

---

### Task 8: Page chrome (app bar + bottom bars + tab switch)

**Files:**
- Create: `lib/src/components/file_selection/ui/tp_file_selection_page.dart`
- Create: `test/components/file_selection/tp_file_selection_page_test.dart`

**Port from:** `huji-app/lib/widgets/file_picker/file_selection_page.dart`

- [ ] **Step 1: Widget tests**

1. Gallery tab omitted when `deps.gallery == null` or `selectionMode == directories`
2. App bar has close + sort; **no** confirm in app bar
3. Files mode shows multi-select bottom bar; directory mode shows “select this directory” bar
4. Switching tabs with selection shows confirm dialog; cancel keeps tab; confirm clears
5. Confirm pops `List<TpPickedEntry>`
6. Path-not-found from filesystem tab pops entire page after dialog

- [ ] **Step 2: Implement page**

Use `TabController`; register both tabs’ `TpFileSelectionTabApi` with the page controller. App-bar sort opens sort sheet then calls **active filesystem tab** `applySorting` (gallery ignores). Prefer `TpDialog` / `AlertDialog` with injected strings. Toast via `TpToast` if `TpToastWrapper` present, else `ScaffoldMessenger`.

**Selection summary size:** `TpPickedEntry` has no size field. v1 bottom-bar summary may show **count only** (omit total bytes) unless the filesystem/gallery tab caches sizes when selecting and passes them through an optional `Map<path, size>` on the controller. Do not call `dart:io` from the page. Prefer count-only unless parity testing requires sizes — then extend controller cache, not the public entry model.

- [ ] **Step 3: PASS + Commit** (if asked)

---

### Task 9: shared_ui README + analyze gate

**Files:**
- Modify: `client/packages/shared_ui/README.md`
- Verify: `pubspec.yaml` still has **no** photo/permission/file_picker deps

- [ ] **Step 1: Add “File Selection” section** documenting `showTpFileSelection`, deps/ports, optional gallery, result type

- [ ] **Step 2: Run full package verification**

```bash
cd client/packages/shared_ui
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test test/components/file_selection
```

Expected: clean analyze for new code; all file_selection tests PASS

- [ ] **Step 3: Commit shared_ui** (if asked) and note submodule SHA for apps

---

### Task 10: huji adapters

**Files (under `huji/huji-app/`):**
- Create: `lib/widgets/file_picker/adapters/io_filesystem_port.dart`
- Create: `lib/widgets/file_picker/adapters/photo_manager_gallery_port.dart`
- Create: `lib/widgets/file_picker/adapters/permission_handler_port.dart`
- Create: `lib/widgets/file_picker/adapters/desktop_file_picker_port.dart`
- Create: `lib/widgets/file_picker/adapters/video_player_preview_port.dart`
- Create: `lib/widgets/file_picker/huji_file_selection_deps.dart`
- Create: `test/widgets/file_picker/io_filesystem_port_test.dart` (thin)
- Bump: `packages/shared_ui` submodule to SHA that contains Tasks 1–9

- [ ] **Step 1: Implement `IoFilesystemPort`** using `dart:io` + existing `file_utils` for downloads/app folders; implement `searchFiles` using prior `GlobalSearchDialog` search logic extracted from old `filesystem_tab.dart`

- [ ] **Step 2: Implement gallery/permission/desktop/preview adapters** wrapping current package APIs (`photo_manager`, `PermissionService`, `file_picker`, `VideoPlayerPage.show`). For desktop, **port** huji `DesktopFilePicker._resolveFileType` (video/image/media/custom) so `selectVideos` / `selectImages` keep desktop parity.

- [ ] **Step 3: `hujiFileSelectionDeps(BuildContext context)` builds `TpFileSelectionDeps` + `TpFileSelectionStrings` from `context.hujiL10n`

- [ ] **Step 4: Unit-test `IoFilesystemPort.listDir` against a temp directory**

- [ ] **Step 5: Commit** (if asked) in huji repo after submodule bump

---

### Task 11: huji facade cutover

**Files:**
- Today’s public API lives in `huji-app/lib/widgets/file_picker/file_selection_page.dart` (class `FileSelection` + page). Call sites import that path.
- Create: `huji-app/lib/widgets/file_picker/file_selection.dart` (facade only)
- Either: (A) make `file_selection_page.dart` export/redirect to facade for one release, or (B) update all imports to `file_selection.dart` in the same change
- Delete after green: old page/tab implementations (`filesystem_tab.dart`, `photo_gallery_tab.dart`, body of `file_selection_page.dart`, `desktop_file_picker.dart`)

- [ ] **Step 1: Extract facade from `file_selection_page.dart`**

Preserve:

- `FileSelection.show`
- `selectVideos` / `selectImages` / `selectMedia`
- `selectDirectories` / `selectFilesAndDirectories`
- enums `TabType`, `SelectionMode` — either keep as typedefs/wrappers mapping to `Tp*` or re-export mapping in facade

Map results:

```dart
List<FileSystemEntity> mapEntries(List<TpPickedEntry> entries) => [
  for (final e in entries)
    if (e.kind == TpPickedKind.directory) Directory(e.path) else File(e.path),
];
```

Grep call sites: `import 'package:huji_app/widgets/file_picker/file_selection_page.dart'` and relative `file_selection_page.dart` — update or keep shim.
- [ ] **Step 2: Run huji analyzer + targeted tests**

```bash
cd huji-app && flutter analyze --no-fatal-infos --no-fatal-warnings
# run any existing tests that import file_selection
```

- [ ] **Step 3: Manual smoke checklist** (document in PR): mobile files, gallery multi-select, directory mode, desktop pick, tab-switch clear

- [ ] **Step 4: Delete old monolithic files once no remaining imports**

- [ ] **Step 5: Commit** (if asked)

---

### Task 12: TeamPilot thin consumer (filesystem + desktop, no gallery)

**Files (under `teampilot/client/`):**
- Create: `lib/services/file_selection/teampilot_file_selection_deps.dart`
- Create: `lib/services/file_selection/adapters/local_filesystem_port.dart`
- Create: `lib/services/file_selection/adapters/permission_port.dart` (Android storage; desktop always granted)
- Create: `lib/services/file_selection/adapters/desktop_picker_port.dart`
- Create: `lib/services/file_selection/show_local_file_selection.dart`
- Optional one call-site swap: e.g. a local-only path in `workspace_path_picker.dart` **without** removing SSH `RemoteDirectoryBrowserDialog`
- Bump `packages/shared_ui` submodule
- Test: `test/services/file_selection/show_local_file_selection_test.dart` with fakes if practical

- [ ] **Step 1: Adapters + deps (`gallery: null`, `preview: null`)**

- [ ] **Step 2: `showLocalFileSelection` wrapper returning `List<String>?` paths (TeamPilot prefers paths over `dart:io` in many layers)

- [ ] **Step 3: Wire **one** low-risk local pick call site OR leave wrapper unused behind a TODO comment in README — prefer one real wire if a safe site exists (desktop local directory pick)

- [ ] **Step 4: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration` for touched tests

- [ ] **Step 5: Commit** (if asked)

---

## Verification matrix (done when all true)

| Check | Command / method |
|-------|------------------|
| shared_ui zero forbidden deps | Inspect `packages/shared_ui/pubspec.yaml` |
| shared_ui unit/widget tests | `flutter test test/components/file_selection` |
| huji facade API stable | Existing imports compile; manual smoke |
| TeamPilot builds with submodule | `flutter analyze` in `client/` |
| No `as dynamic` tab reflection | Grep shared_ui file_selection |

---

## Execution notes

- Prefer implementing Tasks 1–9 entirely inside the **shared_ui** checkout used by teampilot (`client/packages/shared_ui`), then sync submodule into huji.
- When porting UI, keep huji source open side-by-side; do not “simplify away” bottom bars or search.
- If a single UI file exceeds ~600 lines, split widgets into `ui/widgets/` before continuing.
