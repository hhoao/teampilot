# SVG Preview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** SVG files open in the workbench with a rendered preview (zoom/pan) by default and an Edit|Preview toggle to switch to source editing.

**Architecture:** SVG stays in the text pipeline (`kEditorTextExtensions` unchanged) so editing/dirty/save all keep working; a new `SvgPreviewPane` reads on-disk bytes itself (like `HtmlPreviewPane`) and renders them via `PhotoView.customChild` + `SvgPicture.memory`. A new `SvgViewModeStore` (default `preview`) hangs off `WorkbenchEditorOpener`, and `FileEditorSurface` routes svg paths between preview pane and code editor.

**Tech Stack:** Flutter, flutter_bloc, `flutter_svg` 2.3 (already a dependency — it re-exports `vg`, `PictureInfo`, `SvgBytesLoader` from `vector_graphics`, no new pubspec entry), `photo_view` 0.15 (already a dependency).

**Spec:** `docs/superpowers/specs/2026-09-09-svg-preview-design.md`

## Global Constraints

- **Never run `flutter test` directly.** Always: `cd client && dart run tool/run_tests.dart <paths>` (concurrent direct runs corrupt the shared build cache). Narrow with `--plain-name`.
- **Test loop:** inner loop is `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`; verify with one test file; full suite only once at the end (Task 7).
- **l10n:** no new strings needed — reuse `htmlViewToggleEdit`/`htmlViewTogglePreview`, `shortcutsZoomIn`/`shortcutsZoomOut`/`shortcutsZoomReset`, `editorPanelErrorMessage`. Never hand-edit `client/lib/l10n/app_localizations*.dart` (generated).
- **`svg` must stay in `kEditorTextExtensions`** (`client/lib/services/editor/file_editor_theme.dart:96`) and **must NOT be added to `kEditorImageExtensions`** — `isImagePreviewPath('/a/x.svg')` stays `false`.
- **Typography:** text styles only via `TpTextStyles.of(context)` named tokens (e.g. `.sm`, `.mdSemibold`) from `package:shared_ui`.
- **Filesystem access** always through the injected `Filesystem` (never `File`/`Directory.current` in feature code). Tests use `test/support/in_memory_filesystem.dart` (stores files as `Map<String, String>`; `readBytes` utf8-encodes — fine for SVG, not for binary PNG).
- **Commits:** after each task, conventional style (`feat:`/`refactor:`/`test:`), end message with `Co-Authored-By: Claude <noreply@anthropic.com>`.
- Working tree already has unrelated modifications (git graph panes, layout cubit, incident-detection docs). **Only stage the files this plan touches** — never `git add -A`.

---

### Task 1: `isSvgPreviewPath` classification

**Files:**
- Modify: `client/lib/services/editor/file_editor_theme.dart` (after `isHtmlPreviewPath`, ~line 162)
- Test: `client/test/services/editor/file_editor_theme_image_test.dart`

**Interfaces:**
- Consumes: `kEditorTextExtensions`, `kEditorImageExtensions` (unchanged).
- Produces: `bool isSvgPreviewPath(String filePath)` — used by Task 6 (`FileEditorSurface`) and its test.

- [ ] **Step 1: Write the failing test**

Append to the `main()` of `client/test/services/editor/file_editor_theme_image_test.dart`:

```dart
test('isSvgPreviewPath allowlist', () {
  expect(isSvgPreviewPath('/a/icon.svg'), isTrue);
  expect(isSvgPreviewPath('/a/icon.SVG'), isTrue);
  expect(isSvgPreviewPath('/a/icon.png'), isFalse);
  expect(isSvgPreviewPath('/a/svg'), isFalse); // extensionless basename
  expect(isSvgPreviewPath('/a/x.txt'), isFalse);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/editor/file_editor_theme_image_test.dart`
Expected: FAIL — `isSvgPreviewPath` undefined.

- [ ] **Step 3: Write minimal implementation**

In `client/lib/services/editor/file_editor_theme.dart`, after `isHtmlPreviewPath` (line ~162):

```dart
const kSvgPreviewExtensions = {'svg'};

/// Whether [filePath] renders through the in-app SVG preview pane
/// (Edit|Preview, preview is the default). SVG also stays in
/// [kEditorTextExtensions] for source editing.
bool isSvgPreviewPath(String filePath) {
  final ext = p.extension(filePath).replaceFirst('.', '').toLowerCase();
  return ext.isNotEmpty && kSvgPreviewExtensions.contains(ext);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/editor/file_editor_theme_image_test.dart`
Expected: PASS (all tests in the file, including the pre-existing svg assertions).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/editor/file_editor_theme.dart client/test/services/editor/file_editor_theme_image_test.dart
git commit -m "feat(editor): add isSvgPreviewPath classification for svg files

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: `SvgViewModeStore`

**Files:**
- Create: `client/lib/services/editor/svg_view_mode_store.dart`
- Test: `client/test/services/editor/svg_view_mode_store_test.dart`

**Interfaces:**
- Produces: `enum SvgViewMode { preview, edit }` and `class SvgViewModeStore extends ChangeNotifier` with `SvgViewMode modeFor(String path)` (default `preview`) and `void setMode(String path, SvgViewMode mode)`. Used by Tasks 5–6.

- [ ] **Step 1: Write the failing test**

Create `client/test/services/editor/svg_view_mode_store_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/editor/svg_view_mode_store.dart';

void main() {
  test('defaults to preview and is per-path in-session', () {
    final store = SvgViewModeStore();
    addTearDown(store.dispose);

    expect(store.modeFor('/a/x.svg'), SvgViewMode.preview);

    var notifications = 0;
    store.addListener(() => notifications++);

    store.setMode('/a/x.svg', SvgViewMode.edit);
    expect(store.modeFor('/a/x.svg'), SvgViewMode.edit);
    expect(notifications, 1);

    // Same mode again: no redundant notification.
    store.setMode('/a/x.svg', SvgViewMode.edit);
    expect(notifications, 1);

    // Other paths keep the default.
    expect(store.modeFor('/a/y.svg'), SvgViewMode.preview);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/editor/svg_view_mode_store_test.dart`
Expected: FAIL — file/class not found.

- [ ] **Step 3: Write minimal implementation**

Create `client/lib/services/editor/svg_view_mode_store.dart`, mirroring `html_view_mode_store.dart`:

```dart
import 'package:flutter/foundation.dart';

/// In-session Preview|Edit mode for SVG editor paths.
///
/// SVG opens **rendered** by default (unlike [HtmlViewModeStore], which
/// defaults to edit). Survives File↔Diff and tab switches (FileEditorSurface
/// dispose). Not persisted to disk.
class SvgViewModeStore extends ChangeNotifier {
  SvgViewModeStore();

  final Map<String, SvgViewMode> _modes = {};

  SvgViewMode modeFor(String path) => _modes[path] ?? SvgViewMode.preview;

  void setMode(String path, SvgViewMode mode) {
    if (_modes[path] == mode) return;
    _modes[path] = mode;
    notifyListeners();
  }
}

enum SvgViewMode { preview, edit }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/editor/svg_view_mode_store_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/editor/svg_view_mode_store.dart client/test/services/editor/svg_view_mode_store_test.dart
git commit -m "feat(editor): add SvgViewModeStore defaulting to preview

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3: Generalize the Edit|Preview toggle widget

`HtmlViewModeToggle` (`client/lib/widgets/workbench/html_view_mode_toggle.dart`) is hard-wired to `HtmlViewMode`. Rename to `EditorViewModeToggle` with a caller-owned selection API so the SVG toolbar reuses it.

**Files:**
- Create: `client/lib/widgets/workbench/editor_view_mode_toggle.dart`
- Delete: `client/lib/widgets/workbench/html_view_mode_toggle.dart`
- Modify: `client/lib/pages/workbench/file_editor_surface.dart:375` (html call site + import)
- Test: `client/test/widgets/workbench/editor_view_mode_toggle_test.dart`

**Interfaces:**
- Produces: `class EditorViewModeToggle extends StatelessWidget` with `const EditorViewModeToggle({required bool editSelected, required bool previewSelected, required VoidCallback onEditTap, required VoidCallback onPreviewTap, super.key})`. Used by Task 6 for both HTML and SVG.

- [ ] **Step 1: Write the failing test**

Create `client/test/widgets/workbench/editor_view_mode_toggle_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/widgets/workbench/editor_view_mode_toggle.dart';

Widget host({required bool editSelected}) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Center(
      child: EditorViewModeToggle(
        editSelected: editSelected,
        previewSelected: !editSelected,
        onEditTap: () {},
        onPreviewTap: () {},
      ),
    ),
  ),
);

void main() {
  testWidgets('shows both segments with tooltips', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.pumpWidget(host(editSelected: false));
    expect(find.byTooltip(l10n.htmlViewToggleEdit), findsOneWidget);
    expect(find.byTooltip(l10n.htmlViewTogglePreview), findsOneWidget);
  });

  testWidgets('taps fire the matching callback', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    var editTaps = 0;
    var previewTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: EditorViewModeToggle(
              editSelected: true,
              previewSelected: false,
              onEditTap: () => editTaps++,
              onPreviewTap: () => previewTaps++,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip(l10n.htmlViewToggleEdit));
    await tester.tap(find.byTooltip(l10n.htmlViewTogglePreview));
    expect(editTaps, 1);
    expect(previewTaps, 1);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/widgets/workbench/editor_view_mode_toggle_test.dart`
Expected: FAIL — file/class not found.

- [ ] **Step 3: Write the implementation**

Create `client/lib/widgets/workbench/editor_view_mode_toggle.dart` by copying `html_view_mode_toggle.dart` and changing only the public API — the `Container`/`Row`/`_Segment` visual structure (lines 25–end, including the private `_Segment` class) moves over **verbatim**:

```dart
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';

/// Dual-segment Edit|Preview toggle shared by the HTML and SVG editor
/// toolbars. Selection state is caller-owned.
class EditorViewModeToggle extends StatelessWidget {
  const EditorViewModeToggle({
    required this.editSelected,
    required this.previewSelected,
    required this.onEditTap,
    required this.onPreviewTap,
    super.key,
  });

  final bool editSelected;
  final bool previewSelected;
  final VoidCallback onEditTap;
  final VoidCallback onPreviewTap;

  static const double _size = TpIconButton.kCompactSize;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final color = cs.tpIconMuted;
    return Container(
      height: _size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Segment(
            icon: Icons.code,
            tooltip: l10n.htmlViewToggleEdit,
            selected: editSelected,
            color: color,
            onTap: onEditTap,
          ),
          Container(width: 1, height: 14, color: cs.outlineVariant),
          _Segment(
            icon: Icons.visibility_outlined,
            tooltip: l10n.htmlViewTogglePreview,
            selected: previewSelected,
            color: color,
            onTap: onPreviewTap,
          ),
        ],
      ),
    );
  }
}

// ... copy the private `_Segment` class from
// html_view_mode_toggle.dart verbatim (icon, tooltip, selected, color, onTap)
```

Then: delete `client/lib/widgets/workbench/html_view_mode_toggle.dart`; in `client/lib/pages/workbench/file_editor_surface.dart` replace the `html_view_mode_toggle.dart` import with `editor_view_mode_toggle.dart` and change the HTML call site (~line 375) to:

```dart
return EditorViewModeToggle(
  editSelected: mode == HtmlViewMode.edit,
  previewSelected: mode == HtmlViewMode.preview,
  onEditTap: () => opener.htmlViewModes.setMode(path, HtmlViewMode.edit),
  onPreviewTap: () =>
      opener.htmlViewModes.setMode(path, HtmlViewMode.preview),
);
```

Also `git grep -n "HtmlViewModeToggle"` to confirm no other references remain (only `file_editor_surface.dart` uses it today).

- [ ] **Step 4: Analyze + run tests**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart test/widgets/workbench/editor_view_mode_toggle_test.dart`
Expected: analyze clean, test PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/widgets/workbench/editor_view_mode_toggle.dart client/lib/widgets/workbench/html_view_mode_toggle.dart client/lib/pages/workbench/file_editor_surface.dart client/test/widgets/workbench/editor_view_mode_toggle_test.dart
git commit -m "refactor(workbench): generalize HtmlViewModeToggle into EditorViewModeToggle

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 4: Extract `PhotoZoomControllerMixin` from `FileEditorImagePreview`

Pure behavior-preserving refactor: pull the PhotoView zoom plumbing (controllers, scale percent, clamp-to-1:1, wheel zoom, reset) out of `FileEditorImagePreview` into a mixin so `SvgPreviewPane` (Task 5) reuses it. A smoke test guards the refactor.

**Files:**
- Create: `client/lib/pages/workbench/photo_zoom_controller.dart`
- Modify: `client/lib/pages/workbench/file_editor_image_preview.dart`
- Test: `client/test/pages/workbench/file_editor_image_preview_test.dart`

**Interfaces:**
- Produces: `mixin PhotoZoomControllerMixin<T extends StatefulWidget> on State<T>` exposing:
  - `controller` (`PhotoViewController`), `scaleStateController` (`PhotoViewScaleStateController`) — both created/disposed by the mixin (`initState`/`dispose`)
  - `int get scalePercent`, `void zoomBy(double factor)`, `void resetZoom()`, `void onZoomPointerSignal(PointerSignalEvent)`, `PhotoViewScaleState clampCycle(void _)`
  - static consts: `zoomStep = 1.25`, `nativeScale = 1.0`, `minScale = 0.25`, `maxScale = 8.0`
  - Consumed by Tasks 5–6's `SvgPreviewPane`.

- [ ] **Step 1: Write the smoke test**

Create `client/test/pages/workbench/file_editor_image_preview_test.dart` (uses `LocalFilesystem` + a real temp file because `InMemoryFilesystem` cannot store binary PNG bytes):

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_view/photo_view.dart';
import 'package:teampilot/cubits/editor_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/workbench/file_editor_image_preview.dart';
import 'package:teampilot/services/io/local_filesystem.dart';

// 1x1 transparent PNG (same fixture as markdown_preview_svg_image_test.dart).
final pngBytes = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

void main() {
  testWidgets('renders bitmap bytes through PhotoView with zoom toolbar',
      (tester) async {
    final dir = await Directory.systemTemp.createTemp('tp_image_preview');
    addTearDown(() => dir.delete(recursive: true));
    final png = File('${dir.path}/a.png')..writeAsBytesSync(pngBytes);

    final editor = EditorCubit(fs: LocalFilesystem());
    addTearDown(editor.close);
    await editor.openFile('ws', png.path);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: BlocProvider<EditorCubit>.value(
            value: editor,
            child: FileEditorImagePreview(workspaceId: 'ws', path: png.path),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PhotoView), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it passes (pre-refactor baseline)**

Run: `cd client && dart run tool/run_tests.dart test/pages/workbench/file_editor_image_preview_test.dart`
Expected: PASS. If it fails, fix the harness first — this is the baseline that must stay green across the refactor.

- [ ] **Step 3: Create the mixin**

Create `client/lib/pages/workbench/photo_zoom_controller.dart` — every member moves verbatim from `_FileEditorImagePreviewState` (`file_editor_image_preview.dart:28-115`), only renamed public:

```dart
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';

/// Shared PhotoView zoom plumbing for the workbench file-preview panes
/// (bitmap [FileEditorImagePreview], SVG SvgPreviewPane).
///
/// Contract: fit-to-pane initial scale; initial/reset upscale clamped to
/// 1:1 (one image unit per logical pixel); 0.25–8.0 zoom range; wheel zoom;
/// `scalePercent` relative to the contained baseline.
mixin PhotoZoomControllerMixin<T extends StatefulWidget> on State<T> {
  static const zoomStep = 1.25;
  /// Absolute PhotoView scale: 1.0 = one image pixel per logical pixel.
  static const nativeScale = 1.0;
  static const minScale = 0.25;
  static const maxScale = 8.0;

  late final PhotoViewController controller = PhotoViewController();
  late final PhotoViewScaleStateController scaleStateController =
      PhotoViewScaleStateController();

  StreamSubscription<PhotoViewControllerValue>? _scaleSub;
  double? _scale;
  double? _baselineScale;
  bool _cappedInitialUpscale = false;

  @override
  void initState() {
    super.initState();
    _scaleSub = controller.outputStateStream.listen(_onControllerValue);
  }

  void _onControllerValue(PhotoViewControllerValue value) {
    final next = value.scale;
    if (next == null) return;
    // Fit to the pane but never upscale past 1:1 on open.
    if (!_cappedInitialUpscale && next > nativeScale) {
      _cappedInitialUpscale = true;
      controller.scale = nativeScale;
      return;
    }
    _cappedInitialUpscale = true;
    if (next == _scale) return;
    _baselineScale ??= next <= nativeScale ? next : nativeScale;
    if (!mounted) return;
    setState(() => _scale = next);
  }

  int get scalePercent {
    final current = _scale;
    final base = _baselineScale;
    if (current == null || base == null || base == 0) return 100;
    return ((current / base) * 100).round();
  }

  void zoomBy(double factor) {
    final current = controller.scale;
    if (current == null) return;
    controller.scale = (current * factor).clamp(minScale, maxScale);
  }

  /// Fit in the pane, but never larger than native 1:1.
  void resetZoom() {
    scaleStateController.scaleState = PhotoViewScaleState.initial;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final scale = controller.scale;
      if (scale != null && scale > nativeScale) {
        controller.scale = nativeScale;
      }
    });
  }

  void onZoomPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || event.scrollDelta.dy == 0) return;
    zoomBy(event.scrollDelta.dy < 0 ? zoomStep : 1 / zoomStep);
  }

  /// `scaleStateCycle` for panes that clamp upscale to 1:1.
  PhotoViewScaleState clampCycle(void _) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final scale = controller.scale;
      if (scale != null && scale > nativeScale) {
        controller.scale = nativeScale;
      }
    });
    return PhotoViewScaleState.initial;
  }

  @override
  void dispose() {
    _scaleSub?.cancel();
    controller.dispose();
    scaleStateController.dispose();
    super.dispose();
  }
}
```

- [ ] **Step 4: Refactor `FileEditorImagePreview` onto the mixin**

In `client/lib/pages/workbench/file_editor_image_preview.dart`:
- `class _FileEditorImagePreviewState extends State<FileEditorImagePreview> with PhotoZoomControllerMixin<FileEditorImagePreview>`
- Delete the now-duplicated members (`_zoomStep`, `_nativeScale`, `_minScale`, `_maxScale`, `_controller`, `_scaleStateController`, `_scaleSub`, `_scale`, `_baselineScale`, `_cappedInitialUpscale`, `initState`, `dispose`, `_onControllerValue`, `_scalePercent`, `_zoomBy`, `_resetZoom`, `_onPointerSignal`, and the inline `scaleStateCycle` closure).
- Replace call sites: `_controller` → `controller`, `_scaleStateController` → `scaleStateController`, `_scalePercent` → `scalePercent`, `_zoomBy(...)` → `zoomBy(...)`, `_resetZoom` → `resetZoom`, `_onPointerSignal` → `onZoomPointerSignal`, `_zoomStep` → `PhotoZoomControllerMixin.zoomStep`, `_minScale`/`_maxScale` → the mixin consts, and the `scaleStateCycle: (_) {...}` argument → `scaleStateCycle: clampCycle`.
- Keep `_decodeFailureReported`, `reportImageDecodeFailed`, the toolbar and `_buildBody` unchanged.

- [ ] **Step 5: Analyze + rerun smoke test**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart test/pages/workbench/file_editor_image_preview_test.dart`
Expected: analyze clean, test PASS.

- [ ] **Step 6: Commit**

```bash
git add client/lib/pages/workbench/photo_zoom_controller.dart client/lib/pages/workbench/file_editor_image_preview.dart client/test/pages/workbench/file_editor_image_preview_test.dart
git commit -m "refactor(workbench): extract PhotoZoomControllerMixin from image preview

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 5: `SvgPreviewPane` widget

**Files:**
- Create: `client/lib/pages/workbench/svg_preview_pane.dart`
- Test: `client/test/pages/workbench/svg_preview_pane_test.dart`

**Interfaces:**
- Consumes: `PhotoZoomControllerMixin` (Task 4), `EditorCubit.fsFor` / `EditorCubit.reportImageDecodeFailed`, `EditorMessage.couldNotRead`, `l10n.editorPanelErrorMessage`, `l10n.shortcutsZoom*`.
- Produces: `class SvgPreviewPane extends StatefulWidget` with `const SvgPreviewPane({required String workspaceId, required String path, Filesystem? fs, super.key})`. Used by Task 6.

Notes for the implementer:
- `flutter_svg` re-exports `vg`, `PictureInfo`, and `SvgBytesLoader` — import `package:flutter_svg/flutter_svg.dart` only; do **not** add `vector_graphics` to pubspec.
- After a successful `vg.loadPicture`, dispose the returned `info.picture` (the pane re-renders through `SvgPicture.memory`, which loads independently).
- Parse failure semantics: if `vg.loadPicture` throws, keep the bytes and set natural size to `null` — `SvgPicture.memory`'s `errorBuilder` then produces the failure surface (same shrink + snackbar pattern as the bitmap pane). "No natural size but renders" also falls out as fit-without-childSize.
- The pane owns a zoom toolbar row (no filename — the file-tab toolbar above already shows it).

- [ ] **Step 1: Write the failing tests**

Create `client/test/pages/workbench/svg_preview_pane_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_view/photo_view.dart';
import 'package:teampilot/cubits/editor_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/editor_message.dart'; // adjust to real path of EditorMessage
import 'package:teampilot/pages/workbench/svg_preview_pane.dart';
import 'package:teampilot/services/io/filesystem.dart';

import '../../support/in_memory_filesystem.dart';

const svgV1 =
    '<svg xmlns="http://www.w3.org/2000/svg" width="108" height="20">'
    '<rect width="108" height="20" fill="#555"/></svg>';
const svgV2 =
    '<svg xmlns="http://www.w3.org/2000/svg" width="50" height="50">'
    '<rect width="50" height="50" fill="#007ec6"/></svg>';

class _CountingFilesystem implements Filesystem {
  _CountingFilesystem(this._inner);
  final Filesystem _inner;
  int readBytesCalls = 0;

  @override
  get pathContext => _inner.pathContext;

  @override
  Future<List<int>?> readBytes(String path) {
    readBytesCalls++;
    return _inner.readBytes(path);
  }

  @override
  noSuchMethod(Invocation invocation) => _inner.noSuchMethod(invocation);
}
```

(If `Filesystem` has members `noSuchMethod` forwarding can't cover for the analyzer, implement the remaining members by delegating to `_inner` — copy the delegation style from `test/services/agent_runtime/runtime_event_journal_test.dart:343`.)

```dart
Future<void> pumpPane(
  WidgetTester tester, {
  required EditorCubit editor,
  required String path,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: BlocProvider<EditorCubit>.value(
          value: editor,
          child: SvgPreviewPane(workspaceId: 'ws', path: path),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders svg bytes through PhotoView with zoom toolbar',
      (tester) async {
    final fs = InMemoryFilesystem()..files['/repo/icon.svg'] = svgV1;
    final editor = EditorCubit(fs: fs);
    addTearDown(editor.close);
    await editor.openFile('ws', '/repo/icon.svg');

    await pumpPane(tester, editor: editor, path: '/repo/icon.svg');

    expect(find.byType(PhotoView), findsOneWidget);
    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
  });

  testWidgets('invalid svg reports decode failure', (tester) async {
    final fs = InMemoryFilesystem()..files['/repo/bad.svg'] = 'not an svg';
    final editor = EditorCubit(fs: fs);
    addTearDown(editor.close);
    await editor.openFile('ws', '/repo/bad.svg');

    await pumpPane(tester, editor: editor, path: '/repo/bad.svg');

    expect(
      editor.state.bucket('ws').errorByPath['/repo/bad.svg'],
      EditorMessage.imageDecodeFailed,
    );
  });

  testWidgets('re-reads bytes after a save (dirty -> clean)', (tester) async {
    final inner = InMemoryFilesystem()..files['/repo/icon.svg'] = svgV1;
    final fs = _CountingFilesystem(inner);
    final editor = EditorCubit(fs: fs);
    addTearDown(editor.close);
    await editor.openFile('ws', '/repo/icon.svg');

    await pumpPane(tester, editor: editor, path: '/repo/icon.svg');
    expect(fs.readBytesCalls, 1);

    // Simulate an external edit + save: pane must re-read on dirty->clean.
    inner.files['/repo/icon.svg'] = svgV2;
    final controller = editor.controllerFor('ws', '/repo/icon.svg');
    expect(controller, isNotNull);
    controller!.text = svgV2;
    expect(editor.state.bucket('ws').isDirty('/repo/icon.svg'), isTrue);

    await editor.saveFile('ws', '/repo/icon.svg');
    await tester.pumpAndSettle();

    expect(fs.readBytesCalls, 2);
  });

  testWidgets('missing file shows read error', (tester) async {
    final fs = InMemoryFilesystem();
    final editor = EditorCubit(fs: fs);
    addTearDown(editor.close);
    // No openFile: the pane reads directly from fs.

    await pumpPane(tester, editor: editor, path: '/repo/missing.svg');

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(
      find.text(l10n.editorPanelErrorMessage(EditorMessage.couldNotRead)),
      findsOneWidget,
    );
    expect(find.byType(PhotoView), findsNothing);
  });
}
```

Before running, verify the real import path and enum name of `EditorMessage` with `git grep -n "enum EditorMessage\|class EditorMessage"` and check `errorByPath`'s value type in `EditorState` — adjust the test to the actual types (it may be a code `String`, in which case compare against the constant's value). Also check `InMemoryFilesystem.files` is public (it is — `test/services/workbench/workbench_editor_opener_test.dart` writes `..files['/repo/a.txt'] = 'hello'`).

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/pages/workbench/svg_preview_pane_test.dart`
Expected: FAIL — `svg_preview_pane.dart` not found.

- [ ] **Step 3: Implement the pane**

Create `client/lib/pages/workbench/svg_preview_pane.dart`:

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:photo_view/photo_view.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/editor_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/io/filesystem.dart';
import 'photo_zoom_controller.dart';

/// Workbench SVG preview: renders on-disk bytes with zoom (PhotoView) and a
/// zoom toolbar. Unsaved editor edits are not reflected — the pane re-reads
/// when the file transitions dirty -> saved. The SVG natural size (declared
/// width/height, else viewBox) defines 1:1; parse failure degrades to
/// fit-without-natural-size and surfaces via the decode-failure channel.
class SvgPreviewPane extends StatefulWidget {
  const SvgPreviewPane({
    required this.workspaceId,
    required this.path,
    this.fs,
    super.key,
  });

  final String workspaceId;
  final String path;
  final Filesystem? fs;

  @override
  State<SvgPreviewPane> createState() => _SvgPreviewPaneState();
}

class _SvgPreviewPaneState extends State<SvgPreviewPane>
    with PhotoZoomControllerMixin<SvgPreviewPane> {
  Filesystem? _fs;
  bool _loadStarted = false;
  bool _loading = true;
  Uint8List? _bytes;
  Size? _naturalSize;
  bool _readFailed = false;
  bool _decodeFailureReported = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _fs ??= widget.fs ??
        context.read<EditorCubit>().fsFor(widget.workspaceId, widget.path);
    if (!_loadStarted) {
      _loadStarted = true;
      unawaited(_load());
    }
  }

  @override
  void didUpdateWidget(SvgPreviewPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path ||
        oldWidget.workspaceId != widget.workspaceId) {
      // Retarget: re-resolve fs and reload.
      _fs = widget.fs;
      _loadStarted = true;
      _decodeFailureReported = false;
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _readFailed = false;
    });
    final fs = _fs;
    if (fs == null) return;
    List<int>? raw;
    try {
      raw = await fs.readBytes(widget.path);
    } on Object {
      raw = null;
    }
    if (!mounted) return;
    if (raw == null) {
      setState(() {
        _loading = false;
        _readFailed = true;
        _bytes = null;
        _naturalSize = null;
      });
      return;
    }
    final bytes = Uint8List.fromList(raw);
    // Natural size only; SvgPicture.memory re-parses for rendering, so
    // dispose the probe picture immediately.
    Size? natural;
    try {
      final info = await vg.loadPicture(SvgBytesLoader(bytes), null);
      try {
        natural = info.size;
      } finally {
        info.picture.dispose();
      }
    } on Object {
      natural = null;
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _bytes = bytes;
      _naturalSize =
          (natural != null && natural.width > 0 && natural.height > 0)
          ? natural
          : null;
    });
  }

  void _reportDecodeFailed() {
    if (_decodeFailureReported) return;
    _decodeFailureReported = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<EditorCubit>().reportImageDecodeFailed(
        widget.workspaceId,
        widget.path,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final hasBytes = _bytes != null && !_readFailed;
    final canZoom = hasBytes && !_loading;

    return BlocListener<EditorCubit, EditorState>(
      // Unsaved edits must not affect the preview; re-read once saved.
      listenWhen: (previous, next) =>
          previous.bucket(widget.workspaceId).isDirty(widget.path) &&
          !next.bucket(widget.workspaceId).isDirty(widget.path),
      listener: (context, state) {
        _decodeFailureReported = false;
        unawaited(_load());
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 36,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: l10n.shortcutsZoomOut,
                    icon: const Icon(Icons.remove, size: 18),
                    onPressed: canZoom
                        ? () => zoomBy(1 / PhotoZoomControllerMixin.zoomStep)
                        : null,
                  ),
                  Text('$scalePercent%', style: TpTextStyles.of(context).sm),
                  IconButton(
                    tooltip: l10n.shortcutsZoomIn,
                    icon: const Icon(Icons.add, size: 18),
                    onPressed: canZoom
                        ? () => zoomBy(PhotoZoomControllerMixin.zoomStep)
                        : null,
                  ),
                  IconButton(
                    tooltip: l10n.shortcutsZoomReset,
                    icon: const Icon(Icons.fit_screen_outlined, size: 18),
                    onPressed: canZoom ? resetZoom : null,
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildBody(context, l10n, cs)),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, AppLocalizations l10n, ColorScheme cs) {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_readFailed || _bytes == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            l10n.editorPanelErrorMessage(EditorMessage.couldNotRead),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ClipRect(
      child: Listener(
        onPointerSignal: onZoomPointerSignal,
        child: PhotoView.customChild(
          SvgPicture.memory(
            _bytes!,
            errorBuilder: (context, error, stackTrace) {
              _reportDecodeFailed();
              return const SizedBox.shrink();
            },
          ),
          childSize: _naturalSize,
          controller: controller,
          scaleStateController: scaleStateController,
          minScale: PhotoZoomControllerMixin.minScale,
          maxScale: PhotoZoomControllerMixin.maxScale,
          initialScale: PhotoViewComputedScale.contained,
          backgroundDecoration: BoxDecoration(color: cs.surface),
          scaleStateCycle: clampCycle,
        ),
      ),
    );
  }
}
```

Notes:
- `AppLocalizations` type in `_buildBody`'s signature: check how `context.l10n` resolves (`l10n_extensions.dart`) and use that type, or drop the parameter and call `context.l10n` inside.
- Import path for `EditorMessage`: locate with `git grep -n "imageDecodeFailed" client/lib/models client/lib/cubits` and use the real one.
- `PhotoView.customChild` accepts a nullable `childSize`; if the version in use requires non-null, pass `_naturalSize ?? MediaQuery.sizeOf(context)` and keep a comment.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/pages/workbench/svg_preview_pane_test.dart`
Expected: PASS (all four). The invalid-svg test may need `await tester.pump()` extra frames for the post-frame `reportImageDecodeFailed` — add `await tester.pumpAndSettle()` after the first settle if the assertion runs early.

- [ ] **Step 5: Analyze + commit**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: clean.

```bash
git add client/lib/pages/workbench/svg_preview_pane.dart client/test/pages/workbench/svg_preview_pane_test.dart
git commit -m "feat(workbench): add SvgPreviewPane rendering on-disk svg bytes

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 6: Wire into `WorkbenchEditorOpener` and `FileEditorSurface`

**Files:**
- Modify: `client/lib/services/workbench/workbench_editor_opener.dart:25-46`
- Modify: `client/lib/pages/workbench/file_editor_surface.dart` (toolbar ~line 298-382, body ~line 455)
- Test: `client/test/pages/workbench/file_editor_surface_svg_test.dart`

**Interfaces:**
- Consumes: `isSvgPreviewPath` (Task 1), `SvgViewModeStore`/`SvgViewMode` (Task 2), `EditorViewModeToggle` (Task 3), `SvgPreviewPane` (Task 5).
- Produces: `WorkbenchEditorOpener.svgViewModes` (`SvgViewModeStore`, constructor-injectable like `htmlViewModes`).

- [ ] **Step 1: Write the failing test**

Create `client/test/pages/workbench/file_editor_surface_svg_test.dart` (harness follows `workbench_editor_opener_test.dart` for opener construction):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/editor_cubit.dart';
import 'package:teampilot/cubits/floating_workspace/floating_workspace_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/workbench/file_editor_surface.dart';
import 'package:teampilot/pages/workbench/svg_preview_pane.dart';
import 'package:teampilot/services/editor/markdown_view_mode_store.dart';
import 'package:teampilot/services/workbench/workbench_editor_opener.dart';

import '../../support/in_memory_filesystem.dart';

const svgSource =
    '<svg xmlns="http://www.w3.org/2000/svg" width="108" height="20">'
    '<rect width="108" height="20" fill="#555"/></svg>';

void main() {
  late EditorCubit editor;
  late WorkbenchCubit workbench;
  late FloatingWorkspaceCubit floating;
  late WorkbenchEditorOpener opener;

  setUp(() async {
    final fs = InMemoryFilesystem()..files['/repo/icon.svg'] = svgSource;
    editor = EditorCubit(fs: fs);
    workbench = WorkbenchCubit();
    floating = FloatingWorkspaceCubit();
    opener = WorkbenchEditorOpener(
      editor: editor,
      workbench: workbench,
      floating: floating,
      markdownViewModes: MarkdownViewModeStore(),
      readMarkdownOpenMode: () => MarkdownOpenMode.preview,
    );
    await editor.openFile('ws', '/repo/icon.svg');
    addTearDown(editor.close);
    addTearDown(workbench.close);
    addTearDown(floating.close);
  });

  Future<void> pumpSurface(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<WorkbenchEditorOpener>.value(value: opener),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider<EditorCubit>.value(value: editor),
            BlocProvider<WorkbenchCubit>.value(value: workbench),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: FileEditorSurface(
                workspaceId: 'ws',
                path: '/repo/icon.svg',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('svg opens in preview mode by default', (tester) async {
    await pumpSurface(tester);
    expect(find.byType(SvgPreviewPane), findsOneWidget);
  });

  testWidgets('edit toggle switches to the source editor', (tester) async {
    await pumpSurface(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.tap(find.byTooltip(l10n.htmlViewToggleEdit));
    await tester.pumpAndSettle();
    expect(find.byType(SvgPreviewPane), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/pages/workbench/file_editor_surface_svg_test.dart`
Expected: FAIL — no `SvgPreviewPane` in the tree (svg currently renders the plain code editor, no toggle).

- [ ] **Step 3: Add the store to `WorkbenchEditorOpener`**

In `client/lib/services/workbench/workbench_editor_opener.dart`, mirror the `htmlViewModes` pattern (lines 25, 39, 46):
- Constructor param: `SvgViewModeStore? svgViewModes,`
- Initializer: `svgViewModes = svgViewModes ?? SvgViewModeStore(),`
- Field: `final SvgViewModeStore svgViewModes;`
- Import `package:teampilot/services/editor/svg_view_mode_store.dart`.

- [ ] **Step 4: Wire the toolbar and body in `FileEditorSurface`**

In `client/lib/pages/workbench/file_editor_surface.dart`:

Toolbar (in `_FileEditorToolbar.build`, next to `final isHtml = ...` ~line 298):
```dart
final isSvg = isSvgPreviewPath(path);
```
and after the `if (isHtml) ...[]` block (~line 382):
```dart
if (isSvg) ...[
  const SizedBox(width: 4),
  ListenableBuilder(
    listenable: opener.svgViewModes,
    builder: (context, _) {
      final mode = opener.svgViewModes.modeFor(path);
      return EditorViewModeToggle(
        editSelected: mode == SvgViewMode.edit,
        previewSelected: mode == SvgViewMode.preview,
        onEditTap: () => opener.svgViewModes.setMode(path, SvgViewMode.edit),
        onPreviewTap: () =>
            opener.svgViewModes.setMode(path, SvgViewMode.preview),
      );
    },
  ),
],
```

Body (in `_FileEditorBody`, after the `isHtmlPreviewPath` branch ending ~line 472, before the markdown branch):
```dart
if (isSvgPreviewPath(path)) {
  final opener = context.read<WorkbenchEditorOpener>();
  return ListenableBuilder(
    listenable: opener.svgViewModes,
    builder: (context, _) {
      if (opener.svgViewModes.modeFor(path) == SvgViewMode.preview) {
        return SvgPreviewPane(workspaceId: workspaceId, path: path);
      }
      return _CodeEditorPane(
        workspaceId: workspaceId,
        path: path,
        controller: controller,
        readOnly: model.readOnly,
      );
    },
  );
}
```

Imports: `svg_preview_pane.dart`, `svg_view_mode_store.dart`.

- [ ] **Step 5: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/pages/workbench/file_editor_surface_svg_test.dart`
Expected: PASS. If the edit-toggle case fails because `_CodeEditorPane` needs extra providers at pump time, check its constructor/imports for required scopes (tree-sitter, fonts) and add the minimal providers to the harness — the assertion itself (`SvgPreviewPane` gone after tapping edit) stays the same.

- [ ] **Step 6: Analyze + run the workbench-adjacent tests**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart test/pages/workbench/ test/services/editor/ test/services/workbench/`
Expected: analyze clean, all pass (regression check on link handler, opener, theme tests).

- [ ] **Step 7: Commit**

```bash
git add client/lib/services/workbench/workbench_editor_opener.dart client/lib/pages/workbench/file_editor_surface.dart client/test/pages/workbench/file_editor_surface_svg_test.dart
git commit -m "feat(workbench): route svg files to rendered preview with edit toggle

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 7: Full verification

**Files:** none (verification only).

- [ ] **Step 1: Analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: clean exit.

- [ ] **Step 2: Full test suite**

Run (in background, it is long): `cd client && dart run tool/run_tests.dart`
Expected: all pass. Investigate and fix any failure before claiming done — a failure here means an earlier task broke something its narrow test missed.

- [ ] **Step 3: Manual smoke check (optional but recommended)**

Launch the app (`/run` or the user's usual flow), open a workspace containing an `.svg` file: it should open rendered with the zoom toolbar, the Edit segment should switch to source, editing + Ctrl+S should refresh the rendered view on switching back to Preview.

- [ ] **Step 4: No commit needed**

All tasks already committed individually. If Step 2 surfaced fixes, commit those with a `fix:` message.
