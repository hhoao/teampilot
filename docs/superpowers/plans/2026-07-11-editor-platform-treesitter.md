# Editor Platform (Tree-sitter) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `re_highlight` whole-document Isolate highlighting with a TeamPilot `EditorPlatform` that uses Tree-sitter for viewport-first, incremental syntax coloring in file and diff editors.

**Architecture:** Own FFI package bundles tree-sitter C runtime + first-wave native grammars. UI isolate owns `DocumentSession` and talks to a pooled worker that owns the parse tree. Forked `re-editor` paints tokens from a `CodeTokenProvider`; language knowledge lives only in `services/editor_platform/`.

**Tech Stack:** Flutter/Dart, Dart FFI (`package_ffi` / native assets), tree-sitter C API, vendored `re-editor`, `flutter_bloc` `EditorCubit`.

**Spec:** [docs/superpowers/specs/2026-07-11-editor-platform-treesitter-design.md](../specs/2026-07-11-editor-platform-treesitter-design.md)

**Locked choices (from spec review):**

| Topic | Choice |
|-------|--------|
| Grammar artifacts | **Native** `.so` / `.dylib` / `.dll` (not wasm); bundled in app; **no runtime download** |
| FFI home | `client/packages/teampilot_tree_sitter` (`flutter create --template=package_ffi`) |
| `.scss` | **Plain text** this phase (no css stand-in); only `.css` uses `css` pack |
| Offsets | Worker stores **UTF-8 bytes**; UI converts Dart `String` ↔ UTF-8 via `Utf8IndexMap` |
| Diff | Two independent read-only `DocumentSession`s |
| Workers | Shared pool size **2**; session pinned to one worker for life |

---

## File map (target)

| File | Responsibility |
|------|----------------|
| `client/packages/teampilot_tree_sitter/` | FFI to tree-sitter + bundled grammars; parse/edit/query |
| `client/lib/services/editor_platform/utf8_index_map.dart` | Dart code-unit ↔ UTF-8 byte offsets |
| `client/lib/services/editor_platform/language_pack.dart` | Pack metadata + asset paths + query source |
| `client/lib/services/editor_platform/language_registry.dart` | resolve/ensureLoaded/prewarm |
| `client/lib/services/editor_platform/editor_syntax_theme.dart` | scope → TextStyle; light/dark |
| `client/lib/services/editor_platform/token_span.dart` | `TokenSpan`, line token snapshots |
| `client/lib/services/editor_platform/worker_protocol.dart` | open/edit/queryRange/dispose messages + seq |
| `client/lib/services/editor_platform/tree_sitter_worker_pool.dart` | 1–2 isolates; session affinity |
| `client/lib/services/editor_platform/document_session.dart` | UI-side session; token cache |
| `client/lib/services/editor_platform/document_session_token_provider.dart` | `CodeTokenProvider` adapter |
| `client/lib/services/editor_platform/editor_viewport_token_binder.dart` | scroll/visible lines → `ensureTokensForLines` |
| `client/lib/services/editor_platform/decorations_model.dart` | Placeholder for search/folds/diagnostics |
| `client/lib/services/editor_platform/language_features.dart` | Stub interfaces only |
| `client/lib/services/editor_platform/editor_platform.dart` | `bootstrap()`, facade |
| `client/assets/editor_languages/**` | `highlights.scm` per language |
| `client/packages/re-editor/lib/src/code_token_provider.dart` | Provider API |
| `client/packages/re-editor/lib/src/_code_highlight.dart` | Provider-driven spans (no isolate highlight) |
| `client/packages/re-editor/pubspec.yaml` | Remove `re_highlight` / unused `isolate_manager` |
| `client/lib/services/editor/file_editor_theme.dart` | Drop `re_highlight`; wire theme + provider |
| `client/lib/cubits/editor_cubit.dart` | Create/dispose `DocumentSession` |
| `client/lib/pages/workbench/file_editor_surface.dart` | Pass provider into `CodeEditor` |
| `client/lib/widgets/diff/*` | Dual read-only sessions |
| `client/lib/app/app_shell.dart` | `EditorPlatform.bootstrap()` |

---

### Task 1: `teampilot_tree_sitter` package + JSON smoke

**Files:**
- Create: `client/packages/teampilot_tree_sitter/` (full FFI package)
- Create: `client/packages/teampilot_tree_sitter/third_party/README.md` (pin commit SHAs)
- Create: `client/packages/teampilot_tree_sitter/test/parse_json_test.dart`
- Modify: `client/pubspec.yaml`

- [ ] **Step 1: Scaffold**

```bash
cd /home/hhoa/git/hhoa/teampilot/client/packages
flutter create --template=package_ffi teampilot_tree_sitter
```

- [ ] **Step 2: Vendor sources (pinned commits; document SHAs in third_party/README.md)**

```text
third_party/
  tree-sitter/          # github.com/tree-sitter/tree-sitter  (lib/src/*.c + include/)
  tree-sitter-json/     # github.com/tree-sitter/tree-sitter-json (src/parser.c + scanner if any)
```

Do **not** git-submodule the whole internet if avoidable: copy/vendoring the needed C files is fine. Prefer a script `tool/fetch_grammars.sh` that checks out pinned tags into `third_party/`.

- [ ] **Step 3: Native build (`hook/build.dart`)**

Compile into **one** native asset `teampilot_tree_sitter`:

1. All `tree-sitter/lib/src/*.c` (core)
2. `tree-sitter-json/src/parser.c` (+ scanner if present)
3. Thin `src/teampilot_ts_api.c` exporting a stable C ABI used by ffigen, e.g.:
   - `tp_ts_language_json(void)` → `TSLanguage*`
   - wrappers only if ffigen cannot bind headers cleanly

Include paths: `third_party/tree-sitter/lib/include`.

Verify Android NDK + Linux desktop both produce the asset (run package tests on Linux host; Android compile via `flutter build apk` smoke later in Task 12).

- [ ] **Step 4: ffigen + Dart API**

Generate bindings from tree-sitter headers / `teampilot_ts_api.h`. Expose:

```dart
class TsParser {
  void setLanguage(TsLanguage language);
  TsTree parseUtf8(Uint8List bytes, {TsTree? oldTree});
  void edit(TsTree tree, TsInputEdit edit);
}

class TsQuery {
  TsQuery(TsLanguage language, String source);
  List<TsCapture> captures(
    TsTree tree, {
    required int startByte,
    required int endByte,
  });
}

class TsLanguage {
  static TsLanguage json(); // dlsym / @Native tp_ts_language_json
}
```

Symbols that must resolve at runtime: core `ts_*` used by the Dart API + `tp_ts_language_json` (or `tree_sitter_json`).

- [ ] **Step 5: Smoke test**

```dart
test('parses json and captures string', () {
  final lang = TsLanguage.json();
  final parser = TsParser()..setLanguage(lang);
  final bytes = utf8.encode('{"a": 1}');
  final tree = parser.parseUtf8(Uint8List.fromList(bytes));
  final query = TsQuery(lang, '(string) @string');
  final caps = query.captures(tree, startByte: 0, endByte: bytes.length);
  expect(caps.any((c) => c.name == 'string'), isTrue);
});
```

Run: `cd client/packages/teampilot_tree_sitter && flutter test`  
Expected: PASS on Linux host

- [ ] **Step 6: Path dependency**

```yaml
# client/pubspec.yaml
  teampilot_tree_sitter:
    path: packages/teampilot_tree_sitter
```

- [ ] **Step 7: Commit**

```bash
git add client/packages/teampilot_tree_sitter client/pubspec.yaml client/pubspec.lock
git commit -m "$(cat <<'EOF'
feat(editor): add teampilot_tree_sitter FFI package with json smoke

EOF
)"
```

---

### Task 2: `Utf8IndexMap` (TDD)

**Files:**
- Create: `client/lib/services/editor_platform/utf8_index_map.dart`
- Create: `client/test/services/editor_platform/utf8_index_map_test.dart`

- [ ] **Step 1: Failing test**

```dart
test('maps emoji and cjk between code units and utf8 bytes', () {
  const s = 'a😀中';
  final map = Utf8IndexMap(s);
  expect(map.byteOffsetForCodeUnit(0), 0);
  expect(map.byteOffsetForCodeUnit(1), 1);
  expect(map.codeUnitOffsetForByte(map.byteOffsetForCodeUnit(s.length)), s.length);
});
```

- [ ] **Step 2: Implement** — `byteOffsetForCodeUnit`, `codeUnitOffsetForByte`, rebuild-on-edit helpers

- [ ] **Step 3: Run** `cd client && flutter test test/services/editor_platform/utf8_index_map_test.dart` → PASS

- [ ] **Step 4: Commit**

```bash
git add client/lib/services/editor_platform/utf8_index_map.dart \
  client/test/services/editor_platform/utf8_index_map_test.dart
git commit -m "$(cat <<'EOF'
feat(editor): add Utf8IndexMap for tree-sitter byte offsets

EOF
)"
```

---

### Task 3: LanguagePack + LanguageRegistry (TDD)

**Files:**
- Create: `client/lib/services/editor_platform/language_pack.dart`
- Create: `client/lib/services/editor_platform/language_registry.dart`
- Create: `client/test/services/editor_platform/language_registry_test.dart`
- Create: `client/assets/editor_languages/json/highlights.scm`
- Modify: `client/pubspec.yaml` (assets)

- [ ] **Step 1: Failing tests**

```dart
test('resolves .json to json pack', () {
  expect(LanguageRegistry.builtins().resolve('/x/a.json')?.id, 'json');
});

test('scss is plain text this phase', () {
  expect(LanguageRegistry.builtins().resolve('/x/a.scss'), isNull);
});
```

Task 3 registers **json only**; Task 10 adds remaining packs.

- [ ] **Step 2: Implement `LanguagePack` + `LanguageRegistry.builtins()`**

- [ ] **Step 3: Tests PASS + commit**

```bash
git commit -m "$(cat <<'EOF'
feat(editor): add LanguageRegistry with json pack

EOF
)"
```

---

### Task 4: `EditorSyntaxTheme` (TDD)

**Files:**
- Create: `client/lib/services/editor_platform/editor_syntax_theme.dart`
- Create: `client/test/services/editor_platform/editor_syntax_theme_test.dart`

- [ ] **Step 1: Test scope fallback** (`keyword.control` → `keyword`)

- [ ] **Step 2: Implement light/dark maps aligned with atom-one**

- [ ] **Step 3: PASS + commit**

```bash
git commit -m "$(cat <<'EOF'
feat(editor): add EditorSyntaxTheme scope styles

EOF
)"
```

---

### Task 5: Worker protocol + pool + DocumentSession

**Files:**
- Create: `client/lib/services/editor_platform/worker_protocol.dart`
- Create: `client/lib/services/editor_platform/tree_sitter_worker_pool.dart`
- Create: `client/lib/services/editor_platform/document_session.dart`
- Create: `client/lib/services/editor_platform/token_span.dart`
- Create: `client/test/services/editor_platform/document_session_test.dart`
- Optional test double: `client/test/services/editor_platform/fake_ts_worker.dart`

- [ ] **Step 1: Protocol** — `TsOpen` / `TsEdit` / `TsQueryRange` / `TsDispose` with monotonic `seq`

Worker returns **byte ranges + capture names**; UI maps via `Utf8IndexMap`. Drop replies where `seq < latestAppliedEditSeq`.

- [ ] **Step 2: Pool** — max 2 isolates; session affinity; serial mailbox per session

- [ ] **Step 3: `DocumentSession` API + token cache rules**

```dart
class DocumentSession {
  Future<void> open({required String path, required String text});
  void applyEdit({
    required int codeUnitStart,
    required int codeUnitDeleteCount,
    required String insert,
  });
  Future<void> ensureTokensForLines(
    int startLine,
    int endLine, {
    bool awaitResult = false,
    bool highPriority = false,
  });
  /// After open: await viewport, then enqueue non-awaited full-file fill.
  Future<void> colorizeAfterOpen({required int viewportEndLine});
  List<TokenSpan> tokensForLine(int lineIndex);
  void dispose();
}
```

**Cache / edit rules (normative):**

1. `applyEdit` updates local text + `Utf8IndexMap`, bumps `editSeq`, sends `TsEdit`, and **invalidates token lines overlapping the edited code-unit range** (keep other lines).
2. After edit, enqueue `ensureTokensForLines` for dirty lines ∪ current viewport (`highPriority: true` for viewport).
3. If awaiting a high-priority query exceeds **8ms**, stop awaiting; keep prior tokens for non-invalidated lines; apply when reply arrives (no flash to empty).
4. `colorizeAfterOpen`: `await ensureTokensForLines(0, viewportEndLine, awaitResult: true, highPriority: true)` then fire-and-forget `ensureTokensForLines(viewportEndLine + 1, lineCount - 1)` rate-limited on the worker.

- [ ] **Step 4: Tests**

Prefer a **fake worker** implementing the protocol for unit tests (no FFI), plus one integration test that uses real `teampilot_tree_sitter` if host native asset loads.

```dart
test('open json colors viewport without waiting full file', () async {
  final session = DocumentSession(registry: reg, pool: fakePool);
  await session.open(path: 'a.json', text: '{"hello": "world"}\n' * 200);
  await session.colorizeAfterOpen(viewportEndLine: 5);
  expect(session.tokensForLine(0), isNotEmpty);
});

test('applyEdit invalidates and refreshes dirty line', () async {
  // open small json, edit a string, expect tokensForLine updates after await
});
```

Run: `cd client && flutter test test/services/editor_platform/document_session_test.dart`

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(editor): add DocumentSession worker pool for tree-sitter

EOF
)"
```

---

### Task 6: re-editor `CodeTokenProvider` (delete re_highlight path)

**Files:**
- Create: `client/packages/re-editor/lib/src/code_token_provider.dart`
- Modify: `client/packages/re-editor/lib/src/_code_highlight.dart`
- Modify: `client/packages/re-editor/lib/src/_code_editable.dart`
- Modify: `client/packages/re-editor/lib/src/code_editor.dart`
- Modify: `client/packages/re-editor/lib/src/code_theme.dart`
- Modify: `client/packages/re-editor/pubspec.yaml`
- Modify: `client/packages/re-editor/lib/src/re_editor.dart`
- Fix: `client/packages/re-editor/example/**` if broken

- [ ] **Step 1: Provider API**

```dart
class CodeTokenSpan {
  const CodeTokenSpan({
    required this.start,
    required this.length,
    required this.scope,
  });
  final int start;
  final int length;
  final String scope;
}

abstract class CodeTokenProvider extends Listenable {
  List<CodeTokenSpan> tokensForLine(int lineIndex);
}
```

- [ ] **Step 2: Replace `_CodeHighlightEngine` / isolate highlight** with provider + `syntaxTheme: Map<String, TextStyle>`

- [ ] **Step 3:** `cd client/packages/re-editor && flutter test && dart analyze`

- [ ] **Step 4: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(re-editor): replace re_highlight isolate with CodeTokenProvider

EOF
)"
```

---

### Task 7: Bridge session → provider + theme cleanup

**Files:**
- Create: `client/lib/services/editor_platform/document_session_token_provider.dart`
- Modify: `client/lib/services/editor/file_editor_theme.dart`
- Modify: `client/lib/services/editor/file_editor_ai_context.dart`
- Update tests importing old highlight helpers

- [ ] **Step 1: `DocumentSessionTokenProvider`** implements `CodeTokenProvider`

- [ ] **Step 2: Rewrite `codeEditorStyleFor`** to take `tokenProvider` + `EditorSyntaxTheme`; delete `codeHighlightThemeFor` / `highlightModeForKey` / `re_highlight` imports

Keep `isEditorOpenableFilePath` allowlists (edit policy ≠ highlight).

- [ ] **Step 3: `editorLanguageIdForPath` → `LanguageRegistry.resolve(path)?.id ?? extension`

- [ ] **Step 4: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(editor): wire DocumentSession tokens into CodeEditorStyle

EOF
)"
```

---

### Task 8: EditorCubit + FileEditorSurface lifecycle

**Files:**
- Modify: `client/lib/cubits/editor_cubit.dart`
- Modify: `client/lib/pages/workbench/file_editor_surface.dart`
- Create: `client/lib/services/editor_platform/editor_viewport_token_binder.dart` (scroll → ensureTokens)
- Create/extend: editor cubit tests

- [ ] **Step 1: Cubit creates/disposes `DocumentSession` with controller; expose `tokenProviderFor`**

- [ ] **Step 2: After load, `await session.colorizeAfterOpen(viewportEndLine: 80)` then attach provider

- [ ] **Step 3: Surface passes provider into `CodeEditor` via `codeEditorStyleFor`**

- [ ] **Step 4: Viewport binder**

Hook re-editor scroll / visible line range (use `CodeScrollController` or indicator notifier). On visible range change:

```dart
unawaited(session.ensureTokensForLines(
  firstVisible,
  lastVisible,
  awaitResult: false,
  highPriority: true,
));
```

If entering lines with empty tokens, optionally `awaitResult: true` with 8ms budget (same as session).

- [ ] **Step 5: Controller listener → `applyEdit`** (code-unit ranges)

- [ ] **Step 6: Manual check — open large `.json`, scroll past line 200, new lines color without full-file wait

- [ ] **Step 7: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(editor): bind DocumentSession lifecycle and viewport token requests

EOF
)"
```

---

### Task 9: Diff dual read-only sessions

**Files:**
- Modify: `client/lib/widgets/diff/unified_diff_view.dart`
- Modify: `client/lib/widgets/diff/side_by_side_diff_view.dart`
- Modify: `client/lib/pages/workbench/diff_editor_surface.dart` if needed

- [ ] **Step 1: For original + modified text, create two read-only `DocumentSession`s** (same pack from path)

- [ ] **Step 2: For each session**

```dart
await session.open(path: absolutePath, text: paneText);
await session.colorizeAfterOpen(viewportEndLine: min(80, lineCount - 1));
```

Pass each `DocumentSessionTokenProvider` into the corresponding `CodeEditor`.

- [ ] **Step 3: On scroll of either pane, call `ensureTokensForLines` (same binder pattern as Task 8)**

- [ ] **Step 4: Dispose both sessions in `dispose()`**

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(editor): use dual DocumentSessions for diff syntax color

EOF
)"
```

---

### Task 10: First-wave grammars + bootstrap prewarm

**Files:**
- Extend: `client/packages/teampilot_tree_sitter` native grammars
- Add: `client/assets/editor_languages/<id>/highlights.scm`
- Modify: `language_registry.dart`, `editor_platform.dart`, app bootstrap

**Extension map:**

| Pack | Extensions |
|------|------------|
| dart | `.dart` |
| json | `.json` |
| yaml | `.yaml`, `.yml` |
| markdown | `.md`, `.markdown` |
| python | `.py` |
| rust | `.rs` |
| typescript | `.ts`, `.tsx`, `.js`, `.jsx`, `.mjs`, `.cjs` |
| bash | `.sh`, `.bash` |
| xml | `.xml`, `.html`, `.htm` |
| toml | `.toml` |
| css | `.css` |
| _(none)_ | `.scss` → plain text |

- [ ] **Step 1: Add grammars + per-language smoke tests**

- [ ] **Step 2: `EditorPlatform.bootstrap(prewarm: ['json','dart','typescript','yaml'])` from app shell**

- [ ] **Step 3: Load failure → plain text + `AppLogger`**

- [ ] **Step 4: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(editor): ship first-wave tree-sitter grammars and prewarm

EOF
)"
```

---

### Task 11: Stubs + cleanup

**Files:**
- Create: `language_features.dart`, `decorations_model.dart`
- Modify: `client/pubspec.yaml` — remove app `re_highlight` dependency if unused
- Modify: `client/packages/re-editor/pubspec.yaml` — remove `re_highlight`; remove `isolate_manager` **only if** no remaining `_IsolateTasker` users (e.g. find); otherwise keep
- Grep-remove leftover `re_highlight` / `CodeHighlightTheme` / `highlightLanguageKeyForPath`

- [ ] **Step 1: Stub `LanguageFeatures` + empty `DecorationsModel` layers**

- [ ] **Step 2: Analyze + unit tests**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd client && flutter test --exclude-tags integration
```

- [ ] **Step 3: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(editor): add LanguageFeatures stubs and remove re_highlight leftovers

EOF
)"
```

---

### Task 12: Verification

- [ ] Open `.dart` / `.json` / `.ts`: viewport colored on first paint
- [ ] Scroll large file: newly visible lines color via high-priority `ensureTokensForLines`
- [ ] Large file typing stays responsive (prior tokens / 8ms budget)
- [ ] `.scss` plain text; `.toml` / `.css` real packs
- [ ] Diff colors both sides after open
- [ ] `rg re_highlight client/lib client/packages/re-editor` clean for highlight path
- [ ] Android: `flutter build apk` (or device run) loads native asset; open `.json` colors
- [ ] Fix follow-ups + commit if needed

---

## Out of scope

- LSP / real `LanguageFeatures`
- Language pack download UI
- Semantic highlighting
- Replacing re-editor layout engine
- Monaco / WebView

## Notes

- Grammar sources may be fetched at **dev build time** only; runtime is bundled/offline.
- Desktop can land first, but Android must work before release on the same feature branch.
