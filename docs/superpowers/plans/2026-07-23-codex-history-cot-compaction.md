# Codex History Cot Compaction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Coalesce adjacent assistant History fragments into one `AiMessage` per turn, and default-collapse contiguous reasoning + tool-call parts into a single「思考过程 · N 步」row so Codex (and other CLIs) stop rendering long R→T→R→T lists.

**Architecture:** Shared `coalesceAdjacentAssistants` inside `finalizeAiMessagesForHistory` (`ai_message_core`). Cot-aware `groupMessageParts` + `AiRenderChainOfThought` + collapsed Cot widget in `ai_message_ui`, with force-open inners on expand. TeamPilot wires new `AiMessageStrings` via existing l10n.

**Tech Stack:** Dart / Flutter packages `ai_message_core`, `ai_message_ui`; TeamPilot History adapters + `session_chat_view` strings scope.

**Spec:** `docs/superpowers/specs/2026-07-23-codex-history-cot-compaction-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `client/packages/ai_message_core/lib/src/message.dart` | `coalesceAdjacentAssistants` + call from `finalizeAiMessagesForHistory` |
| `client/packages/ai_message_core/test/coalesce_assistants_test.dart` | Coalesce unit tests |
| `client/packages/ai_message_core/test/tool_status_export_test.dart` | Keep passing; may gain coalesce+finalize combo case |
| `client/packages/ai_message_ui/lib/src/part_grouping.dart` | Cot scan + extract consecutive grouping for Cot inners |
| `client/packages/ai_message_ui/lib/src/parts/chain_of_thought_view.dart` | Default-collapsed Cot chrome |
| `client/packages/ai_message_ui/lib/src/parts/reasoning_part_view.dart` | `initiallyExpanded` for Cot inners |
| `client/packages/ai_message_ui/lib/src/parts/tool_call_part_view.dart` | `initiallyExpanded` for Cot inners |
| `client/packages/ai_message_ui/lib/src/part_registry.dart` | Cot node + optional builder; pass `initiallyExpanded` when building Cot children |
| `client/packages/ai_message_ui/lib/src/strings.dart` | `thinkingProcess` + `formatThinkingProcessSteps` |
| `client/packages/ai_message_ui/lib/ai_message_ui.dart` | Export Cot view if needed |
| `client/packages/ai_message_ui/test/part_grouping_test.dart` | Update for Cot nodes |
| `client/packages/ai_message_ui/test/chain_of_thought_view_test.dart` | Collapsed by default; expand shows content |
| `client/test/services/cli/registry/capabilities/history/codex_ai_transcript_test.dart` | Expect coalesced message counts / shapes |
| `client/lib/l10n/app_en.arb` / `app_zh.arb` | New Cot strings |
| `client/lib/pages/chat/session_chat_view.dart` | Wire new `AiMessageStrings` fields |

No Codex adapter rewrite required for v1 (coalesce at finalize is enough).

---

### Task 1: Coalesce adjacent assistants (TDD)

**Files:**
- Modify: `client/packages/ai_message_core/lib/src/message.dart`
- Create: `client/packages/ai_message_core/test/coalesce_assistants_test.dart`

- [ ] **Step 1: Write failing tests**

```dart
import 'package:ai_message_core/ai_message_core.dart';
import 'package:test/test.dart';

void main() {
  group('coalesceAdjacentAssistants', () {
    test('merges adjacent assistants and keeps first id/createdAt', () {
      final t0 = DateTime.utc(2026, 7, 23, 1);
      final t1 = DateTime.utc(2026, 7, 23, 2);
      final out = coalesceAdjacentAssistants([
        AiMessage(
          id: 'u1',
          role: AiRole.user,
          parts: const [AiTextPart(text: 'go')],
        ),
        AiMessage(
          id: 'a1',
          role: AiRole.assistant,
          createdAt: t0,
          parts: const [AiReasoningPart(text: 'think')],
        ),
        AiMessage(
          id: 'a2',
          role: AiRole.assistant,
          createdAt: t1,
          parts: [
            AiToolCallPart(toolCallId: 'c1', toolName: 'shell_command'),
          ],
        ),
        AiMessage(
          id: 'a3',
          role: AiRole.assistant,
          parts: const [AiTextPart(text: 'done')],
        ),
      ]);

      expect(out, hasLength(2));
      expect(out[1].id, 'a1');
      expect(out[1].createdAt, t0);
      expect(out[1].parts, hasLength(3));
      expect(out[1].parts[0], isA<AiReasoningPart>());
      expect(out[1].parts[1], isA<AiToolCallPart>());
      expect(out[1].parts[2], isA<AiTextPart>());
    });

    test('does not merge across user messages', () {
      final out = coalesceAdjacentAssistants([
        AiMessage(
          id: 'a1',
          role: AiRole.assistant,
          parts: const [AiTextPart(text: 'one')],
        ),
        AiMessage(
          id: 'u1',
          role: AiRole.user,
          parts: const [AiTextPart(text: 'again')],
        ),
        AiMessage(
          id: 'a2',
          role: AiRole.assistant,
          parts: const [AiTextPart(text: 'two')],
        ),
      ]);
      expect(out.map((m) => m.id).toList(), ['a1', 'u1', 'a2']);
    });

    test('does not merge across system messages', () {
      final out = coalesceAdjacentAssistants([
        AiMessage(
          id: 'a1',
          role: AiRole.assistant,
          parts: const [AiTextPart(text: 'one')],
        ),
        AiMessage(
          id: 's1',
          role: AiRole.system,
          parts: const [AiTextPart(text: 'note')],
        ),
        AiMessage(
          id: 'a2',
          role: AiRole.assistant,
          parts: const [AiTextPart(text: 'two')],
        ),
      ]);
      expect(out.map((m) => m.id).toList(), ['a1', 's1', 'a2']);
    });
  });

  test('finalizeAiMessagesForHistory coalesces then normalizes tools', () {
    final out = finalizeAiMessagesForHistory([
      AiMessage(
        id: 'a1',
        role: AiRole.assistant,
        parts: [
          AiToolCallPart(
            toolCallId: 't1',
            toolName: 'Bash',
            status: AiToolCallStatus.complete,
          ),
        ],
      ),
      AiMessage(
        id: 'a2',
        role: AiRole.assistant,
        parts: const [AiTextPart(text: 'ok')],
      ),
    ]);
    expect(out, hasLength(1));
    expect(out.single.id, 'a1');
    final tool = out.single.parts.first as AiToolCallPart;
    expect(tool.status, AiToolCallStatus.incomplete);
    expect(out.single.parts.last, isA<AiTextPart>());
  });
}
```

- [ ] **Step 2: Run tests — expect FAIL**

```bash
cd client/packages/ai_message_core && dart test test/coalesce_assistants_test.dart
```

Expected: compile/runtime fail — `coalesceAdjacentAssistants` undefined, and/or finalize does not merge.

- [ ] **Step 3: Implement coalesce + wire into finalize**

In `message.dart`, add:

```dart
/// Merge runs of adjacent [AiRole.assistant] messages (cut on user/system).
/// Keeps the first message's id, createdAt, and status; concatenates parts.
List<AiMessage> coalesceAdjacentAssistants(List<AiMessage> messages) {
  if (messages.isEmpty) return const [];
  final out = <AiMessage>[];
  for (final msg in messages) {
    if (out.isNotEmpty &&
        out.last.role == AiRole.assistant &&
        msg.role == AiRole.assistant) {
      final prev = out.last;
      out[out.length - 1] = prev.copyWith(
        parts: [...prev.parts, ...msg.parts],
      );
    } else {
      out.add(msg);
    }
  }
  return out;
}
```

Change `finalizeAiMessagesForHistory` to:

```dart
List<AiMessage> finalizeAiMessagesForHistory(List<AiMessage> messages) {
  final coalesced = coalesceAdjacentAssistants(messages);
  return [
    for (final message in coalesced)
      message.copyWith(
        parts: [
          for (final part in message.parts)
            if (part is AiToolCallPart &&
                part.result == null &&
                part.status == AiToolCallStatus.complete &&
                !part.isError)
              part.copyWith(status: AiToolCallStatus.incomplete)
            else if (part is AiToolCallPart &&
                part.result == null &&
                part.status == AiToolCallStatus.running)
              part.copyWith(status: AiToolCallStatus.incomplete)
            else
              part,
        ],
      ),
  ];
}
```

- [ ] **Step 4: Run tests — expect PASS**

```bash
cd client/packages/ai_message_core && dart test test/coalesce_assistants_test.dart test/tool_status_export_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add client/packages/ai_message_core/lib/src/message.dart \
  client/packages/ai_message_core/test/coalesce_assistants_test.dart
git commit -m "$(cat <<'EOF'
feat(ai_message_core): coalesce adjacent assistant history turns

EOF
)"
```

---

### Task 2: Update Codex transcript expectations

**Files:**
- Modify: `client/test/services/cli/registry/capabilities/history/codex_ai_transcript_test.dart`
- (Optional fixture only if assertions need a clearer R→T→R→T sample; existing fixtures are enough)

- [ ] **Step 1: Write/adjust failing assertions for coalesced shapes**

Update expectations:

1. **basic.jsonl:** `hasLength(2)` — user + one assistant with tool then text (not 3). Assert `messages[1].parts` has tool then text; keep first assistant id stable if asserted.
2. **reasoning_and_tools:** Assert exactly **one** assistant after the user (`messages` length 2), with parts ordered reasoning → tool → text.
3. **reasoning_dual_write:** `hasLength(2)` (not 4); still one `AiReasoningPart`; tool + text on the same assistant as reasoning.

Example for dual_write:

```dart
expect(messages, hasLength(2));
final asst = messages[1];
expect(asst.role, AiRole.assistant);
expect(asst.parts.whereType<AiReasoningPart>(), hasLength(1));
expect(asst.parts.whereType<AiToolCallPart>().single.toolCallId, 'call_demo1');
expect(asst.parts.whereType<AiTextPart>().single.text, 'I will inspect the plan first.');
```

- [ ] **Step 2: Run — expect FAIL before Task 1 lands in same branch; after Task 1, fix any remaining mismatches**

```bash
cd client && flutter test test/services/cli/registry/capabilities/history/codex_ai_transcript_test.dart
```

If Task 1 is already merged in this branch, this step should go red only until assertions are updated, then green.

- [ ] **Step 3: Commit**

```bash
git add client/test/services/cli/registry/capabilities/history/codex_ai_transcript_test.dart
git commit -m "$(cat <<'EOF'
test(codex): expect coalesced assistant turns in history parse

EOF
)"
```

---

### Task 3: Cot-aware `groupMessageParts` (TDD)

**Files:**
- Modify: `client/packages/ai_message_ui/lib/src/part_grouping.dart`
- Modify: `client/packages/ai_message_ui/test/part_grouping_test.dart`

- [ ] **Step 1: Rewrite grouping tests for Cot scan**

```dart
import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('wraps contiguous R|T runs in Cot; text stays outside', () {
    final nodes = groupMessageParts([
      const AiReasoningPart(text: 'r1'),
      AiToolCallPart(toolCallId: '1', toolName: 'shell_command'),
      const AiReasoningPart(text: 'r2'),
      AiToolCallPart(toolCallId: '2', toolName: 'shell_command'),
      const AiTextPart(text: 'done'),
    ]);
    expect(nodes, hasLength(2));
    expect(nodes[0], isA<AiRenderChainOfThought>());
    expect((nodes[0] as AiRenderChainOfThought).parts, hasLength(4));
    expect(nodes[1], isA<AiRenderPart>());
  });

  test('opens a second Cot after mid-turn text', () {
    final nodes = groupMessageParts([
      const AiReasoningPart(text: 'a'),
      const AiTextPart(text: 'mid'),
      AiToolCallPart(toolCallId: '1', toolName: 'Read'),
      const AiTextPart(text: 'end'),
    ]);
    expect(nodes, hasLength(4));
    expect(nodes[0], isA<AiRenderChainOfThought>());
    expect(nodes[1], isA<AiRenderPart>());
    expect(nodes[2], isA<AiRenderChainOfThought>());
    expect(nodes[3], isA<AiRenderPart>());
  });

  test('pure text has no Cot', () {
    final nodes = groupMessageParts([const AiTextPart(text: 'hi')]);
    expect(nodes.single, isA<AiRenderPart>());
  });

  test('groupConsecutiveParts still groups tools and reasoning', () {
    final nodes = groupConsecutiveParts([
      AiToolCallPart(toolCallId: '1', toolName: 'Read'),
      AiToolCallPart(toolCallId: '2', toolName: 'Grep'),
      const AiReasoningPart(text: 'a'),
      const AiReasoningPart(text: 'b'),
    ]);
    expect(nodes[0], isA<AiRenderToolGroup>());
    expect(nodes[1], isA<AiRenderReasoningGroup>());
  });
}
```

- [ ] **Step 2: Run — expect FAIL**

```bash
cd client/packages/ai_message_ui && flutter test test/part_grouping_test.dart
```

- [ ] **Step 3: Implement grouping**

In `part_grouping.dart`:

1. Add `AiRenderChainOfThought` holding `List<AiMessagePart> parts`.
2. Rename today’s algorithm to `groupConsecutiveParts`.
3. Implement `groupMessageParts` as left-to-right Cot scan; non–R/T parts become `AiRenderPart` (text/other). Cot children are raw parts (inner consecutive grouping happens at render time).

```dart
final class AiRenderChainOfThought extends AiRenderNode {
  const AiRenderChainOfThought(this.parts);
  final List<AiMessagePart> parts;
}

bool _isCotPart(AiMessagePart part) =>
    part is AiReasoningPart || part is AiToolCallPart;

List<AiRenderNode> groupMessageParts(List<AiMessagePart> parts) {
  final out = <AiRenderNode>[];
  var i = 0;
  while (i < parts.length) {
    if (_isCotPart(parts[i])) {
      final run = <AiMessagePart>[];
      while (i < parts.length && _isCotPart(parts[i])) {
        run.add(parts[i]);
        i++;
      }
      out.add(AiRenderChainOfThought(run));
      continue;
    }
    out.add(AiRenderPart(parts[i]));
    i++;
  }
  return out;
}

/// Existing consecutive tool/reasoning grouping (Cot expanded inners).
List<AiRenderNode> groupConsecutiveParts(List<AiMessagePart> parts) {
  // move current groupMessageParts body here unchanged
}
```

- [ ] **Step 4: Run — expect PASS**

```bash
cd client/packages/ai_message_ui && flutter test test/part_grouping_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add client/packages/ai_message_ui/lib/src/part_grouping.dart \
  client/packages/ai_message_ui/test/part_grouping_test.dart
git commit -m "$(cat <<'EOF'
feat(ai_message_ui): group reasoning/tool runs as chain-of-thought

EOF
)"
```

---

### Task 4: Cot widget + force-open inners + registry

**Files:**
- Create: `client/packages/ai_message_ui/lib/src/parts/chain_of_thought_view.dart`
- Modify: `client/packages/ai_message_ui/lib/src/parts/reasoning_part_view.dart`
- Modify: `client/packages/ai_message_ui/lib/src/parts/tool_call_part_view.dart`
- Modify: `client/packages/ai_message_ui/lib/src/part_registry.dart`
- Modify: `client/packages/ai_message_ui/lib/src/strings.dart`
- Modify: `client/packages/ai_message_ui/lib/ai_message_ui.dart`
- Create: `client/packages/ai_message_ui/test/chain_of_thought_view_test.dart`
- Modify: `client/packages/ai_message_ui/test/ai_message_parts_test.dart` (Cot chrome for leading R/T)

- [ ] **Step 1: Failing widget tests**

In `chain_of_thought_view_test.dart`:

```dart
import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Cot collapsed by default; expand reveals reasoning without second tap',
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

    expect(find.textContaining('secret plan'), findsOneWidget);
    expect(find.textContaining('ok'), findsOneWidget); // tool result visible
  });

  testWidgets('multi-tool Cot expands all tool payloads without nested group click',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiMessageView(
            message: AiMessage(
              id: 'a1',
              role: AiRole.assistant,
              parts: [
                AiToolCallPart(
                  toolCallId: 'c1',
                  toolName: 'Read',
                  result: 'file-a',
                ),
                AiToolCallPart(
                  toolCallId: 'c2',
                  toolName: 'Grep',
                  result: 'file-b',
                ),
                const AiTextPart(text: 'summary'),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.textContaining('Thinking process'));
    await tester.pumpAndSettle();

    expect(find.textContaining('file-a'), findsOneWidget);
    expect(find.textContaining('file-b'), findsOneWidget);
    // Must NOT require tapping "Used 2 tools" group chrome.
    expect(find.textContaining('Used 2 tools'), findsNothing);
  });

  testWidgets('R/T-only turn is a single Cot with no trailing text', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AiMessageView(
            message: AiMessage(
              id: 'a1',
              role: AiRole.assistant,
              parts: [
                AiReasoningPart(text: 'only think'),
                AiToolCallPart(toolCallId: 'c1', toolName: 'Shell'),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('Thinking process'), findsOneWidget);
    expect(find.textContaining('only think'), findsNothing);
  });
}
```

- [ ] **Step 2: Run — expect FAIL**

```bash
cd client/packages/ai_message_ui && flutter test test/chain_of_thought_view_test.dart
```

- [ ] **Step 3: Implement (locked expand rule)**

1. **`AiMessageStrings`:** add `thinkingProcess` and `formatThinkingProcessSteps` (`Object count` → full trigger), defaults e.g. `Thinking process` / `'Thinking process · $count steps'`.
2. **`initiallyExpanded`** on `AiReasoningPartView` and `AiToolCallPartView`: `this.initiallyExpanded = false`, init `_open = widget.initiallyExpanded`.
3. **`AiChainOfThoughtView`:** mirror reasoning chrome (border + trigger + chevron); default `_open = false`.
4. **Expanded Cot body (critical):** render Cot `parts` **directly** as a `Column` of force-open part views (`AiReasoningPartView(..., initiallyExpanded: true)` / `AiToolCallPartView(..., initiallyExpanded: true)`). **Do not** call `groupConsecutiveParts` inside an expanded Cot — that would reintroduce collapsed `AiToolGroupView` / reasoning-group chrome and violate “no second click”.
5. **`AiPartRegistry`:** `chainOfThoughtBuilder`; `buildNode` handles `AiRenderChainOfThought`.
6. Export Cot view from barrel if useful for tests.

- [ ] **Step 4: Update `ai_message_parts_test.dart` for Cot**

Leading/tool-only messages now show Cot trigger first:

- `tool fallback shows Used tool label…` → tap Cot (`Thinking process`) first (or assert Cot then expand to see `Used tool:` with `initiallyExpanded`).
- `consecutive tools render as a collapsible group` → expect Cot chrome (`Thinking process · 3 steps`), **not** top-level `Used 2/3 tools`; after Cot expand, individual tools are visible (no nested tool-group trigger).

Also fix any other widget tests that assumed top-level tool-group for leading tools.

- [ ] **Step 5: Run package tests — expect PASS**

```bash
cd client/packages/ai_message_ui && flutter test
```

- [ ] **Step 6: Commit**

```bash
git add client/packages/ai_message_ui
git commit -m "$(cat <<'EOF'
feat(ai_message_ui): collapse chain-of-thought by default

EOF
)"
```

---

### Task 5: TeamPilot l10n wiring

**Files:**
- Modify: `client/lib/l10n/app_en.arb`
- Modify: `client/lib/l10n/app_zh.arb`
- Modify: `client/lib/pages/chat/session_chat_view.dart` (AiMessageStringsScope)

- [ ] **Step 1: Add ARB keys**

`app_en.arb`:

```json
"aiMessageThinkingProcess": "Thinking process",
"aiMessageThinkingProcessSteps": "Thinking process · {count} steps",
"@aiMessageThinkingProcessSteps": {
  "placeholders": {
    "count": { "type": "int" }
  }
}
```

`app_zh.arb`:

```json
"aiMessageThinkingProcess": "思考过程",
"aiMessageThinkingProcessSteps": "思考过程 · {count} 步",
"@aiMessageThinkingProcessSteps": {
  "placeholders": {
    "count": { "type": "int" }
  }
}
```

- [ ] **Step 2: Wire in `session_chat_view.dart`**

```dart
thinkingProcess: l10n.aiMessageThinkingProcess,
formatThinkingProcessSteps: (count) =>
    l10n.aiMessageThinkingProcessSteps(count as int),
```

(Match the exact generated signature after `flutter gen-l10n` / build.)

- [ ] **Step 3: Regenerate l10n if required by repo workflow, then analyze**

```bash
cd client && flutter gen-l10n
# if warmup glyphs required by project after ARB edits:
# dart run tool/gen_warmup_glyphs.dart
flutter analyze --no-fatal-infos --no-fatal-warnings \
  lib/pages/chat/session_chat_view.dart \
  packages/ai_message_ui \
  packages/ai_message_core
```

- [ ] **Step 4: Commit**

```bash
git add client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb \
  client/lib/pages/chat/session_chat_view.dart \
  client/lib/l10n/app_localizations*.dart
git commit -m "$(cat <<'EOF'
feat(l10n): wire History chain-of-thought strings

EOF
)"
```

---

### Task 6: Verification sweep

- [ ] **Step 1: Run focused tests**

```bash
cd client/packages/ai_message_core && dart test
cd ../ai_message_ui && flutter test
cd ../.. && flutter test \
  test/services/cli/registry/capabilities/history/codex_ai_transcript_test.dart \
  packages/ai_message_ui/test/part_grouping_test.dart \
  packages/ai_message_ui/test/chain_of_thought_view_test.dart
```

- [ ] **Step 2: Broader client check (exclude integration)**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings \
  && flutter test --exclude-tags integration
```

Fix any fallout from coalesce changing message counts in other History tests (search for `hasLength` on Codex/assistant lists if failures appear).

- [ ] **Step 3: Manual smoke (optional but preferred)**

Open a Codex session History with many shell steps: default one「思考过程 · N 步」+ final text; expand shows reasoning text and tool results without nested second-click to see payload.

- [ ] **Step 4: Final commit only if verification produced fixes**

---

## Execution notes

- **TDD order:** Task 1 → 2 → 3 → 4 → 5 → 6.
- **Do not** change Codex rollout on disk or seat-isolation code in this plan.
- **Do not** add a settings toggle to hide reasoning (non-goal).
- Expanded Cot must never nest a second collapsed group; force-open part views only.
- `groupConsecutiveParts` remains for non-Cot callers / tests; Cot expanded path does not use it.
