# Tool Card Whole-Card Expand + Shell Mini-Preview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Whole-card tap toggles edit/shell History cards (basename + line gutter still open files); shell collapsed state always shows mini `$ command` + ≤5 output lines, expanding in the same panel.

**Architecture:** Add shared `AiExpandableToolCard` + preview/height constants under `ai_message_ui/lib/src/parts/`. Wrap presentational `EditToolCard` with it; extract/refactor shell into an in-card body (no outer `_ShellTerminalPanel`). Narrow `SelectionContainer.disabled` so expanded bodies are selectable.

**Tech Stack:** Dart / Flutter; package `ai_message_ui` (depends on `ai_message_core`).

**Spec:** `docs/superpowers/specs/2026-07-30-tool-card-expand-click-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `client/packages/ai_message_ui/lib/src/parts/expandable_tool_card.dart` | `AiExpandableToolCard`, `kAiToolCardPreviewLines`, `kAiToolCardExpandedMaxHeight`; helpers `previewShellOutputLines` optional |
| `client/packages/ai_message_ui/lib/src/edit/edit_tool_card.dart` | Use shared constants; wrap with expandable card; remove redundant status/chevron toggles; keep basename + gutter exclusive |
| `client/packages/ai_message_ui/lib/src/parts/tool_call_part_view.dart` | Shell in-card chrome; drop outer shell `AnimatedSize` panel; narrow selection dead-zone; gate shared args/`Result:` to non-shell/non-edit |
| `client/packages/ai_message_ui/lib/ai_message_ui.dart` | Export expandable card + constants if hosts need them (optional) |
| `client/packages/ai_message_ui/test/tool_call_edit_target_test.dart` | Tap-diff toggles; basename/gutter no-toggle |
| `client/packages/ai_message_ui/test/tool_call_shell_target_test.dart` | Collapsed shows command/output; tap panel toggles; update old assertions |

**Selection strategy (fixed for this plan):** Prefer “only disable header + collapsed preview”; expanded scroll body sits in a selectable region (sibling outside `SelectionContainer.disabled`, or disable only the header row). Do **not** leave the entire shell/edit card inside a permanent selection dead zone when expanded.

**Important:** Today `tool_call_part_view.dart` wraps shell/edit triggers in an outer `SelectionContainer.disabled`. Task 3 must **lift or narrow that wrapper** so expanded shell/edit bodies are selectable. Task 2 may prepare edit-card internals, but the outer wrap fix lands with Task 3’s shell refactor (same file).

Also update `tool_call_edit_target_test.dart` Bash regression that still expects collapsed shell to hide the command (do this in Task 3 when shell chrome changes).

---

### Task 1: Shared `AiExpandableToolCard` + constants (TDD)

**Files:**
- Create: `client/packages/ai_message_ui/lib/src/parts/expandable_tool_card.dart`
- Create: `client/packages/ai_message_ui/test/expandable_tool_card_test.dart`
- Modify: `client/packages/ai_message_ui/lib/ai_message_ui.dart` (export)

- [ ] **Step 1: Failing widget test**

```dart
testWidgets('card tap calls onToggle; child exclusive tap does not', (tester) async {
  var toggles = 0;
  var childTaps = 0;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AiExpandableToolCard(
          onToggle: () => toggles++,
          child: Column(
            children: [
              const Text('card-body'),
              GestureDetector(
                onTap: () => childTaps++,
                behavior: HitTestBehavior.opaque,
                child: const Text('exclusive'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('card-body'));
  await tester.pump();
  expect(toggles, 1);
  await tester.tap(find.text('exclusive'));
  await tester.pump();
  expect(childTaps, 1);
  expect(toggles, 1); // exclusive wins; parent does not also fire
});
```

- [ ] **Step 2: FAIL then implement**

```dart
const kAiToolCardPreviewLines = 5;
const kAiToolCardExpandedMaxHeight = 320.0;

class AiExpandableToolCard extends StatelessWidget {
  const AiExpandableToolCard({
    required this.onToggle,
    required this.child,
    super.key,
  });
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onToggle,
      child: child,
    );
  }
}

/// First [kAiToolCardPreviewLines] lines of [text] (split on `\n`).
String previewToolCardText(String text, {int lines = kAiToolCardPreviewLines}) { … }
```

- [ ] **Step 3: PASS + Commit**

```bash
cd client/packages/ai_message_ui && flutter test test/expandable_tool_card_test.dart
git add client/packages/ai_message_ui/lib/src/parts/expandable_tool_card.dart \
  client/packages/ai_message_ui/test/expandable_tool_card_test.dart \
  client/packages/ai_message_ui/lib/ai_message_ui.dart
git commit -m "$(cat <<'EOF'
feat(ai_message_ui): add shared expandable tool card shell

EOF
)"
```

---

### Task 2: Edit card whole-card tap (TDD)

**Files:**
- Modify: `client/packages/ai_message_ui/lib/src/edit/edit_tool_card.dart`
- Modify: `client/packages/ai_message_ui/test/tool_call_edit_target_test.dart`

- [ ] **Step 1: Failing tests**

```dart
testWidgets('tap diff panel toggles expand', (tester) async { … });
testWidgets('tap basename opens file and does not toggle', (tester) async {
  // pump collapsed; tap basename; expect onOpenFile called;
  // expect still collapsed (CHANGED still hidden if using long hunk)
});
testWidgets('tap line gutter opens file and does not toggle', (tester) async {
  // find by line number text '10' in gutter; tap; expect open, no toggle
});
```

Reuse existing StrReplace fixtures; for toggle test use the long old/new from expand test.

- [ ] **Step 2: Implement**

Inside `EditToolCardHost.build`, wrap presentational `EditToolCard` with:

```dart
return AiExpandableToolCard(
  onToggle: widget.onToggle,
  child: EditToolCard(...),
);
```

- Replace `_previewCap` / `_expandedMaxHeight` with shared constants.
- Remove redundant `GestureDetector(onTap: onToggle)` on status icon / chevron (keep chevron visual).
- Keep basename + gutter exclusive `onOpenFile` detectors.
- Structure selection: wrap **header row + collapsed-only chrome** in `SelectionContainer.disabled` if needed; ensure expanded `_EditDiffPanel` text can be selected when `open`.

- [ ] **Step 3: PASS + Commit**

```bash
cd client/packages/ai_message_ui && flutter test test/tool_call_edit_target_test.dart
git commit -m "$(cat <<'EOF'
feat(ai_message_ui): whole-card tap toggles edit tool cards

EOF
)"
```

---

### Task 3: Shell always-visible mini panel + in-card expand (TDD)

**Files:**
- Modify: `client/packages/ai_message_ui/lib/src/parts/tool_call_part_view.dart`
- Optionally create: `client/packages/ai_message_ui/lib/src/parts/shell_tool_card.dart` if extracting keeps `tool_call_part_view` under control
- Modify: `client/packages/ai_message_ui/test/tool_call_shell_target_test.dart`

- [ ] **Step 1: Update / add failing shell tests**

Rewrite first test expectations:

```dart
// Collapsed: summary visible AND command + output preview visible
expect(find.textContaining('Check worktree git state'), findsOneWidget);
expect(find.textContaining('git status --short'), findsOneWidget); // was findsNothing
expect(find.textContaining('M client/lib/a.dart'), findsOneWidget); // was findsNothing

// Tap mini panel / header area (not only chevron) toggles — if already showing
// short output, use a longer result (≥6 lines) to assert truncation then expand
```

Add:

```dart
testWidgets('collapsed shell output capped at 5 lines', …);
testWidgets('tap shell mini panel toggles full output', …);
testWidgets('initiallyExpanded shows full shell output', …);
```

- [ ] **Step 2: Implement shell card**

1. Replace `_ShellToolTrigger` + outer `_ShellTerminalPanel` with a single `_ShellToolCard` (or `ShellToolCard`) wrapped in `AiExpandableToolCard`:
   - Header row (status, terminal icon, summary, chevron visual)
   - Always-mounted panel: `$` + command; if result non-blank, show `previewToolCardText(result)` when `!open`, else full result in `SingleChildScrollView(maxHeight: kAiToolCardExpandedMaxHeight)`
2. In `AiToolCallPartView.build`:

```dart
if (shellTarget != null)
  AiExpandableToolCard / ShellToolCard(..., open: _open, onToggle: _toggleExpanded)
else if (editTarget != null)
  EditToolCardHost(...)
else
  // summary / legacy triggers

if (_open && shellTarget == null && editTarget == null)
  // existing args + Result: AnimatedSize column
```

3. Narrow `SelectionContainer.disabled` so it does not cover expanded shell/edit bodies.

4. Preserve error coloring for `part.isError` on output (from prior shell spec).

- [ ] **Step 3: PASS + Commit**

```bash
cd client/packages/ai_message_ui && flutter test \
  test/tool_call_shell_target_test.dart \
  test/tool_call_edit_target_test.dart \
  test/tool_call_file_target_test.dart
git commit -m "$(cat <<'EOF'
feat(ai_message_ui): always-visible shell mini panel with whole-card expand

EOF
)"
```

---

### Task 4: Regression polish

**Files:** any tests still asserting collapsed shell hides command

- [ ] **Step 1: Grep and fix**

```bash
rg -n "git status --short|findsNothing|ShellTerminal|_ShellToolTrigger|expand_more" \
  client/packages/ai_message_ui/test -g'*test*.dart'
```

- [ ] **Step 2: Run suites**

```bash
cd client/packages/ai_message_ui && flutter test test/tool_call_*.dart test/expandable_tool_card_test.dart
```

- [ ] **Step 3: Commit only if fixes**

```bash
git commit -m "$(cat <<'EOF'
test(ai_message_ui): align shell/edit card regressions with expand-click

EOF
)"
```

---

## Out of scope

- Read / summary / legacy redesign
- Shell syntax highlight / exit-code chips
- CoT behavior changes
- Host app wiring (no change required)
