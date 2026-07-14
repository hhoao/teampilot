# File Tree Image Preview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Open common bitmap images from the file tree in an in-app workbench file tab with `photo_view` zoom (scroll / toolbar / double-tap reset).

**Architecture:** Reuse `WorkbenchTabKind.file`. Add image-extension helpers beside the text allowlist; `EditorCubit` loads `Uint8List` via `Filesystem.readBytes` (no text session); `FileEditorSurface` swaps to an image toolbar + `PhotoView` body. File tree / opener gate on text **or** image.

**Tech Stack:** Flutter, `flutter_bloc`, existing `Filesystem` / workbench tab APIs, [`photo_view`](https://pub.dev/packages/photo_view) `^0.15.0`, ARB l10n.

**Spec:** `docs/superpowers/specs/2026-07-14-file-tree-image-preview-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `client/pubspec.yaml` | Add `photo_view` |
| `client/lib/services/editor/file_editor_theme.dart` | `kEditorImageExtensions`, `kEditorMaxImageBytes`, `isImagePreviewPath`, `isWorkbenchOpenableFilePath` |
| `client/lib/services/editor/editor_messages.dart` | `imageTooLarge`, `imageDecodeFailed` codes |
| `client/lib/l10n/app_en.arb`, `app_zh.arb` (+ generated) | Image too-large / decode-failed strings |
| `client/lib/l10n/l10n_extensions.dart` | Map new `EditorMessage` codes |
| `client/lib/cubits/editor_cubit.dart` | Bytes open/close; `bytesFor`; `reportImageDecodeFailed` |
| `client/lib/services/workbench/workbench_editor_opener.dart` | Gate with `isWorkbenchOpenableFilePath` |
| `client/lib/widgets/file_tree_node.dart` | Same gate for styling + open |
| `client/lib/widgets/file_tree/file_tree_context_menu.dart` | Open newly created image files in-app when applicable |
| `client/lib/pages/workbench/file_editor_image_preview.dart` | **New** — toolbar zoom + `PhotoView` body |
| `client/lib/pages/workbench/file_editor_surface.dart` | Branch toolbar/body for image paths |
| `client/test/support/in_memory_filesystem.dart` | Return `size` from `stat` for byte/text files (needed for size-limit tests) |
| `client/test/services/editor/file_editor_theme_image_test.dart` | **New** — extension helpers |
| `client/test/cubits/editor_cubit_test.dart` | Image open / oversize / close |
| `client/test/services/workbench/workbench_editor_opener_test.dart` | Image path creates file tab before bytes load |

---

### Task 1: Classification helpers (TDD)

**Files:**
- Create: `client/test/services/editor/file_editor_theme_image_test.dart`
- Modify: `client/lib/services/editor/file_editor_theme.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/editor/file_editor_theme.dart';

void main() {
  test('isImagePreviewPath allowlist', () {
    expect(isImagePreviewPath('/a/b.PNG'), isTrue);
    expect(isImagePreviewPath('/a/photo.jpeg'), isTrue);
    expect(isImagePreviewPath('/a/x.webp'), isTrue);
    expect(isImagePreviewPath('/a/x.gif'), isTrue);
    expect(isImagePreviewPath('/a/x.bmp'), isTrue);
    expect(isImagePreviewPath('/a/x.svg'), isFalse);
    expect(isImagePreviewPath('/a/x.txt'), isFalse);
    expect(isImagePreviewPath('/a/x.heic'), isFalse);
  });

  test('workbench openable is text or image; svg stays text-only', () {
    expect(isWorkbenchOpenableFilePath('/a/x.png'), isTrue);
    expect(isWorkbenchOpenableFilePath('/a/x.dart'), isTrue);
    expect(isWorkbenchOpenableFilePath('/a/x.svg'), isTrue);
    expect(isEditorOpenableFilePath('/a/x.png'), isFalse);
    expect(isEditorOpenableFilePath('/a/x.svg'), isTrue);
    expect(isWorkbenchOpenableFilePath('/a/x.pdf'), isFalse);
  });

  test('kEditorMaxImageBytes is 25 MiB', () {
    expect(kEditorMaxImageBytes, 25 * 1024 * 1024);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run from `client/`:

```bash
flutter test test/services/editor/file_editor_theme_image_test.dart
```

Expected: FAIL (undefined helpers / constants).

- [ ] **Step 3: Implement helpers** in `file_editor_theme.dart` (near existing text allowlist):

```dart
const kEditorImageExtensions = {
  'png',
  'jpg',
  'jpeg',
  'gif',
  'webp',
  'bmp',
};

/// Max image bytes loaded for in-app preview (separate from text editor cap).
const kEditorMaxImageBytes = 25 * 1024 * 1024;

bool isImagePreviewPath(String filePath) {
  final ext = p.extension(filePath).replaceFirst('.', '').toLowerCase();
  return ext.isNotEmpty && kEditorImageExtensions.contains(ext);
}

bool isWorkbenchOpenableFilePath(String filePath) =>
    isEditorOpenableFilePath(filePath) || isImagePreviewPath(filePath);
```

Do **not** add image extensions to `kEditorTextExtensions`.

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/services/editor/file_editor_theme_image_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/editor/file_editor_theme.dart \
  client/test/services/editor/file_editor_theme_image_test.dart
git commit -m "feat(editor): classify image paths for workbench open"
```

---

### Task 2: l10n + EditorMessage codes

**Files:**
- Modify: `client/lib/services/editor/editor_messages.dart`
- Modify: `client/lib/l10n/app_en.arb`
- Modify: `client/lib/l10n/app_zh.arb`
- Modify: `client/lib/l10n/l10n_extensions.dart`
- Modify: generated `app_localizations*.dart` via `flutter gen-l10n`

- [ ] **Step 1: Add message codes**

```dart
static const imageTooLarge = 'editor_error_image_too_large';
static const imageDecodeFailed = 'editor_error_image_decode_failed';
```

- [ ] **Step 2: Add ARB keys** near existing `editor*` strings:

```json
"editorImageTooLarge": "Image is too large to preview in TeamPilot (max 25 MB).",
"editorImageDecodeFailed": "Could not decode this image.",
```

```json
"editorImageTooLarge": "图片过大，无法在 TeamPilot 中预览（上限 25 MB）。",
"editorImageDecodeFailed": "无法解码此图片。",
```

- [ ] **Step 3: Wire l10n mapping**

```dart
EditorMessage.imageTooLarge => editorImageTooLarge,
EditorMessage.imageDecodeFailed => editorImageDecodeFailed,
```

- [ ] **Step 4: Regenerate localizations**

```bash
cd client && flutter gen-l10n
```

If the project also regenerates warmup glyphs after ARB changes, run:

```bash
dart run tool/gen_warmup_glyphs.dart
```

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/editor/editor_messages.dart client/lib/l10n/
git commit -m "l10n: add editor image too-large and decode-failed strings"
```

---

### Task 3: InMemoryFilesystem `stat` size + EditorCubit image open (TDD)

**Files:**
- Modify: `client/test/support/in_memory_filesystem.dart`
- Modify: `client/test/cubits/editor_cubit_test.dart`
- Modify: `client/lib/cubits/editor_cubit.dart`

- [ ] **Step 1: Make `InMemoryFilesystem.stat` return sizes**

When resolving a text or byte file, set `size:` to content length (UTF-16 code units for strings is fine for tests; prefer `utf8.encode(text).length` if the file already imports `dart:convert`, otherwise `text.length` is acceptable for oversize tests that use `byteFiles`).

Example for `byteFiles`:

```dart
if (byteFiles.containsKey(path)) {
  return FsStat(kind: FsEntityKind.file, size: byteFiles[path]!.length);
}
```

- [ ] **Step 2: Write failing cubit tests** (append to `editor_cubit_test.dart`):

```dart
test('openFile loads image bytes without text controller', () async {
  final fs = InMemoryFilesystem();
  // Minimal valid 1x1 PNG
  fs.byteFiles['/repo/dot.png'] = <int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // ... or any non-empty bytes for open path
  ];
  // Prefer writing a real tiny PNG via LocalFilesystem temp file if decode is not required here.
  final cubit = EditorCubit(fs: fs);
  addTearDown(cubit.close);

  await cubit.openFile(ws, '/repo/dot.png');
  expect(cubit.state.bucket(ws).openFilePaths, ['/repo/dot.png']);
  expect(cubit.controllerFor(ws, '/repo/dot.png'), isNull);
  expect(cubit.bytesFor(ws, '/repo/dot.png'), isNotNull);
  expect(cubit.documentSessionFor(ws, '/repo/dot.png'), isNull);

  cubit.closeFile(ws, '/repo/dot.png', force: true);
  expect(cubit.bytesFor(ws, '/repo/dot.png'), isNull);
});

test('openFile rejects oversized images', () async {
  final fs = InMemoryFilesystem();
  fs.byteFiles['/repo/big.png'] = List<int>.filled(kEditorMaxImageBytes + 1, 0);
  final cubit = EditorCubit(fs: fs);
  addTearDown(cubit.close);

  await cubit.openFile(ws, '/repo/big.png');
  expect(cubit.state.bucket(ws).openFilePaths, isEmpty);
  expect(
    cubit.state.bucket(ws).errorByPath['/repo/big.png'],
    EditorMessage.imageTooLarge,
  );
});
```

Import `file_editor_theme.dart` and `editor_messages.dart` as needed. For the first test, any non-empty `byteFiles` entry is enough (decode is UI-side).

- [ ] **Step 3: Run tests to verify they fail**

```bash
flutter test test/cubits/editor_cubit_test.dart --name image
```

Expected: FAIL (`bytesFor` missing / images still treated as binary).

- [ ] **Step 4: Implement cubit image branch**

In `openFile`:

1. If `isImagePreviewPath(normalized)` → image path (do **not** require `isEditorOpenableFilePath`).
2. Else if `!isEditorOpenableFilePath(normalized)` → existing binary snackbar + return.
3. Image path: loading → `stat` → missing → size `> kEditorMaxImageBytes` → `EditorMessage.imageTooLarge` → `readBytes` → store handle → add to `openFilePaths`.

Handle storage options (pick one; prefer separate map for clarity):

```dart
final Map<String, Uint8List> _imageBytes = {};

Uint8List? bytesFor(String workspaceId, String path) =>
    _imageBytes[_handleKey(workspaceId, path)];

void reportImageDecodeFailed(String workspaceId, String path) {
  // set errorByPath[path] = EditorMessage.imageDecodeFailed if still open
}
```

On `_disposeHandle` / close: also remove `_imageBytes[key]`. Do not create `_OpenFileHandle` for images.

When storing `Filesystem.readBytes` (`List<int>?`), use `Uint8List.fromList(bytes)` (or keep if already `Uint8List`) so `bytesFor` / `MemoryImage` typing is clear. Add `import 'dart:typed_data';` if needed.

- [ ] **Step 5: Run tests to verify they pass**

```bash
flutter test test/cubits/editor_cubit_test.dart
```

Expected: all PASS (including existing text tests).

- [ ] **Step 6: Commit**

```bash
git add client/lib/cubits/editor_cubit.dart \
  client/test/cubits/editor_cubit_test.dart \
  client/test/support/in_memory_filesystem.dart
git commit -m "feat(editor): open image files as workbench byte previews"
```

---

### Task 4: Opener + file tree gates (TDD opener)

**Files:**
- Modify: `client/test/services/workbench/workbench_editor_opener_test.dart`
- Modify: `client/lib/services/workbench/workbench_editor_opener.dart`
- Modify: `client/lib/widgets/file_tree_node.dart`
- Modify: `client/lib/widgets/file_tree/file_tree_context_menu.dart`

- [ ] **Step 1: Write failing opener test**

```dart
test('openFile ensures workbench tab for image paths', () async {
  final gate = Completer<void>();
  final fs = _GatedFilesystem(gate)
    ..byteFiles['/repo/a.png'] = const [1, 2, 3];
  final editor = EditorCubit(fs: fs);
  final workbench = WorkbenchCubit();
  addTearDown(editor.close);
  addTearDown(workbench.close);

  final opener = WorkbenchEditorOpener(
    editor: editor,
    workbench: workbench,
    markdownViewModes: MarkdownViewModeStore(),
    readMarkdownOpenMode: () => MarkdownOpenMode.preview,
  );
  final pending = opener.openFile('ws', '/repo/a.png');
  await Future<void>.delayed(Duration.zero);

  expect(workbench.activeTabId('ws'), WorkbenchTabId.file('/repo/a.png'));
  gate.complete();
  await pending;
  expect(editor.bytesFor('ws', '/repo/a.png'), isNotNull);
});
```

Ensure `_GatedFilesystem.stat` still awaits the gate (already does).

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/services/workbench/workbench_editor_opener_test.dart
```

Expected: FAIL — image path currently skips `ensureTab` (non-text early path).

- [ ] **Step 3: Fix opener gate**

Replace `isEditorOpenableFilePath` check with `isWorkbenchOpenableFilePath`:

```dart
if (!isWorkbenchOpenableFilePath(normalized)) {
  await _editor.openFile(workspaceId, normalized, fs: fs);
  return;
}
// ensureTab + openFile (markdown seed only when isMarkdownEditorPath)
```

- [ ] **Step 4: Update file tree**

In `file_tree_node.dart`:

- `canOpenInEditor` → `isWorkbenchOpenableFilePath(widget.path)`
- `_openFile`: if `!isWorkbenchOpenableFilePath` → external; else opener

In `file_tree_context_menu.dart`: when auto-opening a created file, use `isWorkbenchOpenableFilePath(created)`.

Leave `terminal_uri_opener.dart` / markdown link handler on text-only gate (spec follow-up).

- [ ] **Step 5: Run opener tests**

```bash
flutter test test/services/workbench/workbench_editor_opener_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/workbench/workbench_editor_opener.dart \
  client/lib/widgets/file_tree_node.dart \
  client/lib/widgets/file_tree/file_tree_context_menu.dart \
  client/test/services/workbench/workbench_editor_opener_test.dart
git commit -m "feat(workbench): open image paths in file tabs from tree"
```

---

### Task 5: Add `photo_view` dependency

**Files:**
- Modify: `client/pubspec.yaml`
- Modify: `client/pubspec.lock` (via pub get)

- [ ] **Step 1: Add dependency**

Under `dependencies:`:

```yaml
photo_view: ^0.15.0
```

- [ ] **Step 2: Resolve**

```bash
cd client && flutter pub get
```

Expected: success; lockfile updates.

- [ ] **Step 3: Commit**

```bash
git add client/pubspec.yaml client/pubspec.lock
git commit -m "deps: add photo_view for editor image preview"
```

---

### Task 6: Image preview UI surface

**Files:**
- Create: `client/lib/pages/workbench/file_editor_image_preview.dart`
- Modify: `client/lib/pages/workbench/file_editor_surface.dart`

- [ ] **Step 1: Create `FileEditorImagePreview`**

Stateful widget taking only `workspaceId` and `path`. It reads loading / `errorByPath` / `bytesFor` from `EditorCubit` (same pattern as `_FileEditorBody`) so the tab can show spinner/error before bytes arrive.

Behavior:

- Hold `PhotoViewController` and/or `PhotoViewScaleStateController`; dispose in `dispose`.
- Header: 36px row with basename + zoom (`−` / percent / `+` / reset). No Save/Diff/Markdown.
- Body: when bytes ready, `PhotoView` with `MemoryImage(bytes)`, `minScale` / `maxScale` reasonable (e.g. contained × 0.5 … 4), `initialScale: PhotoViewComputedScale.contained`, background matching workspace surface.
- Wire `errorBuilder` / image stream errors → `context.read<EditorCubit>().reportImageDecodeFailed(workspaceId, path)`.
- Double-tap reset via PhotoView scale-state (`PhotoViewScaleState.initial`) or equivalent.

Keep the widget under ~200 lines.

- [ ] **Step 2: Branch `FileEditorSurface`**

When `isImagePreviewPath(path)`:

```dart
return ColoredBox(
  color: cs.workspaceCard,
  child: FileEditorImagePreview(workspaceId: workspaceId, path: path),
);
```

Skip the dirty→pin `BlocListener` for images (never dirty) or leave it no-op. When not image: keep the existing text/markdown column unchanged.

- [ ] **Step 3: Manual smoke (implementer)**

Run the app, open a workspace file tree, click a `.png` / `.jpg`:

- Preview tab opens; image visible and centered.
- Wheel / ± zoom; double-tap resets.
- Double-click file pins tab (existing workbench behavior).
- Oversize / corrupt file shows l10n error (optional quick check with a renamed `.png` text file).

- [ ] **Step 4: Analyze**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings \
  lib/pages/workbench/file_editor_surface.dart \
  lib/pages/workbench/file_editor_image_preview.dart \
  lib/cubits/editor_cubit.dart
```

Expected: no new errors in touched files.

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/workbench/file_editor_image_preview.dart \
  client/lib/pages/workbench/file_editor_surface.dart
git commit -m "feat(workbench): PhotoView image preview surface"
```

---

### Task 7: Verification

**Files:** none (run only)

- [ ] **Step 1: Run focused tests**

```bash
cd client && flutter test \
  test/services/editor/file_editor_theme_image_test.dart \
  test/cubits/editor_cubit_test.dart \
  test/services/workbench/workbench_editor_opener_test.dart
```

Expected: all PASS.

- [ ] **Step 2: Broader check (per CODE_QUALITY)**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && \
  flutter test --exclude-tags integration
```

Expected: analyze clean enough for CI norms; tests green (or only pre-existing failures unrelated to this change — do not expand scope).

- [ ] **Step 3: Final commit only if Step 2 produced leftover fixes**

Otherwise no commit.

---

## Out of scope (do not implement in this plan)

- SVG preview, HEIC/ICO, system viewer button, gallery, EXIF
- Switching terminal URI / markdown link openers to `isWorkbenchOpenableFilePath`
