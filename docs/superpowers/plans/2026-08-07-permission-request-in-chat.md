# Permission-Request Confirmation in Chat — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users answer Claude-family `PermissionRequest` inline in Chat (Allow/Deny) gated by the session workbench view, and make the AskUserQuestion hook-hold view-aware (fixing the frozen terminal / dead "answer in terminal" button).

**Architecture:** View-aware hook hold. When a Claude-family `PermissionRequest` or AskUserQuestion `PreToolUse` arrives, the `/agent-status` HTTP handler holds the hook only when `resolveHoldInChat` says the session is in Chat view with the requesting seat selected; otherwise it responds `{}` so the native TUI renders. A new `PermissionRequestHookGate` (keyed by `sessionId`/`memberId`, no `tool_use_id`) completes the held hook with `decision.behavior: allow|deny`. Switching Chat → Terminal releases held hooks (fallthrough `{}`). A `PermissionRequestCard` renders in chat via the existing `AgentPermissionAttentionBanner`.

**Tech Stack:** Flutter (client/), `flutter_bloc` cubits, `CliToolRegistry` capabilities, TeamBus MCP gateway loopback HTTP.

**Spec:** `docs/superpowers/specs/2026-08-07-permission-request-in-chat-design.md`

## Global Constraints

- Claude Code `PermissionRequest` hook response uses the **nested** form `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"|"deny"}}}` — NOT the PreToolUse flat `permissionDecision`.
- Fallthrough (native TUI) = respond `{}` (empty map), never `decision.behavior: deny`.
- PermissionRequest carries **no** `tool_use_id` → gate key is `(sessionId, memberId)` only.
- Bypass mode (`dangerouslySkipPermissions`) must never hold a hook or show a card.
- Do not hold when the workbench view is Terminal, there is no open tab, or (team sessions) the requesting seat is not the selected member.
- `PermissionRequestCapability` only on claude / flashskyai / codex; cursor / opencode get `NoPermissionRequestCapability`.
- l10n: edit `client/lib/l10n/app_en.arb` **and** `app_zh.arb` only.
- Before claiming done: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`.

---

### Task 1: `PermissionRequestCapability` + per-CLI wiring

**Files:**
- Create: `client/lib/services/cli/registry/capabilities/permission_request_capability.dart`
- Modify: `client/lib/services/cli/registry/tools/claude_cli_tool.dart`, `flashskyai_cli_tool.dart`, `codex_cli_tool.dart`, `cursor_cli_tool.dart`, `opencode_cli_tool.dart`
- Test: `client/test/services/cli/registry/capabilities/permission_request_capability_test.dart`

**Interfaces:**
- Produces: `PermissionRequestCapability` (interface), `ClaudePermissionRequestCapability`, `NoPermissionRequestCapability` — resolvable via `CliToolRegistry.capability<PermissionRequestCapability>(cli)`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/permission_request_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  final registry = CliToolRegistry.builtIn();

  test('claude/flashskyai/codex support in-chat permission answer', () {
    for (final cli in [CliTool.claude, CliTool.flashskyai, CliTool.codex]) {
      expect(
        registry.capability<PermissionRequestCapability>(cli)?.supportsInChatAnswer,
        isTrue,
        reason: '$cli should support in-chat permission answer',
      );
    }
  });

  test('cursor/opencode do not support in-chat permission answer', () {
    for (final cli in [CliTool.cursor, CliTool.opencode]) {
      expect(
        registry.capability<PermissionRequestCapability>(cli)?.supportsInChatAnswer,
        isFalse,
        reason: '$cli should not support in-chat permission answer',
      );
    }
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/cli/registry/capabilities/permission_request_capability_test.dart -v`
Expected: FAIL — `CliToolRegistry.capability<PermissionRequestCapability>` throws (no such capability registered) or returns null and the `?.supportsInChatAnswer` is null → `expect(null, isTrue)` fails.

- [ ] **Step 3: Create the capability file**

Create `client/lib/services/cli/registry/capabilities/permission_request_capability.dart`:

```dart
import '../cli_capability.dart';

abstract interface class PermissionRequestCapability implements CliCapability {
  bool get supportsInChatAnswer;
}

final class ClaudePermissionRequestCapability
    implements PermissionRequestCapability {
  const ClaudePermissionRequestCapability();

  @override
  bool get supportsInChatAnswer => true;
}

final class NoPermissionRequestCapability
    implements PermissionRequestCapability {
  const NoPermissionRequestCapability();

  @override
  bool get supportsInChatAnswer => false;
}
```

- [ ] **Step 4: Wire onto the five tool definitions**

For `claude_cli_tool.dart`:
- Add `import '../capabilities/permission_request_capability.dart';`
- In the constructor defaults: add `this.permissionRequest = const ClaudePermissionRequestCapability(),` (after the `askUserQuestion` line).
- Add field `final PermissionRequestCapability permissionRequest;` (near `askUserQuestion`).
- Add `permissionRequest,` to the `capabilities` list.

For `flashskyai_cli_tool.dart` and `codex_cli_tool.dart`: same three edits, `ClaudePermissionRequestCapability`.

For `cursor_cli_tool.dart` and `opencode_cli_tool.dart`: same three edits, but `NoPermissionRequestCapability`.

- [ ] **Step 5: Run test to verify it passes**

Run: `cd client && flutter test test/services/cli/registry/capabilities/permission_request_capability_test.dart -v`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
cd client && git add lib/services/cli/registry/capabilities/permission_request_capability.dart \
  lib/services/cli/registry/tools/claude_cli_tool.dart \
  lib/services/cli/registry/tools/flashskyai_cli_tool.dart \
  lib/services/cli/registry/tools/codex_cli_tool.dart \
  lib/services/cli/registry/tools/cursor_cli_tool.dart \
  lib/services/cli/registry/tools/opencode_cli_tool.dart \
  test/services/cli/registry/capabilities/permission_request_capability_test.dart
git commit -m "feat(cli): add PermissionRequestCapability (claude-family in-chat answer)"
```

---

### Task 2: `PermissionRequestHookGate`

**Files:**
- Create: `client/lib/services/agent_status/permission_request_hook_gate.dart`
- Test: `client/test/services/agent_status/permission_request_hook_gate_test.dart`

**Interfaces:**
- Consumes: nothing (self-contained).
- Produces:
  - `sealed class PermissionRequestHookReply` with `PermissionDecisionAllow`, `PermissionDecisionDeny`, `PermissionDecisionFallthrough`.
  - `PermissionRequestHookGate.wait({sessionId, memberId, timeout}) -> Future<PermissionRequestHookReply?>` (null on timeout).
  - `complete({sessionId, memberId, reply}) -> bool`.
  - `hasWaiter({sessionId, memberId}) -> bool`.
  - `releaseForSession(String sessionId)` — completes all waiters for the session with fallthrough.
  - `clearSeat({sessionId, memberId})` and `clearSession(String sessionId)` — complete waiters with fallthrough.

- [ ] **Step 1: Write the failing test**

Create `client/test/services/agent_status/permission_request_hook_gate_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/agent_status/permission_request_hook_gate.dart';

void main() {
  group('PermissionRequestHookGate', () {
    test('complete allow unblocks wait', () async {
      final gate = PermissionRequestHookGate();
      final future = gate.wait(sessionId: 's', memberId: 'm');
      expect(
        gate.complete(
          sessionId: 's',
          memberId: 'm',
          reply: const PermissionDecisionAllow(),
        ),
        isTrue,
      );
      expect(await future, isA<PermissionDecisionAllow>());
    });

    test('complete deny unblocks wait', () async {
      final gate = PermissionRequestHookGate();
      final future = gate.wait(sessionId: 's', memberId: 'm');
      expect(
        gate.complete(
          sessionId: 's',
          memberId: 'm',
          reply: const PermissionDecisionDeny(),
        ),
        isTrue,
      );
      expect(await future, isA<PermissionDecisionDeny>());
    });

    test('releaseForSession completes held waiters with fallthrough', () async {
      final gate = PermissionRequestHookGate();
      final f1 = gate.wait(sessionId: 's', memberId: 'm1');
      final f2 = gate.wait(sessionId: 's', memberId: 'm2');
      gate.releaseForSession('s');
      expect(await f1, isA<PermissionDecisionFallthrough>());
      expect(await f2, isA<PermissionDecisionFallthrough>());
      expect(gate.hasWaiter(sessionId: 's', memberId: 'm1'), isFalse);
    });

    test('clearSeat completes that seat only with fallthrough', () async {
      final gate = PermissionRequestHookGate();
      final f1 = gate.wait(sessionId: 's', memberId: 'm1');
      final f2 = gate.wait(sessionId: 's', memberId: 'm2');
      gate.clearSeat(sessionId: 's', memberId: 'm1');
      expect(await f1, isA<PermissionDecisionFallthrough>());
      expect(gate.hasWaiter(sessionId: 's', memberId: 'm2'), isTrue);
      expect(await f2, isNull); // never completed → test just ensures f2 still open
    });

    test('wait times out to null', () async {
      final gate = PermissionRequestHookGate();
      final reply = await gate.wait(
        sessionId: 's',
        memberId: 'm',
        timeout: const Duration(milliseconds: 20),
      );
      expect(reply, isNull);
    });

    test('second wait for same seat replaces prior waiter with fallthrough',
        () async {
      final gate = PermissionRequestHookGate();
      final first = gate.wait(sessionId: 's', memberId: 'm');
      final second = gate.wait(sessionId: 's', memberId: 'm');
      expect(await first, isA<PermissionDecisionFallthrough>());
      expect(gate.hasWaiter(sessionId: 's', memberId: 'm'), isTrue);
      gate.clearSeat(sessionId: 's', memberId: 'm');
      expect(await second, isA<PermissionDecisionFallthrough>());
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/agent_status/permission_request_hook_gate_test.dart -v`
Expected: FAIL — `permission_request_hook_gate.dart` not found.

- [ ] **Step 3: Create the gate**

Create `client/lib/services/agent_status/permission_request_hook_gate.dart`:

```dart
import 'dart:async';

/// Reply for a held Claude-family `PermissionRequest` HTTP hook.
sealed class PermissionRequestHookReply {
  const PermissionRequestHookReply();
}

final class PermissionDecisionAllow extends PermissionRequestHookReply {
  const PermissionDecisionAllow();
}

final class PermissionDecisionDeny extends PermissionRequestHookReply {
  const PermissionDecisionDeny();
}

/// No decision — respond `{}` so Claude Code shows its native permission TUI.
final class PermissionDecisionFallthrough extends PermissionRequestHookReply {
  const PermissionDecisionFallthrough();
}

/// Holds open Claude-family `PermissionRequest` HTTP hooks (keyed by
/// session+member — PermissionRequest carries no `tool_use_id`) until the chat
/// card allows/denies, the view switches away, or the session tears down.
final class PermissionRequestHookGate {
  final _waiters = <String, Completer<PermissionRequestHookReply>>{};

  /// Waits for [complete] / release with the same seat. Returns `null` on
  /// timeout so the handler falls through to Claude's native prompt (`{}`).
  Future<PermissionRequestHookReply?> wait({
    required String sessionId,
    required String memberId,
    Duration timeout = const Duration(hours: 24),
  }) async {
    final key = _key(sessionId, memberId);
    final existing = _waiters.remove(key);
    if (existing != null && !existing.isCompleted) {
      existing.complete(const PermissionDecisionFallthrough());
    }
    final completer = Completer<PermissionRequestHookReply>();
    _waiters[key] = completer;
    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      return null;
    } finally {
      final current = _waiters[key];
      if (identical(current, completer)) {
        _waiters.remove(key);
      }
    }
  }

  /// Returns true when a waiter was completed (hook still open).
  bool complete({
    required String sessionId,
    required String memberId,
    required PermissionRequestHookReply reply,
  }) {
    final completer = _waiters.remove(_key(sessionId, memberId));
    if (completer == null || completer.isCompleted) return false;
    completer.complete(reply);
    return true;
  }

  bool hasWaiter({required String sessionId, required String memberId}) {
    final completer = _waiters[_key(sessionId, memberId)];
    return completer != null && !completer.isCompleted;
  }

  /// Release every held hook for [sessionId] with fallthrough (view switch).
  void releaseForSession(String sessionId) {
    final prefix = '${sessionId.trim()}/';
    _releaseWhere((key) => key.startsWith(prefix));
  }

  void clearSeat({required String sessionId, required String memberId}) {
    _releaseWhere((key) => key == _key(sessionId, memberId));
  }

  void clearSession(String sessionId) => releaseForSession(sessionId);

  void _releaseWhere(bool Function(String key) test) {
    final doomed = <String>[];
    for (final key in _waiters.keys) {
      if (test(key)) doomed.add(key);
    }
    for (final key in doomed) {
      final c = _waiters.remove(key);
      if (c != null && !c.isCompleted) {
        c.complete(const PermissionDecisionFallthrough());
      }
    }
  }

  String _key(String sessionId, String memberId) =>
      '${sessionId.trim()}/${memberId.trim()}';
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/services/agent_status/permission_request_hook_gate_test.dart -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd client && git add lib/services/agent_status/permission_request_hook_gate.dart \
  test/services/agent_status/permission_request_hook_gate_test.dart
git commit -m "feat(agent-status): PermissionRequestHookGate keyed by session+member"
```

---

### Task 3: `shouldHoldInChat` policy + fallthrough support on `AskUserQuestionHookGate`

**Files:**
- Create: `client/lib/services/agent_status/hold_in_chat_policy.dart`
- Modify: `client/lib/services/agent_status/ask_user_question_hook_gate.dart`
- Test: `client/test/services/agent_status/hold_in_chat_policy_test.dart`, modify `client/test/services/agent_status/ask_user_question_hook_gate_test.dart`

**Interfaces:**
- Produces:
  - `bool shouldHoldInChat({required bool chatViewActive, required bool seatSelected, required bool skipPermissions, required bool capabilitySupportsInChat})`
  - `AskUserQuestionHookReply.fallthrough` + `AskUserQuestionHookGate.releaseForSession(String sessionId)` + `bool get fallthrough` on the reply.

- [ ] **Step 1: Write the failing policy test**

Create `client/test/services/agent_status/hold_in_chat_policy_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/agent_status/hold_in_chat_policy.dart';

void main() {
  test('holds only when chat view, seat selected, no skip, capability on', () {
    expect(
      shouldHoldInChat(
        chatViewActive: true,
        seatSelected: true,
        skipPermissions: false,
        capabilitySupportsInChat: true,
      ),
      isTrue,
    );
  });

  test('never holds when skipPermissions', () {
    expect(
      shouldHoldInChat(
        chatViewActive: true,
        seatSelected: true,
        skipPermissions: true,
        capabilitySupportsInChat: true,
      ),
      isFalse,
    );
  });

  test('never holds when terminal view', () {
    expect(
      shouldHoldInChat(
        chatViewActive: false,
        seatSelected: true,
        skipPermissions: false,
        capabilitySupportsInChat: true,
      ),
      isFalse,
    );
  });

  test('never holds when seat not selected', () {
    expect(
      shouldHoldInChat(
        chatViewActive: true,
        seatSelected: false,
        skipPermissions: false,
        capabilitySupportsInChat: true,
      ),
      isFalse,
    );
  });

  test('never holds when capability off', () {
    expect(
      shouldHoldInChat(
        chatViewActive: true,
        seatSelected: true,
        skipPermissions: false,
        capabilitySupportsInChat: false,
      ),
      isFalse,
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/agent_status/hold_in_chat_policy_test.dart -v`
Expected: FAIL — file not found.

- [ ] **Step 3: Create the policy**

Create `client/lib/services/agent_status/hold_in_chat_policy.dart`:

```dart
/// Whether an agent-status hook that can be answered in Chat should be held
/// open (awaiting the chat card) instead of letting the native TUI render.
///
/// Same resolver serves AskUserQuestion `PreToolUse` and `PermissionRequest`.
bool shouldHoldInChat({
  required bool chatViewActive,
  required bool seatSelected,
  required bool skipPermissions,
  required bool capabilitySupportsInChat,
}) {
  if (skipPermissions) return false;
  if (!chatViewActive) return false;
  if (!seatSelected) return false;
  return capabilitySupportsInChat;
}
```

- [ ] **Step 4: Add fallthrough release to AskUserQuestionHookGate**

Modify `client/lib/services/agent_status/ask_user_question_hook_gate.dart`:

- Extend `AskUserQuestionHookReply` — change the class to:

```dart
final class AskUserQuestionHookReply {
  const AskUserQuestionHookReply.allow({
    required this.questions,
    required this.answers,
  })  : reject = false,
        fallthrough = false;

  const AskUserQuestionHookReply.reject()
    : questions = null,
      answers = null,
      reject = true,
      fallthrough = false;

  /// No decision — respond `{}` so Claude Code renders its native TUI.
  const AskUserQuestionHookReply.fallthrough()
    : questions = null,
      answers = null,
      reject = false,
      fallthrough = true;

  final List<AgentAskUserQuestion>? questions;

  /// Question text → selected label (comma-joined for multi-select).
  final Map<String, String>? answers;
  final bool reject;
  final bool fallthrough;
}
```

- Add `releaseForSession` (mirror the existing `clearSession` but complete with `fallthrough()` instead of `reject()`):

```dart
  /// Release every held hook for [sessionId] with fallthrough (view switch →
  /// native TUI renders).
  void releaseForSession(String sessionId) {
    final prefix = '${sessionId.trim()}/';
    final doomed = <String>[];
    for (final key in _waiters.keys) {
      if (key.startsWith(prefix)) doomed.add(key);
    }
    for (final key in doomed) {
      final c = _waiters.remove(key);
      if (c != null && !c.isCompleted) {
        c.complete(const AskUserQuestionHookReply.fallthrough());
      }
    }
  }
```

- [ ] **Step 5: Add a gate test for fallthrough release**

Append to `client/test/services/agent_status/ask_user_question_hook_gate_test.dart` inside the `AskUserQuestionHookGate` group:

```dart
    test('releaseForSession completes held waiters with fallthrough', () async {
      final gate = AskUserQuestionHookGate();
      final future = gate.wait(sessionId: 's', memberId: 'm', toolUseId: 't1');
      gate.releaseForSession('s');
      final reply = await future;
      expect(reply?.fallthrough, isTrue);
      expect(reply?.reject, isFalse);
    });
```

- [ ] **Step 6: Run both tests to verify they pass**

Run: `cd client && flutter test test/services/agent_status/hold_in_chat_policy_test.dart test/services/agent_status/ask_user_question_hook_gate_test.dart -v`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
cd client && git add lib/services/agent_status/hold_in_chat_policy.dart \
  lib/services/agent_status/ask_user_question_hook_gate.dart \
  test/services/agent_status/hold_in_chat_policy_test.dart \
  test/services/agent_status/ask_user_question_hook_gate_test.dart
git commit -m "feat(agent-status): shouldHoldInChat policy + hook fallthrough release"
```

---

### Task 4: `AgentStatusHttpHandler` — hold PermissionRequest + view-aware AskUserQuestion

**Files:**
- Modify: `client/lib/services/agent_status/agent_status_http_handler.dart`
- Test: `client/test/services/agent_status/agent_status_http_handler_ask_user_test.dart` (append), new `client/test/services/agent_status/agent_status_http_handler_permission_test.dart`

**Interfaces:**
- Consumes: `PermissionRequestHookGate`, `PermissionRequestHookReply`, `shouldHoldInChat`.
- Produces: `AgentStatusHttpHandler` now takes optional `PermissionRequestHookGate? permissionGate` and `bool Function(String sessionId, String memberId)? resolveHoldInChat`.

- [ ] **Step 1: Write the failing handler tests**

Create `client/test/services/agent_status/agent_status_http_handler_permission_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/agent_status/agent_attention_state.dart';
import 'package:teampilot/services/agent_status/agent_status_http_handler.dart';
import 'package:teampilot/services/agent_status/permission_request_hook_gate.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_config.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_gateway.dart';

void main() {
  setUpAll(() {
    HttpOverrides.global = null;
  });

  late AgentAttentionCubit cubit;
  late PermissionRequestHookGate gate;
  late TeammateBusMcpGateway gateway;
  late HttpClient client;

  setUp(() async {
    cubit = AgentAttentionCubit(pruneInterval: null);
    gate = PermissionRequestHookGate();
    gateway = TeammateBusMcpGateway();
    await gateway.ensureStarted();
    gateway.attachAgentStatusHandler(
      AgentStatusHttpHandler(
        attention: cubit,
        resolveCli: (_, __) => CliTool.claude,
        resolveSkipPermissions: (_, __) => false,
        permissionGate: gate,
        resolveHoldInChat: (_, __) => true,
      ),
    );
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await cubit.close();
    await gateway.dispose();
  });

  Future<HttpClientResponse> postPermission({
    required String sessionId,
    required String memberId,
    String event = 'PermissionRequest',
    Map<String, Object?>? extra,
  }) async {
    final uri = Uri.parse('http://127.0.0.1:${gateway.httpPort}/agent-status');
    final req = await client.postUrl(uri);
    req.headers.set('content-type', 'application/json');
    req.headers.set('connection', 'close');
    req.headers.set(teammateBusMcpSessionHeader, sessionId);
    req.headers.set(teammateBusMcpMemberHeader, memberId);
    req.add(
      utf8.encode(
        jsonEncode({
          'hook_event_name': event,
          'tool_name': 'Bash',
          'tool_input': {'command': 'rm -rf build'},
          ...?extra,
        }),
      ),
    );
    return req.close();
  }

  Future<void> waitUntilWaiter({
    required String sessionId,
    required String memberId,
  }) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      if (gate.hasWaiter(sessionId: sessionId, memberId: memberId)) return;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    fail('timed out waiting for PermissionRequest hook waiter');
  }

  test('hold → allow complete → decision.behavior allow', () async {
    const sessionId = 'perm-s1';
    const memberId = 'm1';
    gateway.registerAgentStatusSession(sessionId: sessionId);

    final responseFuture = postPermission(sessionId: sessionId, memberId: memberId);
    await waitUntilWaiter(sessionId: sessionId, memberId: memberId);
    expect(
      cubit.state.attentionFor(sessionId: sessionId, memberId: memberId),
      AgentSeatAttention.waiting,
    );

    expect(
      gate.complete(
        sessionId: sessionId,
        memberId: memberId,
        reply: const PermissionDecisionAllow(),
      ),
      isTrue,
    );

    final resp = await responseFuture.timeout(const Duration(seconds: 5));
    expect(resp.statusCode, HttpStatus.ok);
    final decoded = jsonDecode(await resp.transform(utf8.decoder).join()) as Map;
    final hook = decoded['hookSpecificOutput'] as Map;
    expect(hook['hookEventName'], 'PermissionRequest');
    final decision = hook['decision'] as Map;
    expect(decision['behavior'], 'allow');
  });

  test('hold → deny complete → decision.behavior deny', () async {
    const sessionId = 'perm-s2';
    const memberId = 'm1';
    gateway.registerAgentStatusSession(sessionId: sessionId);

    final responseFuture = postPermission(sessionId: sessionId, memberId: memberId);
    await waitUntilWaiter(sessionId: sessionId, memberId: memberId);

    expect(
      gate.complete(
        sessionId: sessionId,
        memberId: memberId,
        reply: const PermissionDecisionDeny(),
      ),
      isTrue,
    );

    final resp = await responseFuture.timeout(const Duration(seconds: 5));
    final decoded = jsonDecode(await resp.transform(utf8.decoder).join()) as Map;
    final decision = (decoded['hookSpecificOutput'] as Map)['decision'] as Map;
    expect(decision['behavior'], 'deny');
  });

  test('releaseForSession → empty {} response (native TUI)', () async {
    const sessionId = 'perm-s3';
    const memberId = 'm1';
    gateway.registerAgentStatusSession(sessionId: sessionId);

    final responseFuture = postPermission(sessionId: sessionId, memberId: memberId);
    await waitUntilWaiter(sessionId: sessionId, memberId: memberId);

    gate.releaseForSession(sessionId);

    final resp = await responseFuture.timeout(const Duration(seconds: 5));
    expect(resp.statusCode, HttpStatus.ok);
    expect(jsonDecode(await resp.transform(utf8.decoder).join()), <String, Object?>{});
  });

  test('terminal view (resolveHoldInChat false) → empty {} immediately',
      () async {
    final soloCubit = AgentAttentionCubit(pruneInterval: null);
    addTearDown(soloCubit.close);
    final soloGateway = TeammateBusMcpGateway();
    await soloGateway.ensureStarted();
    addTearDown(soloGateway.dispose);
    soloGateway.attachAgentStatusHandler(
      AgentStatusHttpHandler(
        attention: soloCubit,
        resolveCli: (_, __) => CliTool.claude,
        resolveSkipPermissions: (_, __) => false,
        permissionGate: PermissionRequestHookGate(),
        resolveHoldInChat: (_, __) => false,
      ),
    );
    soloGateway.registerAgentStatusSession(sessionId: 'perm-term');

    final resp = await postPermission(
      sessionId: 'perm-term',
      memberId: 'm1',
    ).timeout(const Duration(seconds: 5));
    expect(jsonDecode(await resp.transform(utf8.decoder).join()), <String, Object?>{});
    expect(
      soloCubit.state.attentionFor(sessionId: 'perm-term', memberId: 'm1'),
      AgentSeatAttention.waiting,
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/agent_status/agent_status_http_handler_permission_test.dart -v`
Expected: FAIL — `permissionGate` / `resolveHoldInChat` not parameters of `AgentStatusHttpHandler`.

- [ ] **Step 3: Extend the handler**

Modify `client/lib/services/agent_status/agent_status_http_handler.dart`:

- Add imports: `permission_request_hook_gate.dart`, `hold_in_chat_policy.dart`.
- Constructor: add `this.permissionGate`, `this.resolveHoldInChat`.

```dart
  AgentStatusHttpHandler({
    required this.attention,
    required this.resolveCli,
    required this.resolveSkipPermissions,
    this.askUserHookGate,
    this.permissionGate,
    this.resolveHoldInChat,
  });

  final AskUserQuestionHookGate? askUserHookGate;
  final PermissionRequestHookGate? permissionGate;

  /// Null = not wired. When non-null, a hook is held only if this returns true
  /// (chat view + selected seat + capability + !skipPermissions).
  final bool Function(String sessionId, String memberId)? resolveHoldInChat;
```

- In `handle`, after `attention.applyEvent(...)`, replace the `answered = await _maybeAnswerAskUserQuestionHook(...)` block with two dispatches (ask then permission):

```dart
            final answered = await _maybeAnswerAskUserQuestionHook(
              request,
              sessionId: sessionId,
              memberId: memberId,
              event: event,
            );
            if (answered) return;
            final answeredPermission = await _maybeAnswerPermissionRequestHook(
              request,
              sessionId: sessionId,
              memberId: memberId,
              event: event,
            );
            if (answeredPermission) return;
```

- Add the new method (after `_maybeAnswerAskUserQuestionHook`):

```dart
  /// Returns true when the HTTP response was already written.
  Future<bool> _maybeAnswerPermissionRequestHook(
    HttpRequest request, {
    required String sessionId,
    required String memberId,
    required AgentStatusEvent event,
  }) async {
    final gate = permissionGate;
    if (gate == null) return false;
    final hook = event.hookEventName?.trim() ?? '';
    if (hook != 'PermissionRequest') return false;
    final hold = resolveHoldInChat?.call(sessionId, memberId) ?? false;
    if (!hold) return false;

    final reply = await gate.wait(sessionId: sessionId, memberId: memberId);
    if (reply == null) return false;

    switch (reply) {
      case PermissionDecisionAllow():
        await _writeJson(request, {
          'hookSpecificOutput': {
            'hookEventName': 'PermissionRequest',
            'decision': {'behavior': 'allow'},
          },
        });
      case PermissionDecisionDeny():
        await _writeJson(request, {
          'hookSpecificOutput': {
            'hookEventName': 'PermissionRequest',
            'decision': {'behavior': 'deny'},
          },
        });
      case PermissionDecisionFallthrough():
        return false; // fall through to `{}`
    }
    return true;
  }
```

- Gate AskUserQuestion hold on `resolveHoldInChat`. In `_maybeAnswerAskUserQuestionHook`, after the existing guards, add:

```dart
    final hold = resolveHoldInChat?.call(sessionId, memberId);
    if (hold == false) return false;
```

- Handle fallthrough in the ask reply. In `_maybeAnswerAskUserQuestionHook`, after `if (reply == null) return false;`, add:

```dart
    if (reply.fallthrough) return false; // respond `{}`, native TUI renders
```

(Keep the existing `if (reply.reject)` deny branch and the allow branch unchanged.)

- [ ] **Step 4: Append an AskUserQuestion view-aware test**

Append to `client/test/services/agent_status/agent_status_http_handler_ask_user_test.dart`:

```dart
  test('Ask PreToolUse not held when resolveHoldInChat false → empty 200',
      () async {
    final soloCubit = AgentAttentionCubit(pruneInterval: null);
    addTearDown(soloCubit.close);
    final soloGateway = TeammateBusMcpGateway();
    await soloGateway.ensureStarted();
    addTearDown(soloGateway.dispose);
    soloGateway.attachAgentStatusHandler(
      AgentStatusHttpHandler(
        attention: soloCubit,
        resolveCli: (_, __) => CliTool.claude,
        resolveSkipPermissions: (_, __) => false,
        askUserHookGate: AskUserQuestionHookGate(),
        resolveHoldInChat: (_, __) => false,
      ),
    );
    soloGateway.registerAgentStatusSession(sessionId: 'ask-term');

    final uri = Uri.parse(
      'http://127.0.0.1:${soloGateway.httpPort}/agent-status',
    );
    final req = await client.postUrl(uri);
    req.headers.set('content-type', 'application/json');
    req.headers.set('connection', 'close');
    req.headers.set(teammateBusMcpSessionHeader, 'ask-term');
    req.headers.set(teammateBusMcpMemberHeader, 'm1');
    req.add(
      utf8.encode(
        jsonEncode(
          askBody(
            toolUseId: 'toolu-y',
            questions: [
              {
                'question': 'OK?',
                'options': ['Yes'],
              },
            ],
          ),
        ),
      ),
    );
    final resp = await req.close().timeout(const Duration(seconds: 5));
    expect(resp.statusCode, HttpStatus.ok);
    expect(jsonDecode(await resp.transform(utf8.decoder).join()), <String, Object?>{});
    expect(
      soloCubit.state.attentionFor(sessionId: 'ask-term', memberId: 'm1'),
      AgentSeatAttention.waiting,
    );
  });
```

- [ ] **Step 5: Run handler tests**

Run: `cd client && flutter test test/services/agent_status/agent_status_http_handler_permission_test.dart test/services/agent_status/agent_status_http_handler_ask_user_test.dart -v`
Expected: PASS (new tests + existing still green).

- [ ] **Step 6: Commit**

```bash
cd client && git add lib/services/agent_status/agent_status_http_handler.dart \
  test/services/agent_status/agent_status_http_handler_permission_test.dart \
  test/services/agent_status/agent_status_http_handler_ask_user_test.dart
git commit -m "feat(agent-status): hold PermissionRequest hook + view-aware AskUserQuestion"
```

---

### Task 5: app_shell + seat-lookup wiring

**Files:**
- Modify: `client/lib/app/app_shell.dart`
- Modify: `client/lib/cubits/chat_cubit.dart` (constructor params + fields + `resolveHoldInChat` population)

**Interfaces:**
- Consumes: `PermissionRequestHookGate`, `ChatTabStore` (via ChatCubit), `SessionWorkbenchView`, `PermissionRequestCapability`, `CliToolRegistry`.
- Produces: `ChatCubit` gains optional `PermissionRequestHookGate? permissionGate` param; a `late bool Function(String, String) resolveHoldInChat` on ChatCubit.

- [ ] **Step 1: Add constructor params + resolver to ChatCubit**

In `client/lib/cubits/chat_cubit.dart`:
- Add imports: `../services/agent_status/permission_request_hook_gate.dart`, `../services/agent_status/hold_in_chat_policy.dart`, `../services/cli/registry/capabilities/permission_request_capability.dart`, `model/session_workbench_view.dart` (verify existing import; add if absent).
- Constructor: add `PermissionRequestHookGate? permissionGate,` and store `_permissionGate = permissionGate`.
- Field: `final PermissionRequestHookGate? _permissionGate;`
- Add a public resolver setter, populated once the cubit exists (call this in app_shell after construction):

```dart
  late bool Function(String sessionId, String memberId) resolveHoldInChat =
      (_, __) => false;

  void bindResolveHoldInChat({
    required ChatTabStore tabStore,
    required CliToolRegistry registry,
    required AgentStatusSeatLookup seatLookup,
  }) {
    resolveHoldInChat = (sessionId, memberId) {
      final tab = tabStore.openTabBySessionId(sessionId);
      if (tab == null) return false;
      if (tab.workbenchView != SessionWorkbenchView.chat) return false;
      if (seatLookup.resolveSkipPermissions(sessionId, memberId)) return false;
      final cli = seatLookup.resolveCli(sessionId, memberId);
      if (cli == null) return false;
      final cap = registry.capability<PermissionRequestCapability>(cli);
      if (cap == null || !cap.supportsInChatAnswer) return false;
      final mid = memberId.trim();
      // Simple seats are always "selected". Team seats hold only when the
      // requesting member is the one whose chat body is visible.
      final sess = tab.persistedSession;
      if (sess == null || sess.isSimple) return true;
      return tab.selectedMemberId.trim() == mid;
    };
  }
```

- [ ] **Step 2: Add `markPermissionAnswered` to AgentAttentionCubit**

Modify `client/lib/cubits/agent_attention_cubit.dart` — add a method after `markAskAnswered` (PermissionRequest events carry no `askRequestId`, so `markAskAnswered` would no-op):

```dart
  /// Optimistically dismiss a waiting PermissionRequest: move to working so the
  /// card clears before the next tool hook lands. Separate from
  /// [markAskAnswered] — PermissionRequest events carry no `askRequestId`.
  void markPermissionAnswered({
    required String sessionId,
    required String memberId,
  }) {
    final key = agentSeatKey(sessionId: sessionId, memberId: memberId);
    final existing = state.seats[key];
    if (existing == null) return;
    if (existing.attention != AgentSeatAttention.waiting) return;
    final seats = Map<String, AgentSeatAttentionEntry>.of(state.seats);
    seats[key] = AgentSeatAttentionEntry(
      attention: AgentSeatAttention.working,
      updatedAt: _clock(),
      lastEvent: existing.lastEvent,
      dismissedAskRequestId: null,
      askReplyError: null,
    );
    emit(AgentAttentionState(seats: seats, clock: _clock));
  }
```

(`ChatTabStore`, `CliToolRegistry`, `AgentStatusSeatLookup` are already imported or accessible in chat_cubit.dart — verify and add imports if missing.)

- [ ] **Step 2: Add `answerPermissionRequest` / `denyPermissionRequest` + view-switch release**

Add to `client/lib/cubits/chat_cubit.dart` (after `cancelAskUserQuestion`):

```dart
  /// Allows a pending PermissionRequest via the hook gate (skips native TUI).
  Future<bool> answerPermissionRequest({
    required String sessionId,
    required String memberId,
  }) async {
    final gate = _permissionGate;
    if (gate == null) return false;
    final ok = gate.complete(
      sessionId: sessionId,
      memberId: memberId,
      reply: const PermissionDecisionAllow(),
    );
    if (ok) {
      _agentAttentionCubit?.markPermissionAnswered(
        sessionId: sessionId,
        memberId: memberId,
      );
    }
    return ok;
  }

  /// Denies a pending PermissionRequest via the hook gate.
  Future<bool> denyPermissionRequest({
    required String sessionId,
    required String memberId,
  }) async {
    final gate = _permissionGate;
    if (gate == null) return false;
    final ok = gate.complete(
      sessionId: sessionId,
      memberId: memberId,
      reply: const PermissionDecisionDeny(),
    );
    if (ok) {
      _agentAttentionCubit?.markPermissionAnswered(
        sessionId: sessionId,
        memberId: memberId,
      );
    }
    return ok;
  }
```

Modify `setSessionWorkbenchView` to release held hooks when switching away from chat:

```dart
  void setSessionWorkbenchView(String sessionId, SessionWorkbenchView view) {
    final tab = _tabStore.openTabBySessionId(sessionId);
    if (tab == null || tab.workbenchView == view) return;
    final wasChat = tab.workbenchView == SessionWorkbenchView.chat;
    tab.workbenchView = view;
    emit(state.copyWith(stateVersion: state.stateVersion + 1));
    if (wasChat && view == SessionWorkbenchView.terminal) {
      // Release held chat hooks so the native TUI renders in the terminal.
      _permissionGate?.releaseForSession(sessionId);
      _askUserAnswer.releaseHeldForSession(sessionId);
    }
    if (view == SessionWorkbenchView.chat) {
      onSessionHistoryStale?.call(sessionId);
    }
  }
```

- [ ] **Step 3: Add `releaseHeldForSession` to `AskUserQuestionAnswerService`**

Modify `client/lib/services/terminal/ask_user_question_answer_service.dart` — add a method:

```dart
  /// Release every held AskUserQuestion hook for [sessionId] with fallthrough
  /// (view switched to terminal → native TUI renders).
  void releaseHeldForSession(String sessionId) {
    _hookGate?.releaseForSession(sessionId);
  }
```

- [ ] **Step 4: Wire in app_shell**

Modify `client/lib/app/app_shell.dart` (around the existing `askUserQuestionHookGate` construction, ~line 1123):
- Create the gate next to the ask gate:

```dart
  final askUserQuestionHookGate = AskUserQuestionHookGate();
  final permissionRequestHookGate = PermissionRequestHookGate();
```

- Pass to the handler:

```dart
  teammateBusMcpGateway.attachAgentStatusHandler(
    AgentStatusHttpHandler(
      attention: agentAttentionCubit,
      resolveCli: agentStatusSeatLookup.resolveCli,
      resolveSkipPermissions: agentStatusSeatLookup.resolveSkipPermissions,
      askUserHookGate: askUserQuestionHookGate,
      permissionGate: permissionRequestHookGate,
    ),
  );
```

- Pass to ChatCubit: add `permissionGate: permissionRequestHookGate,` to the `ChatCubit(...)` construction.
- After `chatCubit` is constructed, bind the resolver (the resolver needs `chatCubit._tabStore` — use `chatCubit.bindResolveHoldInChat(...)` passing the same `tabStore` instance, `CliToolRegistry.builtIn()`, and `agentStatusSeatLookup`). Add this right after `chatCubit = ChatCubit(...)`:

```dart
  chatCubit.bindResolveHoldInChat(
    tabStore: chatTabStore,
    registry: CliToolRegistry.builtIn(),
    seatLookup: agentStatusSeatLookup,
  );
```

(Confirm the actual `tabStore` variable name in app_shell — use the same `ChatTabStore` instance passed into `ChatCubit`.)

- [ ] **Step 5: Add cubit tests**

Create `client/test/cubits/chat_cubit_permission_answer_test.dart` (mirrors `chat_cubit_ask_user_answer_test.dart`):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat/model/session_workbench_view.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/services/agent_status/agent_attention_state.dart';
import 'package:teampilot/services/agent_status/agent_status_event.dart';
import 'package:teampilot/services/agent_status/permission_request_hook_gate.dart';

import '../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  group('ChatCubit permission answer', () {
    late AgentAttentionCubit attention;
    late PermissionRequestHookGate gate;

    setUp(() {
      attention = AgentAttentionCubit(pruneInterval: null);
      gate = PermissionRequestHookGate();
    });

    tearDown(() async {
      await attention.close();
    });

    ChatCubit _buildCubit() {
      return ChatCubit(
        executableResolver: () => '/bin/true',
        automationRepository: testAutomationRepository(),
        agentAttentionCubit: attention,
        permissionGate: gate,
      );
    }

    void _seedWaitingTab(ChatCubit cubit, {required String sessionId}) {
      final tab = ChatTab(
        info: ChatTabInfo(id: sessionId, title: sessionId, subtitle: ''),
        cliTeamName: sessionId,
        selectedMemberId: sessionId,
      );
      cubit.tabStore.append(tab);
      cubit.refreshActiveWorkspaceTabs();
      attention.applyEvent(
        sessionId: sessionId,
        memberId: sessionId,
        event: const AgentStatusEvent(
          state: AgentSeatAttention.waiting,
          hookEventName: 'PermissionRequest',
          toolName: 'Bash',
          toolInput: 'rm -rf build',
        ),
        skipPermissions: false,
      );
    }

    test('answerPermissionRequest allows + dismisses attention', () async {
      final cubit = _buildCubit();
      addTearDown(cubit.close);

      const sessionId = 'perm-sess';
      _seedWaitingTab(cubit, sessionId: sessionId);
      final waiter = gate.wait(sessionId: sessionId, memberId: sessionId);

      final ok = await cubit.answerPermissionRequest(
        sessionId: sessionId,
        memberId: sessionId,
      );

      expect(ok, isTrue);
      expect(await waiter, isA<PermissionDecisionAllow>());
      final entry = attention.state.entryFor(
        sessionId: sessionId,
        memberId: sessionId,
      );
      expect(entry?.attention, AgentSeatAttention.working);
    });

    test('denyPermissionRequest denies', () async {
      final cubit = _buildCubit();
      addTearDown(cubit.close);

      const sessionId = 'perm-den';
      _seedWaitingTab(cubit, sessionId: sessionId);
      final waiter = gate.wait(sessionId: sessionId, memberId: sessionId);

      final ok = await cubit.denyPermissionRequest(
        sessionId: sessionId,
        memberId: sessionId,
      );

      expect(ok, isTrue);
      expect(await waiter, isA<PermissionDecisionDeny>());
    });

    test('setSessionWorkbenchView → terminal releases held permission hook',
        () async {
      final cubit = _buildCubit();
      addTearDown(cubit.close);

      const sessionId = 'perm-switch';
      _seedWaitingTab(cubit, sessionId: sessionId);
      final waiter = gate.wait(sessionId: sessionId, memberId: sessionId);

      cubit.setSessionWorkbenchView(sessionId, SessionWorkbenchView.terminal);

      expect(await waiter, isA<PermissionDecisionFallthrough>());
    });
  });
}
```

> **Note:** `ChatTab` / `ChatTabInfo` / `SessionWorkbenchView` all come from `cubits/chat/model/chat_tab.dart` (it re-exports `ChatTabInfo` and `SessionWorkbenchView`, as the existing `ask_user_question_card_test.dart` relies on).

- [ ] **Step 6: Run cubit tests**

Run: `cd client && flutter test test/cubits/chat_cubit_ask_user_answer_test.dart test/cubits/chat_cubit_permission_answer_test.dart -v`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
cd client && git add lib/app/app_shell.dart lib/cubits/chat_cubit.dart \
  lib/services/terminal/ask_user_question_answer_service.dart \
  test/cubits/chat_cubit_ask_user_answer_test.dart test/cubits/chat_cubit_permission_answer_test.dart
git commit -m "feat(chat): answer/deny PermissionRequest + release held hooks on view switch"
```

---

### Task 6: `PermissionRequestCard` widget

**Files:**
- Create: `client/lib/pages/chat/permission_request_card.dart`
- Modify: `client/lib/l10n/app_en.arb`, `app_zh.arb` (regenerate via `flutter gen-l10n` or `dart run tool/…` per repo convention — verify against `client/lib/l10n/app_localizations.dart`)
- Test: `client/test/pages/chat/permission_request_card_test.dart`

**Interfaces:**
- Consumes: `AppSession`, `ChatCubit.answerPermissionRequest` / `denyPermissionRequest`.
- Produces: `PermissionRequestCard({required this.session, required this.seatId, required this.toolName, required this.toolInputPreview, required this.onAnswerInTerminal})`.

- [ ] **Step 1: Add l10n keys**

Add to `client/lib/l10n/app_en.arb`:
```json
"permissionRequestCardTitle": "Permission requested",
"permissionRequestCardAllow": "Allow",
"permissionRequestCardDeny": "Deny",
"permissionRequestCardAnswerInTerminal": "Answer in terminal",
"permissionRequestCardHint": "Enter to allow, Esc to deny",
```

Add matching keys to `client/lib/l10n/app_zh.arb`:
```json
"permissionRequestCardTitle": "请求权限",
"permissionRequestCardAllow": "允许",
"permissionRequestCardDeny": "拒绝",
"permissionRequestCardAnswerInTerminal": "在终端中处理",
"permissionRequestCardHint": "Enter 允许，Esc 拒绝",
```

Run the l10n generation step the repo uses (see `docs/DEVELOPMENT.md`; typically `flutter gen-l10n` from `client/`). Do not hand-edit generated files.

- [ ] **Step 2: Write the failing widget test**

Create `client/test/pages/chat/permission_request_card_test.dart` (mirrors `ask_user_question_card_test.dart`):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/chat/permission_request_card.dart';
import 'package:teampilot/theme/app_typography_scale.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

import '../../support/post_frame_test_harness.dart';

class _RecordingChatCubit extends ChatCubit {
  _RecordingChatCubit()
    : super(
        executableResolver: () => 'true',
        automationRepository: testAutomationRepository(),
      );

  final allows = <Map<String, Object?>>[];
  final denies = <Map<String, Object?>>[];
  bool allowResult = true;
  bool denyResult = true;

  @override
  Future<bool> answerPermissionRequest({
    required String sessionId,
    required String memberId,
  }) async {
    allows.add({'sessionId': sessionId, 'memberId': memberId});
    return allowResult;
  }

  @override
  Future<bool> denyPermissionRequest({
    required String sessionId,
    required String memberId,
  }) async {
    denies.add({'sessionId': sessionId, 'memberId': memberId});
    return denyResult;
  }
}

AppSession _simpleSession() {
  return AppSession(
    sessionId: 'sess-1',
    workspaceId: 'ws-1',
    folders: const [WorkspaceFolder(path: '/tmp')],
    createdAt: 1,
    updatedAt: 1,
    cli: CliTool.claude,
  );
}

Widget _tpApp({required Widget child}) {
  final theme = ThemeData(useMaterial3: true);
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    theme: theme,
    home: TpTheme(
      data: TpThemeData.fromColorScheme(
        theme.colorScheme,
        scale: 1.0,
        controlScale: AppTypographyScale.standard.multiplier,
      ),
      child: child,
    ),
  );
}

Widget _cardHarness({
  required ChatCubit chat,
  String? toolName = 'Bash',
  String? toolInputPreview = 'rm -rf build',
  VoidCallback? onAnswerInTerminal,
}) {
  final session = _simpleSession();
  return _tpApp(
    child: MultiBlocProvider(
      providers: [BlocProvider<ChatCubit>.value(value: chat)],
      child: Scaffold(
        body: PermissionRequestCard(
          session: session,
          seatId: session.sessionId,
          toolName: toolName,
          toolInputPreview: toolInputPreview,
          onAnswerInTerminal: onAnswerInTerminal ?? () {},
        ),
      ),
    ),
  );
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  group('PermissionRequestCard', () {
    testWidgets('renders tool + preview', (tester) async {
      final chat = _RecordingChatCubit();
      addTearDown(chat.close);

      await tester.pumpWidget(_cardHarness(chat: chat));
      await tester.pumpAndSettle();

      expect(find.byKey(AppKeys.permissionRequestCard), findsOneWidget);
      expect(find.text('Bash'), findsOneWidget);
      expect(find.text('rm -rf build'), findsOneWidget);
      expect(find.text('Allow'), findsOneWidget);
      expect(find.text('Deny'), findsOneWidget);
    });

    testWidgets('Allow tap calls answerPermissionRequest', (tester) async {
      final chat = _RecordingChatCubit();
      addTearDown(chat.close);

      await tester.pumpWidget(_cardHarness(chat: chat));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(AppKeys.permissionRequestAllowButton));
      await tester.pumpAndSettle();

      expect(chat.allows, hasLength(1));
      expect(chat.allows.single['sessionId'], 'sess-1');
      expect(chat.allows.single['memberId'], 'sess-1');
      expect(chat.denies, isEmpty);
    });

    testWidgets('Deny tap calls denyPermissionRequest', (tester) async {
      final chat = _RecordingChatCubit();
      addTearDown(chat.close);

      await tester.pumpWidget(_cardHarness(chat: chat));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Deny'));
      await tester.pumpAndSettle();

      expect(chat.denies, hasLength(1));
      expect(chat.denies.single['sessionId'], 'sess-1');
      expect(chat.allows, isEmpty);
    });
  });
}
```

> **Note:** The widget needs the l10n delegates + `TpTheme` (see the `_tpApp` helper copied from `ask_user_question_card_test.dart`). The card's `_allow`/`_deny` read `ChatCubit` from context, so the stub cubit must be provided via `BlocProvider`.

- [ ] **Step 3: Create the card**

Create `client/lib/pages/chat/permission_request_card.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/chat_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_session.dart';
import '../../utils/ui/app_keys.dart';

/// Compact card for a Claude-family `PermissionRequest`: tool name + command /
/// path preview + Allow / Deny, shown above Chat compose in Chat view.
class PermissionRequestCard extends StatefulWidget {
  const PermissionRequestCard({
    required this.session,
    required this.seatId,
    required this.toolName,
    required this.toolInputPreview,
    required this.onAnswerInTerminal,
    super.key,
  });

  final AppSession session;

  /// Shell / seat key (`sessionId` for simple, member id for team).
  final String seatId;
  final String? toolName;
  final String? toolInputPreview;
  final VoidCallback onAnswerInTerminal;

  @override
  State<PermissionRequestCard> createState() => _PermissionRequestCardState();
}

class _PermissionRequestCardState extends State<PermissionRequestCard> {
  var _busy = false;
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _allow() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await context.read<ChatCubit>().answerPermissionRequest(
      sessionId: widget.session.sessionId,
      memberId: widget.seatId,
    );
    if (mounted && !ok) setState(() => _busy = false);
  }

  Future<void> _deny() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await context.read<ChatCubit>().denyPermissionRequest(
      sessionId: widget.session.sessionId,
      memberId: widget.seatId,
    );
    if (mounted && !ok) setState(() => _busy = false);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _busy) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _allow();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _deny();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final spacing = context.tpSpacing;
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    final radius = TpTheme.of(context).control.radius;

    final preview = widget.toolInputPreview?.trim() ?? '';
    final title = widget.toolName?.trim().isNotEmpty == true
        ? widget.toolName!.trim()
        : l10n.permissionRequestCardTitle;

    return Padding(
      padding: EdgeInsets.only(bottom: spacing.sm),
      child: Focus(
        focusNode: _focusNode,
        onKeyEvent: _onKey,
        child: Material(
          key: AppKeys.permissionRequestCard,
          elevation: 0,
          color: cs.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius + 4),
            side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.55)),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              spacing.lg,
              spacing.lg,
              spacing.lg,
              spacing.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.permissionRequestCardTitle,
                        style: styles.smColored(cs.onSurfaceVariant),
                      ),
                    ),
                    TpIconButton(
                      icon: Icons.terminal_rounded,
                      tooltip: l10n.permissionRequestCardAnswerInTerminal,
                      compact: true,
                      size: TpIconButton.kCompactSize,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.75),
                      borderRadius: radius,
                      enabled: !_busy,
                      onTap: widget.onAnswerInTerminal,
                    ),
                  ],
                ),
                SizedBox(height: spacing.sm),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: spacing.md,
                    vertical: spacing.xs + 1,
                  ),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: cs.outlineVariant.withValues(alpha: 0.55),
                    ),
                  ),
                  child: Text(
                    title,
                    style: styles.mdColored(cs.onSurface).copyWith(height: 1.3),
                  ),
                ),
                if (preview.isNotEmpty) ...[
                  SizedBox(height: spacing.sm),
                  SelectableText(
                    preview,
                    style: styles.mdColored(cs.onSurfaceVariant).copyWith(
                      height: 1.45,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
                SizedBox(height: spacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.permissionRequestCardHint,
                        style: styles.smColored(cs.onSurfaceVariant),
                      ),
                    ),
                    TpButton(
                      variant: TpButtonVariant.ghost,
                      size: TpControlSize.medium,
                      onPressed: _busy ? null : _deny,
                      child: Text(l10n.permissionRequestCardDeny),
                    ),
                    SizedBox(width: spacing.sm),
                    TpButton(
                      key: AppKeys.permissionRequestAllowButton,
                      variant: TpButtonVariant.primary,
                      size: TpControlSize.medium,
                      onPressed: _busy ? null : _allow,
                      child: Text(l10n.permissionRequestCardAllow),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Add AppKeys**

Modify `client/lib/utils/ui/app_keys.dart` — add:

```dart
  static const Key permissionRequestCard = Key('permission-request-card');
  static const Key permissionRequestAllowButton =
      Key('permission-request-allow');
```

- [ ] **Step 5: Run widget test**

Run: `cd client && flutter test test/pages/chat/permission_request_card_test.dart -v`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
cd client && git add lib/pages/chat/permission_request_card.dart \
  lib/utils/ui/app_keys.dart \
  lib/l10n/app_en.arb lib/l10n/app_zh.arb \
  test/pages/chat/permission_request_card_test.dart
git commit -m "feat(chat): PermissionRequestCard with Allow/Deny + preview"
```

---

### Task 7: Banner + chat-view integration

**Files:**
- Modify: `client/lib/pages/chat/agent_permission_attention_banner.dart`
- Modify: `client/lib/pages/chat/session_chat_view.dart`
- Test: `client/test/pages/chat/agent_permission_attention_banner_test.dart` (new)

**Interfaces:**
- Consumes: `PermissionRequestCard`, `shouldHoldInChat`-style policy via capability.
- Produces: `AgentPermissionAttentionBanner.isSelectedSeatPermissionCard(...)` and `shouldShowPermissionRequestCard(...)` (exported from the banner file or a policy file).

- [ ] **Step 1: Add `shouldShowPermissionRequestCard` policy**

Add to `client/lib/services/agent_status/hold_in_chat_policy.dart` (or a new `permission_request_policy.dart`):

```dart
import '../cli/registry/capabilities/permission_request_capability.dart';
import 'agent_status_event.dart';

/// Whether the chat should render a [PermissionRequestCard] for a waiting
/// seat whose last event is a `PermissionRequest` (vs the generic banner).
bool shouldShowPermissionRequestCard({
  required PermissionRequestCapability? capability,
  required AgentStatusEvent? lastEvent,
}) {
  if (capability == null || !capability.supportsInChatAnswer) return false;
  if (lastEvent == null) return false;
  if (lastEvent.hookEventName?.trim() != 'PermissionRequest') return false;
  return true;
}
```

(Place this in `client/lib/services/agent_status/permission_request_policy.dart` to avoid mixing UI policy into the hold policy. Update the test file `hold_in_chat_policy_test.dart` or add `permission_request_policy_test.dart` with a small truth-table test: capability off → false; lastEvent null → false; non-PermissionRequest event → false; matching → true.)

- [ ] **Step 2: Wire the banner**

Modify `client/lib/pages/chat/agent_permission_attention_banner.dart`:

- Add `import 'permission_request_card.dart';` and `import '../../services/agent_status/permission_request_policy.dart';` and `import '../../services/cli/registry/capabilities/permission_request_capability.dart';`.
- Add a static helper mirroring `isSelectedSeatAskCard`:

```dart
  /// Whether the interactive [PermissionRequestCard] is showing for the seat.
  static bool isSelectedSeatPermissionCard({
    required AgentAttentionCubit attention,
    required AppSession session,
    required String selectedMemberId,
    required CliTool seatCli,
    CliToolRegistry? registry,
  }) {
    final seatId = attentionMemberId(
      session: session,
      selectedMemberId: selectedMemberId,
    );
    final entry = attention.state.entryFor(
      sessionId: session.sessionId,
      memberId: seatId,
    );
    if (entry == null || entry.attention != AgentSeatAttention.waiting) {
      return false;
    }
    final toolRegistry = registry ?? CliToolRegistry.builtIn();
    final capability =
        toolRegistry.capability<PermissionRequestCapability>(seatCli);
    return shouldShowPermissionRequestCard(
      capability: capability,
      lastEvent: entry.lastEvent,
    );
  }
```

- In `build`, after the existing `if (showAskCard && questions != null)` block, add a permission branch (before the generic banner fallthrough):

```dart
    final showPermissionCard = shouldShowPermissionRequestCard(
      capability: registry.capability<PermissionRequestCapability>(lockedCli),
      lastEvent: entry.lastEvent,
    );
    if (showPermissionCard) {
      return PermissionRequestCard(
        session: session,
        seatId: seatId,
        toolName: entry.lastEvent?.toolName,
        toolInputPreview: entry.lastEvent?.toolInput,
        onAnswerInTerminal: () => _openTerminal(
          context,
          sessionId: sessionId,
          seatId: seatId,
          selectedMemberId: selectedMemberId,
        ),
      );
    }
```

- [ ] **Step 3: Hide compose when the permission card shows**

Modify `client/lib/pages/chat/session_chat_view.dart` — the `askCardVisible` select (~line 1182). Replace with a combined selector:

```dart
    final cardVisible = context.select<AgentAttentionCubit, bool>(
      (c) =>
          AgentPermissionAttentionBanner.isSelectedSeatAskCard(
            attention: c,
            session: session,
            selectedMemberId: selectedMemberId,
            seatCli: lockedCli,
            registry: CliToolRegistryScope.maybeOf(context),
          ) ||
          AgentPermissionAttentionBanner.isSelectedSeatPermissionCard(
            attention: c,
            session: session,
            selectedMemberId: selectedMemberId,
            seatCli: lockedCli,
            registry: CliToolRegistryScope.maybeOf(context),
          ),
    );
```

Then change the `if (!askCardVisible)` compose gate at ~line 1629 to `if (!cardVisible)`.

- [ ] **Step 4: Add a banner test**

Create `client/test/pages/chat/agent_permission_attention_banner_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/chat/agent_permission_attention_banner.dart';
import 'package:teampilot/services/agent_status/agent_attention_state.dart';
import 'package:teampilot/services/agent_status/agent_status_event.dart';

AppSession _simpleSession(String id) {
  return AppSession(
    sessionId: id,
    workspaceId: 'ws-1',
    folders: const [WorkspaceFolder(path: '/tmp')],
    createdAt: 1,
    updatedAt: 1,
    cli: CliTool.claude,
  );
}

void main() {
  test('isSelectedSeatPermissionCard true for Bash PermissionRequest waiting',
      () {
    final attention = AgentAttentionCubit(pruneInterval: null);
    addTearDown(attention.close);
    // Simple seat: the attention seat id equals the session id.
    attention.applyEvent(
      sessionId: 's',
      memberId: 's',
      event: const AgentStatusEvent(
        state: AgentSeatAttention.waiting,
        hookEventName: 'PermissionRequest',
        toolName: 'Bash',
        toolInput: 'rm -rf build',
      ),
      skipPermissions: false,
    );
    expect(
      AgentPermissionAttentionBanner.isSelectedSeatPermissionCard(
        attention: attention,
        session: _simpleSession('s'),
        selectedMemberId: 's',
        seatCli: CliTool.claude,
      ),
      isTrue,
    );
  });

  test('isSelectedSeatPermissionCard false for non-permission waiting', () {
    final attention = AgentAttentionCubit(pruneInterval: null);
    addTearDown(attention.close);
    attention.applyEvent(
      sessionId: 's',
      memberId: 's',
      event: const AgentStatusEvent(
        state: AgentSeatAttention.waiting,
        hookEventName: 'PreToolUse',
        toolName: 'Bash',
      ),
      skipPermissions: false,
    );
    expect(
      AgentPermissionAttentionBanner.isSelectedSeatPermissionCard(
        attention: attention,
        session: _simpleSession('s'),
        selectedMemberId: 's',
        seatCli: CliTool.claude,
      ),
      isFalse,
    );
  });
}
```

> **Note:** For a simple session the seat id is the session id — seed attention with `memberId: sessionId`. Capability resolve uses `CliToolRegistry.builtIn()` (claude → `ClaudePermissionRequestCapability` → true).

- [ ] **Step 5: Run banner + policy + chat view tests**

Run: `cd client && flutter test test/pages/chat/agent_permission_attention_banner_test.dart test/services/agent_status/permission_request_policy_test.dart -v`
Expected: PASS. Also run `flutter analyze` on the two modified files to catch unused-import / rename fallout from the `askCardVisible` → `cardVisible` change.

- [ ] **Step 6: Commit**

```bash
cd client && git add lib/services/agent_status/permission_request_policy.dart \
  lib/pages/chat/agent_permission_attention_banner.dart \
  lib/pages/chat/session_chat_view.dart \
  test/services/agent_status/permission_request_policy_test.dart \
  test/pages/chat/agent_permission_attention_banner_test.dart
git commit -m "feat(chat): render PermissionRequestCard + hide compose while waiting"
```

---

### Task 8: Full verification

**Files:** none (verification only).

- [ ] **Step 1: Run analyzer**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: no errors introduced (address any unused-import or missing-import fallout from the wiring changes).

- [ ] **Step 2: Run the affected test suites**

Run: `cd client && flutter test test/services/agent_status test/services/terminal/ask_user_question_answer_service_test.dart test/cubits/chat_cubit_ask_user_answer_test.dart test/cubits/agent_attention_cubit_test.dart test/pages/chat/permission_request_card_test.dart test/pages/chat/agent_permission_attention_banner_test.dart -v`
Expected: all PASS.

- [ ] **Step 3: Run the full non-integration suite**

Run: `cd client && flutter test --exclude-tags integration`
Expected: all PASS (address any regressions from the `setSessionWorkbenchView` release and the handler changes).

- [ ] **Step 4: Commit any fixup**

```bash
git add -A
git commit -m "fix: verify permission-request-in-chat changes (analyze + tests)"
```

---

## Self-review notes

- **Spec coverage:** capability (Task 1), gate (Task 2), hold policy + fallthrough (Task 3), handler hold + decision JSON + view-aware AskUserQuestion (Task 4), wiring + cubit answer/deny + release-on-view-switch (Task 5), card + l10n (Task 6), banner render + compose hidden + `isSelectedSeatPermissionCard` (Task 7), verification (Task 8). AskUserQuestion `_openTerminal` dead button is fixed by the release-on-view-switch in Task 5 (no separate banner change needed). Non-goals (Always allow, OpenCode `permission.asked`, Cursor) untouched.
- **Type consistency:** `PermissionDecisionAllow/Deny/Fallthrough` (Task 2) used in handler (Task 4), cubit (Task 5), tests. `shouldHoldInChat` (Task 3) consumed by handler logic (Task 4). `releaseForSession` on both gates (Tasks 2–3) consumed by `setSessionWorkbenchView` (Task 5). `isSelectedSeatPermissionCard` (Task 7) consumed by `session_chat_view.dart` compose gate (Task 7). Permission dismiss uses `markPermissionAnswered` (added Task 5) — `markAskAnswered` requires an `askRequestId` which `PermissionRequest` events never carry.
