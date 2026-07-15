# Markdown WYSIWYG (AppFlowy Editor) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Source | WYSIWYG | Preview mode for Markdown workbench files using `appflowy_editor`, keeping plain `.md` on disk and `EditorCubit` / `CodeLineEditingController` as the text source of truth.

**Architecture:** Extend `MarkdownViewMode` with `wysiwyg`. A thin `MarkdownBridge` (+ optional front-matter prefix) converts text ↔ `Document`. `MarkdownWysiwygSession` owns `EditorState`, registers with `EditorCubit` for flush-before-save / rebuild-on-revert-reload, marks dirty immediately on Document change, and debounces encode into the controller. `FileEditorSurface` hosts `AppFlowyEditor` in the new mode; non-Markdown paths stay on `re_editor` only.

**Tech Stack:** Flutter, `flutter_bloc`, vendored `re_editor`, `flutter_markdown_plus`, pub `appflowy_editor` (pin concrete version), ARB l10n.

**Spec:** `docs/superpowers/specs/2026-07-15-markdown-wysiwyg-appflowy-editor-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `client/pubspec.yaml` | Add pinned `appflowy_editor` |
| `client/lib/main.dart` | Register `AppFlowyEditorLocalizations.delegate` on workbench `MaterialApp.router` (`_TeamPilotMaterialApp`) |
| `client/lib/app/app_shell.dart` | Optional: same delegate on bootstrap/error `MaterialApp`s for parity |
| `client/lib/l10n/app_en.arb`, `app_zh.arb` (+ gen) | Toggle + open-mode + optional help strings |
| `client/lib/services/editor/markdown_view_mode_store.dart` | `MarkdownViewMode.wysiwyg`; seed rules |
| `client/lib/widgets/workbench/markdown_view_mode_toggle.dart` | Three-segment toggle |
| `client/lib/models/layout_preferences.dart` | Optional `MarkdownOpenMode.wysiwyg` |
| `client/lib/pages/config/layout_appearance_in_layout_section.dart` | Optional dropdown entry |
| `client/lib/services/editor/markdown_bridge.dart` | **New** — front matter + `markdownToDocument` / `documentToMarkdown` |
| `client/lib/services/editor/document_codec.dart` | **New** — thin `DocumentCodec` + `MarkdownFileCodec` |
| `client/lib/services/editor/markdown_wysiwyg_session.dart` | **New** — `EditorState`, debounce, unflushed, flush |
| `client/lib/services/editor/markdown_wysiwyg_theme.dart` | **New** — TeamPilot `EditorStyle` mapping |
| `client/lib/cubits/editor_cubit.dart` | Session registry, public dirty, flush in `saveFile`, notify on revert/close |
| `client/lib/pages/workbench/file_editor_surface.dart` | WYSIWYG pane branch + mode-leave flush |
| `client/lib/pages/workbench/markdown_wysiwyg_pane.dart` | **New** — `AppFlowyEditor` host widget |
| `client/test/services/editor/markdown_bridge_test.dart` | Round-trip + front matter |
| `client/test/services/editor/markdown_view_mode_store_test.dart` | Third mode + seed |
| `client/test/services/editor/markdown_wysiwyg_session_test.dart` | Dirty immediate, flush, no re-encode without edits |
| `client/test/cubits/editor_cubit_wysiwyg_test.dart` | save/close/revert + session registry |

---

### Task 1: Add `appflowy_editor` dependency + localizations

**Files:**
- Modify: `client/pubspec.yaml`
- Modify: `client/lib/main.dart` (`_TeamPilotMaterialApp` → `MaterialApp.router` `localizationsDelegates`)
- Optional: `client/lib/app/app_shell.dart` (bootstrap/error `MaterialApp`s only)

- [ ] **Step 1: Pin dependency**

From `client/`:

```bash
flutter pub add appflowy_editor:6.2.0
```

If resolve fails, pick the latest 6.x that resolves against the repo SDK and pin that exact version in `pubspec.yaml` (no caret drift in the plan commit message — record the chosen version in the commit body).

- [ ] **Step 2: Register editor localizations on the real app**

In `client/lib/main.dart` where `localizationsDelegates: AppLocalizations.localizationsDelegates` is set on `MaterialApp.router`, expand to:

```dart
localizationsDelegates: [
  ...AppLocalizations.localizationsDelegates,
  AppFlowyEditorLocalizations.delegate,
],
```

Import: `package:appflowy_editor/appflowy_editor.dart`.

Do **not** treat `app_shell.dart` as the production app — those `MaterialApp`s are bootstrap/error shells only. Optionally mirror the delegate there for parity.

- [ ] **Step 3: Verify analyze still runs**

```bash
cd client && flutter pub get && dart analyze lib/main.dart
```

Expected: no errors related to the new import/delegate.

- [ ] **Step 4: Commit**

```bash
git add client/pubspec.yaml client/pubspec.lock client/lib/main.dart
# include app_shell.dart only if you mirrored the delegate
git commit -m "$(cat <<'EOF'
chore: add appflowy_editor dependency for markdown WYSIWYG

EOF
)"
```

---

### Task 2: l10n for three-mode toggle (+ optional open mode)

**Files:**
- Modify: `client/lib/l10n/app_en.arb`
- Modify: `client/lib/l10n/app_zh.arb`
- Generated: `app_localizations*.dart`, warmup glyphs if required

- [ ] **Step 1: Add ARB keys** (near existing `markdownViewToggle*` / `markdownOpenMode*`)

English:

```json
"markdownViewToggleWysiwyg": "Edit",
"markdownOpenModeWysiwyg": "Edit (WYSIWYG)",
"markdownWysiwygFidelityHint": "WYSIWYG may normalize Markdown formatting when you save. Use Source for exact control."
```

Chinese:

```json
"markdownViewToggleWysiwyg": "编辑",
"markdownOpenModeWysiwyg": "编辑（所见即所得）",
"markdownWysiwygFidelityHint": "所见即所得保存时可能会规范化 Markdown 排版。需要精确控制请用源码模式。"
```

- [ ] **Step 2: Regenerate**

```bash
cd client && flutter gen-l10n && dart run tool/gen_warmup_glyphs.dart
```

- [ ] **Step 3: Commit**

```bash
git add client/lib/l10n/ client/lib/widgets/warmup_glyphs.g.dart
git commit -m "$(cat <<'EOF'
chore(l10n): markdown WYSIWYG view mode strings

EOF
)"
```

---

### Task 3: Extend `MarkdownViewMode` + toggle UI

**Files:**
- Modify: `client/lib/services/editor/markdown_view_mode_store.dart`
- Modify: `client/lib/widgets/workbench/markdown_view_mode_toggle.dart`
- Modify: `client/test/services/editor/markdown_view_mode_store_test.dart`
- Modify: `client/lib/pages/workbench/file_editor_surface.dart` (mode branch placeholder OK until Task 7 — for this task only ensure toggle compiles with three values; body can map `wysiwyg` → preview temporarily **only if** needed to compile; prefer completing Task 7 next if compile breaks)

- [ ] **Step 1: Write failing store tests**

Extend `markdown_view_mode_store_test.dart`:

```dart
test('modeFor returns wysiwyg when set', () {
  final store = MarkdownViewModeStore();
  store.setMode('/a.md', MarkdownViewMode.wysiwyg);
  expect(store.modeFor('/a.md'), MarkdownViewMode.wysiwyg);
});

test('seedOnOpen wysiwyg preference', () {
  final store = MarkdownViewModeStore();
  store.seedOnOpen('/a.md', MarkdownOpenMode.wysiwyg);
  expect(store.modeFor('/a.md'), MarkdownViewMode.wysiwyg);
});
```

(If `MarkdownOpenMode.wysiwyg` is deferred to Task 8, skip the second test until then and only add the first.)

- [ ] **Step 2: Run tests — expect fail**

```bash
cd client && flutter test test/services/editor/markdown_view_mode_store_test.dart
```

Expected: fail — `MarkdownViewMode.wysiwyg` missing.

- [ ] **Step 3: Implement enum + toggle**

```dart
enum MarkdownViewMode { source, wysiwyg, preview }
```

Update `MarkdownViewModeToggle` to three segments (icons: `Icons.code`, `Icons.edit_note` / `Icons.auto_fix`, `Icons.visibility_outlined`) with tooltips from l10n. Keep File|Diff-style compact chrome.

- [ ] **Step 4: Run tests — expect pass**

```bash
cd client && flutter test test/services/editor/markdown_view_mode_store_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/editor/markdown_view_mode_store.dart \
  client/lib/widgets/workbench/markdown_view_mode_toggle.dart \
  client/test/services/editor/markdown_view_mode_store_test.dart
git commit -m "$(cat <<'EOF'
feat: add markdown WYSIWYG view mode toggle

EOF
)"
```

---

### Task 4: `DocumentCodec` + `MarkdownBridge` (TDD)

**Files:**
- Create: `client/lib/services/editor/document_codec.dart`
- Create: `client/lib/services/editor/markdown_bridge.dart`
- Create: `client/test/services/editor/markdown_bridge_test.dart`

- [ ] **Step 1: Write failing round-trip tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/editor/markdown_bridge.dart';

void main() {
  group('MarkdownBridge', () {
    test('round-trips common subset headings and lists', () {
      const src = '# Title\n\nHello **world**\n\n- a\n- b\n';
      final parsed = MarkdownBridge.splitAndParse(src);
      final out = MarkdownBridge.encode(parsed);
      expect(out, contains('# Title'));
      expect(out, contains('Hello'));
      expect(out, contains('world'));
    });

    test('preserves YAML front matter prefix', () {
      const src = '---\ntitle: x\n---\n\n# Body\n';
      final parsed = MarkdownBridge.splitAndParse(src);
      expect(parsed.frontMatter, '---\ntitle: x\n---\n');
      final out = MarkdownBridge.encode(parsed);
      expect(out.startsWith('---\ntitle: x\n---\n'), isTrue);
      expect(out, contains('# Body'));
    });

    test('undetectable front matter treats whole file as body', () {
      const src = 'not front matter\n---\nstill body\n';
      final parsed = MarkdownBridge.splitAndParse(src);
      expect(parsed.frontMatter, isEmpty);
    });
  });
}
```

Adjust expectations to whatever `appflowy_editor`’s encoder actually emits for bold/lists (assert semantic presence, not byte-identical source).

- [ ] **Step 2: Run — expect fail**

```bash
cd client && flutter test test/services/editor/markdown_bridge_test.dart
```

- [ ] **Step 3: Implement**

`document_codec.dart`:

```dart
import 'package:appflowy_editor/appflowy_editor.dart';

abstract class DocumentCodec {
  Document decodeBody(String body);
  String encodeBody(Document document);
}

class MarkdownFileCodec implements DocumentCodec {
  const MarkdownFileCodec();

  @override
  Document decodeBody(String body) => markdownToDocument(body);

  @override
  String encodeBody(Document document) => documentToMarkdown(document);
}
```

`markdown_bridge.dart`:

```dart
class MarkdownParseResult {
  const MarkdownParseResult({required this.frontMatter, required this.document});
  final String frontMatter; // includes trailing newline after closing --- when present; else ''
  final Document document;
}

class MarkdownBridge {
  MarkdownBridge({DocumentCodec codec = const MarkdownFileCodec()}) : _codec = codec;
  final DocumentCodec _codec;

  static final _frontMatter = RegExp(r'^---\r?\n.*?\r?\n---\r?\n', dotAll: true);

  static MarkdownParseResult splitAndParse(String text, {DocumentCodec codec = const MarkdownFileCodec()}) {
    final match = _frontMatter.firstMatch(text);
    if (match == null) {
      return MarkdownParseResult(frontMatter: '', document: codec.decodeBody(text));
    }
    final prefix = match.group(0)!;
    final body = text.substring(match.end);
    return MarkdownParseResult(frontMatter: prefix, document: codec.decodeBody(body));
  }

  static String encode(MarkdownParseResult parsed, {DocumentCodec codec = const MarkdownFileCodec()}) {
    return '${parsed.frontMatter}${codec.encodeBody(parsed.document)}';
  }

  // instance wrappers used by session if preferred
}
```

Fix API to compile against the pinned `appflowy_editor` (function names may be `documentToMarkdown` vs extension — follow package exports).

- [ ] **Step 4: Run — expect pass**

```bash
cd client && flutter test test/services/editor/markdown_bridge_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/editor/document_codec.dart \
  client/lib/services/editor/markdown_bridge.dart \
  client/test/services/editor/markdown_bridge_test.dart
git commit -m "$(cat <<'EOF'
feat: add MarkdownBridge for AppFlowy document codec

EOF
)"
```

---

### Task 5: `MarkdownWysiwygSession` (TDD)

**Files:**
- Create: `client/lib/services/editor/markdown_wysiwyg_session.dart`
- Create: `client/test/services/editor/markdown_wysiwyg_session_test.dart`

**Behavior (from spec):**
- `attach(text)` → parse → `EditorState(document: …)`; `hasUnflushedEdits == false`
- On `transactionStream` after apply: set unflushed, call `onDirty` immediately, schedule debounced `onEncode(String fullText)`
- `flush()`: cancel timer, encode if unflushed, clear flag, return encoded text (or null if nothing to flush)
- `rebuildFromText(text)`: dispose old state, re-attach, clear unflushed
- `dispose()`: flush if unflushed (via `onEncode`), cancel timer, dispose `EditorState`

- [ ] **Step 1: Write failing session tests**

Use a fake codec or real bridge with short debounce (`Duration.zero` / injectable `Duration debounce`).

```dart
test('document change marks dirty before debounce encode', () async {
  var dirty = 0;
  String? encoded;
  final session = MarkdownWysiwygSession(
    debounce: const Duration(hours: 1), // never fires
    onDirty: () => dirty++,
    onEncode: (t) => encoded = t,
  );
  session.attach('# Hi\n');
  // Simulate an edit the same way production will (apply a transaction or call test-only notifyEdited)
  session.debugNotifyDocumentEdited();
  expect(dirty, 1);
  expect(session.hasUnflushedEdits, isTrue);
  expect(encoded, isNull);
});

test('flush encodes once and clears unflushed', () async {
  ...
});

test('flush with no edits does not call onEncode', () {
  ...
});
```

Prefer a package-visible `debugNotifyDocumentEdited()` **or** apply a real AppFlowy `EditorState` transaction in the test — real transaction is better if lightweight.

Default production debounce: **`Duration(milliseconds: 150)`** (injectable for tests).

- [ ] **Step 2: Run — expect fail**

```bash
cd client && flutter test test/services/editor/markdown_wysiwyg_session_test.dart
```

- [ ] **Step 3: Implement session**

Keep file focused (~200–300 lines). Store `frontMatter` from initial parse; encode always reattaches it.

**Do not** import `package:appflowy_editor` into `editor_cubit.dart` (TeamPilot already defines `EditorState`). Keep AppFlowy types behind `MarkdownWysiwygSession` only; cubit depends on the session interface / callbacks.

- [ ] **Step 4: Run — expect pass**

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/editor/markdown_wysiwyg_session.dart \
  client/test/services/editor/markdown_wysiwyg_session_test.dart
git commit -m "$(cat <<'EOF'
feat: add MarkdownWysiwygSession with dirty-before-encode

EOF
)"
```

---

### Task 6: Wire session registry into `EditorCubit`

**Files:**
- Modify: `client/lib/cubits/editor_cubit.dart`
- Create: `client/test/cubits/editor_cubit_wysiwyg_test.dart`

**API to add:**

```dart
void registerMarkdownWysiwyg(String workspaceId, String path, MarkdownWysiwygSession session);
void unregisterMarkdownWysiwyg(String workspaceId, String path);
void markFileDirty(String workspaceId, String path); // public wrapper around _markDirty

// Inside saveFile, before atomicWrite:
_wysiwygSessions[key]?.flush(); // flush calls onEncode which sets controller.text

// Inside revertFile, after setting controller.text:
_wysiwygSessions[key]?.rebuildFromText(saved);

// Inside closeFile, before _disposeHandle when closing:
_wysiwygSessions.remove(key)?.dispose(); // dispose flushes via onEncode if needed
```

**Encode callback** when registering from UI/session owner:

```dart
onEncode: (text) {
  final handle = ...;
  handle.controller.text = text; // existing listener updates dirty / tree-sitter
},
onDirty: () => editor.markFileDirty(workspaceId, path),
```

Registration may live on the pane (Task 7) calling into cubit; cubit tests can register a fake session.

- [ ] **Step 1: Failing cubit tests**

```dart
test('saveFile flushes wysiwyg session before write', () async {
  // open file with LocalFilesystem temp
  // register session that sets controller text on flush
  // mark dirty / leave unflushed
  // saveFile → filesystem has flushed content
});

test('closeFile returns false when dirty from wysiwyg before debounce', () {
  // markFileDirty without controller change
  expect(cubit.closeFile(ws, path), isFalse);
});

test('revertFile rebuilds wysiwyg session', () {
  // register session with rebuildFromText spy
});
```

- [ ] **Step 2: Run — expect fail**

```bash
cd client && flutter test test/cubits/editor_cubit_wysiwyg_test.dart
```

- [ ] **Step 3: Implement cubit hooks**

Do not re-encode in `saveFile` if session reports no unflushed edits (`flush` no-ops).

Ensure `closeFile` checks `dirtyPaths` **before** disposing session (existing order already does — keep it; early `markFileDirty` is what makes close-before-debounce work).

- [ ] **Step 4: Run — expect pass** (+ existing `editor_cubit_test.dart`)

```bash
cd client && flutter test test/cubits/editor_cubit_test.dart test/cubits/editor_cubit_wysiwyg_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/editor_cubit.dart client/test/cubits/editor_cubit_wysiwyg_test.dart
git commit -m "$(cat <<'EOF'
feat: EditorCubit WYSIWYG session flush and dirty hooks

EOF
)"
```

---

### Task 7: WYSIWYG pane + `FileEditorSurface` integration

**Files:**
- Create: `client/lib/pages/workbench/markdown_wysiwyg_pane.dart`
- Create: `client/lib/services/editor/markdown_wysiwyg_theme.dart`
- Modify: `client/lib/pages/workbench/file_editor_surface.dart`
- Optional widget test if cheap; otherwise rely on cubit/session tests + manual smoke

- [ ] **Step 1: Theme adapter**

Map `Theme.of(context).colorScheme` + `AppTextStyles` into `EditorStyle.desktop()` / package equivalent. No AppFlowy default skin dump.

- [ ] **Step 2: Pane widget**

Stateful widget that:
1. Creates `MarkdownWysiwygSession` from `controller.text`
2. `registerMarkdownWysiwyg` on cubit
3. Builds `AppFlowyEditor(editorState: session.editorState, editorStyle: …)`
4. On mode leave / dispose: `flush` then `unregister`
5. Wire link taps to `handleMarkdownPreviewLink` when the package exposes a hook; otherwise skip links in v1 and note in commit message

- [ ] **Step 3: Surface branch + fidelity hint**

In `_FileEditorBody`, for markdown paths:

```dart
switch (mode) {
  case MarkdownViewMode.source: return _CodeEditorPane(...);
  case MarkdownViewMode.wysiwyg: return MarkdownWysiwygPane(...);
  case MarkdownViewMode.preview: return _MarkdownPreviewPane(...);
}
```

When `setMode` is invoked from the toggle, if leaving `wysiwyg`, call session flush via cubit lookup **before** rebuilding the body (flush in pane `deactivate`/`dispose` is the reliable path — prefer dispose flush + ensure toggle does not dispose controller).

**Fidelity hint (required by spec):** surface `l10n.markdownWysiwygFidelityHint` when WYSIWYG is active — use the Edit segment tooltip **and** a one-line muted banner under the file toolbar (or inside the pane top). Do not leave the ARB key unused.

- [ ] **Step 4: Manual smoke / analyze**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/pages/workbench/ lib/services/editor/ lib/cubits/editor_cubit.dart
```

Manual: open `.md` → Edit → type → close tab before ~200ms → unsaved prompt; Save; Source shows text; Preview renders; `.dart` unchanged.

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/workbench/markdown_wysiwyg_pane.dart \
  client/lib/services/editor/markdown_wysiwyg_theme.dart \
  client/lib/pages/workbench/file_editor_surface.dart
git commit -m "$(cat <<'EOF'
feat: markdown WYSIWYG pane in workbench file editor

EOF
)"
```

---

### Task 8 (optional): `MarkdownOpenMode.wysiwyg` preference

**Files:**
- Modify: `client/lib/models/layout_preferences.dart`
- Modify: `client/lib/services/editor/markdown_view_mode_store.dart` (`seedOnOpen`)
- Modify: `client/lib/pages/config/layout_appearance_in_layout_section.dart`
- Modify tests for seed + JSON round-trip of preferences if covered

- [ ] **Step 1: Add enum value + dropdown entry + seed case**
- [ ] **Step 2: Test seedOnOpen + preferences JSON**
- [ ] **Step 3: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat: optional markdown open mode default to WYSIWYG

EOF
)"
```

Skip this task if timeboxing v1 — in-session toggle alone satisfies the core goal.

---

### Task 9: Verification gate

- [ ] **Step 1: Run focused + broader tests**

```bash
cd client && flutter test \
  test/services/editor/markdown_bridge_test.dart \
  test/services/editor/markdown_view_mode_store_test.dart \
  test/services/editor/markdown_wysiwyg_session_test.dart \
  test/cubits/editor_cubit_test.dart \
  test/cubits/editor_cubit_wysiwyg_test.dart
```

- [ ] **Step 2: Analyze**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

- [ ] **Step 3: Confirm non-goals**

No AppFlowy monorepo path deps; no `re_editor` removal; mode switch does not write disk without Save.

---

## Out of scope (do not implement in this plan)

- Native `.afdoc` / collaboration / AI writer
- Strict lossless Markdown
- Replacing code editor
- Workspace-relative image byte provider beyond best-effort links (follow-up if `appflowy_editor` requires a custom builder)

## Execution notes

- Prefer **subagent-driven-development** with one task per subagent.
- If `appflowy_editor` API names differ from sketches, adapt at the bridge/session boundary only.
- Keep `FileEditorSurface` from growing unbounded — WYSIWYG UI lives in `markdown_wysiwyg_pane.dart`.
