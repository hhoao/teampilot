# Ask-user-question per-CLI answer capability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Gate chat AskUserQuestion cards by CLI capability; answer Claude-family via PTY and OpenCode via Bus pending + plugin `client.question.reply`; optimistic `working` dismiss with `reply_failed` restore; generic l10n.

**Architecture:** Add `AskUserQuestionCapability` on the CLI registry. Pure `shouldShowAskUserQuestionCard` drives the banner. `AskUserQuestionAnswerService` becomes a facade over PTY vs `AskUserAnswerPendingStore`. Gateway exposes `GET /ask-user-answer?request_id=`. OpenCode agent-status plugin polls and calls SDK reply/reject. `AgentAttentionCubit` moves to `working` on local handoff success while retaining ask payload.

**Tech Stack:** Flutter / Dart, `flutter_bloc`, existing TeammateBus HTTP gateway, OpenCode JS plugin, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-08-03-ask-user-question-answer-capability-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/services/cli/registry/capabilities/ask_user_question_capability.dart` | Capability interface + Claude/Codex/flashskyai/OpenCode/Cursor impls |
| `client/lib/services/cli/registry/tools/*_cli_tool.dart` | Register capability on each tool |
| `client/lib/services/agent_status/ask_user_question_policy.dart` | `shouldShowAskUserQuestionCard` |
| `client/lib/services/agent_status/agent_status_event.dart` | `askRequestId`, `nativeSessionId`; reply-failed signal fields as needed |
| `client/lib/services/agent_status/agent_status_normalizer.dart` | Preserve ids; handle `question.reply_failed` |
| `client/lib/cubits/agent_attention_cubit.dart` | Optimistic `working` + dismissed requestId; ignore same-id waiting; restore on reply_failed |
| `client/lib/services/agent_status/ask_user_answer_pending_store.dart` | Pending answers keyed by session/member/requestId |
| `client/lib/services/team_bus/mcp/teammate_bus_mcp_gateway.dart` | `GET /ask-user-answer` |
| `client/lib/services/terminal/ask_user_question_answer_service.dart` | Facade + PTY port + pending port |
| `client/lib/cubits/chat_cubit.dart` | Dispatch via facade; optimistic dismiss on ok |
| `client/lib/services/cli/registry/config_profile/opencode_agent_status_plugin.dart` | Poll + `client.question.reply` / reject |
| `client/lib/pages/chat/agent_permission_attention_banner.dart` | Policy-driven card vs banner |
| `client/lib/pages/chat/ask_user_question_card.dart` | Multi-question UI; inline error; result handling |
| `client/lib/l10n/app_en.arb` / `app_zh.arb` | Generic title + error strings |
| `client/lib/app/app_shell.dart` (or gateway wiring site) | Wire pending store into gateway if needed |
| Tests under `client/test/...` mirroring the above | TDD coverage per task |

---

### Task 1: AskUserQuestionCapability

**Files:**
- Create: `client/lib/services/cli/registry/capabilities/ask_user_question_capability.dart`
- Modify: `client/lib/services/cli/registry/tools/claude_cli_tool.dart`
- Modify: `client/lib/services/cli/registry/tools/flashskyai_cli_tool.dart`
- Modify: `client/lib/services/cli/registry/tools/codex_cli_tool.dart`
- Modify: `client/lib/services/cli/registry/tools/opencode_cli_tool.dart`
- Modify: `client/lib/services/cli/registry/tools/cursor_cli_tool.dart`
- Create: `client/test/services/cli/ask_user_question_capability_test.dart`

- [ ] **Step 1: Write failing capability matrix test**

```dart
test('claude family supports in-chat single-select pty', () {
  final reg = CliToolRegistry.builtIn();
  final cap = reg.capability<AskUserQuestionCapability>(CliTool.claude)!;
  expect(cap.supportsStructuredAsk, isTrue);
  expect(cap.supportsInChatAnswer, isTrue);
  expect(cap.supportsMultiSelectInChat, isFalse);
  expect(cap.answerKind, AskUserAnswerKind.ptyPicker);
});

test('opencode supports pluginSdkReply + multi', () { /* ... */ });
test('cursor has none / no in-chat', () { /* ... */ });
```

- [ ] **Step 2: Run test — expect FAIL**

```bash
cd client && flutter test test/services/cli/ask_user_question_capability_test.dart
```

Expected: FAIL (type / file missing).

- [ ] **Step 3: Implement capability + register on all five tools**

Mirror `TurnInterruptCapability`: field on each `*CliTool`, include in `capabilities` getter.

```dart
enum AskUserAnswerKind { ptyPicker, pluginSdkReply, none }

abstract interface class AskUserQuestionCapability implements CliCapability {
  bool get supportsStructuredAsk;
  bool get supportsInChatAnswer;
  bool get supportsMultiSelectInChat;
  AskUserAnswerKind get answerKind;
}

final class PtyAskUserQuestionCapability implements AskUserQuestionCapability {
  const PtyAskUserQuestionCapability();
  @override bool get supportsStructuredAsk => true;
  @override bool get supportsInChatAnswer => true;
  @override bool get supportsMultiSelectInChat => false;
  @override AskUserAnswerKind get answerKind => AskUserAnswerKind.ptyPicker;
}

final class OpenCodeAskUserQuestionCapability implements AskUserQuestionCapability {
  const OpenCodeAskUserQuestionCapability();
  @override bool get supportsStructuredAsk => true;
  @override bool get supportsInChatAnswer => true;
  @override bool get supportsMultiSelectInChat => true;
  @override AskUserAnswerKind get answerKind => AskUserAnswerKind.pluginSdkReply;
}

final class NoAskUserQuestionCapability implements AskUserQuestionCapability {
  const NoAskUserQuestionCapability();
  @override bool get supportsStructuredAsk => false;
  @override bool get supportsInChatAnswer => false;
  @override bool get supportsMultiSelectInChat => false;
  @override AskUserAnswerKind get answerKind => AskUserAnswerKind.none;
}
```

- [ ] **Step 4: Run test — expect PASS**

```bash
cd client && flutter test test/services/cli/ask_user_question_capability_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/cli/registry/capabilities/ask_user_question_capability.dart \
  client/lib/services/cli/registry/tools/*.dart \
  client/test/services/cli/ask_user_question_capability_test.dart
git commit -m "$(cat <<'EOF'
feat(cli): add AskUserQuestionCapability per tool

EOF
)"
```

---

### Task 2: Card policy pure function

**Files:**
- Create: `client/lib/services/agent_status/ask_user_question_policy.dart`
- Create: `client/test/services/agent_status/ask_user_question_policy_test.dart`

- [ ] **Step 1: Write failing policy tests**

Cover: Cursor/none → false; single single-select + pty → true; multi without `supportsMultiSelectInChat` → false; multi with OpenCode → true; `pluginSdkReply` missing `askRequestId` → false; empty options → false.

```dart
bool shouldShowAskUserQuestionCard({
  required AskUserQuestionCapability? capability,
  required List<AgentAskUserQuestion>? questions,
  String? askRequestId,
});
```

- [ ] **Step 2: Run — expect FAIL**

```bash
cd client && flutter test test/services/agent_status/ask_user_question_policy_test.dart
```

- [ ] **Step 3: Implement policy**

Follow spec § Card policy exactly.

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(agent-status): add shouldShowAskUserQuestionCard policy

EOF
)"
```

---

### Task 3: Event fields + normalizer (requestId / reply_failed)

**Files:**
- Modify: `client/lib/services/agent_status/agent_status_event.dart`
- Modify: `client/lib/services/agent_status/agent_status_normalizer.dart`
- Modify: `client/test/services/agent_status/agent_status_normalizer_test.dart`

- [ ] **Step 1: Write failing normalizer tests**

```dart
test('opencode question.asked keeps request_id and session_id', () {
  final e = AgentStatusNormalizer.normalize(CliTool.opencode, {
    'event': 'question.asked',
    'questions': [/* one question */],
    'request_id': 'req_1',
    'session_id': 'ses_abc',
  });
  expect(e.askRequestId, 'req_1');
  expect(e.nativeSessionId, 'ses_abc');
  expect(e.askUserQuestions, isNotNull);
});

test('opencode question.reply_failed restores signal', () {
  final e = AgentStatusNormalizer.normalize(CliTool.opencode, {
    'event': 'question.reply_failed',
    'request_id': 'req_1',
    'message': 'boom',
  });
  expect(e.hookEventName, 'question.reply_failed');
  expect(e.askRequestId, 'req_1');
  // state: use a dedicated convention — e.g. waiting + hook name, or a bool
  // `restoreAskWaiting` on the event; pick one and assert it here.
});
```

Also: Claude-family AskUserQuestion PreToolUse sets `askRequestId` from `tool_use_id` when present (may equal `toolUseId`).

- [ ] **Step 2: Run — expect FAIL**

```bash
cd client && flutter test test/services/agent_status/agent_status_normalizer_test.dart
```

- [ ] **Step 3: Extend `AgentStatusEvent` + normalizer**

Add `askRequestId`, `nativeSessionId`, optional `message`, and `restoreAskWaiting` (true only for `question.reply_failed`). Update `==` / `hashCode` / `copyWith`.

Claude-family AskUserQuestion `PreToolUse`: set `askRequestId` from `tool_use_id` when present (may equal `toolUseId` — both fields set is fine).

OpenCode `question.asked`: parse `request_id` / `id` → `askRequestId`; `session_id` / `sessionID` → `nativeSessionId`.

OpenCode `question.reply_failed`: require `request_id`; set `restoreAskWaiting = true`; pass through optional `message`.

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(agent-status): retain ask request ids and reply_failed

EOF
)"
```

---

### Task 4: Attention optimistic dismiss + reconciliation

**Files:**
- Modify: `client/lib/cubits/agent_attention_cubit.dart` (and `AgentSeatAttentionEntry` in same file or `agent_attention_state.dart` if split)
- Modify: `client/test/cubits/agent_attention_cubit_test.dart`

- [ ] **Step 1: Write failing cubit tests**

```dart
test('markAskAnswered moves to working and retains lastEvent', () { /* ... */ });
test('same askRequestId waiting after dismiss is ignored', () { /* ... */ });
test('reply_failed restores waiting from retained lastEvent', () { /* ... */ });
test('new different askRequestId waiting replaces dismissed id', () { /* ... */ });
```

Add API used by ChatCubit after successful answer:

```dart
void markAskAnswered({
  required String sessionId,
  required String memberId,
});
```

On `applyEvent` when `restoreAskWaiting` / `question.reply_failed`: if entry has matching dismissed/`askRequestId`, set `attention=waiting`, keep prior `askUserQuestions` on `lastEvent` (merge — do not wipe questions).

- [ ] **Step 2: Run — expect FAIL**

```bash
cd client && flutter test test/cubits/agent_attention_cubit_test.dart
```

- [ ] **Step 3: Implement entry field `dismissedAskRequestId` + logic**

Also store optional `askReplyError` (String?) on the seat entry when applying `reply_failed`, taken from event `message`. Clear it on a fresh successful waiting ask or on `markAskAnswered`. Card reads this (via entry / lastEvent) for inline error after restore.

- [ ] **Step 4: Run — expect PASS**

Also assert: after `reply_failed` with message `"boom"`, entry is `waiting` and `askReplyError == "boom"` (or equivalent field).

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(attention): optimistic ask dismiss with reply_failed restore

EOF
)"
```

---

### Task 5: AskUserAnswerPendingStore

**Files:**
- Create: `client/lib/services/agent_status/ask_user_answer_pending_store.dart`
- Create: `client/test/services/agent_status/ask_user_answer_pending_store_test.dart`

- [ ] **Step 1: Write failing store tests**

```dart
test('put then take consumes once', () { /* ... */ });
test('take missing returns null', () { /* ... */ });
test('reject entry', () { /* ... */ });
test('clearSeat drops all for session+member', () { /* ... */ });
test('overwrite same requestId', () { /* ... */ });
```

```dart
class AskUserAnswerPendingEntry {
  const AskUserAnswerPendingEntry({
    required this.requestId,
    this.answers,
    this.reject = false,
  });
  final String requestId;
  final List<List<String>>? answers;
  final bool reject;
}
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement in-memory store**

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(agent-status): add AskUserAnswerPendingStore

EOF
)"
```

---

### Task 6: Gateway GET /ask-user-answer

**Files:**
- Modify: `client/lib/services/team_bus/mcp/teammate_bus_mcp_gateway.dart`
- Modify: wiring site that constructs the gateway / `app_shell.dart` to inject the store (same singleton ChatCubit/facade will use)
- Create or modify: `client/test/services/team_bus/...` gateway test if one exists; otherwise add focused unit test with a fake HttpServer harness used by existing gateway tests

- [ ] **Step 1: Locate existing gateway HTTP tests; write failing cases**

- `GET /ask-user-answer?request_id=req_1` with headers → 204 when empty
- After `store.put(...)` → 200 JSON then second GET → 204
- Missing `request_id` query → 204 (unsupported for pollers)

JSON body shape:

```json
{ "request_id": "req_1", "answers": [["Label"]], "reject": false }
```

or `{ "request_id": "req_1", "reject": true }`.

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement route before/near `/agent-status` handling**

Auth/session resolution: same `X-Session` / `X-Member` / bus token rules as `/agent-status`. Prefer best-effort 204 on bad session (do not 4xx in a way that breaks plugins) — match agent-status leniency unless tests prove otherwise.

Expose `Uri get askUserAnswerEndpoint` parallel to `agentStatusEndpoint` if plugins need base URL construction (plugin can derive from `TEAMPILOT_BUS_PORT`).

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(team-bus): expose GET /ask-user-answer for OpenCode plugin

EOF
)"
```

---

### Task 7: Answer facade (PTY + pending)

**Files:**
- Modify: `client/lib/services/terminal/ask_user_question_answer_service.dart`
- Modify: `client/test/services/terminal/ask_user_question_answer_service_test.dart`

- [ ] **Step 1: Extend tests**

Keep existing PTY digit + Esc tests. Add:

```dart
test('pluginSdkReply puts pending answers and returns ok', () { /* fake store + registry */ });
test('pluginSdkReply cancel puts reject', () { /* ... */ });
test('pty disconnected returns failed', () { /* ... */ });
test('none capability returns failed', () { /* ... */ });
```

Result type:

```dart
sealed class AskUserAnswerResult {}
final class AskUserAnswerOk extends AskUserAnswerResult {}
final class AskUserAnswerFailed extends AskUserAnswerResult {
  const AskUserAnswerFailed(this.reason);
  final String reason; // machine key or message for l10n lookup
}
```

Facade signature (adjust names to fit ChatCubit):

```dart
Future<AskUserAnswerResult> answer({
  required CliTool cli,
  required String sessionId,
  required String memberId,
  required TerminalSession? shell,
  required String? askRequestId,
  required List<List<String>> answers, // label arrays; pty uses first question's first label → index
  // OR keep optionIndex for pty single-select path from UI
});
```

For PTY single-select UI, prefer keeping `optionIndex` path that maps to digit inject. For OpenCode, UI passes label arrays + `askRequestId`.

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement facade with `CliToolRegistry` + store injection**

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(ask-user): facade PTY and pending answer ports

EOF
)"
```

---

### Task 8: OpenCode plugin poll + SDK reply

**Files:**
- Modify: `client/lib/services/cli/registry/config_profile/opencode_agent_status_plugin.dart`
- Modify: `client/test/services/cli/config_profile/opencode_agent_status_plugin_test.dart`

- [ ] **Step 1: Extend plugin string tests**

Assert source contains:

- `question.asked` payload fields `request_id`, `session_id`
- poll path `/ask-user-answer?request_id=`
- `client.question.reply` and reject path
- `question.reply_failed` POST on error
- poll loop bound (30m / attention TTL comment or constant in JS)

- [ ] **Step 2: Run — expect FAIL**

```bash
cd client && flutter test test/services/cli/config_profile/opencode_agent_status_plugin_test.dart
```

- [ ] **Step 3: Implement plugin JS**

Pattern (sketch):

```javascript
const client = input?.client;
// on question.asked:
await post("question.asked", { questions, request_id, session_id });
const deadline = Date.now() + 30 * 60 * 1000;
while (Date.now() < deadline) {
  const r = await fetch(`http://127.0.0.1:${port}/ask-user-answer?request_id=${encodeURIComponent(id)}`, { headers });
  if (r.status === 200) {
    const body = await r.json();
    try {
      if (body.reject) {
        await client.question.reject({ path: { sessionID, requestID: id } });
      } else {
        await client.question.reply({
          path: { sessionID, requestID: id },
          body: { answers: body.answers },
        });
      }
    } catch (e) {
      await post("question.reply_failed", { request_id: id, message: String(e) });
    }
    return;
  }
  await new Promise((res) => setTimeout(res, 400));
}
// Poll deadline exceeded: always signal so Dart can restore waiting if the
// user already answered (optimistic working) or keep recoverable UI.
await post("question.reply_failed", {
  request_id: id,
  message: "ask-user-answer poll timed out",
});
```

Adapt exact SDK method names to what OpenCode plugin client exposes (match idle plugin’s `client.session.prompt` style). If `reject` API name differs, probe and document in plugin comment.

Also forward `session_id` from the event into the status POST.

Plugin string tests must also assert timeout path posts `question.reply_failed`.

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(opencode): poll Bus and reply to question via SDK

EOF
)"
```

---

### Task 9: ChatCubit wiring + optimistic dismiss

**Files:**
- Modify: `client/lib/cubits/chat_cubit.dart`
- Modify: `client/lib/app/app_shell.dart` (construct shared `AskUserAnswerPendingStore`, inject into gateway + ChatCubit answer service)
- Create/modify: focused ChatCubit test if feasible; otherwise cover via facade + cubit attention tests already added

- [ ] **Step 1: Update `answerAskUserQuestion` / `cancelAskUserQuestion`**

- Resolve seat CLI from tab/session.
- Call facade.
- On `AskUserAnswerOk`: `agentAttention.markAskAnswered(...)` — applies to **answer and cancel** handoffs (PTY Esc success and OpenCode pending reject put both count as local success).
- On failed: do **not** mark answered; return failure to UI (throw or return result — prefer return result so card can show inline error).

`markAskAnswered` reads `dismissedAskRequestId` from `entry.lastEvent.askRequestId` (no caller-passed id).

Add a unit assertion (ChatCubit test or facade+attention integration): `AskUserAnswerFailed` must **not** call `markAskAnswered`.

Change method signatures to return `Future<AskUserAnswerResult>` if needed; update card call sites in Task 10.

- [ ] **Step 2: Wire singleton pending store in app bootstrap**

Reuse the **same** `AskUserAnswerPendingStore` instance already injected into the gateway in Task 6 — do not construct a second store. ChatCubit facade + gateway share it.

Clear store on session dispose / seat disconnect where shells are torn down (grep existing dispose paths near attention clear).

- [ ] **Step 3: Run related tests**

```bash
cd client && flutter test test/cubits/agent_attention_cubit_test.dart test/services/terminal/ask_user_question_answer_service_test.dart
```

- [ ] **Step 4: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(chat): wire ask-user answer facade and optimistic dismiss

EOF
)"
```

---

### Task 10: UI + l10n

**Files:**
- Modify: `client/lib/pages/chat/agent_permission_attention_banner.dart`
- Modify: `client/lib/pages/chat/ask_user_question_card.dart`
- Modify: `client/lib/l10n/app_en.arb`
- Modify: `client/lib/l10n/app_zh.arb`
- (Regenerate or hand-update `app_localizations*.dart` per repo convention)
- Modify: `client/lib/utils/ui/app_keys.dart` if multi Submit needs keys

- [ ] **Step 1: l10n**

Change:

- EN: `agentAskUserQuestionTitle` → `Agent is asking you a question`
- ZH: → `正在向你提问`

Add:

- `agentAskAnswerFailed` / `agentAskTerminalDisconnected` (or one generic fail string)
- `agentAskSubmitAnswers` for multi Submit button

- [ ] **Step 2: Banner uses policy**

Resolve CLI for seat (same way compose / interrupt resolves locked CLI). Call `shouldShowAskUserQuestionCard`. Pass full `questions` list + `askRequestId` into card when multi supported.

- [ ] **Step 3: Card UI**

- Single single-select: keep option tap → answer (existing).
- Multi / multi-question: radio/checkbox groups + Submit; require ≥1 selection per question; submit `List<List<String>>`.
- On failure: show inline error text (from facade failure reason **or** from attention entry `askReplyError` after `reply_failed` restore); clear `_answering`.
- Cancel: facade cancel (PTY Esc vs pending reject).

Listen to `AgentAttentionCubit` entry for the seat so when `reply_failed` restores `waiting`, the card reappears with inline error from `askReplyError` (fallback to l10n `agentAskAnswerFailed` when message empty).

- [ ] **Step 4: Manual sanity / widget tests if cheap** — optional small test on policy already covers gating; prefer not heavy widget tests unless existing pattern.

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(chat): capability-gated ask card, multi UI, generic l10n

EOF
)"
```

---

### Task 11: Full verification

**Files:** none new (fix any failures)

- [ ] **Step 1: Analyze + unit tests**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration
```

Expected: clean / all pass. Fix any breakage from signature changes.

- [ ] **Step 2: Commit fixes if any**

```bash
git commit -m "$(cat <<'EOF'
fix: ask-user answer capability follow-ups from verify

EOF
)"
```

---

## Execution notes

- Prefer TDD order inside each task; do not skip red→green.
- Remote SSH: `/ask-user-answer` rides the same HTTP tunnel as `/agent-status` — no separate tunnel work if path is on the same gateway server.
- If OpenCode SDK method names differ from `client.question.reply`, adjust plugin only; keep Dart pending JSON stable.
- Do not implement Cursor structured ask or PTY multi-select in-chat (spec non-goals).
