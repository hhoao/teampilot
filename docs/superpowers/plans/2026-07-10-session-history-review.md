# Session History Review Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Opening an existing session never starts a PTY; the session body shows transcript history plus slim compose, and submit connects then injects for the selected member.

**Architecture:** `connectImmediately: false` on every open-existing path; `SessionHistoryCapability` on each launch CLI normalizes on-disk transcripts to `SessionHistoryTurn`; a read-only context builder supplies resume-compatible locate fields without `prepareLaunch`; `SessionHistoryReview` replaces the Start placeholder inside `ChatWorkbench` (session body under workbench when center tabs are active).

**Tech Stack:** Flutter / Dart, `flutter_bloc`, CLI registry capabilities, `flutter_markdown_plus`, existing `deliverUserCommandToMember(directToPty: true)` inject path.

**Spec:** [docs/superpowers/specs/2026-07-10-session-history-review-design.md](../specs/2026-07-10-session-history-review-design.md)

**Constraints:**
- No backward compatibility, shims, feature flags, or dual UIs.
- No defensive programming: launch CLIs must expose history capability; missing capability is a hard failure in tests/asserts. Soft `empty`/`error` only for real disk/transcript absence.
- Best architecture over incremental patches: delete placeholder Start surface; one review host; parsers live only under registry.

---

## File map (target)

| File | Responsibility |
|------|----------------|
| `client/lib/services/cli/registry/capabilities/session_history_capability.dart` | `SessionHistoryRole`, `SessionHistoryTurn`, `SessionHistorySnapshot`, `SessionHistoryContext`, `SessionHistoryCapability` |
| `client/lib/services/cli/registry/capabilities/history/claude_session_history.dart` | Claude JSONL → turns |
| `client/lib/services/cli/registry/capabilities/history/flashskyai_session_history.dart` | flashskyai workspaces JSONL → turns |
| `client/lib/services/cli/registry/capabilities/history/codex_session_history.dart` | Codex rollout JSONL → turns |
| `client/lib/services/cli/registry/capabilities/history/opencode_session_history.dart` | OpenCode disk under `OPENCODE_DATA_DIR` → turns |
| `client/lib/services/cli/registry/capabilities/history/cursor_session_history.dart` | Cursor isolated chat/transcript → turns |
| `client/lib/services/session/session_history_context_builder.dart` | Read-only locate context (no PTY / no prepareLaunch writes) |
| `client/lib/services/session/session_history_loader.dart` | Resolve CLI → capability → snapshot; cache by sessionId+memberId+mtime |
| `client/lib/cubits/session_history_cubit.dart` | loading / ready / empty / error for active review member |
| `client/lib/pages/chat/session_history_review.dart` | History list + slim compose host |
| `client/lib/pages/chat/session_history_turn_list.dart` | Turn list; Markdown via `flutter_markdown_plus` |
| `client/lib/pages/chat/session_review_compose_card.dart` | Slim compose (input, attach, enhance, voice, send) |
| `client/lib/pages/chat_workbench.dart` | Non-running body → review; delete placeholder branch |
| Delete `ChatWorkbenchTerminalPlaceholder` usage / widget | Gone |
| Open-existing call sites | Always `connectImmediately: false` |
| `client/pubspec.yaml` | Add `flutter_markdown_plus` |
| Fixtures under `client/test/fixtures/session_history/{claude,flashskyai,codex,opencode,cursor}/` | Mainstream-shaped transcripts |

---

### Task 1: Normalized history model + capability interface

**Files:**
- Create: `client/lib/services/cli/registry/capabilities/session_history_capability.dart`
- Create: `client/test/services/cli/registry/capabilities/session_history_capability_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/registry/capabilities/session_history_capability.dart';

void main() {
  test('SessionHistorySnapshot.ready holds turns', () {
    const turn = SessionHistoryTurn(
      role: SessionHistoryRole.user,
      markdown: 'hello',
    );
    const snap = SessionHistorySnapshot(
      turns: [turn],
      status: SessionHistoryLoadStatus.ready,
    );
    expect(snap.turns.single.markdown, 'hello');
    expect(snap.status, SessionHistoryLoadStatus.ready);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/cli/registry/capabilities/session_history_capability_test.dart`

Expected: FAIL (library missing)

- [ ] **Step 3: Implement model + interface**

Define exactly:

```dart
enum SessionHistoryRole { user, assistant, tool, system }

enum SessionHistoryLoadStatus { ready, empty, error }

class SessionHistoryTurn {
  const SessionHistoryTurn({
    required this.role,
    required this.markdown,
    this.timestamp,
    this.toolName,
    this.collapsedByDefault = false,
  });
  final SessionHistoryRole role;
  final String markdown;
  final DateTime? timestamp;
  final String? toolName;
  final bool collapsedByDefault;
}

class SessionHistorySnapshot {
  const SessionHistorySnapshot({
    required this.turns,
    required this.status,
    this.errorMessage,
  });
  final List<SessionHistoryTurn> turns;
  final SessionHistoryLoadStatus status;
  final String? errorMessage;
}

class SessionHistoryContext {
  // Mirror ResumeContext locate fields needed by adapters:
  // fs, env, transcriptRoots, bucket, taskId, persistedNativeId,
  // workspaceId, sessionId, memberId, teamId, manifestDataRoot
}

abstract interface class SessionHistoryCapability implements CliCapability {
  Future<SessionHistorySnapshot> loadHistory(SessionHistoryContext ctx);
}
```

Reuse field shapes from `ResumeContext` where identical; do not subclass `ResumeContext` if that couples history to resume mutations — prefer a dedicated context type with the same locate inputs.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/services/cli/registry/capabilities/session_history_capability_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/cli/registry/capabilities/session_history_capability.dart \
  client/test/services/cli/registry/capabilities/session_history_capability_test.dart
git commit -m "$(cat <<'EOF'
feat: add SessionHistoryCapability model

EOF
)"
```

---

### Task 2: Claude history adapter (fixture-driven)

**Files:**
- Create: `client/lib/services/cli/registry/capabilities/history/claude_session_history.dart`
- Create: `client/test/fixtures/session_history/claude/basic.jsonl`
- Create: `client/test/services/cli/registry/capabilities/history/claude_session_history_test.dart`

- [ ] **Step 1: Add a minimal mainstream-shaped fixture**

`basic.jsonl` with at least: one `user` text turn, one `assistant` text turn, one `tool_use` / `tool_result` pair (Claude Code JSONL event shapes).

- [ ] **Step 2: Write the failing test**

```dart
test('parses user assistant and collapses tools', () async {
  final fs = /* MemoryFilesystem or temp dir with fixture copied to transcript path */;
  final cap = const ClaudeSessionHistory();
  final snap = await cap.loadHistory(ctxPointingAtFixture);
  expect(snap.status, SessionHistoryLoadStatus.ready);
  expect(snap.turns.any((t) => t.role == SessionHistoryRole.user), isTrue);
  expect(snap.turns.any((t) => t.role == SessionHistoryRole.assistant), isTrue);
  expect(
    snap.turns.where((t) => t.role == SessionHistoryRole.tool).every(
      (t) => t.collapsedByDefault,
    ),
    isTrue,
  );
});

test('missing transcript file is empty', () async {
  final snap = await const ClaudeSessionHistory().loadHistory(ctxWithNoFile);
  expect(snap.status, SessionHistoryLoadStatus.empty);
  expect(snap.turns, isEmpty);
});
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd client && flutter test test/services/cli/registry/capabilities/history/claude_session_history_test.dart`

Expected: FAIL

- [ ] **Step 4: Implement `ClaudeSessionHistory`**

- Locate `{bucket}/{taskId}.jsonl` under `transcriptRoots` (same layout as `ClaudeResumeStrategy` / pinned probe).
- Stream line-by-line JSON; map known `type`s; skip unknown lines (corrupt/noise), do not wrap the whole file in a catch-all that returns empty on programmer bugs.
- Align field extraction with cc-transcript / claude-devtools docs (content blocks: text, tool_use, tool_result).

- [ ] **Step 5: Run tests — PASS, then commit**

```bash
git commit -m "$(cat <<'EOF'
feat: add Claude SessionHistoryCapability adapter

EOF
)"
```

---

### Task 3: flashskyai / Codex / OpenCode / Cursor adapters

**Files:**
- Create: `.../history/flashskyai_session_history.dart` + test + fixtures
- Create: `.../history/codex_session_history.dart` + test + fixtures
- Create: `.../history/opencode_session_history.dart` + test + fixtures
- Create: `.../history/cursor_session_history.dart` + test + fixtures

Do **one CLI per commit**. For each:

- [ ] **Step 1: Fixture from mainstream schema** (Codex: agenthud rollout; OpenCode: disk `ses_*.json` + messages; Cursor: agent-transcript JSONL; flashskyai: workspaces JSONL sibling to Claude)
- [ ] **Step 2: Failing parser tests** (ready + empty)
- [ ] **Step 3: Implement adapter**
  - Codex: filter `environment_context` / developer noise; prefer `event_msg` user/agent text; attach tool names from `function_call`
  - OpenCode: **disk only** under `OPENCODE_DATA_DIR` — no `opencode export` subprocess
  - Cursor: after resolving `chatId` (persisted native id / manifest / scan under isolated `.cursor/chats/` as `CursorResumeStrategy` does), load that chat’s conversation transcript from the **session-isolated** cursor tree (`CursorSessionConfigDir.resolve` → `…/home/.cursor/`). Prefer the chat directory’s transcript/JSONL used for agent history under that isolation — do **not** read the user’s global `~/.cursor/projects/.../agent-transcripts` as the primary source. If the isolated chat only has `meta.json` + message files, parse those on-disk shapes; document the chosen file path in the adapter header comment with a fixture that matches it.
  - flashskyai: dedicated class, not `ClaudeSessionHistory` alias
- [ ] **Step 4: Tests PASS + commit** per CLI

---

### Task 4: Register capability on all five launch tools

**Files:**
- Modify: `client/lib/services/cli/registry/tools/claude_cli_tool.dart`
- Modify: `client/lib/services/cli/registry/tools/flashskyai_cli_tool.dart`
- Modify: `client/lib/services/cli/registry/tools/codex_cli_tool.dart`
- Modify: `client/lib/services/cli/registry/tools/opencode_cli_tool.dart`
- Modify: `client/lib/services/cli/registry/tools/cursor_cli_tool.dart`
- Create: `client/test/services/cli/registry/session_history_registration_test.dart`

- [ ] **Step 1: Failing test**

```dart
test('every launch-supported tool exposes SessionHistoryCapability', () {
  final registry = CliToolRegistry.builtIn();
  for (final tool in CliTool.values.where((t) /* launch supported via registry */)) {
    final def = registry.definition(tool);
    if (!def.isLaunchSupported) continue;
    expect(
      registry.capability<SessionHistoryCapability>(tool),
      isNotNull,
      reason: '$tool missing SessionHistoryCapability',
    );
  }
});
```

- [ ] **Step 2: Add `sessionHistory` field + include in `capabilities` getter for each of the five tools**

- [ ] **Step 3: PASS + commit**

```bash
git commit -m "$(cat <<'EOF'
feat: register SessionHistoryCapability on launch CLIs

EOF
)"
```

---

### Task 5: Read-only `SessionHistoryContextBuilder`

**Files:**
- Create: `client/lib/services/session/session_history_context_builder.dart`
- Create: `client/test/services/session/session_history_context_builder_test.dart`

- [ ] **Step 1: Failing test**

For a previously launched simple session under test `AppStorage` / `RuntimeLayout`:

1. Builder returns `SessionHistoryContext` whose env/roots match the **on-disk isolation dirs** below.
2. Builder does **not** call `ConfigProfileService.prepare*` / `ensureSessionProfile` / shell connect.
3. Never-launched session still returns a context pointing at the would-be session tool dirs; adapters then return `empty` if files are absent.

- [ ] **Step 2: Implement using these read-only path APIs (do not call prepare*)**

| CLI | How to fill locate fields (read-only) |
|-----|----------------------------------------|
| claude / flashskyai | `RuntimeLayout.transcriptSearchRoots(...)` + `workspaceBucketForPrimaryPath` (or the same bucket helper resume/`hasCliState` use) — **read paths only** |
| codex | `env['CODEX_HOME'] = CodexSessionConfigDir.resolve(layout, workspaceId:, sessionId:, memberId:)` |
| opencode | `env['OPENCODE_DATA_DIR'] = layout.sessionRuntimeToolDir(workspaceId, sessionId, 'opencode', memberId:)` (same dir `OpencodeConfigProfileCapability` pins as data dir — do not run `contributeLaunch`) |
| cursor | `env` / roots from `CursorSessionConfigDir.resolve(layout, workspaceId:, sessionId:, memberId:, teamId:)` → that path is `<toolDir>/home/.cursor/` |

Also set `fs`, `taskId`, `persistedNativeId` from session member bindings, `manifestDataRoot` from app data root, and ids for workspace/session/member/team.

**Forbidden:** `_prepareEnvFromRuntimePlan`, `prepareLaunch`, provisioning writes, PTY schedule.

If a required id is missing for the seat (programmer error), throw/assert — do not soft-empty.

- [ ] **Step 3: PASS + commit**

```bash
git commit -m "$(cat <<'EOF'
feat: add read-only session history context builder

EOF
)"
```

---

### Task 6: `SessionHistoryLoader` + `SessionHistoryCubit`

**Files:**
- Create: `client/lib/services/session/session_history_loader.dart`
- Create: `client/lib/cubits/session_history_cubit.dart`
- Create: `client/test/cubits/session_history_cubit_test.dart`
- Wire cubit in `client/lib/app/app_shell.dart` (or workspace-scoped provider — match existing cubit DI style)

- [ ] **Step 1: Failing cubit tests**

```dart
test('load emits loading then ready', () async { ... });
test('cache key is sessionId+memberId; member switch reloads', () async { ... });
test('mtime unchanged reuses cache on reload', () async { ... });
```

- [ ] **Step 2: Implement loader**

```dart
class SessionHistoryLoader {
  Future<SessionHistorySnapshot> load({
    required AppSession session,
    required String memberId,
    // workspace, team, cli, builder, registry
  });
}
```

Resolve seat CLI via `cliForMember` / `SessionMemberCliResolver` → `registry.capability<SessionHistoryCapability>(cli)!` — **assert non-null** for launch CLIs (no silent empty fallback for missing capability).

- [ ] **Step 3: Implement cubit states:** `loading` | `ready` | `empty` | `error` (host-local; must not reuse session-connecting UI strings)

- [ ] **Step 4: PASS + commit**

```bash
git commit -m "$(cat <<'EOF'
feat: add SessionHistoryCubit and loader

EOF
)"
```

---

### Task 7: Gate — open-existing never auto-connects

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/workspace_session_actions.dart` (`openWorkspaceSessionTab`)
- Modify: `client/lib/pages/chat/chat_workbench_terminal.dart` (`consumeChatWorkbenchRouteSession`)
- Audit: search open, any other `SessionOpenRequest` for persisted sessions
- Create/extend: `client/test/...` gate tests (prefer cubit/launch tests already covering `connectImmediately: false`)

- [ ] **Step 1: Write failing tests** proving sidebar/open-existing and route deep-link pass `connectImmediately: false` and do not begin session connect

- [ ] **Step 2: Change all open-existing call sites**

```dart
SessionOpenRequest(
  session: session,
  // ...
  connectImmediately: false,
)
```

Landing create+send and automation keep `true`.

- [ ] **Step 3: Grep audit + regression asserts**

Run: `cd client && rg "SessionOpenRequest\\(" -n lib/`

Every persisted-session open must set `false` unless it is landing-create or automation.

Add/keep tests that landing submit path and `AutomationDispatcher` still pass `connectImmediately: true`.

- [ ] **Step 4: PASS + commit**

```bash
git commit -m "$(cat <<'EOF'
fix: open existing sessions without auto-connect

EOF
)"
```

---

### Task 8: Slim review compose + history UI

**Files:**
- Add dependency: `client/pubspec.yaml` → `flutter_markdown_plus`
- Create: `client/lib/pages/chat/session_history_turn_list.dart`
- Create: `client/lib/pages/chat/session_review_compose_card.dart`
- Create: `client/lib/pages/chat/session_history_review.dart`
- Modify: `client/lib/pages/chat_workbench.dart`
- Delete: `ChatWorkbenchTerminalPlaceholder` from `chat_workbench_placeholders.dart` (or delete widget entirely if unused)
- l10n: `client/lib/l10n/app_en.arb` + `app_zh.arb` for empty/error/history loading copy

- [ ] **Step 1: `flutter pub add flutter_markdown_plus`**

- [ ] **Step 2: Implement turn list**

- Assistant/user: `MarkdownBody` / `Markdown` with `noScroll: true` inside list
- Tool: collapsed by default
- States: loading skeleton, empty, error+retry calling cubit.reload

- [ ] **Step 3: Implement slim compose**

Reuse `ComposeTriggerField` + attach/enhance/voice patterns from landing compose card. **Omit** project/worktree/mode/expert/preset/permission chips and Start button. Empty text → send disabled.

- [ ] **Step 4: `SessionHistoryReview` layout** = turn list (Expanded) + slim compose

- [ ] **Step 5: Wire `chat_workbench.dart`**

When `!session.isRunning` and not connecting → `SessionHistoryReview` (not placeholder).

On review appear / selectedMemberId change → `SessionHistoryCubit.load(...)`.

- [ ] **Step 6: Delete placeholder Start widget and update any tests that referenced it**

- [ ] **Step 7: Widget/cubit tests for empty/error/ready; commit**

```bash
git commit -m "$(cat <<'EOF'
feat: session history review UI with slim compose

EOF
)"
```

---

### Task 9: Review submit → connect + inject

**Files:**
- Modify: `client/lib/pages/chat/session_history_review.dart` (or small helper beside workspace_session_actions)
- Reuse: `ChatCubit.connectWorkspaceSession` + `sessionRuntime.deliverUserCommandToMember(..., directToPty: true)` + `applyFirstPromptTitle` (same pattern as `submitWorkspaceLandingMessage`)

- [ ] **Step 1: Failing test** (unit or cubit-level)

Given open tab in review, submit message → connect scheduled for selected member → deliver called with that text. Must **not** call `requestOpenSession(connectImmediately: true)`.

- [ ] **Step 2: Implement submit handler**

1. Trim message; if empty return
2. `connectWorkspaceSession` for current personal/team request
3. Wait until selected member ready via `ensureMemberInputReady` (or the landing path’s equivalent direct-PTY readiness wait)
4. `deliverUserCommandToMember(sessionId, selectedMemberId, text, directToPty: true)`
5. `applyFirstPromptTitle` when appropriate
6. **Clear compose text only after successful inject**
7. On connect/inject failure: stay in review, **keep** compose text, surface existing launch error

- [ ] **Step 3: PASS + commit**

```bash
git commit -m "$(cat <<'EOF'
feat: review compose submit connects and injects

EOF
)"
```

---

### Task 10: Verification sweep

- [ ] **Step 1: Analyze + unit tests**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration
```

Expected: clean / all pass

- [ ] **Step 2: Manual checklist (document in PR later)**

1. Open workspace → click old conversation → no PTY spawn; history or empty + compose
2. Switch team member in review → history reloads for that member
3. Submit message → connecting → terminal; message delivered
4. Disconnect → back to review
5. Landing new chat still auto-starts on send (`connectImmediately: true`)
6. Automation still immediate-connects
7. Deep-link to session does not auto-start

- [ ] **Step 3: Final commit only if sweep fixed stragglers**

---

## Execution notes for agents

- Follow TDD per task; do not batch “write all adapters then test.”
- Prefer deleting dead Start-placeholder code over leaving unused widgets.
- When unsure about a CLI JSON field, copy from mainstream fixture/docs — do not invent.
- `@docs/superpowers/specs/2026-07-10-session-history-review-design.md`
