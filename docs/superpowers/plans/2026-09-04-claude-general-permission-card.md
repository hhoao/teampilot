# Claude Family General Permission Card Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render a general tool permission request from Claude-family CLIs (claude, flashskyai, codex) as an interactive `AiPermissionCard` in chat (Allow once / Always allow / Deny / Answer in terminal) by holding the official `PermissionRequest` HTTP hook and replying with the `decision` object.

**Architecture:** Mirror the shipped ExitPlanMode hold pattern: a generic `SeatHoldGate<TReply>` primitive (extracted from `ExitPlanPermissionRequestGate`), a new `GeneralPermissionRequestGate` + responder projection with routing strictly complementary to the ExitPlanMode projection, normalizer payload for non-ExitPlanMode `PermissionRequest` events, and per-channel answer routing in `ChatCubit` (OpenCode plugin SDK vs Claude hook hold).

**Tech Stack:** Flutter (`client/`, package `teampilot`), `flutter_bloc`, vendored `client/packages/ai_message_ui` + `ai_message_core`, Claude Code HTTP hooks.

**Spec:** `docs/superpowers/specs/2026-09-04-claude-general-permission-card-design.md`

## Global Constraints

- Verify before claiming done: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart` (see `docs/DEVELOPMENT.md`).
- Layering: `services/` must not import `ai_message_ui`/`ai_message_core` — that is why `AgentPermissionReplyKind` lives host-side in `agent_permission_request.dart`.
- l10n: edit `client/lib/l10n/app_en.arb` and `app_zh.arb` only; existing getters use the `opencodePermission*` prefix.
- Zero behavior change to ExitPlanMode / AskUserQuestion paths (existing tests must pass unmodified except where a task explicitly updates one).
- The working tree has ~3300 lines of in-flight related changes — build on top of them; do not revert or "clean up" unrelated modifications.
- Follow the existing deny-on-replace + 24h-timeout gate lifecycle; do not invent new session-clear wiring.

## File Structure

| File | Responsibility |
|------|----------------|
| `client/lib/services/agent_status/agent_permission_request.dart` (modify) | `AgentPermissionAlwaysOption`, `AgentPermissionReplyKind`, `parseClaudePermissionRequest`, OpenCode parse mapping |
| `client/lib/services/agent_status/seat_hold_gate.dart` (create) | Generic seat-keyed single-slot hook-hold primitive |
| `client/lib/services/agent_status/exit_plan_mode_hook_gate.dart` (modify) | `ExitPlanPermissionRequestGate` refactored onto `SeatHoldGate` (behavior-preserving) |
| `client/lib/services/agent_status/general_permission_request_gate.dart` (create) | `GeneralPermissionRequestReply` (official `decision` JSON) + `GeneralPermissionRequestGate` |
| `client/lib/services/cli/registry/capabilities/claude_family_agent_status_normalizer.dart` (modify) | Build `permissionRequest` for general `PermissionRequest` events |
| `client/lib/services/agent_runtime/runtime_event_projection.dart` (modify) | `GeneralPermissionRuntimeEventProjection` responder |
| `client/lib/services/agent_runtime/agent_event_gateway.dart` (modify) | `forAttention` factory param for the new gate |
| `client/lib/services/cli/{claude,flashskyai,codex}/capabilities/chat_interaction.dart` (modify) | `supportsInChatPermissionReply => true` |
| `client/lib/services/agent_status/ask_user_question_policy.dart` (modify) | Channel-conditional `askRequestId` gating |
| `client/lib/services/terminal/ask_user_question_answer_service.dart` (modify) | Per-channel answer routing + `releasePermission` |
| `client/lib/cubits/chat_cubit.dart` (modify) | `answerPermissionRequest` kind-based signature, `releasePermissionToTerminal` |
| `client/packages/ai_message_ui/lib/src/tool_chrome/permission_card.dart` (modify) | `AiPermissionReply` API + multiple always options |
| `client/lib/pages/chat/agent_permission_attention_banner.dart` (modify) | Render card for Claude family, always-option labels, terminal release |
| `client/lib/l10n/app_en.arb`, `app_zh.arb` (modify) | `agentPermissionAlwaysAllowRule` |
| `client/lib/app/app_shell.dart` (modify) | Production wiring of gate + projection + service |

---

### Task 1: Permission request model — structured always options + Claude parser

**Files:**
- Modify: `client/lib/services/agent_status/agent_permission_request.dart`
- Test: `client/test/services/agent_status/agent_permission_request_test.dart` (create; if a test for this file already exists, extend it)

**Interfaces:**
- Produces (used by Tasks 4, 7, 9, 10):
  - `class AgentPermissionAlwaysOption { final String label; final Object? payload; }` — `label` is the raw rule text (e.g. `Bash(rm -rf node_modules)`), `payload` is `null` for OpenCode prefixes and the raw suggestion `Map<String, Object?>` for Claude.
  - `enum AgentPermissionReplyKind { allowOnce, always, reject }`
  - `AgentPermissionRequest.always` changes type to `List<AgentPermissionAlwaysOption>` (was `List<String>`).
  - `AgentPermissionRequest? parseClaudePermissionRequest(Map<String, Object?> body, {required String toolName, required String? toolInputPreview})` — returns a request with empty `id` (hook-hold channel has no reply id).

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/agent_status/agent_permission_request.dart';

void main() {
  group('parseClaudePermissionRequest', () {
    test('builds description from tool name + input preview and echoes addRules suggestions', () {
      final request = parseClaudePermissionRequest(
        {
          'tool_name': 'Bash',
          'tool_input': {'command': 'rm -rf node_modules'},
          'permission_suggestions': [
            {
              'type': 'addRules',
              'rules': [
                {'toolName': 'Bash', 'ruleContent': 'rm -rf node_modules'},
              ],
              'behavior': 'allow',
              'destination': 'localSettings',
            },
            {'type': 'setMode', 'mode': 'auto', 'destination': 'session'},
          ],
        },
        toolName: 'Bash',
        toolInputPreview: 'rm -rf node_modules',
      );
      expect(request, isNotNull);
      expect(request!.id, '');
      expect(request.description, 'Bash rm -rf node_modules');
      expect(request.patterns, isEmpty);
      // Only addRules entries become always options; setMode is skipped (v1).
      expect(request.always, hasLength(1));
      expect(request.always.first.label, 'Bash(rm -rf node_modules)');
      expect(request.always.first.payload, isA<Map<String, Object?>>());
      expect(
        (request.always.first.payload as Map)['type'],
        'addRules',
      );
    });

    test('whole-tool addRules suggestion has bare tool label', () {
      final request = parseClaudePermissionRequest(
        {
          'tool_name': 'WebFetch',
          'tool_input': {'url': 'https://example.com'},
          'permission_suggestions': [
            {
              'type': 'addRules',
              'rules': [
                {'toolName': 'WebFetch'},
              ],
              'behavior': 'allow',
              'destination': 'session',
            },
          ],
        },
        toolName: 'WebFetch',
        toolInputPreview: 'https://example.com',
      );
      expect(request!.always.first.label, 'WebFetch');
    });

    test('returns null without a tool name', () {
      expect(
        parseClaudePermissionRequest(
          const {},
          toolName: '',
          toolInputPreview: null,
        ),
        isNull,
      );
    });

    test('description falls back to tool name without input preview', () {
      final request = parseClaudePermissionRequest(
        {'tool_name': 'Bash'},
        toolName: 'Bash',
        toolInputPreview: null,
      );
      expect(request!.description, 'Bash');
    });
  });

  group('parsePermissionRequest (OpenCode)', () {
    test('always prefixes map to options with null payload and prefix label', () {
      final request = parsePermissionRequest(const {
        'request_id': 'perm-1',
        'permission': 'Run `npm install`',
        'always': ['Bash', 'Bash(npm install:*)'],
      });
      expect(request!.always, hasLength(2));
      expect(request.always.first.label, 'Bash');
      expect(request.always.first.payload, isNull);
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd client && flutter test test/services/agent_status/agent_permission_request_test.dart`
Expected: FAIL — `AgentPermissionAlwaysOption` / `parseClaudePermissionRequest` undefined, `always` type mismatch.

- [ ] **Step 3: Implement**

In `agent_permission_request.dart`:

1. Add before `AgentPermissionRequest`:

```dart
/// One "always allow" option on a permission card.
///
/// [label] is the raw rule text shown to the user (e.g.
/// `Bash(rm -rf node_modules)`); [payload] is opaque channel data — the
/// OpenCode SDK prefix string (unused on reply) or the raw Claude
/// `permission_suggestions` entry echoed back as `updatedPermissions`.
class AgentPermissionAlwaysOption {
  const AgentPermissionAlwaysOption({required this.label, this.payload});

  final String label;
  final Object? payload;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentPermissionAlwaysOption && label == other.label;

  @override
  int get hashCode => label.hashCode;
}

/// User's card reply, shared by both answer channels.
enum AgentPermissionReplyKind { allowOnce, always, reject }
```

2. Change `AgentPermissionRequest.always` to `List<AgentPermissionAlwaysOption>` and update `==`/`hashCode` to use `Object.hashAll(always)` (already the pattern — only the element type changes).

3. In `parsePermissionRequest` (OpenCode), map prefixes:

```dart
final always = _readStringList(body['always'])
    .map((prefix) => AgentPermissionAlwaysOption(label: prefix))
    .toList();
```

4. Add the Claude-family parser:

```dart
/// Parses a Claude-family `PermissionRequest` hook payload into an
/// [AgentPermissionRequest]. The hook-hold channel correlates replies by the
/// gate's seat key, so the request carries no reply id (`id` is empty).
///
/// Only `addRules` suggestions become always options (v1): `setMode`-style
/// suggestions are skipped. The raw suggestion entry is kept as the option
/// [AgentPermissionAlwaysOption.payload] for the `updatedPermissions` echo.
AgentPermissionRequest? parseClaudePermissionRequest(
  Map<String, Object?> body, {
  required String toolName,
  required String? toolInputPreview,
}) {
  if (toolName.trim().isEmpty) return null;
  final preview = toolInputPreview?.trim() ?? '';
  final description = preview.isEmpty ? toolName : '$toolName $preview';

  final always = <AgentPermissionAlwaysOption>[];
  final suggestions = body['permission_suggestions'];
  if (suggestions is List) {
    for (final suggestion in suggestions) {
      if (suggestion is! Map || suggestion['type'] != 'addRules') continue;
      final label = _claudeAddRulesLabel(Map<String, Object?>.from(suggestion));
      if (label.isEmpty) continue;
      always.add(
        AgentPermissionAlwaysOption(
          label: label,
          payload: Map<String, Object?>.from(suggestion),
        ),
      );
    }
  }

  return AgentPermissionRequest(
    id: '',
    description: description,
    patterns: const [],
    always: always,
  );
}

String _claudeAddRulesLabel(Map<String, Object?> suggestion) {
  final rules = suggestion['rules'];
  if (rules is! List || rules.isEmpty || rules.first is! Map) return '';
  final first = Map<String, Object?>.from(rules.first as Map);
  final tool = first['toolName']?.toString().trim() ?? '';
  if (tool.isEmpty) return '';
  final ruleContent = first['ruleContent']?.toString().trim() ?? '';
  return ruleContent.isEmpty ? tool : '$tool($ruleContent)';
}
```

5. Fix any other compile errors from the `always` type change (`grep -rn "\.always" client/lib client/test` — the banner uses `always.isNotEmpty`, which still compiles; OpenCode answer paths use the reply string, not `always`).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd client && flutter test test/services/agent_status/agent_permission_request_test.dart`
Expected: PASS

- [ ] **Step 5: Run the analyzer**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: No new errors (warnings about the changed type in tests that referenced `always` as strings — fix those tests to the new type).

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/agent_status/agent_permission_request.dart client/test/services/agent_status/agent_permission_request_test.dart
git commit -m "feat(permission): structured always options + Claude PermissionRequest parser"
```

---

### Task 2: `SeatHoldGate<TReply>` primitive + behavior-preserving ExitPlan refactor

**Files:**
- Create: `client/lib/services/agent_status/seat_hold_gate.dart`
- Modify: `client/lib/services/agent_status/exit_plan_mode_hook_gate.dart` (only the `ExitPlanPermissionRequestGate` class, lines ~149-260)
- Test: `client/test/services/agent_status/seat_hold_gate_test.dart` (create)
- Test (regression): `client/test/services/agent_status/exit_plan_mode_hook_gate_test.dart` (must pass unmodified)

**Interfaces:**
- Produces (used by Task 3):

```dart
final class SeatHoldGate<TReply> {
  SeatHoldGate({required TReply Function() staleReply});
  Future<TReply?> wait({required String sessionId, required String memberId,
      Duration timeout = const Duration(hours: 24)});        // null = timeout/fall-through
  bool complete({required String sessionId, required String memberId, required TReply reply});
  bool releaseHold({required String sessionId, required String memberId}); // resolves null → gateway answers {}
  bool hasWaiter({required String sessionId, required String memberId});
  void clearSeat({required String sessionId, required String memberId});
  void clearSession(String sessionId);
}
```

- [ ] **Step 1: Write the failing primitive tests**

```dart
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/agent_status/seat_hold_gate.dart';

void main() {
  SeatHoldGate<String> gate() =>
      SeatHoldGate<String>(staleReply: () => 'stale');

  test('wait completes with the reply from complete', () async {
    final g = gate();
    final future = g.wait(sessionId: 's', memberId: 'm');
    expect(g.hasWaiter(sessionId: 's', memberId: 'm'), isTrue);
    expect(g.complete(sessionId: 's', memberId: 'm', reply: 'allow'), isTrue);
    expect(await future, 'allow');
    expect(g.hasWaiter(sessionId: 's', memberId: 'm'), isFalse);
  });

  test('a second wait resolves the first with the stale reply', () async {
    final g = gate();
    final first = g.wait(sessionId: 's', memberId: 'm');
    final second = g.wait(sessionId: 's', memberId: 'm');
    expect(await first, 'stale');
    g.complete(sessionId: 's', memberId: 'm', reply: 'allow');
    expect(await second, 'allow');
  });

  test('releaseHold resolves null (fall-through to native TUI)', () async {
    final g = gate();
    final future = g.wait(sessionId: 's', memberId: 'm');
    expect(g.releaseHold(sessionId: 's', memberId: 'm'), isTrue);
    expect(await future, isNull);
  });

  test('timeout resolves null', () async {
    final g = gate();
    final future = g.wait(
      sessionId: 's',
      memberId: 'm',
      timeout: const Duration(milliseconds: 10),
    );
    expect(await future, isNull);
    expect(g.hasWaiter(sessionId: 's', memberId: 'm'), isFalse);
  });

  test('complete returns false with no waiter', () async {
    final g = gate();
    expect(g.complete(sessionId: 's', memberId: 'm', reply: 'allow'), isFalse);
  });

  test('clearSeat and clearSession resolve held waiters with the stale reply',
      () async {
    final g = gate();
    final a = g.wait(sessionId: 's1', memberId: 'm1');
    final b = g.wait(sessionId: 's2', memberId: 'm2');
    g.clearSeat(sessionId: 's1', memberId: 'm1');
    g.clearSession('s2');
    expect(await a, 'stale');
    expect(await b, 'stale');
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd client && flutter test test/services/agent_status/seat_hold_gate_test.dart`
Expected: FAIL — `seat_hold_gate.dart` does not exist.

- [ ] **Step 3: Implement the primitive**

Create `client/lib/services/agent_status/seat_hold_gate.dart` with exactly the mechanics currently in `ExitPlanPermissionRequestGate` (lines 156-259 of `exit_plan_mode_hook_gate.dart`), generalized:

```dart
import 'dart:async';

/// Generic single-slot, seat-keyed HTTP-hook hold.
///
/// One held waiter per `(sessionId, memberId)` seat. A newer [wait] resolves
/// the previous waiter with [staleReply]; [releaseHold] resolves `null` so the
/// gateway answers `{}` and the CLI's native prompt takes over; a timeout
/// resolves `null` the same way. Extracted from
/// `ExitPlanPermissionRequestGate` — that class keeps only its plan-fingerprint
/// decision memory on top of this primitive.
final class SeatHoldGate<TReply> {
  SeatHoldGate({required this.staleReply});

  /// Reply applied to a waiter replaced by a newer hold or cleared by
  /// [clearSeat] / [clearSession] (deny semantics for permissions).
  final TReply Function() staleReply;

  final _waiters = <String, Completer<TReply?>>{};

  Future<TReply?> wait({
    required String sessionId,
    required String memberId,
    Duration timeout = const Duration(hours: 24),
  }) async {
    final key = _key(sessionId, memberId);
    final existing = _waiters.remove(key);
    if (existing != null && !existing.isCompleted) {
      existing.complete(staleReply());
    }
    final completer = Completer<TReply?>();
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
    required TReply reply,
  }) {
    final completer = _waiters.remove(_key(sessionId, memberId));
    if (completer == null || completer.isCompleted) return false;
    completer.complete(reply);
    return true;
  }

  /// Active fall-through: resolves the held waiter with `null` so the gateway
  /// answers `{}` and the native TUI prompt appears.
  bool releaseHold({required String sessionId, required String memberId}) {
    final completer = _waiters.remove(_key(sessionId, memberId));
    if (completer == null || completer.isCompleted) return false;
    completer.complete(null);
    return true;
  }

  bool hasWaiter({required String sessionId, required String memberId}) {
    final completer = _waiters[_key(sessionId, memberId)];
    return completer != null && !completer.isCompleted;
  }

  void clearSeat({required String sessionId, required String memberId}) {
    final completer = _waiters.remove(_key(sessionId, memberId));
    if (completer != null && !completer.isCompleted) {
      completer.complete(staleReply());
    }
  }

  void clearSession(String sessionId) {
    final prefix = '${sessionId.trim()}/';
    final doomed = _waiters.keys
        .where((key) => key.startsWith(prefix))
        .toList();
    for (final key in doomed) {
      final completer = _waiters.remove(key);
      if (completer != null && !completer.isCompleted) {
        completer.complete(staleReply());
      }
    }
  }

  String _key(String sessionId, String memberId) =>
      '${sessionId.trim()}/${memberId.trim()}';
}
```

- [ ] **Step 4: Run the primitive tests**

Run: `cd client && flutter test test/services/agent_status/seat_hold_gate_test.dart`
Expected: PASS

- [ ] **Step 5: Refactor `ExitPlanPermissionRequestGate` onto the primitive (behavior-preserving)**

In `exit_plan_mode_hook_gate.dart`, replace the waiter map mechanics of `ExitPlanPermissionRequestGate` with a composed `SeatHoldGate<ExitPlanPermissionRequestReply>` while keeping the public API byte-for-byte identical (`wait({sessionId, memberId, planFingerprint, timeout})`, `complete`, `hasWaiter`, `remember`, `forget`, `clearSeat`, `clearSession`):

```dart
final class ExitPlanPermissionRequestGate {
  ExitPlanPermissionRequestGate()
    : _hold = SeatHoldGate<ExitPlanPermissionRequestReply>(
        staleReply: () => const ExitPlanPermissionRequestReply.deny(),
      );

  final SeatHoldGate<ExitPlanPermissionRequestReply> _hold;
  final _remembered = <String, _RememberedPlanDecision>{};

  Future<ExitPlanPermissionRequestReply?> wait({
    required String sessionId,
    required String memberId,
    required String planFingerprint,
    Duration timeout = const Duration(hours: 24),
  }) async {
    final key = _key(sessionId, memberId);
    final remembered = _remembered.remove(key);
    if (remembered != null && remembered.fingerprint == planFingerprint) {
      return remembered.deny
          ? const ExitPlanPermissionRequestReply.deny()
          : const ExitPlanPermissionRequestReply.allow();
    }
    return _hold.wait(
      sessionId: sessionId,
      memberId: memberId,
      timeout: timeout,
    );
  }

  bool complete({
    required String sessionId,
    required String memberId,
    required ExitPlanPermissionRequestReply reply,
  }) => _hold.complete(
    sessionId: sessionId,
    memberId: memberId,
    reply: reply,
  );

  bool hasWaiter({required String sessionId, required String memberId}) =>
      _hold.hasWaiter(sessionId: sessionId, memberId: memberId);

  // remember / forget / clearSeat / clearSession keep their current bodies,
  // delegating waiter cleanup to _hold.clearSeat / _hold.clearSession.
  // _key stays '${sessionId.trim()}/${memberId.trim()}'.
}
```

Delete the now-dead `_waiters` map and waiter-loop code from the class. `ExitPlanModeHookGate` (the tool_use_id-keyed gate above it) is NOT touched.

- [ ] **Step 6: Run the ExitPlan regression suite**

Run: `cd client && flutter test test/services/agent_status/exit_plan_mode_hook_gate_test.dart test/services/agent_status/agent_status_http_handler_exit_plan_test.dart test/services/terminal/exit_plan_mode_approval_service_test.dart`
Expected: PASS, unmodified.

- [ ] **Step 7: Commit**

```bash
git add client/lib/services/agent_status/seat_hold_gate.dart client/lib/services/agent_status/exit_plan_mode_hook_gate.dart client/test/services/agent_status/seat_hold_gate_test.dart
git commit -m "refactor(agent-status): extract SeatHoldGate primitive from ExitPlanPermissionRequestGate"
```

---

### Task 3: `GeneralPermissionRequestGate` + reply

**Files:**
- Create: `client/lib/services/agent_status/general_permission_request_gate.dart`
- Test: `client/test/services/agent_status/general_permission_request_gate_test.dart` (create)

**Interfaces:**
- Consumes: `SeatHoldGate` (Task 2), `AgentPermissionAlwaysOption.payload` echo shape (Task 1).
- Produces (used by Tasks 5, 8, 9, 11):

```dart
final class GeneralPermissionRequestReply {
  const GeneralPermissionRequestReply.allow({List<Map<String, Object?>> updatedPermissions = const []});
  const GeneralPermissionRequestReply.deny(String? message);
  Map<String, Object?> toHookResponse();  // official PermissionRequest decision JSON
}

final class GeneralPermissionRequestGate {
  Future<GeneralPermissionRequestReply?> wait({required String sessionId, required String memberId, Duration timeout});
  bool complete({required String sessionId, required String memberId, required GeneralPermissionRequestReply reply});
  bool releaseHold({required String sessionId, required String memberId});
  bool hasWaiter({required String sessionId, required String memberId});
  void clearSeat({required String sessionId, required String memberId});
  void clearSession(String sessionId);
}
```

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/agent_status/general_permission_request_gate.dart';

void main() {
  test('allow reply renders the official decision object', () {
    final reply = GeneralPermissionRequestReply.allow(
      updatedPermissions: [
        {
          'type': 'addRules',
          'rules': [
            {'toolName': 'Bash', 'ruleContent': 'rm -rf node_modules'},
          ],
          'behavior': 'allow',
          'destination': 'localSettings',
        },
      ],
    );
    expect(reply.toHookResponse(), {
      'hookSpecificOutput': {
        'hookEventName': 'PermissionRequest',
        'decision': {
          'behavior': 'allow',
          'updatedPermissions': [
            {
              'type': 'addRules',
              'rules': [
                {'toolName': 'Bash', 'ruleContent': 'rm -rf node_modules'},
              ],
              'behavior': 'allow',
              'destination': 'localSettings',
            },
          ],
        },
      },
    });
  });

  test('plain allow omits updatedPermissions', () {
    expect(
      const GeneralPermissionRequestReply.allow().toHookResponse(),
      {
        'hookSpecificOutput': {
          'hookEventName': 'PermissionRequest',
          'decision': {'behavior': 'allow'},
        },
      },
    );
  });

  test('deny reply carries the message', () {
    expect(
      const GeneralPermissionRequestReply.deny('User denied via TeamPilot')
          .toHookResponse(),
      {
        'hookSpecificOutput': {
          'hookEventName': 'PermissionRequest',
          'decision': {
            'behavior': 'deny',
            'message': 'User denied via TeamPilot',
          },
        },
      },
    );
  });

  test('gate hold/complete/releaseHold lifecycle', () async {
    final gate = GeneralPermissionRequestGate();
    final held = gate.wait(sessionId: 's', memberId: 'm');
    expect(gate.hasWaiter(sessionId: 's', memberId: 'm'), isTrue);
    expect(
      gate.complete(
        sessionId: 's',
        memberId: 'm',
        reply: const GeneralPermissionRequestReply.allow(),
      ),
      isTrue,
    );
    expect(await held, isA<GeneralPermissionRequestReply>());
    expect(gate.hasWaiter(sessionId: 's', memberId: 'm'), isFalse);
  });

  test('releaseHold falls through to the native TUI', () async {
    final gate = GeneralPermissionRequestGate();
    final held = gate.wait(sessionId: 's', memberId: 'm');
    expect(gate.releaseHold(sessionId: 's', memberId: 'm'), isTrue);
    expect(await held, isNull);
  });

  test('a newer wait denies the previous held request', () async {
    final gate = GeneralPermissionRequestGate();
    final first = gate.wait(sessionId: 's', memberId: 'm');
    gate.wait(sessionId: 's', memberId: 'm');
    final reply = await first;
    expect(reply, isNotNull);
    expect(reply!.deny, isTrue);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd client && flutter test test/services/agent_status/general_permission_request_gate_test.dart`
Expected: FAIL — file does not exist.

- [ ] **Step 3: Implement**

Create `client/lib/services/agent_status/general_permission_request_gate.dart`:

```dart
import 'seat_hold_gate.dart';

/// Reply for a held Claude-family general `PermissionRequest` hook — the
/// official `decision` object (see Claude Code hooks reference:
/// "PermissionRequest decision control").
///
/// `updatedPermissions` echoes a `permission_suggestions` entry for
/// "always allow" persistence; a hook allow never overrides a matching deny
/// rule (official semantics).
final class GeneralPermissionRequestReply {
  const GeneralPermissionRequestReply.allow({
    this.updatedPermissions = const [],
  }) : deny = false,
       message = null;

  const GeneralPermissionRequestReply.deny(this.message) : deny = true,
       updatedPermissions = const [];

  final bool deny;

  /// Deny reason shown to Claude (allow it to adapt).
  final String? message;

  /// Echoed `permission_suggestions` entries (allow + always only).
  final List<Map<String, Object?>> updatedPermissions;

  Map<String, Object?> toHookResponse() => {
    'hookSpecificOutput': {
      'hookEventName': 'PermissionRequest',
      'decision': {
        'behavior': deny ? 'deny' : 'allow',
        if (!deny && updatedPermissions.isNotEmpty)
          'updatedPermissions': updatedPermissions,
        if (deny && message != null) 'message': message,
      },
    },
  };
}

/// Holds open Claude-family general `PermissionRequest` HTTP hooks until the
/// chat card answers. Seat-keyed single slot: Claude blocks the turn while a
/// permission decision is pending, so one seat has at most one live request.
///
/// Parallel to `ExitPlanPermissionRequestGate`; releaseHold answers `{}` so
/// the native TUI prompt takes over (card "answer in terminal").
final class GeneralPermissionRequestGate {
  GeneralPermissionRequestGate()
    : _hold = SeatHoldGate<GeneralPermissionRequestReply>(
        staleReply: () => const GeneralPermissionRequestReply.deny(
          'Replaced by a newer permission request',
        ),
      );

  final SeatHoldGate<GeneralPermissionRequestReply> _hold;

  Future<GeneralPermissionRequestReply?> wait({
    required String sessionId,
    required String memberId,
    Duration timeout = const Duration(hours: 24),
  }) => _hold.wait(sessionId: sessionId, memberId: memberId, timeout: timeout);

  bool complete({
    required String sessionId,
    required String memberId,
    required GeneralPermissionRequestReply reply,
  }) => _hold.complete(
    sessionId: sessionId,
    memberId: memberId,
    reply: reply,
  );

  bool releaseHold({required String sessionId, required String memberId}) =>
      _hold.releaseHold(sessionId: sessionId, memberId: memberId);

  bool hasWaiter({required String sessionId, required String memberId}) =>
      _hold.hasWaiter(sessionId: sessionId, memberId: memberId);

  void clearSeat({required String sessionId, required String memberId}) =>
      _hold.clearSeat(sessionId: sessionId, memberId: memberId);

  void clearSession(String sessionId) => _hold.clearSession(sessionId);
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd client && flutter test test/services/agent_status/general_permission_request_gate_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/agent_status/general_permission_request_gate.dart client/test/services/agent_status/general_permission_request_gate_test.dart
git commit -m "feat(agent-status): GeneralPermissionRequestGate with official decision replies"
```

---

### Task 4: Normalizer builds the general permission payload (Claude family)

**Files:**
- Modify: `client/lib/services/cli/registry/capabilities/claude_family_agent_status_normalizer.dart`
- Test: `client/test/services/cli/registry/capabilities/claude_family_agent_status_normalizer_test.dart` (extend; create if absent)

**Interfaces:**
- Consumes: `parseClaudePermissionRequest` (Task 1).
- Produces: `AgentStatusEvent.permissionRequest` populated for `PermissionRequest` events whose tool is neither `AskUserQuestion` nor `ExitPlanMode` (used by Tasks 5, 10).

- [ ] **Step 1: Write the failing tests**

```dart
test('PermissionRequest for a general tool carries a permissionRequest payload',
    () {
  final status = const ClaudeFamilyAgentStatusNormalizer().normalize({
    'hook_event_name': 'PermissionRequest',
    'tool_name': 'Bash',
    'tool_input': {'command': 'rm -rf node_modules'},
    'permission_suggestions': [
      {
        'type': 'addRules',
        'rules': [
          {'toolName': 'Bash', 'ruleContent': 'rm -rf node_modules'},
        ],
        'behavior': 'allow',
        'destination': 'localSettings',
      },
    ],
  });
  expect(status, isNotNull);
  expect(status!.state, AgentSeatAttention.waiting);
  expect(status.permissionRequest, isNotNull);
  expect(status.permissionRequest!.description, contains('Bash'));
  expect(status.permissionRequest!.always, hasLength(1));
  expect(status.permissionRequest!.always.first.label,
      'Bash(rm -rf node_modules)');
});

test('PermissionRequest for ExitPlanMode carries no permissionRequest payload',
    () {
  final status = const ClaudeFamilyAgentStatusNormalizer().normalize({
    'hook_event_name': 'PermissionRequest',
    'tool_name': 'ExitPlanMode',
    'tool_input': {'plan': 'Do the thing'},
  });
  expect(status, isNotNull);
  expect(status!.state, AgentSeatAttention.waiting);
  expect(status.permissionRequest, isNull);
  expect(status.planText, isNotNull); // plan card path, unchanged
});
```

(Add to the existing normalizer test group; import `agent_attention_state.dart` for `AgentSeatAttention`.)

- [ ] **Step 2: Run to verify failure**

Run: `cd client && flutter test test/services/cli/registry/capabilities/claude_family_agent_status_normalizer_test.dart`
Expected: FAIL — `permissionRequest` is null for the general tool.

- [ ] **Step 3: Implement**

In `ClaudeFamilyAgentStatusNormalizer.normalize`, after `toolInput` is derived and before `build`:

```dart
// General Claude-family permission request (not AskUserQuestion /
// ExitPlanMode, which have their own card paths).
final permissionRequest =
    eventName == 'PermissionRequest' && !askUser && !exitPlan
        ? parseClaudePermissionRequest(
            body,
            toolName: toolName ?? '',
            toolInputPreview: toolInput,
          )
        : null;
```

Add `permissionRequest: permissionRequest` to the `build()` constructor call. Add the import `import '../../../agent_status/agent_permission_request.dart';`. Existing behavior for every other event (including OpenCode's `parsePermissionRequest` in its own normalizer) is untouched.

- [ ] **Step 4: Run to verify pass + regression**

Run: `cd client && flutter test test/services/cli/registry/capabilities/claude_family_agent_status_normalizer_test.dart test/services/agent_status/claude_permission_sticky_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/cli/registry/capabilities/claude_family_agent_status_normalizer.dart client/test/services/cli/registry/capabilities/claude_family_agent_status_normalizer_test.dart
git commit -m "feat(claude): normalize general PermissionRequest payloads for the chat card"
```

---

### Task 5: `GeneralPermissionRuntimeEventProjection` responder

**Files:**
- Modify: `client/lib/services/agent_runtime/runtime_event_projection.dart`
- Modify: `client/lib/services/agent_runtime/agent_event_gateway.dart` (`forAttention` factory only)
- Test: `client/test/services/agent_runtime/runtime_event_projection_test.dart` (extend)

**Interfaces:**
- Consumes: `GeneralPermissionRequestGate` (Task 3), `isExitPlanModeTool` / `isAskUserQuestionTool` from `exit_plan_mode.dart` / `ask_user_question.dart`, `ChatInteractionCapability.supportsInChatPermissionReply`.
- Produces:

```dart
final class GeneralPermissionRuntimeEventProjection extends RuntimeEventProjection
    implements RuntimeEventHookResponderProjection {
  GeneralPermissionRuntimeEventProjection({required GeneralPermissionRequestGate gate, CliToolRegistry? registry});
}
```
and `AgentEventGateway.forAttention(..., GeneralPermissionRequestGate? generalPermissionGate)` (used by Task 11 e2e and production assembly).

- [ ] **Step 1: Write the failing tests**

Add to `runtime_event_projection_test.dart`, following the file's existing pattern (direct `RuntimeEventEnvelope` construction + `SeatEventStream.publish`, as in the plan-responder tests at ~line 130):

```dart
test(
  'general permission projection holds PermissionRequest and answers via the gate',
  () async {
    final stream = SeatEventStream();
    final gate = GeneralPermissionRequestGate();
    const seat = RuntimeSeatKey(sessionId: 'session', memberId: 'member');
    final projection = GeneralPermissionRuntimeEventProjection(gate: gate);
    final subscription = projection.attach(stream, seat);
    addTearDown(subscription.cancel);
    addTearDown(stream.close);
    final event = RuntimeEventEnvelope(
      seat: seat,
      cli: CliTool.claude,
      kind: RuntimeEventKind.statusReported,
      occurredAt: DateTime.utc(2026, 9, 4),
      raw: const {
        'hook_event_name': 'PermissionRequest',
        'tool_name': 'Bash',
        'tool_input': {'command': 'rm -rf node_modules'},
        'permission_suggestions': [
          {
            'type': 'addRules',
            'rules': [
              {'toolName': 'Bash', 'ruleContent': 'rm -rf node_modules'},
            ],
            'behavior': 'allow',
            'destination': 'localSettings',
          },
        ],
      },
      sequence: 1,
    );

    stream.publish(event);
    await pumpEventQueue();
    expect(gate.hasWaiter(sessionId: 'session', memberId: 'member'), isTrue);
    final pending = projection.responseFor(event);
    expect(pending, isNotNull);
    expect(
      gate.complete(
        sessionId: 'session',
        memberId: 'member',
        reply: const GeneralPermissionRequestReply.allow(),
      ),
      isTrue,
    );
    expect(await pending, {
      'hookSpecificOutput': {
        'hookEventName': 'PermissionRequest',
        'decision': {'behavior': 'allow'},
      },
    });
  },
);

test('general permission projection never holds ExitPlanMode requests',
    () async {
  final stream = SeatEventStream();
  final gate = GeneralPermissionRequestGate();
  const seat = RuntimeSeatKey(sessionId: 'session', memberId: 'member');
  final projection = GeneralPermissionRuntimeEventProjection(gate: gate);
  final subscription = projection.attach(stream, seat);
  addTearDown(subscription.cancel);
  addTearDown(stream.close);
  final event = RuntimeEventEnvelope(
    seat: seat,
    cli: CliTool.claude,
    kind: RuntimeEventKind.statusReported,
    occurredAt: DateTime.utc(2026, 9, 4),
    raw: const {
      'hook_event_name': 'PermissionRequest',
      'tool_name': 'ExitPlanMode',
      'tool_input': {'plan': '1. Ship it.'},
    },
    sequence: 1,
  );

  stream.publish(event);
  await pumpEventQueue();
  expect(gate.hasWaiter(sessionId: 'session', memberId: 'member'), isFalse);
  expect(projection.responseFor(event), isNull);
});

test('general permission projection skips CLIs without in-chat reply',
    () async {
  final stream = SeatEventStream();
  final gate = GeneralPermissionRequestGate();
  const seat = RuntimeSeatKey(sessionId: 'session', memberId: 'member');
  final projection = GeneralPermissionRuntimeEventProjection(gate: gate);
  final subscription = projection.attach(stream, seat);
  addTearDown(subscription.cancel);
  addTearDown(stream.close);
  final event = RuntimeEventEnvelope(
    seat: seat,
    cli: CliTool.cursor, // supportsInChatPermissionReply == false
    kind: RuntimeEventKind.statusReported,
    occurredAt: DateTime.utc(2026, 9, 4),
    raw: const {
      'hook_event_name': 'PermissionRequest',
      'tool_name': 'Bash',
      'tool_input': {'command': 'ls'},
    },
    sequence: 1,
  );

  stream.publish(event);
  await pumpEventQueue();
  expect(gate.hasWaiter(sessionId: 'session', memberId: 'member'), isFalse);
  expect(projection.responseFor(event), isNull);
});
```

- [ ] **Step 2: Run to verify failure**

Run: `cd client && flutter test test/services/agent_runtime/runtime_event_projection_test.dart`
Expected: FAIL — `GeneralPermissionRuntimeEventProjection` undefined.

- [ ] **Step 3: Implement the projection**

Append to `runtime_event_projection.dart` (imports: `general_permission_request_gate.dart`):

```dart
/// Holds Claude-family general `PermissionRequest` hooks for the chat
/// permission card. Routing is strictly complementary to
/// [ExitPlanModeRuntimeEventProjection]: ExitPlanMode / AskUserQuestion
/// permission requests belong to the plan / ask gates and are skipped here.
final class GeneralPermissionRuntimeEventProjection extends RuntimeEventProjection
    implements RuntimeEventHookResponderProjection {
  GeneralPermissionRuntimeEventProjection({
    required this.gate,
    CliToolRegistry? registry,
  }) : _registry = registry ?? CliToolRegistry.builtIn(),
       super(onEvent: (_) {});

  final GeneralPermissionRequestGate gate;
  final CliToolRegistry _registry;
  final _responses = <(RuntimeSeatKey, int), Future<Map<String, Object?>?>>{};

  @override
  void apply(RuntimeEventEnvelope event) {
    final cursor = cursorFor(event.seat);
    super.apply(event);
    if (event.sequence <= cursor) return;
    final raw = event.raw;
    if (raw == null) return;
    final capability = _registry.capability<ChatInteractionCapability>(
      event.cli,
    );
    if (capability?.supportsInChatPermissionReply != true) return;
    final status = capability?.normalize(raw);
    if (status?.hookEventName?.trim() != 'PermissionRequest') return;
    if (isExitPlanModeTool(status?.toolName) ||
        isAskUserQuestionTool(status?.toolName)) {
      return;
    }
    if (status?.permissionRequest == null) return;
    final key = (event.seat, event.sequence);
    // Replay/duplicate guard, same rationale as the sibling projections.
    if (_responses.containsKey(key)) return;
    _responses[key] = gate
        .wait(sessionId: event.seat.sessionId, memberId: event.seat.memberId)
        .then((reply) => reply?.toHookResponse());
  }

  @override
  Future<Map<String, Object?>?>? responseFor(RuntimeEventEnvelope event) =>
      _responses[(event.seat, event.sequence)];
}
```

- [ ] **Step 4: Extend the `forAttention` factory**

In `agent_event_gateway.dart`, add the parameter and wire the projection exactly like the plan projection:

```dart
factory AgentEventGateway.forAttention({
  required AgentAttentionCubit attention,
  required CliTool? Function(String sessionId, String memberId) resolveCli,
  required bool Function(String sessionId, String memberId)
  resolveSkipPermissions,
  AskUserQuestionHookGate? askUserHookGate,
  ExitPlanModeHookGate? exitPlanModeHookGate,
  ExitPlanPermissionRequestGate? exitPlanPermissionRequestGate,
  GeneralPermissionRequestGate? generalPermissionGate,     // NEW
  CliToolRegistry? registry,
  DateTime Function()? clock,
}) {
  ...
  final generalPermissionProjection = generalPermissionGate == null
      ? null
      : GeneralPermissionRuntimeEventProjection(
          gate: generalPermissionGate,
          registry: effectiveRegistry,
        );
  return AgentEventGateway(
    ...
    projections: [
      ...,
      if (generalPermissionProjection != null) generalPermissionProjection,
    ],
    responders: [
      ...,
      if (generalPermissionProjection != null) generalPermissionProjection,
    ],
  );
}
```

- [ ] **Step 5: Run tests + regression**

Run: `cd client && flutter test test/services/agent_runtime/runtime_event_projection_test.dart test/services/agent_status/agent_status_http_handler_exit_plan_test.dart`
Expected: PASS (exit-plan suite unaffected — its factory call omits the new optional param).

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/agent_runtime/runtime_event_projection.dart client/lib/services/agent_runtime/agent_event_gateway.dart client/test/services/agent_runtime/runtime_event_projection_test.dart
git commit -m "feat(agent-runtime): GeneralPermission responder projection with ExitPlanMode-exclusive routing"
```

---

### Task 6: Capability flags — Claude family supports in-chat permission reply

**Files:**
- Modify: `client/lib/services/cli/claude/capabilities/chat_interaction.dart:59`
- Modify: `client/lib/services/cli/flashskyai/capabilities/chat_interaction.dart:59`
- Modify: `client/lib/services/cli/codex/capabilities/chat_interaction.dart:59`
- Test: extend the existing capability test file(s) covering `ChatInteractionCapability` (find with `grep -rln "supportsInChatPermissionReply" client/test`)

**Interfaces:**
- Produces: `supportsInChatPermissionReply == true` for claude / flashskyai / codex (consumed by Tasks 5, 7, 10). `answerKind` stays `ptyPicker`; `supportsInChatAnswer` etc. unchanged.

- [ ] **Step 1: Write the failing test**

```dart
test('Claude family supports in-chat permission replies', () {
  final registry = CliToolRegistry.builtIn();
  for (final cli in [CliTool.claude, CliTool.flashskyai, CliTool.codex]) {
    final capability = registry.capability<ChatInteractionCapability>(cli);
    expect(capability?.supportsInChatPermissionReply, isTrue,
        reason: '$cli should support the held PermissionRequest card');
  }
  // Cursor and OpenCode semantics unchanged (OpenCode already true via SDK).
  expect(
    registry
        .capability<ChatInteractionCapability>(CliTool.cursor)
        ?.supportsInChatPermissionReply,
    isFalse,
  );
});
```

- [ ] **Step 2: Run to verify failure**

Run the extended test file. Expected: FAIL for the three family CLIs.

- [ ] **Step 3: Implement**

In each of the three `chat_interaction.dart` files change:

```dart
@override
bool get supportsInChatPermissionReply => true;
```

Update the doc comment on `ClaudeChatInteraction` to mention the held `PermissionRequest` decision path alongside the existing `PreToolUse` ExitPlanMode note.

- [ ] **Step 4: Run the capability tests + analyzer**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test <capability test file>`
Expected: PASS. If any existing test asserts `false` for these CLIs, update that assertion in the same commit (it is the behavior change this task ships).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/cli
git commit -m "feat(cli): enable in-chat permission replies for the Claude family"
```

---

### Task 7: Policy — channel-conditional request-id gating

**Files:**
- Modify: `client/lib/services/agent_status/ask_user_question_policy.dart:8-27`
- Test: `client/test/services/agent_status/ask_user_question_policy_test.dart` (extend; create if absent)

**Interfaces:**
- Consumes: `ChatInteractionCapability.answerKind` (`pluginSdkReply` = OpenCode SDK channel; `ptyPicker` = Claude family hook-hold channel).
- Produces: `shouldShowPermissionCard` returns true for a Claude-family capability with a permission payload even when `askRequestId` is null.

- [ ] **Step 1: Write the failing test**

```dart
test('hook-hold channel needs no request id', () {
  final claude = CliToolRegistry.builtIn()
      .capability<ChatInteractionCapability>(CliTool.claude);
  expect(
    shouldShowPermissionCard(
      capability: claude,
      permissionRequest: AgentPermissionRequest(
        id: '',
        description: 'Bash rm -rf node_modules',
      ),
      askRequestId: null,
    ),
    isTrue,
  );
});

test('plugin-SDK channel still requires a request id', () {
  final opencode = CliToolRegistry.builtIn()
      .capability<ChatInteractionCapability>(CliTool.opencode);
  expect(
    shouldShowPermissionCard(
      capability: opencode,
      permissionRequest: AgentPermissionRequest(
        id: '',
        description: 'Run `npm install`',
      ),
      askRequestId: null,
    ),
    isFalse,
  );
});
```

- [ ] **Step 2: Run to verify failure**

Expected: the first test FAILS (current code requires an id unconditionally).

- [ ] **Step 3: Implement**

Replace the unconditional id check in `shouldShowPermissionCard`:

```dart
// The plugin-SDK channel (OpenCode) correlates replies by request id; the
// hook-hold channel (Claude family) correlates by the gate's seat key.
if (capability.answerKind == AskUserAnswerKind.pluginSdkReply &&
    (askRequestId == null || askRequestId.isEmpty)) {
  return false;
}
```

- [ ] **Step 4: Run the policy tests + banner regression**

Run: `cd client && flutter test test/services/agent_status/ask_user_question_policy_test.dart test/pages/chat/agent_permission_attention_banner_test.dart`
Expected: PASS — the banner suite still passes because Claude-family events do not yet carry payloads in its fixtures; the OpenCode cases keep their ids.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/agent_status/ask_user_question_policy.dart client/test/services/agent_status/ask_user_question_policy_test.dart
git commit -m "feat(agent-status): channel-conditional askRequestId gating for permission cards"
```

---

### Task 8: `AiPermissionCard` reply API + multiple always options

**Files:**
- Modify: `client/packages/ai_message_ui/lib/src/tool_chrome/permission_card.dart`
- Test: `client/packages/ai_message_ui/test/permission_card_test.dart` (update existing)

**Interfaces:**
- Produces (used by Task 9's banner glue):

```dart
enum AiPermissionReplyKind { allowOnce, always, reject }

final class AiPermissionReply {
  const AiPermissionReply.allowOnce();
  const AiPermissionReply.always(int optionIndex);
  const AiPermissionReply.reject();
  final AiPermissionReplyKind kind;
  final int? alwaysOptionIndex;
}
```
Card props change: `showAlwaysAllow` → `alwaysOptions: List<String>` (empty = no always button; host supplies localized labels); `onReply: Future<AiInteractiveResult> Function(AiPermissionReply reply)` (was `Function(String)`).

- [ ] **Step 1: Update the existing card tests (failing first)**

Rewrite the interactions in `permission_card_test.dart` to the new API — representative cases:

```dart
test('tapping allow once replies allowOnce', (tester) async {
  AiPermissionReply? captured;
  await tester.pumpWidget(harness(
    AiPermissionCard(
      description: 'Run `npm install`',
      alwaysOptions: const ['Always allow'],
      onReply: (reply) async {
        captured = reply;
        return const AiInteractiveOk();
      },
      onAnswerInTerminal: () {},
    ),
  ));
  await tester.tap(find.byKey(AiPermissionCard.allowOnceButtonKey));
  await tester.pumpAndSettle();
  expect(captured!.kind, AiPermissionReplyKind.allowOnce);
});

test('tapping the always button replies with the option index', (tester) async {
  AiPermissionReply? captured;
  await tester.pumpWidget(harness(
    AiPermissionCard(
      description: 'Bash rm -rf node_modules',
      alwaysOptions: const [
        'Always allow Bash(rm -rf node_modules)',
        'Always allow Bash',
      ],
      onReply: (reply) async {
        captured = reply;
        return const AiInteractiveOk();
      },
      onAnswerInTerminal: () {},
    ),
  ));
  await tester.tap(find.byKey(AiPermissionCard.alwaysButtonKey)); // first option
  await tester.pumpAndSettle();
  expect(captured!.kind, AiPermissionReplyKind.always);
  expect(captured!.alwaysOptionIndex, 0);
  // second always button is keyed by index
  await tester.tap(find.byKey(const Key('opencode-permission-always-1')));
  await tester.pumpAndSettle();
  expect(captured!.alwaysOptionIndex, 1);
});

test('no always buttons when alwaysOptions is empty', (tester) async {
  await tester.pumpWidget(harness(
    AiPermissionCard(
      description: 'Run `npm install`',
      onReply: (reply) async => const AiInteractiveOk(),
      onAnswerInTerminal: () {},
    ),
  ));
  expect(find.byKey(AiPermissionCard.alwaysButtonKey), findsNothing);
});
```

Keep the existing error-state test, adapting `onReply` to the new type.

- [ ] **Step 2: Run to verify failure**

Run: `cd client/packages/ai_message_ui && flutter test test/permission_card_test.dart`
Expected: FAIL — old API.

- [ ] **Step 3: Implement**

In `permission_card.dart`:

1. Add the reply types above the widget:

```dart
enum AiPermissionReplyKind { allowOnce, always, reject }

/// Card reply: [kind] plus the selected always-option index (when the kind
/// is [AiPermissionReplyKind.always]). The host owns option payloads.
final class AiPermissionReply {
  const AiPermissionReply.allowOnce()
    : kind = AiPermissionReplyKind.allowOnce,
      alwaysOptionIndex = null;
  const AiPermissionReply.always(int optionIndex)
    : kind = AiPermissionReplyKind.always,
      alwaysOptionIndex = optionIndex;
  const AiPermissionReply.reject()
    : kind = AiPermissionReplyKind.reject,
      alwaysOptionIndex = null;

  final AiPermissionReplyKind kind;
  final int? alwaysOptionIndex;
}
```

2. Replace `final bool showAlwaysAllow;` with `final List<String> alwaysOptions;` (default `const []`) and `onReply`'s type with `Future<AiInteractiveResult> Function(AiPermissionReply reply)`.

3. Replace `_reply('once')` / `_reply('always')` / `_reply('reject')` with `const AiPermissionReply.allowOnce()` / `AiPermissionReply.always(index)` / `const AiPermissionReply.reject()`.

4. Replace the single always button with a loop (first button keeps `alwaysButtonKey` so existing key-based tests survive):

```dart
for (final (index, label) in widget.alwaysOptions.indexed) ...[
  SizedBox(width: spacing.sm),
  TpButton(
    key: index == 0
        ? AiPermissionCard.alwaysButtonKey
        : ValueKey('opencode-permission-always-$index'),
    variant: TpButtonVariant.primary,
    size: TpControlSize.medium,
    onPressed: _answering ? null : () => _reply(AiPermissionReply.always(index)),
    child: Text(label),
  ),
],
```

5. Check the package export file re-exports `permission_card.dart` (it already does — the banner imports `AiPermissionCard` from `package:ai_message_ui/ai_message_ui.dart`); the new types are exported with it.

- [ ] **Step 4: Fix the host compile (banner call site only)**

`agent_permission_attention_banner.dart` is the only `AiPermissionCard` caller. Keep it compiling by mapping the new reply to the existing string-based cubit call (the cubit signature changes in Task 9):

```dart
onReply: (reply) async {
  final result = await context.read<ChatCubit>().answerPermissionRequest(
        sessionId: sessionId,
        memberId: seatId,
        permissionRequestId: askRequestId,
        reply: switch (reply.kind) {
          AiPermissionReplyKind.allowOnce => 'once',
          AiPermissionReplyKind.always => 'always',
          AiPermissionReplyKind.reject => 'reject',
        },
      );
  return _fromAskUser(result);
},
```
and `showAlwaysAllow: permissionRequest.always.isNotEmpty` → `alwaysOptions: permissionRequest.always.map((o) => o.label).toList()`.

- [ ] **Step 5: Run package + host tests**

Run: `cd client/packages/ai_message_ui && flutter test test/permission_card_test.dart` then `cd client && flutter test test/pages/chat/agent_permission_attention_banner_test.dart`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add client/packages/ai_message_ui client/lib/pages/chat/agent_permission_attention_banner.dart
git commit -m "feat(ai-message-ui): typed AiPermissionReply with multiple always options"
```

---

### Task 9: Answer routing — service, ChatCubit, terminal release, banner wiring, l10n

**Files:**
- Modify: `client/lib/services/terminal/ask_user_question_answer_service.dart` (answerPermission + new releasePermission)
- Modify: `client/lib/cubits/chat_cubit.dart` (`answerPermissionRequest` signature, new `releasePermissionToTerminal`, constructor param)
- Modify: `client/lib/pages/chat/agent_permission_attention_banner.dart` (typed reply, terminal release)
- Modify: `client/lib/l10n/app_en.arb`, `app_zh.arb`
- Test: `client/test/services/terminal/ask_user_question_answer_service_test.dart` (extend), `client/test/pages/chat/agent_permission_attention_banner_test.dart` (extend)

**Interfaces:**
- Consumes: `AgentPermissionReplyKind` (Task 1), `GeneralPermissionRequestGate` / `GeneralPermissionRequestReply` (Task 3), `AiPermissionReply` (Task 8).
- Produces:
  - `AskUserQuestionAnswerService.answerPermission({required CliTool cli, required String sessionId, required String memberId, String? requestId, required AgentPermissionReplyKind kind, Object? alwaysPayload})` — routes `pluginSdkReply` → pending store (string reply), else → `generalPermissionGate.complete`.
  - `AskUserQuestionAnswerService.releasePermission({required CliTool cli, required String sessionId, required String memberId})` — `generalPermissionGate.releaseHold` (hook-hold channel only).
  - `ChatCubit.answerPermissionRequest({required String sessionId, required String memberId, String? permissionRequestId, required AgentPermissionReplyKind kind, Object? alwaysPayload})`
  - `ChatCubit.releasePermissionToTerminal({required String sessionId, required String memberId})`

- [ ] **Step 1: Write the failing service tests**

```dart
test('hook-hold channel completes the gate with an allow reply', () async {
  final gate = GeneralPermissionRequestGate();
  final service = AskUserQuestionAnswerService(generalPermissionGate: gate);
  final held = gate.wait(sessionId: 's', memberId: 'm');
  final result = await service.answerPermission(
    cli: CliTool.claude,
    sessionId: 's',
    memberId: 'm',
    kind: AgentPermissionReplyKind.allowOnce,
  );
  expect(result, isA<AskUserAnswerOk>());
  final reply = await held;
  expect(reply, isNotNull);
  expect(reply!.deny, isFalse);
});

test('hook-hold always echoes the suggestion payload', () async {
  final gate = GeneralPermissionRequestGate();
  final service = AskUserQuestionAnswerService(generalPermissionGate: gate);
  final held = gate.wait(sessionId: 's', memberId: 'm');
  await service.answerPermission(
    cli: CliTool.claude,
    sessionId: 's',
    memberId: 'm',
    kind: AgentPermissionReplyKind.always,
    alwaysPayload: {
      'type': 'addRules',
      'rules': [
        {'toolName': 'Bash', 'ruleContent': 'rm -rf node_modules'},
      ],
      'behavior': 'allow',
      'destination': 'localSettings',
    },
  );
  final reply = await held;
  expect(reply!.updatedPermissions, hasLength(1));
});

test('releasePermission falls through to the native TUI', () async {
  final gate = GeneralPermissionRequestGate();
  final service = AskUserQuestionAnswerService(generalPermissionGate: gate);
  final held = gate.wait(sessionId: 's', memberId: 'm');
  final result = await service.releasePermission(
    cli: CliTool.claude,
    sessionId: 's',
    memberId: 'm',
  );
  expect(result, isA<AskUserAnswerOk>());
  expect(await held, isNull);
});

test('plugin-SDK channel keeps the string reply path', () async {
  final store = AskUserAnswerPendingStore();
  final service = AskUserQuestionAnswerService(store: store);
  final result = await service.answerPermission(
    cli: CliTool.opencode,
    sessionId: 's',
    memberId: 'm',
    requestId: 'perm-1',
    kind: AgentPermissionReplyKind.always,
  );
  expect(result, isA<AskUserAnswerOk>());
  final entry = store.take(sessionId: 's', memberId: 'm', requestId: 'perm-1');
  expect(entry?.permissionReply, 'always');
});
```

(If the existing suite constructs the service differently — e.g. a shared store fixture — follow that fixture; the assertion is the `take(...)?.permissionReply` mapping.)

- [ ] **Step 2: Run to verify failure**

Run: `cd client && flutter test test/services/terminal/ask_user_question_answer_service_test.dart`
Expected: FAIL — no `generalPermissionGate` param, wrong `answerPermission` signature.

- [ ] **Step 3: Implement the service routing**

In `ask_user_question_answer_service.dart`:

1. Constructor gains `GeneralPermissionRequestGate? generalPermissionGate` (import `../agent_status/general_permission_request_gate.dart` and `../agent_status/agent_permission_request.dart`).
2. Replace `answerPermission`:

```dart
/// Answers a permission request. OpenCode (plugin SDK channel) maps the kind
/// to its `once` / `always` / `reject` string; the Claude family (hook-hold
/// channel) completes the held `PermissionRequest` hook with the official
/// decision — allow-once, allow + echoed suggestion (`alwaysPayload`), or
/// deny with a message.
Future<AskUserAnswerResult> answerPermission({
  required CliTool cli,
  required String sessionId,
  required String memberId,
  String? requestId,
  required AgentPermissionReplyKind kind,
  Object? alwaysPayload,
}) async {
  final channel = _answerKind(cli);
  if (channel == AskUserAnswerKind.pluginSdkReply) {
    final id = requestId?.trim() ?? '';
    if (id.isEmpty) {
      return const AskUserAnswerFailed('missing_request_id');
    }
    final reply = switch (kind) {
      AgentPermissionReplyKind.allowOnce => 'once',
      AgentPermissionReplyKind.always => 'always',
      AgentPermissionReplyKind.reject => 'reject',
    };
    _store.put(
      sessionId: sessionId,
      memberId: memberId,
      entry: AskUserAnswerPendingEntry(requestId: id, permissionReply: reply),
    );
    return const AskUserAnswerOk();
  }
  final gate = _generalPermissionGate;
  if (gate == null) return const AskUserAnswerFailed('unsupported');
  final GeneralPermissionRequestReply reply;
  switch (kind) {
    case AgentPermissionReplyKind.allowOnce:
      reply = const GeneralPermissionRequestReply.allow();
    case AgentPermissionReplyKind.always:
      reply = GeneralPermissionRequestReply.allow(
        updatedPermissions: alwaysPayload is Map<String, Object?>
            ? [alwaysPayload]
            : const [],
      );
    case AgentPermissionReplyKind.reject:
      reply = const GeneralPermissionRequestReply.deny(
        'User denied via TeamPilot',
      );
  }
  final completed = gate.complete(
    sessionId: sessionId,
    memberId: memberId,
    reply: reply,
  );
  return completed
      ? const AskUserAnswerOk()
      : const AskUserAnswerFailed('no_pending_permission');
}

/// Releases a held Claude-family permission hook so the gateway answers `{}`
/// and the native TUI prompt appears (card "answer in terminal").
Future<AskUserAnswerResult> releasePermission({
  required CliTool cli,
  required String sessionId,
  required String memberId,
}) async {
  final gate = _generalPermissionGate;
  if (gate == null) return const AskUserAnswerFailed('unsupported');
  final released = gate.releaseHold(sessionId: sessionId, memberId: memberId);
  return released
      ? const AskUserAnswerOk()
      : const AskUserAnswerFailed('no_pending_permission');
}
```

(Delete the old string-validating branch — validation is now the enum.)

- [ ] **Step 4: Update `ChatCubit`**

1. `answerPermissionRequest` signature: replace `required String reply` with `required AgentPermissionReplyKind kind, Object? alwaysPayload`; forward both to `_askUserAnswer.answerPermission` (the existing `_resolveAskRequestId` / `markAskAnswered` plumbing stays).
2. Add:

```dart
/// Releases the seat's held Claude-family permission hook (card "answer in
/// terminal"): the gateway answers `{}` and the native TUI prompt appears.
Future<AskUserAnswerResult> releasePermissionToTerminal({
  required String sessionId,
  required String memberId,
}) async {
  final tab = _tabStore.openTabBySessionId(sessionId);
  if (tab == null) {
    return const AskUserAnswerFailed('session_not_found');
  }
  final mid = memberId.trim();
  if (mid.isEmpty) {
    return const AskUserAnswerFailed('member_not_found');
  }
  final cli = SessionMemberCliResolver.resolve(
    persistedSession: tab.persistedSession,
    team: _teamForSessionTab(tab),
    memberId: mid,
    cliForMember: _shellFactory.cliForMember,
    globalPresets: _lifecycle.globalPresets,
  );
  return _askUserAnswer.releasePermission(
    cli: cli,
    sessionId: sessionId,
    memberId: mid,
  );
}
```

3. `ChatCubit` constructor gains `GeneralPermissionRequestGate? generalPermissionGate` forwarded into the `AskUserQuestionAnswerService` it builds (find the existing `_askUserAnswer =` initialization at ~line 181; when a custom `askUserQuestionAnswerService` is injected the gate is ignored, matching the existing pattern).

- [ ] **Step 5: l10n + banner wiring**

Add to `app_en.arb`:

```json
"agentPermissionAlwaysAllowRule": "Always allow {rule}",
"@agentPermissionAlwaysAllowRule": {
  "placeholders": { "rule": {} }
}
```
and to `app_zh.arb`:
```json
"agentPermissionAlwaysAllowRule": "始终允许 {rule}",
```

In the banner's permission-card branch:
- `alwaysOptions`: Claude family options are rule-wrapped via `context.l10n.agentPermissionAlwaysAllowRule(option.label)`; OpenCode (payload null) keeps the generic card string `context.l10n.opencodePermissionAllowAlways`:

```dart
final alwaysOptions = [
  for (final option in permissionRequest.always)
    option.payload == null
        ? context.l10n.opencodePermissionAllowAlways
        : context.l10n.agentPermissionAlwaysAllowRule(option.label),
];
```

- `onReply` becomes the typed call (replacing Task 8's temporary string mapping):

```dart
onReply: (reply) async {
  final alwaysIndex = reply.alwaysOptionIndex;
  final result = await context.read<ChatCubit>().answerPermissionRequest(
        sessionId: sessionId,
        memberId: seatId,
        permissionRequestId: askRequestId,
        kind: switch (reply.kind) {
          AiPermissionReplyKind.allowOnce => AgentPermissionReplyKind.allowOnce,
          AiPermissionReplyKind.always => AgentPermissionReplyKind.always,
          AiPermissionReplyKind.reject => AgentPermissionReplyKind.reject,
        },
        alwaysPayload: alwaysIndex == null
            ? null
            : permissionRequest.always[alwaysIndex].payload,
      );
  return _fromAskUser(result);
},
```

- `onAnswerInTerminal` releases the hold before switching views (both channels — the release is a no-op failure when nothing is held):

```dart
onAnswerInTerminal: () {
  unawaited(
    context.read<ChatCubit>().releasePermissionToTerminal(
          sessionId: sessionId,
          memberId: seatId,
        ),
  );
  _openTerminal(
    context,
    sessionId: sessionId,
    seatId: seatId,
    selectedMemberId: selectedMemberId,
  );
},
```

Run `cd client && flutter gen-l10n` if the generated `app_localizations*.dart` files are not refreshed automatically by `flutter test`.

- [ ] **Step 6: Extend the banner widget tests**

Add a case pumping the banner with a Claude-family `AgentSeatAttentionEntry` whose `lastEvent` is a `PermissionRequest` status carrying a `permissionRequest` payload (fixture mirroring the existing OpenCode case in that file, minus `askRequestId`), asserting:
- `AiPermissionCard` renders (not just the generic banner),
- tapping allow-once invokes `ChatCubit.answerPermissionRequest` with `kind: allowOnce` (mock/spy cubit per the existing harness),
- the always button label contains the rule text,
- the terminal button invokes `releasePermissionToTerminal`.

- [ ] **Step 7: Run tests + analyzer**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test test/services/terminal/ask_user_question_answer_service_test.dart test/pages/chat/agent_permission_attention_banner_test.dart`
Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add client/lib/services/terminal/ask_user_question_answer_service.dart client/lib/cubits/chat_cubit.dart client/lib/pages/chat/agent_permission_attention_banner.dart client/lib/l10n client/test
git commit -m "feat(chat): route Claude-family permission answers via the held hook gate"
```

---

### Task 10: Production assembly in `app_shell.dart`

**Files:**
- Modify: `client/lib/app/app_shell.dart` (~lines 1637-1680, the gate/projection wiring block)
- Test: covered by Task 11's e2e; no new unit test file (assembly is integration-verified).

**Interfaces:**
- Consumes: everything from Tasks 3, 5, 9.
- Produces: production runtime where a Claude-family `PermissionRequest` HTTP hook is held and answerable from chat.

- [ ] **Step 1: Wire the gate, projection, and service**

In the block after `exitPlanModeApprovalService` (line ~1650):

```dart
final generalPermissionRequestGate = GeneralPermissionRequestGate();
```

Pass it into the `AskUserQuestionAnswerService` construction (line ~1637, add `generalPermissionGate: generalPermissionRequestGate` — construct the gate before the service). Create the projection next to `exitPlanModeProjection`:

```dart
final generalPermissionProjection = GeneralPermissionRuntimeEventProjection(
  gate: generalPermissionRequestGate,
);
```

Add it to `runtimeProjections` and to the gateway's `responders` list:

```dart
final runtimeProjections = [
  ...,
  generalPermissionProjection,
];
final agentEventGateway = AgentEventGateway(
  ...,
  responders: [
    askUserQuestionProjection,
    exitPlanModeProjection,
    generalPermissionProjection,
  ],
);
```

Add the import for `general_permission_request_gate.dart`.

- [ ] **Step 2: Analyzer + smoke test**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add client/lib/app/app_shell.dart
git commit -m "feat(app): assemble GeneralPermissionRequestGate into the runtime gateway"
```

---

### Task 11: End-to-end HTTP test + full verification

**Files:**
- Test: `client/test/services/agent_status/agent_status_http_handler_general_permission_test.dart` (create — mirror `agent_status_http_handler_exit_plan_test.dart`'s harness exactly)

**Interfaces:**
- Consumes: `AgentEventGateway.forAttention(..., generalPermissionGate:)` (Task 5), `GeneralPermissionRequestGate` (Task 3).

- [ ] **Step 1: Write the e2e test**

Mirror the exit-plan harness (`TeammateBusMcpGateway.ensureStarted` + `attachAgentEventGateway(AgentEventGateway.forAttention(...))` + `HttpClient` POST to `/agent-status` with `teammateBusMcpSessionHeader` / `teammateBusMcpMemberHeader`):

```dart
void main() {
  setUpAll(() => HttpOverrides.global = null);

  late AgentAttentionCubit cubit;
  late GeneralPermissionRequestGate gate;
  late TeammateBusMcpGateway gateway;
  late HttpClient client;

  setUp(() async {
    cubit = AgentAttentionCubit(pruneInterval: null);
    gate = GeneralPermissionRequestGate();
    gateway = TeammateBusMcpGateway();
    await gateway.ensureStarted();
    gateway.attachAgentEventGateway(
      AgentEventGateway.forAttention(
        attention: cubit,
        resolveCli: (_, __) => CliTool.claude,
        resolveSkipPermissions: (_, __) => false,
        generalPermissionGate: gate,
      ),
    );
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await cubit.close();
    await gateway.dispose();
  });

  test('allow decision answers the held hook; attention waits then settles',
      () async {
    final post = postPermission(  // same shape as postExitPlan in the exit-plan test
      sessionId: 's1',
      memberId: 'm1',
      body: {
        'hook_event_name': 'PermissionRequest',
        'tool_name': 'Bash',
        'tool_input': {'command': 'rm -rf node_modules'},
        'permission_suggestions': [
          {
            'type': 'addRules',
            'rules': [
              {'toolName': 'Bash', 'ruleContent': 'rm -rf node_modules'},
            ],
            'behavior': 'allow',
            'destination': 'localSettings',
          },
        ],
      },
    );
    // The hook is held — the POST stays open until the gate answers.
    await waitUntilWaiter(sessionId: 's1', memberId: 'm1'); // gate.hasWaiter poll, 5s deadline
    expect(
      cubit.state.entryFor(sessionId: 's1', memberId: 'm1')?.attention,
      AgentSeatAttention.waiting,
    );
    expect(
      gate.complete(
        sessionId: 's1',
        memberId: 'm1',
        reply: GeneralPermissionRequestReply.allow(
          updatedPermissions: [
            {
              'type': 'addRules',
              'rules': [
                {'toolName': 'Bash', 'ruleContent': 'rm -rf node_modules'},
              ],
              'behavior': 'allow',
              'destination': 'localSettings',
            },
          ],
        ),
      ),
      isTrue,
    );
    final response = await post;
    expect(response.statusCode, 200);
    expect(jsonDecode(await response.transform(utf8.decoder).join()), {
      'hookSpecificOutput': {
        'hookEventName': 'PermissionRequest',
        'decision': {
          'behavior': 'allow',
          'updatedPermissions': [
            {
              'type': 'addRules',
              'rules': [
                {'toolName': 'Bash', 'ruleContent': 'rm -rf node_modules'},
              ],
              'behavior': 'allow',
              'destination': 'localSettings',
            },
          ],
        },
      },
    });
  });

  test('releaseHold answers {} so the native TUI takes over', () async {
    final post = postPermission(
      sessionId: 's1',
      memberId: 'm1',
      body: {
        'hook_event_name': 'PermissionRequest',
        'tool_name': 'Bash',
        'tool_input': {'command': 'ls'},
      },
    );
    await waitUntilWaiter(sessionId: 's1', memberId: 'm1');
    expect(gate.releaseHold(sessionId: 's1', memberId: 'm1'), isTrue);
    final response = await post;
    expect(response.statusCode, 200);
    expect(
      jsonDecode(await response.transform(utf8.decoder).join()),
      isEmpty,
    );
  });
}
```

- [ ] **Step 2: Run the e2e test**

Run: `cd client && flutter test test/services/agent_status/agent_status_http_handler_general_permission_test.dart`
Expected: PASS (if the held POST deadlocks, the seat serialization in `AgentEventGateway._handleJson` is holding the response — the responder future is awaited inside `handle`, which is correct; check `waitUntilWaiter` polls `gate.hasWaiter` before the POST's future completes).

- [ ] **Step 3: Full verification**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`
Expected: Analyze clean; full suite PASS (including the untouched ExitPlanMode and AskUserQuestion suites).

- [ ] **Step 4: Commit**

```bash
git add client/test/services/agent_status/agent_status_http_handler_general_permission_test.dart
git commit -m "test(agent-status): e2e held PermissionRequest hook with card decision replies"
```

---

## Manual Verification (after all tasks)

1. Launch a Claude session in TeamPilot with default permissions (not `--dangerously-skip-permissions`).
2. Prompt something requiring a Bash permission (e.g. "run rm -rf node_modules").
3. Expect: chat shows the `AiPermissionCard` (not the generic banner); the embedded terminal shows no native prompt while held.
4. Click **Allow once** — the tool runs; card dismisses.
5. Repeat, click **Always allow Bash(...)** — the tool runs and the rule persists (next identical call does not prompt).
6. Repeat, click the terminal icon — the native TUI prompt appears in the terminal and is answerable there.
7. Repeat with an ExitPlanMode plan — the plan card still renders (not the permission card).
8. flashskyai / codex spot-check: same card behavior.
