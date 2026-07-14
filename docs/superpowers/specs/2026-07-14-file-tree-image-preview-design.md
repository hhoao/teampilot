# File tree image preview

Open common bitmap images from the workspace file tree in an in-app workbench tab (same preview/pin behavior as text files), with basic zoom via `photo_view`.

## Goal

Today only allowlisted text extensions open in the editor. Image files fall through to the system default app (`xdg-open` / `open` / `start`) from the file tree, and `EditorCubit.openFile` treats non-text paths as binary and shows a snackbar.

Users should click (preview) / double-click (pin) a PNG/JPEG/etc. in the file tree and see it centered in the workbench file surface, with scroll-wheel and toolbar zoom plus double-tap reset.

## Non-goals

- SVG preview (SVG stays text-editable via `kEditorTextExtensions`).
- HEIC, ICO, RAW, or other formats beyond the first-version allowlist.
- System image-viewer affordance from the editor toolbar.
- Image editing, crop, annotate, or EXIF panels.
- Multi-image gallery / next-prev browsing.
- Changing markdown embedded-image rendering.

## Formats (v1)

`png`, `jpg`, `jpeg`, `gif`, `webp`, `bmp` — case-insensitive extension match.

## Approach

Reuse existing `WorkbenchTabKind.file` tabs. Classify paths as text vs image; both are “openable in app.” Images load bytes instead of a text document session; `FileEditorSurface` swaps the body to a `PhotoView` preview.

Do **not** add `WorkbenchTabKind.image`.

## Open path

1. File tree (and any caller of `WorkbenchEditorOpener.openFile`) treats image paths as in-app openable — no muted row styling, no immediate external open.
2. `WorkbenchEditorOpener.openFile` always `ensureTab` for image paths (same preview/pin as text), then `EditorCubit.openFile`.
3. Other non-text, non-image files keep today’s external-open behavior from the file tree.

Classification helpers live next to `isEditorOpenableFilePath` in `file_editor_theme.dart` (or a small sibling module if that file grows):

| Helper | Role |
|--------|------|
| `kEditorImageExtensions` | Allowlist above |
| `isImagePreviewPath(path)` | Extension in allowlist |
| `isEditorOpenableFilePath` | Unchanged text/basename rules |
| `isWorkbenchOpenableFilePath` (or equivalent) | text **or** image — used by file tree / opener gating |

## Data flow (`EditorCubit`)

For `isImagePreviewPath`:

1. Normalize path; skip if already open (same as text).
2. Mark loading; `Filesystem.stat` via injected/`fs` (local, WSL, SSH).
3. Reject missing / non-file.
4. Reject size above `kEditorMaxImageBytes` (**25 MiB**, separate from `kEditorMaxFileBytes`).
5. `readBytes`; store a bytes handle — **no** `CodeLineEditingController`, **no** DocumentSession / token provider.
6. Emit open path into the workspace bucket; clear loading.

On close: dispose bytes handle; existing preview-tab replace / `closeFile` paths apply.

Decode failure (bad bytes for a matching extension): detect in the surface via `ImageStream` / `ImageProvider` error listener (or `PhotoView` error builder if available), then set `errorByPath` / show the error body — do not leave a blank crash surface. Do **not** require a cubit-side pre-decode for v1.

## UI (`FileEditorSurface`)

When the active path is an image preview:

- **Toolbar:** basename + zoom controls (`−` / scale label / `+`, optional reset). No Save, Revert, File↔Diff, or Markdown mode toggle.
- **Body:** `PhotoView` with `MemoryImage(bytes)` (dependency: [`photo_view`](https://pub.dev/packages/photo_view) `^0.15.0`). Contained fit by default; mouse-wheel zoom; double-tap resets scale; pan allowed (library default).
- Loading / error: reuse existing editor loading and error presentation for that path.

Text paths keep current behavior.

## Errors

| Case | Behavior |
|------|----------|
| Not found / unreadable | Existing editor error messages |
| Over `kEditorMaxImageBytes` | **New** l10n key (do not reuse `editorFileTooLarge` — it hardcodes 2 MB / “edit”) |
| Decode failure | Error state in surface via image stream error, not silent blank |
| Non-image binary | File tree still opens externally; cubit still rejects if somehow invoked |

Call sites that currently gate on `isEditorOpenableFilePath` only (e.g. terminal URI opener, markdown preview links) may keep text-only behavior in v1; file tree + `WorkbenchEditorOpener` must use the workbench-openable helper. Follow-up: switch those call sites to the same helper so images open in-app everywhere.

## Testing

- Unit: extension helpers (`isImagePreviewPath`, workbench-openable vs text-only).
- Cubit: image open stores bytes and does not create a text session; oversize rejected; close releases handle.
- Opener / integration-style: image path creates/activates a `WorkbenchTabId.file` tab (preview semantics preserved).

## File / module sketch

- `client/pubspec.yaml` — add `photo_view`
- `services/editor/file_editor_theme.dart` — image allowlist + helpers
- `cubits/editor_cubit.dart` — bytes open/close branch
- `services/workbench/workbench_editor_opener.dart` — gate on workbench-openable (text or image)
- `widgets/file_tree_node.dart` (+ context menu if it shares the gate) — use workbench-openable
- `pages/workbench/file_editor_surface.dart` — image toolbar + `PhotoView` body (extract widget if surface grows)
- `l10n` — new image-too-large (and decode-failure if no suitable existing key)

## Out of scope follow-ups

- SVG as optional preview vs source toggle.
- “Open with system viewer” from the image toolbar.
- Higher size limits with downsampled decode / tile cache.
- Routing terminal URI / markdown link opens through `isWorkbenchOpenableFilePath`.
