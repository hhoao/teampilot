# Clickable Tool-Call File Targets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show read/write tool calls as `Read basename.dart L110–189` rows whose file link opens the workbench editor and selects the referenced lines.

**Architecture:** Pluggable `AiToolFileTargetResolver` in `ai_message_core` extracts `AiToolFileTarget` from tool args; `AiToolCallPartView` renders summary chrome and calls host `AiToolFileActions.onOpenFile`; TeamPilot resolves paths (session cwd → workspace folders) and opens via `WorkbenchEditorOpener` + `EditorCubit.selectLines`.

**Tech Stack:** Dart / Flutter; packages `ai_message_core`, `ai_message_ui`; TeamPilot editor / workbench.

**Spec:** `docs/superpowers/specs/2026-07-27-clickable-tool-file-targets-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `client/packages/ai_message_core/lib/src/tool_file_target.dart` | `AiToolFileTarget`, `AiToolFileTargetRule`, resolvers |
| `client/packages/ai_message_core/lib/ai_message_core.dart` | Export new types |
| `client/packages/ai_message_core/test/tool_file_target_resolver_test.dart` | Resolver unit tests |
| `client/packages/ai_message_ui/lib/src/tool_file_actions.dart` | Inherited `AiToolFileActions` scope |
| `client/packages/ai_message_ui/lib/src/parts/tool_call_part_view.dart` | Summary vs legacy chrome + hit testing |
| `client/packages/ai_message_ui/lib/ai_message_ui.dart` | Export actions |
| `client/packages/ai_message_ui/test/tool_call_file_target_test.dart` | Widget tests |
| `client/lib/services/editor/code_line_selection_for_lines.dart` | Pure 1-based → `CodeLineSelection` helper |
| `client/lib/cubits/editor_cubit.dart` | `selectLines(...)` |
| `client/test/services/editor/code_line_selection_for_lines_test.dart` | Helper tests |
| `client/lib/services/workbench/ai_tool_file_open_coordinator.dart` | Path resolve + open + select |
| `client/test/services/workbench/ai_tool_file_open_coordinator_test.dart` | Resolve priority tests |
| `client/lib/pages/chat/session_chat_view.dart` | Wire `AiToolFileActions` |
| `client/lib/l10n/app_en.arb` / `app_zh.arb` | File-not-found AppToast copy |

---

### Task 1: Core target + default resolver (TDD)

**Files:**
- Create: `client/packages/ai_message_core/lib/src/tool_file_target.dart`
- Modify: `client/packages/ai_message_core/lib/ai_message_core.dart`
- Create: `client/packages/ai_message_core/test/tool_file_target_resolver_test.dart`

- [ ] **Step 1: Write failing resolver tests**

```dart
import 'package:ai_message_core/ai_message_core.dart';
import 'package:test/test.dart';

void main() {
  final resolver = const DefaultAiToolFileTargetResolver();

  test('Read file_path + offset/limit', () {
    final t = resolver.resolve(const AiToolCallPart(
      toolCallId: '1',
      toolName: 'Read',
      args: {'file_path': 'lib/a.dart', 'offset': 110, 'limit': 80},
    ));
    expect(t?.path, 'lib/a.dart');
    expect(t?.startLine, 110);
    expect(t?.endLine, 189);
  });

  test('Write path key aliases; no lines', () {
    final t = resolver.resolve(const AiToolCallPart(
      toolCallId: '1',
      toolName: 'WriteFile',
      args: {'path': '/tmp/x.txt'},
    ));
    expect(t?.path, '/tmp/x.txt');
    expect(t?.startLine, isNull);
  });

  test('Edit start_line/end_line', () {
    final t = resolver.resolve(const AiToolCallPart(
      toolCallId: '1',
      toolName: 'StrReplace',
      args: {'file_path': 'a.dart', 'start_line': 3, 'end_line': 5},
    ));
    expect(t?.startLine, 3);
    expect(t?.endLine, 5);
  });

  test('L-range fallback from argsText', () {
    final t = resolver.resolve(const AiToolCallPart(
      toolCallId: '1',
      toolName: 'Read',
      args: {'file_path': 'a.dart'},
      argsText: 'file_path: a.dart\nL42-50',
    ));
    expect(t?.startLine, 42);
    expect(t?.endLine, 50);
  });

  test('unknown tool → null', () {
    expect(
      resolver.resolve(const AiToolCallPart(
        toolCallId: '1',
        toolName: 'Bash',
        args: {'path': 'a.dart'},
      )),
      isNull,
    );
  });

  test('missing path → null', () {
    expect(
      resolver.resolve(const AiToolCallPart(
        toolCallId: '1',
        toolName: 'Read',
        args: {'offset': 1},
      )),
      isNull,
    );
  });
}
```

Also cover case-insensitive tool names and path key precedence (`file_path` before `path`).

- [ ] **Step 2: Run — expect FAIL**

```bash
cd client/packages/ai_message_core && dart test test/tool_file_target_resolver_test.dart
```

- [ ] **Step 3: Implement types + Default resolver**

In `tool_file_target.dart`:

- `AiToolFileTarget`, `AiToolFileTargetRule`, `AiToolFileTargetResolver`
- `DefaultAiToolFileTargetResolver` with v1 rules from spec (Read `useOffsetLimit: true`)
- `CompositeAiToolFileTargetResolver(List<AiToolFileTargetResolver> resolvers)` — first non-null wins

Export from `ai_message_core.dart`.

- [ ] **Step 4: Tests PASS**

```bash
cd client/packages/ai_message_core && dart test test/tool_file_target_resolver_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add client/packages/ai_message_core/lib/src/tool_file_target.dart \
  client/packages/ai_message_core/lib/ai_message_core.dart \
  client/packages/ai_message_core/test/tool_file_target_resolver_test.dart
git commit -m "$(cat <<'EOF'
feat: add pluggable AI tool file-target resolver

EOF
)"
```

---

### Task 2: AiToolFileActions scope

**Files:**
- Create: `client/packages/ai_message_ui/lib/src/tool_file_actions.dart`
- Modify: `client/packages/ai_message_ui/lib/ai_message_ui.dart`

- [ ] **Step 1: Implement InheritedWidget**

```dart
@immutable
class AiToolFileActions {
  const AiToolFileActions({
    this.resolver = const DefaultAiToolFileTargetResolver(),
    this.onOpenFile,
  });

  final AiToolFileTargetResolver resolver;
  final Future<void> Function(AiToolFileTarget target)? onOpenFile;

  static AiToolFileActions of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<_AiToolFileActionsScope>()
            ?.actions ??
        const AiToolFileActions();
  }
}

class AiToolFileActionsScope extends StatelessWidget {
  const AiToolFileActionsScope({
    required this.actions,
    required this.child,
    super.key,
  });

  final AiToolFileActions actions;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _AiToolFileActionsScope(actions: actions, child: child);
  }
}
```

Export from package barrel.

- [ ] **Step 2: Analyze package**

```bash
cd client/packages/ai_message_ui && dart analyze lib/src/tool_file_actions.dart
```

- [ ] **Step 3: Commit**

```bash
git add client/packages/ai_message_ui/lib/src/tool_file_actions.dart \
  client/packages/ai_message_ui/lib/ai_message_ui.dart
git commit -m "$(cat <<'EOF'
feat: add AiToolFileActions host injection scope

EOF
)"
```

---

### Task 3: Summary chrome in AiToolCallPartView (TDD)

**Files:**
- Modify: `client/packages/ai_message_ui/lib/src/parts/tool_call_part_view.dart`
- Create: `client/packages/ai_message_ui/test/tool_call_file_target_test.dart`

- [ ] **Step 1: Failing widget tests**

```dart
testWidgets('summary shows basename; tap opens; chevron expands', (tester) async {
  AiToolFileTarget? opened;
  await tester.pumpWidget(
    MaterialApp(
      home: AiToolFileActionsScope(
        actions: AiToolFileActions(
          onOpenFile: (t) async => opened = t,
        ),
        child: Scaffold(
          body: AiToolCallPartView(
            part: AiToolCallPart(
              toolCallId: '1',
              toolName: 'Read',
              args: {
                'file_path': 'lib/ai_history_seat.dart',
                'offset': 110,
                'limit': 80,
              },
              result: 'ok',
            ),
          ),
        ),
      ),
    ),
  );

  expect(find.textContaining('Used tool:'), findsNothing);
  expect(find.textContaining('Read'), findsOneWidget);
  expect(find.textContaining('ai_history_seat.dart'), findsOneWidget);
  expect(find.textContaining('L110'), findsOneWidget);
  expect(find.textContaining('ok'), findsNothing);

  await tester.tap(find.textContaining('ai_history_seat.dart'));
  await tester.pumpAndSettle();
  expect(opened?.path, 'lib/ai_history_seat.dart');
  expect(opened?.startLine, 110);
  expect(find.textContaining('ok'), findsNothing);

  await tester.tap(find.byIcon(Icons.expand_more));
  await tester.pumpAndSettle();
  expect(find.textContaining('ok'), findsOneWidget);
});

testWidgets('Bash keeps legacy Used tool chrome', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AiToolCallPartView(
          part: const AiToolCallPart(
            toolCallId: '1',
            toolName: 'Bash',
            args: {'command': 'ls'},
          ),
        ),
      ),
    ),
  );
  expect(find.textContaining('Used tool:'), findsOneWidget);
});
```

- [ ] **Step 2: Run — FAIL**

```bash
cd client/packages/ai_message_ui && flutter test test/tool_call_file_target_test.dart
```

- [ ] **Step 3: Implement summary branch**

In `AiToolCallPartView.build`:

1. `final actions = AiToolFileActions.of(context);`
2. `final target = actions.resolver.resolve(part);`
3. If `target == null` → existing legacy row.
4. Else summary `Row`:
   - status icon
   - `Text(toolName)` (non-link)
   - If `onOpenFile != null`: `MouseRegion` + `GestureDetector` wrapping basename + optional `L…` with link style; `onTap: () => actions.onOpenFile!(target)` and **stop** row toggle (separate gesture, not parent opaque detector).
   - Else: plain basename + L text (no gesture).
   - Outer row (excluding link) + chevron toggles `_open`.

Implementation tip: structure as:

```dart
Row(
  children: [
    icon,
    SizedBox,
    Expanded(
      child: Wrap/Rich with separate GestureDetector only on link spans,
    ),
    GestureDetector(onTap: toggle, child: chevron),
  ],
)
```

Avoid a single opaque `GestureDetector` over the whole row when a target exists — use two hit targets.

Line label format: `L$start` or `L$start–$end` (en-dash `–` or hyphen `-`; pick one and use consistently — prefer `-` for font coverage).

- [ ] **Step 4: Tests PASS** + existing package tests

```bash
cd client/packages/ai_message_ui && flutter test
```

Update any tests that assumed Read inside CoT still shows `Used tool:` if they break.

- [ ] **Step 5: Commit**

```bash
git add client/packages/ai_message_ui/lib/src/parts/tool_call_part_view.dart \
  client/packages/ai_message_ui/test/tool_call_file_target_test.dart \
  # plus any updated existing tests
git commit -m "$(cat <<'EOF'
feat: render clickable file summaries for read/write tools

EOF
)"
```

---

### Task 4: Editor selectLines helper + cubit

**Files:**
- Create: `client/lib/services/editor/code_line_selection_for_lines.dart`
- Create: `client/test/services/editor/code_line_selection_for_lines_test.dart`
- Modify: `client/lib/cubits/editor_cubit.dart`

- [ ] **Step 1: Failing helper tests**

```dart
test('single line selection', () {
  final sel = codeLineSelectionForLines(
    lineCount: 10,
    lineLengths: List.filled(10, 5),
    startLine: 3,
  );
  expect(sel.baseIndex, 2);
  expect(sel.baseOffset, 0);
  expect(sel.extentIndex, 2);
  expect(sel.extentOffset, 5);
});

test('range clamps to document', () {
  final sel = codeLineSelectionForLines(
    lineCount: 5,
    lineLengths: List.filled(5, 1),
    startLine: 1,
    endLine: 99,
  );
  expect(sel.extentIndex, 4);
});
```

- [ ] **Step 2: Implement pure helper**

```dart
CodeLineSelection codeLineSelectionForLines({
  required int lineCount,
  required List<int> lineLengths,
  required int startLine, // 1-based
  int? endLine,
}) {
  if (lineCount <= 0) {
    return const CodeLineSelection.collapsed(index: 0, offset: 0);
  }
  final start = (startLine - 1).clamp(0, lineCount - 1);
  final end = ((endLine ?? startLine) - 1).clamp(0, lineCount - 1);
  final lo = start <= end ? start : end;
  final hi = start <= end ? end : start;
  return CodeLineSelection(
    baseIndex: lo,
    baseOffset: 0,
    extentIndex: hi,
    extentOffset: lineLengths[hi].clamp(0, lineLengths[hi]),
  );
}
```

(Adjust API if `CodeLineEditingController` exposes line text lengths differently — read controller API and match.)

- [ ] **Step 3: Add EditorCubit.selectLines**

```dart
void selectLines(
  String workspaceId,
  String path, {
  required int startLine,
  int? endLine,
}) {
  final controller = controllerFor(workspaceId, path);
  if (controller == null) return;
  final lines = controller.codeLines; // verify actual API
  // build lengths, assign controller.selection = ...
}
```

If reveal-in-viewport needs `CodeEditor` key, use existing `editorKeyFor` +
documented scroll API if available; otherwise **v1 accepted degradation:
selection only** (no guaranteed scroll-into-view). Document in commit body.

- [ ] **Step 4: Run helper tests PASS**

```bash
cd client && flutter test test/services/editor/code_line_selection_for_lines_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/editor/code_line_selection_for_lines.dart \
  client/test/services/editor/code_line_selection_for_lines_test.dart \
  client/lib/cubits/editor_cubit.dart
git commit -m "$(cat <<'EOF'
feat: select line ranges in editor for tool file opens

EOF
)"
```

---

### Task 5: AiToolFileOpenCoordinator + path resolve (TDD)

**Files:**
- Create: `client/lib/services/workbench/ai_tool_file_open_coordinator.dart`
- Create: `client/test/services/workbench/ai_tool_file_open_coordinator_test.dart`

- [ ] **Step 1: Failing resolve tests** (inject fake `Filesystem` + opener stubs)

Cases from spec:

1. Relative path exists under session cwd → that absolute path
2. Missing in cwd, exists under workspace folder → folder join
3. Absolute path → as-is when exists
4. Missing everywhere → returns error / calls onMissing (no throw)

Keep `openToolFile` orchestration thin: resolve → `opener.openFile(..., fs: fs)` →
`editor.selectLines` when `startLine != null`.

**Filesystem contract (required):**

- Existence checks: `final st = await fs.stat(candidate);` then
  `st.isFile` (preferred for open) or `st.exists`. **`stat` does not throw on
  missing paths** — it returns `FsStat(kind: notFound)`. Do **not** use
  try/catch for missing detection.
- There is **no** `fs.exists` method; `FsStat.exists` is a getter on the result.
- All join / `isAbsolute` / normalize use **`fs.pathContext`**, not global
  `p.context` — required for WSL/SSH path styles.
- The **same** `Filesystem` instance must be passed to both resolve and
  `WorkbenchEditorOpener.openFile` so remote/WSL opens hit the bound disk.

- [ ] **Step 2: Implement coordinator**

Constructor deps: `WorkbenchEditorOpener`, `EditorCubit`. Tests inject a **fake
`Filesystem`** (implement `stat` + `pathContext` only as needed).

```dart
Future<AiToolFileOpenResult> openToolFile({
  required String workspaceId,
  required AiToolFileTarget target,
  required String? sessionWorkingDirectory,
  required List<String> workspaceFolderPaths,
  required Filesystem fs,
});
```

Path ops: `fs.pathContext.join` / `isAbsolute` / `normalize` only.
Existence: `final st = await fs.stat(candidate); if (!st.isFile) …`
Never use dart:io `File`/`Directory` directly in the coordinator.
Never try/catch around `stat` to detect missing files.

- [ ] **Step 3: Tests PASS**

- [ ] **Step 4: Commit**

```bash
git add client/lib/services/workbench/ai_tool_file_open_coordinator.dart \
  client/test/services/workbench/ai_tool_file_open_coordinator_test.dart
git commit -m "$(cat <<'EOF'
feat: resolve and open AI tool file targets in workbench

EOF
)"
```

---

### Task 6: Wire session_chat_view + l10n

**Files:**
- Modify: `client/lib/pages/chat/session_chat_view.dart`
- Modify: `client/lib/l10n/app_en.arb`, `app_zh.arb` (+ gen-l10n + warmup glyphs)

- [ ] **Step 1: ARB**

```json
"aiToolFileNotFound": "Could not find file: {path}",
"@aiToolFileNotFound": { "placeholders": { "path": { "type": "String" } } }
```

ZH: `"找不到文件：{path}"`

```bash
cd client && flutter gen-l10n && dart run tool/gen_warmup_glyphs.dart
```

- [ ] **Step 2: Wrap History Theme / strings with AiToolFileActionsScope**

Near existing `AiMessageStringsScope` in `session_chat_view.dart`:

```dart
AiToolFileActionsScope(
  actions: AiToolFileActions(
    onOpenFile: (target) async {
      final fs = WorkspaceToolsScope.maybeOf(context)?.tools?.context.filesystem;
      // If WorkspaceToolsScope naming differs, follow file-tree open path.
      if (fs == null) return; // do not fall back to LocalFilesystem
      final result = await coordinator.openToolFile(
        workspaceId: /* widget workspace id field */,
        target: target,
        sessionWorkingDirectory:
            _workspaceRoot.isEmpty ? null : _workspaceRoot,
        workspaceFolderPaths: _launchContext.folderCatalog
            .map((f) => f.path)
            .toList(),
        fs: fs,
      );
      if (!context.mounted) return;
      if (result.isMissing) {
        AppToast.show(
          context,
          l10n.aiToolFileNotFound(target.path),
        );
      }
    },
  ),
  child: AiMessageStringsScope(...),
)
```

Obtain `AiToolFileOpenCoordinator` via `context.read<WorkbenchEditorOpener>()` +
`context.read<EditorCubit>()` (construct locally if not in DI).

**Must** pass a non-null workspace-bound `Filesystem` into `openToolFile`.
If `WorkspaceToolsScope` / tools context is not ready (`fs == null`), **do not
fall back to local `LocalFilesystem()`** — no-op the open (or show a short
toast that the workspace is still loading).

Missing-file UX: **`AppToast.show`** (already used in this file), not a new
`SnackBar`.

- [ ] **Step 3: Analyze**

```bash
cd client && dart analyze lib/pages/chat/session_chat_view.dart \
  lib/services/workbench/ai_tool_file_open_coordinator.dart
```

- [ ] **Step 4: Commit**

```bash
git add client/lib/pages/chat/session_chat_view.dart \
  client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb \
  client/lib/l10n/app_localizations*.dart \
  client/lib/services/workbench/ai_tool_file_open_coordinator.dart
# + warmup if changed
git commit -m "$(cat <<'EOF'
feat: wire clickable tool file opens in session chat

EOF
)"
```

---

### Task 7: Verification

- [ ] **Step 1: Package + host tests**

```bash
cd client/packages/ai_message_core && dart test
cd ../ai_message_ui && flutter test
cd /home/hhoa/git/hhoa/teampilot/client && flutter test --exclude-tags integration \
  test/services/editor/code_line_selection_for_lines_test.dart \
  test/services/workbench/ai_tool_file_open_coordinator_test.dart
flutter analyze --no-fatal-infos --no-fatal-warnings
```

- [ ] **Step 2: Manual smoke**

1. Open History with Read/Write tools → summary rows, no “Used tool:” prefix.
2. Click basename → editor opens; range selected when lines present.
3. Click chevron → args expand; no accidental open.
4. Missing file → AppToast with not-found copy.
5. Bash/MCP tools unchanged.

- [ ] **Step 3: Fixups commit if needed**

---

## Out of scope

- Grep/Glob/Shell linking
- Transcript adapter schema changes
- Multi-file opens
- Remote-only preview UX beyond opener
