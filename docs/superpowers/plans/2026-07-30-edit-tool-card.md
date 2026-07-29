# Edit Tool Card (Cursor-style) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render edit/write tool calls in History as Cursor-like cards (basename + `+N`/`−N` + mini-diff that expands in place) with optional disk context enrichment and host-injected syntax highlighting.

**Architecture:** Parallel to the shell card. `ai_message_core` owns `AiEditHunk` + pluggable `AiEditHunkCodec`s + `DefaultAiEditToolTargetResolver`. `AiToolCallPartView` inserts an edit branch after shell and before file summary. UI defaults to plain monospace; History host injects enricher + highlighter via `AiToolFileActions`.

**Tech Stack:** Dart / Flutter; packages `ai_message_core`, `ai_message_ui`; host wiring in `client/lib` (workspace FS + existing editor syntax stack — **not** adding `re_highlight` unless already present).

**Spec:** `docs/superpowers/specs/2026-07-30-edit-tool-card-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `client/packages/ai_message_core/lib/src/tool_edit_hunk.dart` | `AiEditLineKind`, `AiEditLine`, `AiEditHunk`, `AiEditToolTarget` |
| `client/packages/ai_message_core/lib/src/tool_edit_args.dart` | Shared path / string / `argsText` JSON helpers for codecs |
| `client/packages/ai_message_core/lib/src/tool_edit_hunk_codec.dart` | `AiEditHunkCodec` interface |
| `client/packages/ai_message_core/lib/src/codecs/str_replace_edit_hunk_codec.dart` | StrReplace / Edit codec |
| `client/packages/ai_message_core/lib/src/codecs/write_edit_hunk_codec.dart` | Write / Create codec |
| `client/packages/ai_message_core/lib/src/codecs/unified_diff_edit_hunk_codec.dart` | ApplyPatch codec |
| `client/packages/ai_message_core/lib/src/tool_edit_target_resolver.dart` | `DefaultAiEditToolTargetResolver` + default codec list |
| `client/packages/ai_message_core/lib/ai_message_core.dart` | Export edit APIs |
| `client/packages/ai_message_core/test/tool_edit_*.dart` | Codec + resolver unit tests |
| `client/packages/ai_message_ui/lib/src/edit/edit_line_highlighter.dart` | `AiEditLineHighlighter` + `PlainEditLineHighlighter` |
| `client/packages/ai_message_ui/lib/src/edit/edit_tool_card.dart` | Public/private card widgets extracted from part view |
| `client/packages/ai_message_ui/lib/src/tool_file_actions.dart` | Add `enrichEditContext` + `lineHighlighter` |
| `client/packages/ai_message_ui/lib/src/parts/tool_call_part_view.dart` | Edit branch in resolve order |
| `client/packages/ai_message_ui/lib/ai_message_ui.dart` | Export highlighter types if host needs them |
| `client/packages/ai_message_ui/test/tool_call_edit_target_test.dart` | Widget tests |
| `client/lib/services/ai_history/workspace_edit_context_enricher.dart` | Disk ±context + line numbers |
| `client/lib/services/ai_history/workspace_edit_line_highlighter.dart` | Host highlighter using editor syntax theme / tree-sitter |
| `client/lib/pages/chat/session_chat_view.dart` | Wire enricher + highlighter into `AiToolFileActions` |
| `client/test/services/ai_history/workspace_edit_context_enricher_test.dart` | Enricher unit tests |
| `client/test/services/ai_history/workspace_edit_line_highlighter_test.dart` | Host highlighter smoke tests |

---

### Task 1: Hunk model + StrReplace codec + resolver (TDD)

**Files:**
- Create: `client/packages/ai_message_core/lib/src/tool_edit_hunk.dart`
- Create: `client/packages/ai_message_core/lib/src/tool_edit_args.dart`
- Create: `client/packages/ai_message_core/lib/src/tool_edit_hunk_codec.dart`
- Create: `client/packages/ai_message_core/lib/src/codecs/str_replace_edit_hunk_codec.dart`
- Create: `client/packages/ai_message_core/lib/src/tool_edit_target_resolver.dart`
- Modify: `client/packages/ai_message_core/lib/ai_message_core.dart`
- Create: `client/packages/ai_message_core/test/str_replace_edit_hunk_codec_test.dart`
- Create: `client/packages/ai_message_core/test/tool_edit_target_resolver_test.dart`

- [ ] **Step 1: Write failing StrReplace + resolver tests**

```dart
import 'package:ai_message_core/ai_message_core.dart';
import 'package:test/test.dart';

void main() {
  const codec = StrReplaceEditHunkCodec();
  const resolver = DefaultAiEditToolTargetResolver();

  test('StrReplace splits old/new into remove+add lines (no LCS)', () {
    final hunk = codec.encode(
      const AiToolCallPart(
        toolCallId: '1',
        toolName: 'StrReplace',
        args: {
          'file_path': 'lib/foo.dart',
          'old_string': 'a\nb',
          'new_string': 'a\nc',
        },
      ),
    );
    expect(hunk, isNotNull);
    expect(hunk!.path, 'lib/foo.dart');
    expect(hunk.removedCount, 2);
    expect(hunk.addedCount, 2);
    expect(hunk.lines.map((l) => l.kind).toList(), [
      AiEditLineKind.remove,
      AiEditLineKind.remove,
      AiEditLineKind.add,
      AiEditLineKind.add,
    ]);
    expect(hunk.lines.map((l) => l.text).toList(), ['a', 'b', 'a', 'c']);
  });

  test('start_line numbers consecutive lines', () {
    final hunk = codec.encode(
      const AiToolCallPart(
        toolCallId: '1',
        toolName: 'Edit',
        args: {
          'path': 'a.dart',
          'old_string': 'x',
          'new_string': 'y',
          'start_line': 10,
        },
      ),
    );
    expect(hunk!.startLine, 10);
    expect(hunk.lines[0].lineNumber, 10);
    expect(hunk.lines[1].lineNumber, 11);
  });

  test('missing new_string → null', () {
    expect(
      codec.encode(
        const AiToolCallPart(
          toolCallId: '1',
          toolName: 'StrReplace',
          args: {'file_path': 'a.dart', 'old_string': 'x'},
        ),
      ),
      isNull,
    );
  });

  test('resolver routes StrReplace; unknown tool → null', () {
    expect(
      resolver
          .resolve(
            const AiToolCallPart(
              toolCallId: '1',
              toolName: 'StrReplace',
              args: {
                'file_path': 'a.dart',
                'old_string': 'x',
                'new_string': 'y',
              },
            ),
          )
          ?.hunk
          .path,
      'a.dart',
    );
    expect(
      resolver.resolve(
        const AiToolCallPart(toolCallId: '1', toolName: 'Grep', args: {}),
      ),
      isNull,
    );
  });

  test('argsText JSON fallback', () {
    final t = resolver.resolve(
      const AiToolCallPart(
        toolCallId: '1',
        toolName: 'strreplace',
        argsText:
            '{"file_path":"b.dart","old_string":"o","new_string":"n"}',
      ),
    );
    expect(t?.hunk.path, 'b.dart');
  });
}
```

- [ ] **Step 2: Run — expect FAIL**

```bash
cd client/packages/ai_message_core && dart test test/str_replace_edit_hunk_codec_test.dart test/tool_edit_target_resolver_test.dart
```

- [ ] **Step 3: Implement model, helpers, StrReplace codec, resolver**

Implement types per spec. Path keys: `file_path`, `path`, `file`, `target_file`. Old/new keys: `old_string`/`oldString`, `new_string`/`newString`. Split on `\n` (Dart `LineSplitter` or `split('\n')` — keep empty trailing segment consistent between old and new). `matches`: tool names `strreplace`, `edit`, `editnotebook`, `notebookedit`.

`DefaultAiEditToolTargetResolver`: for each codec where `matches(toolName)`, call `encode`; first non-null wins. Default codecs list starts with StrReplace only (Write/Unified added in Task 2).

Export new libraries from `ai_message_core.dart`.

- [ ] **Step 4: PASS + Commit**

```bash
cd client/packages/ai_message_core && dart test test/str_replace_edit_hunk_codec_test.dart test/tool_edit_target_resolver_test.dart
git add client/packages/ai_message_core
git commit -m "$(cat <<'EOF'
feat(ai_message_core): add edit hunk model and StrReplace codec

EOF
)"
```

---

### Task 2: Write + UnifiedDiff codecs (TDD)

**Files:**
- Create: `client/packages/ai_message_core/lib/src/codecs/write_edit_hunk_codec.dart`
- Create: `client/packages/ai_message_core/lib/src/codecs/unified_diff_edit_hunk_codec.dart`
- Modify: `client/packages/ai_message_core/lib/src/tool_edit_target_resolver.dart` (register codecs)
- Create: `client/packages/ai_message_core/test/write_edit_hunk_codec_test.dart`
- Create: `client/packages/ai_message_core/test/unified_diff_edit_hunk_codec_test.dart`

- [ ] **Step 1: Failing Write + UnifiedDiff tests**

Write:
- `contents` / `content` → all `add` lines; `addedCount` = full line count
- Cap encoded `lines` at 500 but keep full `addedCount` when source has more
- Missing path or empty contents → null

UnifiedDiff:
- Parse body lines with leading `+`/`-`/space; skip `---`/`+++`/`@@` for body
- Path from args, else from `+++ b/path` / `--- a/path`
- Badge counts = `+` / `-` body lines
- `@@ -10,3 +10,4 @@` may set `startLine` from the `+` side when present

- [ ] **Step 2: FAIL then implement; register in `defaultCodecs` order:**
  `StrReplaceEditHunkCodec`, `WriteEditHunkCodec`, `UnifiedDiffEditHunkCodec`

- [ ] **Step 3: PASS + Commit**

```bash
cd client/packages/ai_message_core && dart test test/write_edit_hunk_codec_test.dart test/unified_diff_edit_hunk_codec_test.dart test/tool_edit_target_resolver_test.dart
git add client/packages/ai_message_core
git commit -m "$(cat <<'EOF'
feat(ai_message_core): add Write and ApplyPatch edit hunk codecs

EOF
)"
```

---

### Task 3: Highlighter port + file actions hooks + edit card UI (TDD)

**Files:**
- Create: `client/packages/ai_message_ui/lib/src/edit/edit_line_highlighter.dart`
- Create: `client/packages/ai_message_ui/lib/src/edit/edit_tool_card.dart`
- Modify: `client/packages/ai_message_ui/lib/src/tool_file_actions.dart`
- Modify: `client/packages/ai_message_ui/lib/src/parts/tool_call_part_view.dart`
- Modify: `client/packages/ai_message_ui/lib/ai_message_ui.dart` (export highlighter + actions fields as needed)
- Create: `client/packages/ai_message_ui/test/tool_call_edit_target_test.dart`

- [ ] **Step 1: Write failing widget tests**

```dart
testWidgets('StrReplace shows basename + badge + mini-diff (not Used tool)', (
  tester,
) async {
  await tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(
        body: AiToolCallPartView(
          part: AiToolCallPart(
            toolCallId: '1',
            toolName: 'StrReplace',
            args: {
              'file_path': 'lib/tp_sidebar_provider.dart',
              'old_string': 'final double mobileBreakpoint;',
              'new_string':
                  'final double mobileBreakpoint;\nfinal bool edgeOpenEnabled;',
              'start_line': 40,
            },
            result: 'ok',
          ),
        ),
      ),
    ),
  );

  expect(find.textContaining('Used tool:'), findsNothing);
  expect(find.textContaining('tp_sidebar_provider.dart'), findsOneWidget);
  expect(find.textContaining('+'), findsWidgets); // +N badge
  expect(find.textContaining('edgeOpenEnabled'), findsOneWidget);
  expect(find.textContaining('ok'), findsNothing); // Result hidden until/while collapsed body is hunk-only
});

testWidgets('expand grows same region; no Result: label or args JSON', (
  tester,
) async {
  await tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(
        body: AiToolCallPartView(
          part: AiToolCallPart(
            toolCallId: '1',
            toolName: 'StrReplace',
            args: {
              'file_path': 'lib/a.dart',
              'old_string': 'l1\nl2\nl3\nl4\nl5\nl6',
              'new_string': 'l1\nl2\nl3\nl4\nl5\nCHANGED',
            },
            result: 'ok',
          ),
        ),
      ),
    ),
  );
  expect(find.textContaining('CHANGED'), findsNothing);
  await tester.tap(find.byIcon(Icons.expand_more));
  await tester.pumpAndSettle();
  expect(find.textContaining('CHANGED'), findsOneWidget);
  expect(find.textContaining('Result:'), findsNothing);
  expect(find.textContaining('old_string'), findsNothing);
});

testWidgets('tap basename opens file with endLine', (tester) async {
  AiToolFileTarget? opened;
  await tester.pumpWidget(
    MaterialApp(
      home: AiToolFileActionsScope(
        actions: AiToolFileActions(
          onOpenFile: (t) async => opened = t,
        ),
        child: const Scaffold(
          body: AiToolCallPartView(
            part: AiToolCallPart(
              toolCallId: '1',
              toolName: 'StrReplace',
              args: {
                'file_path': 'lib/a.dart',
                'old_string': 'x',
                'new_string': 'y',
                'start_line': 10,
              },
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.textContaining('a.dart'));
  await tester.pumpAndSettle();
  expect(opened?.path, 'lib/a.dart');
  expect(opened?.startLine, 10);
  expect(opened?.endLine, isNotNull);
});

testWidgets('enrichEditContext success updates line numbers', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: AiToolFileActionsScope(
        actions: AiToolFileActions(
          enrichEditContext: (hunk) async => AiEditHunk(
            path: hunk.path,
            addedCount: hunk.addedCount,
            removedCount: hunk.removedCount,
            startLine: 40,
            lines: [
              const AiEditLine(
                kind: AiEditLineKind.context,
                text: 'before',
                lineNumber: 40,
              ),
              const AiEditLine(
                kind: AiEditLineKind.add,
                text: 'added',
                lineNumber: 41,
              ),
            ],
          ),
        ),
        child: const Scaffold(
          body: AiToolCallPartView(
            part: AiToolCallPart(
              toolCallId: '1',
              toolName: 'StrReplace',
              args: {
                'file_path': 'lib/a.dart',
                'old_string': 'x',
                'new_string': 'y',
              },
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.textContaining('40'), findsWidgets);
  expect(find.textContaining('before'), findsOneWidget);
});

testWidgets('Read still uses summary chrome', (tester) async { /* unchanged */ });
testWidgets('Shell still wins over edit-shaped names', (tester) async {
  // Bash with command — shell chrome, not edit
});
```

- [ ] **Step 2: Run — expect FAIL**

```bash
cd client/packages/ai_message_ui && flutter test test/tool_call_edit_target_test.dart
```

- [ ] **Step 3: Implement**

1. `AiEditLineHighlighter` + `PlainEditLineHighlighter` (returns `TextSpan(text: text, style: baseStyle)`).
2. Extend `AiToolFileActions`:

```dart
const AiToolFileActions({
  this.resolver = const DefaultAiToolFileTargetResolver(),
  this.onOpenFile,
  this.enrichEditContext,
  this.lineHighlighter = const PlainEditLineHighlighter(),
});

final Future<AiEditHunk> Function(AiEditHunk hunk)? enrichEditContext;
final AiEditLineHighlighter lineHighlighter;
```

3. `_EditToolCard` (in `edit_tool_card.dart`) — prefer **Stateless** chrome that
   takes `open` / `onToggle` from the parent (same pattern as `_ShellToolTrigger`),
   plus a thin Stateful wrapper **only** for async enricher `setState`:
   - Header: extension file-type icon + status icon + basename (tappable) +
     badges + chevron (`onToggle`)
   - Diff region (always under header, **inside the card**):
     `lines.take(open ? lines.length : previewCap)` where `previewCap` ≈ 5,
     preferring to include ≥1 add/remove. Expand grows this **same** list —
     do not stack a second full hunk under the card.
   - Per line: gutter lineNumber, kind background (green/red/dim),
     `highlighter.highlight(...)` wrapped in try/catch
   - Post-frame: if `enrichEditContext != null`, await and update hunk; on
     error keep original
   - `onOpenFile` target:

```dart
AiToolFileTarget(
  path: hunk.path,
  startLine: hunk.startLine ?? firstNumbered,
  endLine: lastNumbered, // or null
)
```

4. In `AiToolCallPartView` resolve order:

```dart
final editTarget = useSubagentChrome || shellTarget != null
    ? null
    : const DefaultAiEditToolTargetResolver().resolve(part);
final target = useSubagentChrome || shellTarget != null || editTarget != null
    ? null
    : fileActions.resolver.resolve(part);
```

Pass parent `_open` / `_toggleExpanded` into the edit card so
`initiallyExpanded` / `cotExpandToolsOnOpen` expand the full hunk.

**Critical — expand body branching:** keep shell's dedicated panel; skip shared
args/`Result:` for both shell and edit. Intended structure:

```dart
if (_open && shellTarget != null)
  _ShellTerminalPanel(...)
else if (_open && editTarget == null)
  // existing args + Result: column only (file summary / legacy)
// editTarget != null: no outer panel — card already shows truncated/full hunk via `open`
```

When `editTarget != null`, the card itself always paints the (truncated or
full) diff; the shared args/`Result:` column must **never** appear
(dedicated body only, same rule as shell).

Expanded edit hunks that are long should wrap the line list in a
`SingleChildScrollView` with a reasonable `maxHeight` so History stays usable.

- [ ] **Step 4: PASS + Commit**

```bash
cd client/packages/ai_message_ui && flutter test test/tool_call_edit_target_test.dart test/tool_call_shell_target_test.dart test/tool_call_file_target_test.dart
git add client/packages/ai_message_ui
git commit -m "$(cat <<'EOF'
feat(ai_message_ui): Cursor-style edit tool card with plain highlighter

EOF
)"
```

---

### Task 4: Enricher + host highlighter wiring (TDD)

**Files:**
- Create: `client/lib/services/ai_history/workspace_edit_context_enricher.dart`
- Create: `client/lib/services/ai_history/workspace_edit_line_highlighter.dart`
- Modify: `client/lib/pages/chat/session_chat_view.dart` (~`AiToolFileActions` construction)
- Create: `client/test/services/ai_history/workspace_edit_context_enricher_test.dart`
- Create: `client/test/services/ai_history/workspace_edit_line_highlighter_test.dart` (smoke: does not throw; returns non-empty span)

- [ ] **Step 1: Failing enricher tests (temp dir + LocalFilesystem or in-memory FS used elsewhere)**

```dart
test('adds context lines and absolute numbers when old_string found', () async {
  // file contains:
  // L1: before
  // L2: final double mobileBreakpoint;
  // L3: final bool enableKeyboardShortcut,
  // hunk = remove/add for middle line only → enrich → context before/after + lineNumbers
});

test('file missing or anchor lost → returns input hunk unchanged', () async { … });
```

Enricher algorithm (v1):
1. Resolve `hunk.path` against workspace root(s) the same way `AiToolFileOpenCoordinator` resolves opens (reuse helpers if extractable; otherwise mirror path join + exists checks).
2. Read file text; locate first occurrence of concatenated `remove` lines (joined with `\n`). If not found, return input.
3. Compute 1-based start line of match; prepend/append up to 2 context lines from file; renumber all lines; keep add/remove texts from hunk.
4. Never throw to UI — catch IO and return input.

- [ ] **Step 2: Host highlighter**

Implement `WorkspaceAiEditLineHighlighter` implementing `AiEditLineHighlighter`:
- Prefer existing editor syntax path (tree-sitter / `EditorSyntaxTheme`) for a single line by language from extension.
- If that path is too heavy for History rows, use a **thin** token colorizer driven by `EditorSyntaxTheme.forBrightness` keyword/string/comment regexes — still injected from host, not inside `ai_message_ui`.
- Any exception → plain `TextSpan`.

- [ ] **Step 3: Wire in `session_chat_view.dart`**

```dart
AiToolFileActions(
  onOpenFile: (target) async { … existing … },
  enrichEditContext: (hunk) => WorkspaceEditContextEnricher(
    fs: fs,
    roots: [...],
  ).enrich(hunk),
  lineHighlighter: WorkspaceAiEditLineHighlighter(
    brightness: Theme.of(context).brightness,
  ),
)
```

Guard null `fs` the same way `onOpenFile` already does (skip enricher / use plain).

- [ ] **Step 4: Run suites + Commit**

```bash
cd client && flutter test \
  test/services/ai_history/workspace_edit_context_enricher_test.dart \
  packages/ai_message_ui/test/tool_call_edit_target_test.dart \
  packages/ai_message_core/test/
git add client/lib/services/ai_history client/lib/pages/chat/session_chat_view.dart \
  client/test/services/ai_history
git commit -m "$(cat <<'EOF'
feat(history): enrich edit cards from workspace and inject syntax highlighter

EOF
)"
```

---

### Task 5: Regression polish + fixtures (optional but recommended)

**Files:**
- Optionally add fixture under `client/test/fixtures/` only if useful for docs
- Update any tests that assumed Write/StrReplace use summary-only chrome (search `Write` / `StrReplace` in `ai_message_ui/test`)

- [ ] **Step 1: Grep and fix stale assertions**

```bash
rg -n "StrReplace|WriteFile|ApplyPatch|Used tool" client/packages/ai_message_ui/test client/test -g'*test*.dart'
```

- [ ] **Step 2: Run broader UI + core suites**

```bash
cd client && flutter test \
  packages/ai_message_core/test/ \
  packages/ai_message_ui/test/tool_call_*.dart \
  test/services/ai_history/
```

- [ ] **Step 3: Commit if any fixes**

```bash
git commit -m "$(cat <<'EOF'
test(history): align edit-card regressions with new chrome

EOF
)"
```

---

## Out of scope (do not implement)

- Read tool card redesign
- Loader / transcript adapter changes
- Cursor `store.db`
- Myers/LCS StrReplace unify
- Side-by-side diff editor inside History
