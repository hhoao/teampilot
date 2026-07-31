# TpFileSelection — extract huji mobile file picker into shared_ui

**Date:** 2026-08-01  
**Status:** Approved for planning  
**Problem:** huji ships a polished mobile file/directory/gallery picker (~4500 lines under `huji-app/lib/widgets/file_picker/`) that is tightly coupled to product deps (`photo_manager`, `permission_handler`, `file_picker`, huji l10n, `VideoPlayerPage`, `FileExtensions`). TeamPilot and huji share `shared_ui`, but that package has no reusable file-selection primitive; TeamPilot currently uses OS `file_picker` and a separate remote directory dialog.

**Builds on:** huji `FileSelection` / `FilesystemTab` / `PhotoGalleryTab` / `DesktopFilePicker`; shared_ui `TpTheme`, `TpHover`, `TpDialog` / `showTpDialog`, `TpToast`, `TpEmptyState`.

## Goal

1. Extract the **full** huji mobile file-selection UX into `shared_ui` as **`TpFileSelection`** (filesystem tab + gallery tab + desktop fallback + `showTpFileSelection` entry).
2. Keep **`shared_ui` free of hard deps** on `photo_manager`, `permission_handler`, and `file_picker` — all IO/platform concerns enter through **Ports** injected by each app.
3. Use an abstract result model (`TpPickedEntry`) inside the library; each app may provide a thin facade that maps to `File` / `Directory` for existing call sites.
4. Let TeamPilot and huji both consume the same API; TeamPilot may omit gallery initially.

## Decisions (locked)

| Topic | Choice |
|-------|--------|
| Consumer | Shared `shared_ui` submodule (huji + TeamPilot) |
| Scope (v1) | Full parity with current huji: filesystem + gallery + desktop fallback + show entry |
| Dependency policy | **Zero hard deps** in `shared_ui` for photo/permission/desktop picker packages |
| Result type | Library returns `List<TpPickedEntry>?`; apps own `FileSystemEntity` facades |
| Architecture | Layered: models → ports → controller → UI → `showTpFileSelection` |
| Extra package | **No** separate `shared_ui_file_picker` package |
| Strings | Injected `TpFileSelectionStrings` (not product ARB inside shared_ui) |
| Theme | `TpTheme` / existing Tp primitives; no hard-coded product colors |
| Gallery optional | `TpGalleryPort? == null` hides gallery tab |
| Desktop | If `isDesktop()` and `TpDesktopPickerPort` present → native desktop picker; else mobile page |
| Preview | Optional `TpMediaPreviewPort` (huji wires `VideoPlayerPage`; missing → disable preview affordances) |
| Extension lists | Caller-supplied `allowedExtensions`; product catalogs stay in apps |

## Non-goals

- Embedding `AssetEntity` / `FileSystemEntity` in shared_ui public API
- Adding `photo_manager` / `permission_handler` / `file_picker` to shared_ui `pubspec`
- Redesigning the picker UX from scratch (behavior should match current huji)
- Replacing TeamPilot remote/SFTP `RemoteDirectoryBrowserDialog` in v1 (local/OS picking only via this API)
- Web support
- Persisting last path / album across cold start beyond what huji already does via `initialPath`

## Invariants

1. **shared_ui pubspec** must not depend on `photo_manager`, `permission_handler`, or `file_picker`.
2. **All filesystem/gallery/permission/desktop/preview side effects** go through Ports; UI/controller never import those packages.
3. **Public selection result** is `TpPickedEntry` (path + kind + optional metadata), never `dart:io` types in the shared API.
4. **Cross-tab selection** is owned by a page controller with explicit tab interfaces (`clearSelection` / `selectAll` / `selectableCount`) — no `as dynamic` + GlobalKey reflection.
5. **Behavior parity** with current huji for: multi-select, max count, extension filter, hidden files, directory mode, tab-switch clear confirmation, **in-list search** (filesystem current-dir filter + gallery album filter), sort options, album pagination, desktop fallback, and bottom-bar confirm chrome (not app-bar confirm).
6. **Missing optional ports degrade safely** (no gallery tab / no preview / no full-disk search sub-tab) rather than crashing.

## Design

### 1. Architecture

```
shared_ui
  models/      TpPickedEntry, TpFsEntry, TpGalleryAlbum, TpGalleryAsset, …
  ports/       TpFilesystemPort, TpGalleryPort, TpPermissionPort,
               TpDesktopPickerPort, TpMediaPreviewPort
  controller/  selection state, filters, tab coordination
  ui/          page, filesystem tab, gallery tab, row/thumbnail widgets
  api/         showTpFileSelection(deps, options)

app (huji / teampilot)
  adapters/    concrete ports
  facade/      optional FileSelection.show → FileSystemEntity mapping
```

### 2. Models

```dart
enum TpPickedKind { file, directory }

class TpPickedEntry {
  final String path;
  final TpPickedKind kind;
  final String? displayName;
  final String? mimeType;
}

enum TpFsEntryKind { file, directory, other }

class TpFsEntry {
  final String path;
  final String name;
  final TpFsEntryKind kind;
  final DateTime? modifiedAt;
  final int? sizeBytes;
}

class TpGalleryAlbum {
  final String id;
  final String name;
  final int? assetCount;
}

class TpGalleryAsset {
  final String id;
  final String? displayName;
  final bool isVideo;
  final Duration? duration;
  final DateTime? createDateTime;
}
```

Gallery selection resolves assets to paths via `TpGalleryPort.resolveToPath` before they become `TpPickedEntry` values in the shared selection set.

### 3. Ports

| Port | Required? | Responsibility |
|------|-----------|----------------|
| `TpFilesystemPort` | yes | `listDir(path) → List<TpFsEntry>`; `defaultRoots` (phone storage / app folders / …); optional `searchFiles(root, query)` — if absent/null capability, hide full-disk-search sub-tab |
| `TpPermissionPort` | yes | `ensureStorageAccess` / `ensureGalleryAccess` (or combined); optional `openAppSettings()` for denied empty-states |
| `TpGalleryPort` | no | `listAlbums`; `listAssets(albumId, page, pageSize)`; `thumbnail(assetId) → bytes?`; `resolveToPath(assetId) → String?` |
| `TpDesktopPickerPort` | no | `pickFiles(...)` / `pickDirectory(...)` → `List<TpPickedEntry>?` |
| `TpMediaPreviewPort` | no | `previewImage(context, path)` / `previewVideo(context, path)` |

```dart
class TpFileSelectionDeps {
  final TpFilesystemPort filesystem;
  final TpPermissionPort permission;
  final TpGalleryPort? gallery;
  final TpDesktopPickerPort? desktop;
  final TpMediaPreviewPort? preview;
  final TpFileSelectionStrings strings;
  final bool Function() isDesktop;
}

enum TpSelectionMode { files, directories, both }
enum TpFileSelectionTab { filesystem, gallery }

class TpFileSelectionOptions {
  final bool allowMultiple;
  final List<String>? allowedExtensions;
  final String? title;
  final int? maxSelectionCount;
  final TpFileSelectionTab? initialTab;
  final String? initialPath;
  final TpSelectionMode selectionMode;
  final bool showHiddenFiles;
}

Future<List<TpPickedEntry>?> showTpFileSelection({
  required BuildContext context,
  required TpFileSelectionDeps deps,
  TpFileSelectionOptions options = const TpFileSelectionOptions(),
});
```

### 4. UI behavior and data flow

**Entry**

1. If `deps.isDesktop()` and `deps.desktop != null` → desktop port; return immediately.
2. Else push full-screen `TpFileSelectionPage` (mobile chrome; align with existing huji full-screen page / `TpDialog` page presentation where appropriate).

**Page chrome (match huji layout)**

- **App bar:** title, leading close, trailing **sort** (filesystem). Confirm does **not** live in the app bar.
- **Bottom bar (files / both):** selection summary, clear, select-all, confirm with count.
- **Bottom bar (directories):** current path + “select this directory” (distinct from the multi-select bar).
- Tabs: Filesystem | Gallery. Gallery omitted when `gallery == null` or `selectionMode == directories`.
- Directory mode confirm returns current directory as a single `TpPickedEntry(kind: directory)`.

**Cross-tab**

- Switching tabs with a non-empty selection shows a confirm dialog (`strings`); on confirm, clear then switch.
- Page controller holds `List`/`Set` of `TpPickedEntry`; child tabs implement a small interface for clear/select-all/count.

**Filesystem tab**

- Sub-nav driven by filesystem roots / capabilities: phone storage, app folders, full-disk search (hide that sub-tab if `searchFiles` is unavailable).
- **In-list search:** toolbar query filters the **current directory listing** (client-side); this is separate from the full-disk-search sub-tab.
- Lazy `listDir`; filter by extensions + hidden files; sort by name/date/size/type.
- Permission gate via `permission.ensureStorageAccess()`; denied → empty state (+ `openAppSettings` when provided).
- **`initialPath`:** `null` → platform default root (Android `/storage/emulated/0`, else `$HOME` / port default). Path is a **file** → open its **parent directory**. Path **not found** → error dialog, then **pop the entire selection page** (match huji).

**Gallery tab**

- Album list → paged asset grid/list.
- **In-list search:** filter assets in the current album (`searchMedia` parity).
- Thumbnails via port; selection resolves to path.
- Media kind (image/video/all) derived from `allowedExtensions` in controller.
- Preview affordances call `preview`; absent preview disables those controls.

**Limits / feedback**

- Exceeding `maxSelectionCount` on incremental select: toast/snackbar and reject the extra items.
- Select-all when the selectable set exceeds `maxSelectionCount`: select the first N and toast that the first N were selected (huji gallery/filesystem parity).
- Prefer `TpToast` where the host already wraps it; otherwise a thin host callback is acceptable.

### 5. Package file layout

```
packages/shared_ui/lib/src/components/file_selection/
  models/
  ports/
  controller/
  ui/
    tp_file_selection_page.dart
    tp_filesystem_tab.dart
    tp_gallery_tab.dart
    tp_file_selection_strings.dart
    widgets/
  show_tp_file_selection.dart
```

Export public API from `lib/shared_ui.dart`. Keep row/thumbnail helpers internal unless another consumer needs them.

**App-side (huji example; TeamPilot symmetric, gallery optional)**

```
huji-app/lib/widgets/file_picker/
  huji_file_selection_deps.dart
  adapters/
    io_filesystem_port.dart
    photo_manager_gallery_port.dart
    permission_handler_port.dart
    desktop_file_picker_port.dart
    video_player_preview_port.dart
  file_selection.dart   # legacy facade → FileSystemEntity
```

Delete or shrink the current monolithic tab/page files once adapters + shared_ui land.

### 6. Migration

1. Land models/ports + fake-port unit tests in shared_ui.
2. Port controller + UI with behavior parity vs huji.
3. Wire huji adapters + facade; keep `FileSelection.show` / `selectVideos` / `selectImages` / `selectMedia` / `selectDirectories` / `selectFilesAndDirectories` signatures for call sites.
4. TeamPilot: filesystem (+ desktop) first; gallery later if needed.
5. Document under shared_ui README “File Selection”.

### 7. Testing

| Layer | Coverage |
|-------|----------|
| shared_ui controller | filter, max count, tab-clear confirm logic, extension→media kind |
| shared_ui UI | widget tests with fake ports |
| app adapters | thin mapping tests |
| app facade | smoke that legacy API still returns expected `File`/`Directory` shapes |

No real-device gallery/permission integration tests inside shared_ui CI.

## Success criteria

- shared_ui has zero hard deps on photo/permission/desktop picker packages.
- huji mobile file, gallery, and directory picking match current behavior via the facade.
- TeamPilot can open the same API for local file/directory picking without implementing gallery.
- Call sites no longer depend on the old monolithic widget files.

## Open questions (resolved)

| Question | Resolution |
|----------|------------|
| Which picker? | huji `lib/widgets/file_picker`, not Orca |
| Shared vs huji-only shared_ui? | Shared submodule for both apps |
| Full vs phased feature set? | Full in v1 |
| Hard deps vs ports? | Ports only |
| Result type? | `TpPickedEntry` + app facades |
