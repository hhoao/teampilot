# Selection → Ask AI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users copy a file/terminal selection as AI context, or open a landing Compose dialog (prefilled) from a selection FAB / menu and launch a new session on send.

**Architecture:** Shared `selection_ai/` formatters + `SelectionAskAi.openComposeDialog` (TpDialog hosting `WorkspaceChatLanding` with `initialText`) + `SelectionAskAiFabHost`. Surfaces (file editor, workspace shell, member terminal) only wire selection → format → dialog/clipboard. Submit reuses `submitWorkspaceLandingMessage` via the same path as `WorkspaceChatPane._submit`.

**Tech Stack:** Flutter / `flutter_bloc`; `re_editor`; `flutter_alacritty` `TerminalController`; `TpDialog` / `TpActionMenuSpec`; l10n ARB; existing `WorkspaceChatLanding` + `submitWorkspaceLandingMessage`.

**Spec:** `docs/superpowers/specs/2026-07-27-selection-ask-ai-design.md`

## Global Constraints

- Do **not** call `enterNewChat` when opening Ask AI (stay on editor/terminal visually).
- Clipboard body and Ask AI prefill body (sans trailing `\n\n`) must use the **same** formatter output.
- Prefill = `aiContext + '\n\n'`; caret at end; submit sends full field text unchanged.
- Terminal AI actions enabled only when selection text is non-empty (no current-line fallback).
- Terminal line range: **omit** in v1 (`L<a>-<b>` not required) — `TerminalController` does not expose range.
- Edit `app_en.arb` / `app_zh.arb` only for new strings; after ARB changes run `dart run tool/gen_warmup_glyphs.dart` from `client/`.
- Reuse `editorCopyAsAiContext` for Copy label; add `selectionAskAi`.
- Before claiming done: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration` for touched areas at minimum.

---

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/services/selection_ai/selection_ai_context.dart` | Pure formatters + prefill join |
| `client/test/services/selection_ai/selection_ai_context_test.dart` | Formatter / prefill tests |
| `client/lib/services/editor/file_editor_ai_context.dart` | Delegate template build to shared module |
| `client/lib/services/selection_ai/selection_ask_ai.dart` | `openComposeDialog` + submit wiring |
| `client/lib/services/selection_ai/selection_ask_ai_fab_host.dart` | Overlay FAB over a child surface |
| `client/lib/services/selection_ai/selection_ai_menu_specs.dart` | Shared Copy / Ask AI menu specs |
| `client/lib/pages/home_workspace/workspace/workspace_chat_landing.dart` | `initialText` |
| `client/lib/services/editor/file_editor_toolbar.dart` | Ask AI menu item |
| `client/lib/pages/workbench/file_editor_surface.dart` | Wrap code editor with FAB host |
| `client/lib/widgets/workspace_terminal_panel.dart` | Shell menu AI + FAB |
| `client/lib/pages/chat/chat_workbench_context_menu.dart` | Member menu AI |
| `client/lib/pages/chat/chat_workbench_terminal.dart` | Member FAB host + surface label |
| `client/lib/l10n/app_en.arb` / `app_zh.arb` | `selectionAskAi` |
| `client/test/services/selection_ai/selection_ask_ai_fab_host_test.dart` | FAB show/hide/tap |

---

### Task 1: Shared AI context formatters + prefill

**Files:**
- Create: `client/lib/services/selection_ai/selection_ai_context.dart`
- Create: `client/test/services/selection_ai/selection_ai_context_test.dart`
- Modify: `client/lib/services/editor/file_editor_ai_context.dart`
- Modify: `client/test/services/editor/file_editor_ai_context_test.dart` (keep existing; still passes via delegate)

**Interfaces:**
- Produces:
  - `String buildFileAiContextClipboardText({required String relPath, required int startLine, required int endLine, required String language, required String code})`
  - `String buildTerminalAiContextClipboardText({required String surfaceLabel, required String text, int? startLine, int? endLine})`
  - `String selectionAskAiPrefillText(String aiContext)` → `'$aiContext\n\n'` when non-empty; `''` when trim-empty
- Consumes: none

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/selection_ai/selection_ai_context.dart';

void main() {
  test('buildFileAiContextClipboardText matches editor template', () {
    expect(
      buildFileAiContextClipboardText(
        relPath: 'lib/foo.dart',
        startLine: 10,
        endLine: 12,
        language: 'dart',
        code: 'void main() {}',
      ),
      'lib/foo.dart:10-12\n```dart\nvoid main() {}\n```',
    );
  });

  test('buildTerminalAiContextClipboardText without line range', () {
    expect(
      buildTerminalAiContextClipboardText(
        surfaceLabel: 'workspace-shell',
        text: 'error: boom',
      ),
      'terminal:workspace-shell\n```text\nerror: boom\n```',
    );
  });

  test('buildTerminalAiContextClipboardText with line range', () {
    expect(
      buildTerminalAiContextClipboardText(
        surfaceLabel: 'session/s1/lead',
        text: 'hi',
        startLine: 3,
        endLine: 5,
      ),
      'terminal:session/s1/lead L3-5\n```text\nhi\n```',
    );
  });

  test('buildTerminalAiContextClipboardText empty text returns empty', () {
    expect(
      buildTerminalAiContextClipboardText(
        surfaceLabel: 'workspace-shell',
        text: '  \n',
      ),
      '',
    );
  });

  test('selectionAskAiPrefillText appends blank line', () {
    expect(
      selectionAskAiPrefillText('ctx'),
      'ctx\n\n',
    );
    expect(selectionAskAiPrefillText('  '), '');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/selection_ai/selection_ai_context_test.dart`

Expected: FAIL — library not found.

- [ ] **Step 3: Write minimal implementation**

Create `client/lib/services/selection_ai/selection_ai_context.dart`:

```dart
String buildFileAiContextClipboardText({
  required String relPath,
  required int startLine,
  required int endLine,
  required String language,
  required String code,
}) {
  return '$relPath:$startLine-$endLine\n```$language\n$code\n```';
}

String buildTerminalAiContextClipboardText({
  required String surfaceLabel,
  required String text,
  int? startLine,
  int? endLine,
}) {
  final body = text.trimRight();
  if (body.trim().isEmpty) return '';
  final range = (startLine != null && endLine != null)
      ? ' L$startLine-$endLine'
      : '';
  return 'terminal:$surfaceLabel$range\n```text\n$body\n```';
}

String selectionAskAiPrefillText(String aiContext) {
  final trimmed = aiContext.trimRight();
  if (trimmed.trim().isEmpty) return '';
  return '$trimmed\n\n';
}
```

Update `file_editor_ai_context.dart` so `buildEditorAiContextClipboardText` delegates to `buildFileAiContextClipboardText` (same params). Keep `formatEditorAiContext` / helpers as-is otherwise.

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
cd client && flutter test \
  test/services/selection_ai/selection_ai_context_test.dart \
  test/services/editor/file_editor_ai_context_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/selection_ai/selection_ai_context.dart \
  client/test/services/selection_ai/selection_ai_context_test.dart \
  client/lib/services/editor/file_editor_ai_context.dart
git commit -m "$(cat <<'EOF'
feat(selection-ai): add shared file/terminal AI context formatters

EOF
)"
```

---

### Task 2: l10n for Ask AI

**Files:**
- Modify: `client/lib/l10n/app_en.arb`
- Modify: `client/lib/l10n/app_zh.arb`
- Generated: `app_localizations*.dart` (via Flutter gen-l10n on next build/test)
- Run: `cd client && dart run tool/gen_warmup_glyphs.dart` after ARB edits

**Interfaces:**
- Produces: `AppLocalizations.selectionAskAi` → EN `Ask AI…` / ZH `用 AI 提问…`

- [ ] **Step 1: Add ARB keys near `editorCopyAsAiContext`**

`app_en.arb`:

```json
"selectionAskAi": "Ask AI…"
```

`app_zh.arb`:

```json
"selectionAskAi": "用 AI 提问…"
```

- [ ] **Step 2: Regenerate glyph warmup**

Run: `cd client && dart run tool/gen_warmup_glyphs.dart`

- [ ] **Step 3: Commit**

```bash
git add client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb \
  client/lib/theme/warmup_glyphs.g.dart
git commit -m "$(cat <<'EOF'
feat(l10n): add selectionAskAi string

EOF
)"
```

---

### Task 3: `WorkspaceChatLanding.initialText`

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/workspace_chat_landing.dart`
- Create: `client/test/pages/home_workspace/workspace/workspace_chat_landing_initial_text_test.dart`

**Interfaces:**
- Produces: `WorkspaceChatLanding({ ..., String? initialText })` — applied once in `initState` to `_controller`, selection collapsed at end. Do **not** overwrite on later `didUpdateWidget` / draft reload.

- [ ] **Step 1: Write the failing widget test**

Mount a minimal `WorkspaceChatLanding` with mocked cubits/repositories as other landing tests do (search existing `workspace_chat_landing*_test.dart` and copy the harness). Assert `find.textContaining` / controller text starts with the initial context and ends with `\n\n`.

If no lightweight harness exists, prefer a pure unit-style approach: extract a tiny helper in `selection_ai_context.dart` already covers prefill; for Landing, add a focused test that constructs the State via pumping with `initialText: 'hello'` and reads the first `TextField` / `ComposeTriggerField` value — match whatever finder existing landing tests use.

Minimal assertion shape:

```dart
testWidgets('initialText fills compose field', (tester) async {
  // ... pump WorkspaceChatLanding(workspace: ..., onSubmit: (_, __) {}, initialText: 'ctx\n\n');
  // Expect the compose editable to contain 'ctx' and trailing blank line.
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/pages/home_workspace/workspace/workspace_chat_landing_initial_text_test.dart`

Expected: FAIL (no `initialText` param) or assertion fail.

- [ ] **Step 3: Implement `initialText`**

Add to `WorkspaceChatLanding`:

```dart
const WorkspaceChatLanding({
  required this.workspace,
  required this.onSubmit,
  this.isSubmitting = false,
  this.disabled = false,
  this.initialText,
  super.key,
});

final String? initialText;
```

In `_WorkspaceChatLandingState.initState`, after creating `_controller` / `_focusNode` / voice, before `_loadDraft`:

```dart
final seed = widget.initialText;
if (seed != null && seed.isNotEmpty) {
  _controller.value = TextEditingValue(
    text: seed,
    selection: TextSelection.collapsed(offset: seed.length),
  );
}
```

Do not clear this in `_applyDraft` (draft must not touch compose text).

- [ ] **Step 4: Run test — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/home_workspace/workspace/workspace_chat_landing.dart \
  client/test/pages/home_workspace/workspace/workspace_chat_landing_initial_text_test.dart
git commit -m "$(cat <<'EOF'
feat(landing): support initialText for Ask AI compose seed

EOF
)"
```

---

### Task 4: `SelectionAskAi.openComposeDialog`

**Files:**
- Create: `client/lib/services/selection_ai/selection_ask_ai.dart`
- Create: `client/test/services/selection_ai/selection_ask_ai_test.dart` (optional smoke: empty context no-ops; prefer widget test with mocked submit callback)

**Interfaces:**
- Produces:
  - `Future<void> SelectionAskAi.openComposeDialog(BuildContext context, { required String aiContext, required Workspace workspace, required String tabScopeId })`
  - Uses `selectionAskAiPrefillText`; if empty → return immediately (optional `AppLogger` warn).
  - Dialog: `showDialog` → `TpDialog(maxWidth: 720, maxHeight: ~720, scrollable: true)` with header title from `selectionAskAi`, body `WorkspaceChatLanding(initialText: prefill, onSubmit: ...)`.
  - `onSubmit`: mirror `WorkspaceChatPane._submit` (persist draft, resolve cwd, `submitWorkspaceLandingMessage`); on success `Navigator.pop` dialog; on failure leave open.
  - Never call `enterNewChat`.

- [ ] **Step 1: Implement `selection_ask_ai.dart`**

Sketch (adapt imports to repo):

```dart
abstract final class SelectionAskAi {
  static Future<void> openComposeDialog(
    BuildContext context, {
    required String aiContext,
    required Workspace workspace,
    required String tabScopeId,
  }) async {
    final prefill = selectionAskAiPrefillText(aiContext);
    if (prefill.isEmpty) return;

    // Ensure chat tab store points at this workspace for submit helpers.
    final chat = context.read<ChatCubit>();
    if (chat.tabStore.activeWorkspaceId != tabScopeId) {
      chat.setActiveWorkspace(tabScopeId);
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return _SelectionAskAiDialog(
          workspace: workspace,
          initialText: prefill,
        );
      },
    );
  }
}
```

`_SelectionAskAiDialog` is a `StatefulWidget` holding `_submitting`, builds:

```dart
TpDialog(
  maxWidth: 720,
  maxHeight: 720,
  scrollable: true,
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TpDialogHeader(title: context.l10n.selectionAskAi),
      WorkspaceChatLanding(
        workspace: workspace,
        initialText: initialText,
        isSubmitting: _submitting,
        onSubmit: (message, draft) => unawaited(_submit(message, draft)),
      ),
    ],
  ),
);
```

`_submit` copies the body of `WorkspaceChatPane._submit` (persist + `submitWorkspaceLandingMessage`). After await, if `mounted` and success path completed without early return from empty message, `Navigator.of(context).pop()`.

Detect success: `submitWorkspaceLandingMessage` returns `void` — treat completion without throw as success; it already no-ops on empty. If open status failed it returns early — still pop only when a session was opened is hard without a return value. **v1:** pop after `submitWorkspaceLandingMessage` returns if the message was non-empty **and** `ChatCubit` active session id changed / workbench has the new session tab — simplest reliable approach:

```dart
final before = context.read<ChatCubit>().state.activeSessionId;
await submitWorkspaceLandingMessage(...);
if (!mounted) return;
final after = context.read<ChatCubit>().state.activeSessionId;
if (after != null && after != before) {
  Navigator.of(context).pop();
}
```

(If reuse of same active id is possible, also check `WorkbenchCubit` for new session tab — prefer whatever is most reliable after reading `submitWorkspaceLandingMessage`.)

- [ ] **Step 2: Manual smoke or widget test** — open dialog with fake workspace providers; tap not required if providers are heavy; at least compile via analyze.

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/services/selection_ai/selection_ask_ai.dart`

- [ ] **Step 3: Commit**

```bash
git add client/lib/services/selection_ai/selection_ask_ai.dart \
  client/test/services/selection_ai/selection_ask_ai_test.dart
git commit -m "$(cat <<'EOF'
feat(selection-ai): open landing Compose dialog from selection context

EOF
)"
```

---

### Task 5: Shared menu specs + editor Ask AI

**Files:**
- Create: `client/lib/services/selection_ai/selection_ai_menu_specs.dart`
- Modify: `client/lib/services/editor/file_editor_toolbar.dart`

**Interfaces:**
- Produces:
  - `List<TpActionMenuSpec> selectionAiMenuSpecs({ required AppLocalizations l10n, required bool enabled, required VoidCallback onCopyAsAiContext, required VoidCallback onAskAi })` — two items: copy (icon `Icons.auto_awesome_outlined`, label `editorCopyAsAiContext`), ask (icon `Icons.chat_outlined`, label `selectionAskAi`), both `enabled: enabled`.

- [ ] **Step 1: Add `selection_ai_menu_specs.dart`**

```dart
List<TpActionMenuSpec> selectionAiMenuSpecs({
  required AppLocalizations l10n,
  required bool enabled,
  required VoidCallback onCopyAsAiContext,
  required VoidCallback onAskAi,
}) {
  return [
    TpActionMenuSpec.item(
      icon: Icons.auto_awesome_outlined,
      label: l10n.editorCopyAsAiContext,
      enabled: enabled,
      onAction: onCopyAsAiContext,
    ),
    TpActionMenuSpec.item(
      icon: Icons.chat_outlined,
      label: l10n.selectionAskAi,
      enabled: enabled,
      onAction: onAskAi,
    ),
  ];
}
```

(If `TpActionMenuSpec.item` lacks `enabled`, match existing terminal Copy pattern: pass `enabled` if supported, else omit disabled items when `!enabled` for terminals and keep editor Always-on for copy-as-context when path != null.)

- [ ] **Step 2: Wire editor toolbar**

In `FileEditorContextMenuController.show`, after existing Copy as AI context item, add Ask AI that:

1. Builds text via `formatEditorAiContext(...)`.
2. Resolves `Workspace` from `ChatCubit` using `workspaceId` already found in the workbench loop.
3. Calls `SelectionAskAi.openComposeDialog(context, aiContext: text, workspace: ws, tabScopeId: workspaceId)`.

For editor Copy as AI context, keep clipboard behavior; optionally route label through shared specs for consistency (copy + ask as a pair inserted where the single copy-as-ai item is today).

Editor enable rule for Ask AI: same as copy-as-ai (`path != null`); if selection collapsed, still allow (format uses current line) — matches existing copy-as-ai.

- [ ] **Step 3: Analyze + existing editor tests**

Run: `cd client && flutter test test/services/editor/file_editor_ai_context_test.dart`

- [ ] **Step 4: Commit**

```bash
git add client/lib/services/selection_ai/selection_ai_menu_specs.dart \
  client/lib/services/editor/file_editor_toolbar.dart
git commit -m "$(cat <<'EOF'
feat(editor): add Ask AI context menu action

EOF
)"
```

---

### Task 6: `SelectionAskAiFabHost` + editor surface

**Files:**
- Create: `client/lib/services/selection_ai/selection_ask_ai_fab_host.dart`
- Create: `client/test/services/selection_ai/selection_ask_ai_fab_host_test.dart`
- Modify: `client/lib/pages/workbench/file_editor_surface.dart` (`_CodeEditorPane`)

**Interfaces:**
- Produces:
  - `SelectionAskAiFabHost({ required Listenable listenable, required bool Function() selectionActive, required String Function() readAiContext, required Future<void> Function(String aiContext) onAskAi, required Widget child, Offset Function(BuildContext context)? anchorGlobal, bool menuOpen = false })`
  - Shows a small `Material` / `IconButton` (`Icons.chat_outlined` or `Icons.auto_awesome`) when `selectionActive()` and `readAiContext().trim().isNotEmpty` and `!menuOpen`.
  - Debounce show until next frame after listenable notify (skip mid-drag flicker: require `selectionActive` true for one post-frame).
  - Default position: `anchorGlobal` or `Alignment.bottomRight` inset 16 inside host.
  - Tap → `onAskAi(readAiContext())`.

- [ ] **Step 1: Failing widget test**

```dart
testWidgets('FAB appears when selectionActive', (tester) async {
  final notifier = ValueNotifier(0);
  var active = false;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SelectionAskAiFabHost(
          listenable: notifier,
          selectionActive: () => active,
          readAiContext: () => active ? 'ctx' : '',
          onAskAi: (_) async {},
          child: const SizedBox.expand(),
        ),
      ),
    ),
  );
  expect(find.byIcon(Icons.chat_outlined), findsNothing);
  active = true;
  notifier.value++;
  await tester.pump();
  await tester.pump(); // post-frame
  expect(find.byIcon(Icons.chat_outlined), findsOneWidget);
});
```

(Use whichever icon the host commits to.)

- [ ] **Step 2: Implement host — Stack + Positioned button listening to `listenable`**

- [ ] **Step 3: Wrap `_CodeEditorPane` build**

```dart
return SelectionAskAiFabHost(
  listenable: controller,
  selectionActive: () => !controller.selection.isCollapsed,
  readAiContext: () => formatEditorAiContext(filePath: path, controller: controller),
  onAskAi: (ctx) async {
    final ws = /* resolve Workspace from ChatCubit by workspaceId */;
    if (ws == null) return;
    await SelectionAskAi.openComposeDialog(
      context,
      aiContext: ctx,
      workspace: ws,
      tabScopeId: workspaceId,
    );
  },
  child: CodeEditor(...),
);
```

- [ ] **Step 4: Tests PASS**

Run: `cd client && flutter test test/services/selection_ai/selection_ask_ai_fab_host_test.dart`

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/selection_ai/selection_ask_ai_fab_host.dart \
  client/test/services/selection_ai/selection_ask_ai_fab_host_test.dart \
  client/lib/pages/workbench/file_editor_surface.dart
git commit -m "$(cat <<'EOF'
feat(editor): show Ask AI FAB on non-empty selection

EOF
)"
```

---

### Task 7: Workspace shell terminal — menu + FAB

**Files:**
- Modify: `client/lib/widgets/workspace_terminal_panel.dart`
- Modify: `client/lib/widgets/workspace_terminal/workspace_terminal_view.dart` (optional: wrap with FAB at panel level instead)

**Interfaces:**
- Consumes: `buildTerminalAiContextClipboardText(surfaceLabel: 'workspace-shell', text: ...)`, `selectionAiMenuSpecs`, `SelectionAskAi`, `SelectionAskAiFabHost`
- Produces: shell context menu Copy as AI + Ask AI; FAB over active terminal

- [ ] **Step 1: Extend `_showContextMenu`**

After Copy item (or via shared specs), add AI actions:

```dart
final selText = entry.controller.readSelectionText() ?? '';
final aiContext = buildTerminalAiContextClipboardText(
  surfaceLabel: 'workspace-shell',
  text: selText,
);
final hasAi = aiContext.isNotEmpty;
// insert selectionAiMenuSpecs with onCopy → Clipboard.setData(aiContext),
// onAskAi → SelectionAskAi.openComposeDialog(...)
```

Resolve `Workspace` from `ChatCubit` by `widget.workspaceId`; `tabScopeId: widget.workspaceId`.

Handle menu result values if using value-based switch (add `'copyAi'` / `'askAi'` cases) **or** use `onAction` callbacks inside specs that close the menu (match how editor uses `onAction`). Prefer value cases consistent with existing terminal menu.

- [ ] **Step 2: Wrap active terminal body with `SelectionAskAiFabHost`**

`listenable: active.controller`, `selectionActive: () => active.controller.selectionActive`, `readAiContext: () => buildTerminalAiContextClipboardText(surfaceLabel: 'workspace-shell', text: active.controller.readSelectionText() ?? '')`.

- [ ] **Step 3: Manual / analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/widgets/workspace_terminal_panel.dart`

- [ ] **Step 4: Commit**

```bash
git add client/lib/widgets/workspace_terminal_panel.dart \
  client/lib/widgets/workspace_terminal/workspace_terminal_view.dart
git commit -m "$(cat <<'EOF'
feat(terminal): Ask AI context menu and FAB on workspace shell

EOF
)"
```

---

### Task 8: Chat workbench member terminal — menu + FAB

**Files:**
- Modify: `client/lib/pages/chat/chat_workbench_context_menu.dart`
- Modify: `client/lib/pages/chat/chat_workbench_terminal.dart`

**Interfaces:**
- Surface label: `session/<sessionId>/<memberLabel>` where `memberLabel` is member name or `taskId` available on the terminal session props (use whatever the workbench already has — inspect `ChatWorkbenchTerminal` params; prefer human-readable name, fallback taskId).

- [ ] **Step 1: Add AI cases to `showChatWorkbenchTerminalContextMenu`**

Same pattern as shell: `copyAi` / `askAi` with `buildTerminalAiContextClipboardText(surfaceLabel: 'session/$sessionId/$memberLabel', text: ...)`.

Pass `sessionId`, `memberLabel`, `workspace`, `onAskAi` into the menu function (extend signature) **or** pass a prebuilt `surfaceLabel` + callbacks to avoid ChatCubit lookups inside the menu file.

Recommended signature additions:

```dart
required String aiSurfaceLabel,
required Workspace? workspace,
required String tabScopeId,
```

When `workspace == null`, disable Ask AI / no-op.

- [ ] **Step 2: Wrap terminal view in `SelectionAskAiFabHost` in `chat_workbench_terminal.dart`**

- [ ] **Step 3: Analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/pages/chat/chat_workbench_context_menu.dart lib/pages/chat/chat_workbench_terminal.dart`

- [ ] **Step 4: Commit**

```bash
git add client/lib/pages/chat/chat_workbench_context_menu.dart \
  client/lib/pages/chat/chat_workbench_terminal.dart
git commit -m "$(cat <<'EOF'
feat(terminal): Ask AI context menu and FAB on member terminals

EOF
)"
```

---

### Task 9: Verification + polish

**Files:** touched set from Tasks 1–8

- [ ] **Step 1: Run focused tests**

```bash
cd client && flutter test \
  test/services/selection_ai/ \
  test/services/editor/file_editor_ai_context_test.dart \
  test/pages/home_workspace/workspace/workspace_chat_landing_initial_text_test.dart
```

Expected: PASS.

- [ ] **Step 2: Analyze**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

- [ ] **Step 3: Manual checklist (from spec §5)**

1. File drag-select → FAB → dialog prefill → change launch params → send → new session + first message includes context.
2. File Copy as AI context clipboard matches Ask AI body without trailing `\n\n`.
3. Workspace shell + member terminal same flow.
4. Dismiss dialog: selection retained; FAB can return.
5. Tab switch: no orphan FAB.

- [ ] **Step 4: Fixup commit if needed**

```bash
git add -u
git commit -m "$(cat <<'EOF'
fix(selection-ai): polish Ask AI after verification

EOF
)"
```

Skip empty commit if clean.

---

## Spec coverage checklist

| Spec requirement | Task |
|------------------|------|
| Shared formatters; identical clipboard/Ask body | Task 1 |
| File template unchanged | Task 1 |
| Terminal `terminal:<label>` (+ optional lines) | Task 1 (lines optional API; v1 omit at call sites) |
| Prefill `\n\n` | Task 1 + 3–4 |
| `WorkspaceChatLanding.initialText` | Task 3 |
| Dialog embeds full Landing; no `enterNewChat` | Task 4 |
| Submit → `submitWorkspaceLandingMessage` | Task 4 |
| Editor Copy as AI + Ask AI menu | Task 5 |
| Selection FAB show/hide/tap | Task 6 |
| Workspace shell menu + FAB | Task 7 |
| Member terminal menu + FAB | Task 8 |
| l10n `selectionAskAi` | Task 2 |
| Tests + manual acceptance | Task 1, 3, 6, 9 |

## Self-review notes

- No TBD placeholders left for required behavior; dialog success pop heuristic documented in Task 4.
- Terminal line ranges intentionally omitted at call sites in v1 (API still accepts them).
- `TpActionMenuSpec.enabled` — implementer must verify shared_ui API; if missing, gate by omitting items when `!hasAi`.
`)