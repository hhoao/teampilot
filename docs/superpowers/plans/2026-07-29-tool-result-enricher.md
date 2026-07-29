# Tool Result Enricher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Capability-owned `ToolResultEnricher` fills missing/truncated shell stdout on History `AiToolCallPart.result` (Cursor terminals + Claude truncation) so shell cards show output without UI changes.

**Architecture:** Add `ToolResultEnricher` on `AiHistoryCapability`. `AiHistoryLoader` runs `locate → parse → enrich → inflate`. Cursor reads `projects/{slug}/terminals/*.txt`; Claude/flashskyai share truncation→`toolUseResult` enricher; Codex/OpenCode use NoOp.

**Tech Stack:** Dart / Flutter; `ai_message_core`; TeamPilot CLI registry + History loader.

**Spec:** `docs/superpowers/specs/2026-07-29-tool-result-enricher-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/services/cli/registry/capabilities/history/tool_result_enricher.dart` | Interface + `NoOpToolResultEnricher` |
| `client/lib/services/cli/registry/capabilities/ai_history_capability.dart` | Add `toolResultEnricher` getter |
| `client/lib/services/cli/registry/capabilities/history/builtin_ai_history_capabilities.dart` | Wire enrichers per CLI |
| `client/lib/services/cli/registry/capabilities/history/cursor_terminal_file.dart` | Parse `terminals/*.txt` |
| `client/lib/services/cli/registry/capabilities/history/cursor_terminal_tool_result_enricher.dart` | Match + fill Cursor shell results |
| `client/lib/services/cli/registry/capabilities/history/claude_compatible_tool_result_enricher.dart` | Truncation → `toolUseResult` |
| `client/lib/services/cli/registry/capabilities/history/cursor_ai_transcript.dart` | Raise watch root / cache paths for `terminals/` |
| `client/lib/services/session/ai_history_loader.dart` | Call enrich between parse and inflate |
| `client/test/support/fake_ai_history_registry.dart` | Fake capability + enricher field |
| `client/test/services/session/subagent_attachment_inflater_test.dart` | `_Cap` must implement new getter |
| `client/test/services/cli/registry/ai_history_capability_wiring_test.dart` | Assert enricher bindings |
| `client/test/services/cli/registry/capabilities/history/cursor_terminal_file_test.dart` | Parser tests |
| `client/test/services/cli/registry/capabilities/history/cursor_terminal_tool_result_enricher_test.dart` | Enricher tests |
| `client/test/services/cli/registry/capabilities/history/claude_compatible_tool_result_enricher_test.dart` | Truncation tests |
| `client/test/services/session/ai_history_loader_test.dart` | Enrich called between parse and inflate |
| `client/test/fixtures/session_history/cursor/` | Transcript without `tool_result` + `terminals/*.txt` |

---

### Task 1: Enricher API + capability wiring (TDD)

**Files:**
- Create: `client/lib/services/cli/registry/capabilities/history/tool_result_enricher.dart`
- Modify: `client/lib/services/cli/registry/capabilities/ai_history_capability.dart`
- Modify: `client/lib/services/cli/registry/capabilities/history/builtin_ai_history_capabilities.dart`
- Modify: `client/test/support/fake_ai_history_registry.dart`
- Modify: `client/test/services/session/subagent_attachment_inflater_test.dart` (`_Cap`)
- Modify: `client/test/services/cli/registry/ai_history_capability_wiring_test.dart`

- [ ] **Step 1: Write failing wiring assertions**

Add to `ai_history_capability_wiring_test.dart`:

```dart
test('history capabilities expose toolResultEnricher', () {
  for (final cap in [
    const ClaudeAiHistoryCapability(),
    const FlashskyaiAiHistoryCapability(),
    const CursorAiHistoryCapability(),
    const CodexAiHistoryCapability(),
    const OpencodeAiHistoryCapability(),
  ]) {
    expect(cap.toolResultEnricher, isNotNull);
  }
  expect(
    const CodexAiHistoryCapability().toolResultEnricher,
    isA<NoOpToolResultEnricher>(),
  );
  expect(
    const OpencodeAiHistoryCapability().toolResultEnricher,
    isA<NoOpToolResultEnricher>(),
  );
});
```

(Task 1 wires all five to NoOp; Tasks 3–4 swap Cursor/Claude defaults and tighten assertions.)

- [ ] **Step 2: Run — expect FAIL**

```bash
cd client && flutter test test/services/cli/registry/ai_history_capability_wiring_test.dart
```

Expected: compile error — `toolResultEnricher` missing.

- [ ] **Step 3: Implement interface + NoOp + wire**

Create `tool_result_enricher.dart` with `ToolResultEnricher` + `NoOpToolResultEnricher` (signature per spec).

Add `ToolResultEnricher get toolResultEnricher` to `AiHistoryCapability`.

Each builtin capability: constructor param + field defaulting to `const NoOpToolResultEnricher()`.

Update `FakeAiHistoryCapability` and inflater test `_Cap`.

- [ ] **Step 4: Run — PASS**

```bash
cd client && flutter test \
  test/services/cli/registry/ai_history_capability_wiring_test.dart \
  test/services/session/subagent_attachment_inflater_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/cli/registry/capabilities/ai_history_capability.dart \
  client/lib/services/cli/registry/capabilities/history/tool_result_enricher.dart \
  client/lib/services/cli/registry/capabilities/history/builtin_ai_history_capabilities.dart \
  client/test/support/fake_ai_history_registry.dart \
  client/test/services/session/subagent_attachment_inflater_test.dart \
  client/test/services/cli/registry/ai_history_capability_wiring_test.dart
git commit -m "$(cat <<'EOF'
feat(history): add ToolResultEnricher capability hook

EOF
)"
```

---

### Task 2: Cursor terminal file parser (TDD)

**Files:**
- Create: `client/lib/services/cli/registry/capabilities/history/cursor_terminal_file.dart`
- Create: `client/test/services/cli/registry/capabilities/history/cursor_terminal_file_test.dart`

- [ ] **Step 1: Write failing parser tests**

Cover: full header+body+exit trailer; missing trailer still returns body; garbage → null.

Sample fields: `command`, `title`, `body`, `exitCode`, ISO `started_at`.

- [ ] **Step 2: Run — FAIL**

```bash
cd client && flutter test test/services/cli/registry/capabilities/history/cursor_terminal_file_test.dart
```

- [ ] **Step 3: Implement `CursorTerminalFile` + `parseCursorTerminalFile`**

Split on lines equal to `---`. First segment → key/value (split on first `:`, strip quotes). Second → body. Optional third → `exit_code` / `ended_at`. Require non-empty `command`.

- [ ] **Step 4: PASS**

```bash
cd client && flutter test test/services/cli/registry/capabilities/history/cursor_terminal_file_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/cli/registry/capabilities/history/cursor_terminal_file.dart \
  client/test/services/cli/registry/capabilities/history/cursor_terminal_file_test.dart
git commit -m "$(cat <<'EOF'
feat(history): parse Cursor terminals/*.txt side files

EOF
)"
```

---

### Task 3: CursorTerminalToolResultEnricher (TDD)

**Files:**
- Create: `client/lib/services/cli/registry/capabilities/history/cursor_terminal_tool_result_enricher.dart`
- Create: `client/test/services/cli/registry/capabilities/history/cursor_terminal_tool_result_enricher_test.dart`
- Modify: `builtin_ai_history_capabilities.dart` (Cursor default)

- [ ] **Step 1: Write failing enricher tests**

Temp dir layout:

```
project/agent-transcripts/chat/chat.jsonl
project/terminals/1.txt
```

Cases: match description+command → fill; existing result unchanged; exit_code≠0 → isError; exclusive bind; missing terminals dir; whitespace-only result treated as missing.

Use `DefaultAiShellToolTargetResolver` for command/description.

- [ ] **Step 2: Run — FAIL**

```bash
cd client && flutter test test/services/cli/registry/capabilities/history/cursor_terminal_tool_result_enricher_test.dart
```

- [ ] **Step 3: Implement enricher + wire Cursor capability**

Derive `terminals/` from `rootTranscriptPath`:
`dirname ×3` from `.../agent-transcripts/{id}/{id}.jsonl` → project root.

Walk shell parts in message order; bind each terminal file at most once.

IO errors: `appLogger` + return original messages.

Default: `toolResultEnricher = const CursorTerminalToolResultEnricher()`.

Wiring test: Cursor → `isA<CursorTerminalToolResultEnricher>()`.

- [ ] **Step 4: PASS + Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(history): enrich Cursor Shell results from terminals/*.txt

EOF
)"
```

---

### Task 4: ClaudeCompatibleToolResultEnricher (TDD)

**Files:**
- Create: `client/lib/services/cli/registry/capabilities/history/claude_compatible_tool_result_enricher.dart`
- Create: `client/test/services/cli/registry/capabilities/history/claude_compatible_tool_result_enricher_test.dart`
- Modify: `builtin_ai_history_capabilities.dart` (Claude + flashskyai)

- [ ] **Step 1: Write failing tests**

Truncation sentinel (`tool output truncated`) + Map/String `toolUseResult` → replace; non-truncated unchanged; sentinel without toolUseResult unchanged.

- [ ] **Step 2: FAIL then implement**

Rescan JSONL from `rootTranscriptPath` or bundle fragment; index `tool_use_id` → `toolUseResult`.

Wire Claude + flashskyai to `const ClaudeCompatibleToolResultEnricher()`.

- [ ] **Step 3: PASS + Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(history): enrich truncated Claude/flashskyai toolUseResult stdout

EOF
)"
```

---

### Task 5: Loader seam + Cursor watch hints (TDD)

**Files:**
- Modify: `client/lib/services/session/ai_history_loader.dart`
- Modify: `client/lib/services/cli/registry/capabilities/history/cursor_ai_transcript.dart`
- Modify: `client/test/services/session/ai_history_loader_test.dart`

- [ ] **Step 1: Failing loader test with recording enricher**

`RecordingEnricher` increments `calls`; wire via `FakeAiHistoryCapability`; after load expect `calls == 1`. Cache stores enriched messages.

- [ ] **Step 2: Insert enrich after parse / before inflate**

Compute `parentPath` first, then:

```dart
messages = await cap.toolResultEnricher.enrich(
  messages: messages,
  ctx: ctx,
  rootTranscriptPath: parentPath,
  bundle: bundle,
);
```

Apply in cold load and any live-refresh parse path in this file.

- [ ] **Step 3: Cursor locate watch**

Raise `changeWatchRoot` to `projects/{slug}/`. Include `terminals/` in watch/cache strategy so new `*.txt` invalidate History (prefer project root watch; add `terminalsDir` to `cacheTokenPaths` only if token helper accepts directories).

- [ ] **Step 4: PASS**

```bash
cd client && flutter test test/services/session/ai_history_loader_test.dart \
  test/services/cli/registry/capabilities/history/cursor_ai_transcript_test.dart
```

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(history): run ToolResultEnricher after parse; watch Cursor terminals

EOF
)"
```

---

### Task 6: Fixtures + wiring polish + regression

**Files:**
- Fixtures under `client/test/fixtures/session_history/cursor/`
- Integration / fixture tests
- Final wiring assertions for concrete enricher types

- [ ] **Step 1: Add fixtures + assertions**

Cursor: Shell without `tool_result` + matching `terminals/*.txt` → enriched stdout.

Claude: truncated fixture → enriched stdout.

- [ ] **Step 2: Run suites**

```bash
cd client && flutter test \
  test/services/cli/registry/capabilities/history/ \
  test/services/cli/registry/ai_history_capability_wiring_test.dart \
  test/services/session/ai_history_loader_test.dart \
  test/services/session/subagent_attachment_inflater_test.dart
```

- [ ] **Step 3: Commit**

```bash
git commit -m "$(cat <<'EOF'
test(history): cover Cursor terminals and Claude truncation enrichers

EOF
)"
```

---

## Out of scope

- Cursor `store.db` decryption
- Shell card UI changes
- PTY buffer capture into History
- Non-shell Cursor terminal matching
