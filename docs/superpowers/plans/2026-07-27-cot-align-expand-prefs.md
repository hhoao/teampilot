# CoT Align + Expand Preferences Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Align chain-of-thought chrome with tool/body rows, default-collapse nested reasoning and tools when CoT opens, and expose two Layout preferences for nested auto-expand.

**Architecture:** `AiMessageTheme` carries `cotExpandReasoningOnOpen` / `cotExpandToolsOnOpen` (default `false`). `AiChainOfThoughtView` reads them for nested `initiallyExpanded`, and both CoT + reasoning chrome match `AiToolGroupView` flat triggers (no bordered cards). Host prefs live on `LayoutPreferences` and are injected in `session_chat_view` Theme overlay.

**Tech Stack:** Dart / Flutter; packages `ai_message_ui`, TeamPilot `LayoutCubit` / `LayoutPreferences`, l10n ARB.

**Spec:** `docs/superpowers/specs/2026-07-27-cot-align-expand-prefs-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `client/packages/ai_message_ui/lib/src/theme.dart` | Add two Cot expand bools; `copyWith` / `lerp` / `test` factory |
| `client/packages/ai_message_ui/lib/src/parts/chain_of_thought_view.dart` | Flat ToolGroup-like chrome; pass theme-driven `initiallyExpanded` |
| `client/packages/ai_message_ui/lib/src/parts/reasoning_part_view.dart` | Flat tool-row chrome (drop bordered card) |
| `client/packages/ai_message_ui/test/chain_of_thought_view_test.dart` | Nested collapsed by default; theme overrides |
| `client/lib/models/layout_preferences.dart` | Persist two bool prefs |
| `client/lib/cubits/layout_cubit.dart` | Setters |
| `client/test/models/layout_preferences_default_test.dart` | Round-trip / default tests |
| `client/lib/l10n/app_en.arb` / `app_zh.arb` | Settings strings |
| `client/lib/pages/config/layout_appearance_in_layout_section.dart` | Appearance switches |
| `client/lib/pages/chat/session_chat_view.dart` | Theme overlay inject prefs |

---

### Task 1: Failing CoT nested-expand tests

**Files:**
- Modify: `client/packages/ai_message_ui/test/chain_of_thought_view_test.dart`

- [ ] **Step 1: Rewrite failing expectations**

Replace the two tests that assert nested content appears immediately after opening CoT. New behavior:

```dart
testWidgets(
  'Cot expand keeps nested reasoning/tools collapsed by default',
  (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AiMessageView(
            message: AiMessage(
              id: 'a1',
              role: AiRole.assistant,
              parts: [
                AiReasoningPart(text: 'secret plan'),
                AiToolCallPart(
                  toolCallId: 'c1',
                  toolName: 'shell_command',
                  result: 'ok',
                ),
                AiTextPart(text: 'all done'),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('secret plan'), findsNothing);
    expect(find.text('all done'), findsOneWidget);

    await tester.tap(find.textContaining('Thinking process'));
    await tester.pumpAndSettle();

    // Nested rows visible as triggers, payloads still hidden.
    expect(find.text('Reasoning'), findsOneWidget);
    expect(find.textContaining('shell_command'), findsOneWidget);
    expect(find.textContaining('secret plan'), findsNothing);
    expect(find.textContaining('ok'), findsNothing);

    await tester.tap(find.text('Reasoning'));
    await tester.pumpAndSettle();
    expect(find.textContaining('secret plan'), findsOneWidget);

    await tester.tap(find.textContaining('shell_command'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ok'), findsOneWidget);
  },
);

testWidgets(
  'theme cotExpand*OnOpen auto-expands nested kinds',
  (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [
            AiMessageTheme.test(
              cotExpandReasoningOnOpen: true,
              cotExpandToolsOnOpen: true,
            ),
          ],
        ),
        home: const Scaffold(
          body: AiMessageView(
            message: AiMessage(
              id: 'a1',
              role: AiRole.assistant,
              parts: [
                AiReasoningPart(text: 'secret plan'),
                AiToolCallPart(
                  toolCallId: 'c1',
                  toolName: 'shell_command',
                  result: 'ok',
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.textContaining('Thinking process'));
    await tester.pumpAndSettle();

    expect(find.textContaining('secret plan'), findsOneWidget);
    expect(find.textContaining('ok'), findsOneWidget);
  },
);
```

Delete or rewrite `multi-tool Cot expands all tool payloads…` so it asserts: open CoT → both tool result strings absent; tap each tool row → that result appears. Do not leave an ambiguous “rename/remove if redundant”. Keep `R/T-only turn is a single Cot…` unchanged.

Optional (nice-to-have, not required): a third widget test with only `cotExpandReasoningOnOpen: true` (reasoning body visible, tool result still hidden) to pin independent flags.

Default English strings in package tests: `Reasoning` / `Thinking process` come from `AiMessageStrings` defaults — confirm against `strings.dart` before writing (`reasoning`, `formatThinkingProcessSteps`).

- [ ] **Step 2: Run tests — expect FAIL**

```bash
cd client/packages/ai_message_ui && flutter test test/chain_of_thought_view_test.dart
```

Expected: FAIL — nested payloads still auto-open, and/or `AiMessageTheme.test` rejects new named args.

- [ ] **Step 3: Commit test-only change**

```bash
git add client/packages/ai_message_ui/test/chain_of_thought_view_test.dart
git commit -m "$(cat <<'EOF'
test: expect CoT nested steps collapsed by default

EOF
)"
```

---

### Task 2: Theme flags + nested initiallyExpanded from theme

**Files:**
- Modify: `client/packages/ai_message_ui/lib/src/theme.dart`
- Modify: `client/packages/ai_message_ui/lib/src/parts/chain_of_thought_view.dart`

- [ ] **Step 1: Add theme fields**

In `AiMessageTheme`:

```dart
this.cotExpandReasoningOnOpen = false,
this.cotExpandToolsOnOpen = false,
```

Wire through constructor, `AiMessageTheme.test`, `copyWith`, and `lerp` (bool: `t < 0.5 ? this : other`).

- [ ] **Step 2: Drive nested expand from theme**

In `_buildInnerPart`:

```dart
Widget _buildInnerPart(AiMessagePart part) {
  final aiTheme = AiMessageTheme.of(context);
  return switch (part) {
    AiReasoningPart() => AiReasoningPartView(
      part: part,
      initiallyExpanded: aiTheme.cotExpandReasoningOnOpen,
    ),
    AiToolCallPart() => AiToolCallPartView(
      part: part,
      initiallyExpanded: aiTheme.cotExpandToolsOnOpen,
    ),
    _ => const SizedBox.shrink(),
  };
}
```

- [ ] **Step 3: Re-run CoT tests**

```bash
cd client/packages/ai_message_ui && flutter test test/chain_of_thought_view_test.dart
```

Expected: PASS for expand behavior (visual chrome still bordered — OK for this task).

- [ ] **Step 4: Commit**

```bash
git add client/packages/ai_message_ui/lib/src/theme.dart \
  client/packages/ai_message_ui/lib/src/parts/chain_of_thought_view.dart
git commit -m "$(cat <<'EOF'
fix: default-collapse CoT nested steps via theme flags

EOF
)"
```

---

### Task 3: Flat CoT + reasoning chrome (align with ToolGroup)

**Files:**
- Modify: `client/packages/ai_message_ui/lib/src/parts/chain_of_thought_view.dart`
- Modify: `client/packages/ai_message_ui/lib/src/parts/reasoning_part_view.dart`

- [ ] **Step 1: Restyle `AiChainOfThoughtView` like `AiToolGroupView`**

Remove outer `DecoratedBox` / border. Structure:

```dart
return Padding(
  padding: EdgeInsets.only(bottom: aiTheme.partSpacing),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // trigger row: psychology icon + label + chevron (same padding as ToolGroup)
      SelectionContainer.disabled(... GestureDetector ...),
      if (_open)
        Padding(
          padding: const EdgeInsets.only(left: 8, top: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final part in widget.parts) _buildInnerPart(part),
            ],
          ),
        ),
    ],
  ),
);
```

Keep semantics / AnimatedSize optional — ToolGroup skips AnimatedSize on the list; prefer matching ToolGroup (no AnimatedSize on outer list) for consistency, keep AnimatedSize on reasoning body if already there.

- [ ] **Step 2: Restyle `AiReasoningPartView` like `AiToolCallPartView`**

Drop bordered `DecoratedBox`. Flat Column:

- Trigger row: icon + `strings.reasoning` + chevron
- Expanded body: left indent `24` (match tool payload), `maxHeight: 256` scroll + `AiTextPartView`

Keep `initiallyExpanded` API unchanged.

- [ ] **Step 3: Re-run package tests**

```bash
cd client/packages/ai_message_ui && flutter test
```

Expected: PASS. If any test finds bordered widgets or exact padding, update finders only as needed.

- [ ] **Step 4: Commit**

```bash
git add client/packages/ai_message_ui/lib/src/parts/chain_of_thought_view.dart \
  client/packages/ai_message_ui/lib/src/parts/reasoning_part_view.dart
git commit -m "$(cat <<'EOF'
fix: align CoT and reasoning chrome with tool rows

EOF
)"
```

---

### Task 4: LayoutPreferences + cubit

**Files:**
- Modify: `client/lib/models/layout_preferences.dart`
- Modify: `client/lib/cubits/layout_cubit.dart`
- Modify: `client/test/models/layout_preferences_default_test.dart`

- [ ] **Step 1: Failing prefs test**

Add to `layout_preferences_default_test.dart`:

```dart
test('cot expand prefs default false and round-trip', () {
  expect(const LayoutPreferences().cotExpandReasoningOnOpen, isFalse);
  expect(const LayoutPreferences().cotExpandToolsOnOpen, isFalse);
  expect(LayoutPreferences.fromJson(const {}).cotExpandReasoningOnOpen, isFalse);

  final parsed = LayoutPreferences.fromJson(const {
    'cotExpandReasoningOnOpen': true,
    'cotExpandToolsOnOpen': true,
  });
  expect(parsed.cotExpandReasoningOnOpen, isTrue);
  expect(parsed.cotExpandToolsOnOpen, isTrue);
  expect(parsed.toJson()['cotExpandReasoningOnOpen'], isTrue);
  expect(parsed.toJson()['cotExpandToolsOnOpen'], isTrue);
});
```

- [ ] **Step 2: Run — expect FAIL**

```bash
cd client && flutter test test/models/layout_preferences_default_test.dart
```

- [ ] **Step 3: Implement prefs fields**

Add to `LayoutPreferences`:

```dart
this.cotExpandReasoningOnOpen = false,
this.cotExpandToolsOnOpen = false,
```

Update: constructor fields, `fromJson` (`as bool? ?? false`), `copyWith`, `toJson`, and **every** full `LayoutPreferences(...)` rebuild (including `withAtLeastOneToolVisible`).

Cubit:

```dart
Future<void> setCotExpandReasoningOnOpen(bool value) =>
    _save(state.preferences.copyWith(cotExpandReasoningOnOpen: value));

Future<void> setCotExpandToolsOnOpen(bool value) =>
    _save(state.preferences.copyWith(cotExpandToolsOnOpen: value));
```

- [ ] **Step 4: Run prefs test — PASS**

```bash
cd client && flutter test test/models/layout_preferences_default_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/layout_preferences.dart \
  client/lib/cubits/layout_cubit.dart \
  client/test/models/layout_preferences_default_test.dart
git commit -m "$(cat <<'EOF'
feat: add CoT nested expand layout preferences

EOF
)"
```

---

### Task 5: Settings UI + l10n

**Files:**
- Modify: `client/lib/l10n/app_en.arb`
- Modify: `client/lib/l10n/app_zh.arb`
- Modify: `client/lib/pages/config/layout_appearance_in_layout_section.dart`

- [ ] **Step 1: Add ARB keys** (near `appearance` / markdown open keys)

`app_en.arb`:

```json
"thinkingProcessSectionTitle": "Thinking process",
"cotExpandReasoningOnOpenTitle": "Expand reasoning when opening",
"cotExpandReasoningOnOpenDescription": "When you open a thinking-process block, expand nested reasoning steps automatically.",
"cotExpandToolsOnOpenTitle": "Expand tools when opening",
"cotExpandToolsOnOpenDescription": "When you open a thinking-process block, expand nested tool call details automatically."
```

`app_zh.arb`:

```json
"thinkingProcessSectionTitle": "思考过程",
"cotExpandReasoningOnOpenTitle": "打开时展开推理",
"cotExpandReasoningOnOpenDescription": "展开「思考过程」时，自动展开内部推理步骤。",
"cotExpandToolsOnOpenTitle": "打开时展开工具",
"cotExpandToolsOnOpenDescription": "展开「思考过程」时，自动展开内部工具调用详情。"
```

- [ ] **Step 2: Regenerate l10n + warmup glyphs**

```bash
cd client && flutter gen-l10n && dart run tool/gen_warmup_glyphs.dart
```

Commit regenerated `app_localizations*.dart` and `warmup_glyphs.g.dart` if they change.

- [ ] **Step 3: Appearance section UI**

After the markdown / appearance preference block (before terminal theme or at end of appearance column), add:

```dart
TpSectionHeader(title: l10n.thinkingProcessSectionTitle),
TpPreferenceRow(
  title: l10n.cotExpandReasoningOnOpenTitle,
  subtitle: l10n.cotExpandReasoningOnOpenDescription,
  trailing: Switch(
    value: context.select<LayoutCubit, bool>(
      (c) => c.state.preferences.cotExpandReasoningOnOpen,
    ),
    onChanged: controller.setCotExpandReasoningOnOpen,
  ),
  showDividerBelow: true,
),
TpPreferenceRow(
  title: l10n.cotExpandToolsOnOpenTitle,
  subtitle: l10n.cotExpandToolsOnOpenDescription,
  trailing: Switch(
    value: context.select<LayoutCubit, bool>(
      (c) => c.state.preferences.cotExpandToolsOnOpen,
    ),
    onChanged: controller.setCotExpandToolsOnOpen,
  ),
  showDividerBelow: true,
),
```

If the appearance `BlocSelector` tuple is already crowded, prefer `context.select` on the Switch values (as above) rather than expanding the big selector tuple.

- [ ] **Step 4: Analyze the section file**

```bash
cd client && dart analyze lib/pages/config/layout_appearance_in_layout_section.dart lib/l10n/
```

Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb \
  client/lib/l10n/app_localizations*.dart \
  client/lib/pages/config/layout_appearance_in_layout_section.dart
git commit -m "$(cat <<'EOF'
feat: add thinking-process expand toggles in appearance settings

EOF
)"
```

---

### Task 6: Inject prefs into chat AiMessageTheme

**Files:**
- Modify: `client/lib/pages/chat/session_chat_view.dart`

- [ ] **Step 1: Wire Theme overlay**

In the existing `AiMessageTheme.of(context).copyWith(...)` (~line 1013), add:

```dart
cotExpandReasoningOnOpen:
    context.read<LayoutCubit>().state.preferences.cotExpandReasoningOnOpen,
cotExpandToolsOnOpen:
    context.read<LayoutCubit>().state.preferences.cotExpandToolsOnOpen,
```

**Important:** `build` must rebuild when these prefs change. If the surrounding widget does not already listen to `LayoutCubit`, wrap the Theme (or parent) with:

```dart
BlocSelector<LayoutCubit, LayoutState, (bool, bool)>(
  selector: (s) => (
    s.preferences.cotExpandReasoningOnOpen,
    s.preferences.cotExpandToolsOnOpen,
  ),
  builder: (context, cotExpand) {
    final (expandReasoning, expandTools) = cotExpand;
    return Theme(
      data: Theme.of(context).copyWith(
        extensions: [
          // ... existing filter ...
          AiMessageTheme.of(context).copyWith(
            // ... existing tokens ...
            cotExpandReasoningOnOpen: expandReasoning,
            cotExpandToolsOnOpen: expandTools,
          ),
        ],
      ),
      child: /* existing AiMessageStringsScope + history */,
    );
  },
);
```

Do **not** duplicate wiring in `session_history_thread.dart` unless it builds an independent `AiMessageTheme` that does not inherit this overlay.

- [ ] **Step 2: Analyze**

```bash
cd client && dart analyze lib/pages/chat/session_chat_view.dart
```

- [ ] **Step 3: Commit**

```bash
git add client/lib/pages/chat/session_chat_view.dart
git commit -m "$(cat <<'EOF'
feat: inject CoT expand preferences into chat message theme

EOF
)"
```

---

### Task 7: Verification

- [ ] **Step 1: Package + app tests**

```bash
cd client/packages/ai_message_ui && flutter test
cd ../../ && flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test --exclude-tags integration test/models/layout_preferences_default_test.dart
```

Expected: all green for touched suites; analyze clean for changed files.

- [ ] **Step 2: Manual smoke (optional but recommended)**

1. Open a session with CoT (reasoning + tools).
2. Expand「思考过程」→ nested rows collapsed; left edge aligns with assistant text/tools.
3. Toggle both Appearance switches on → reopen CoT → nested auto-expand.
4. Toggle off → nested stay collapsed again.

- [ ] **Step 3: Final commit only if Step 1 left uncommitted fixups**

Otherwise done.

---

## Out of scope (do not implement)

- Outer CoT default-open
- Per-message expand persistence
- Redesigning user/assistant text bubbles into cards
- Changing `AiToolGroupView` outside CoT
- Transcript parsing changes
