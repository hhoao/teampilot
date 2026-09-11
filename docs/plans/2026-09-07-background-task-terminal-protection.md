# Background Task Terminal Protection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A member terminal whose CLI hosts a live background shell task (`Bash` `run_in_background`) is never discarded by the idle terminal reclaim, via a first-class seat-lease model.

**Architecture:** New `SeatLeaseCubit` owns per-seat keep-alive leases, fed by a `seatLeaseProjection` registered in the runtime-event gateway (same pattern as the attention projection). `PreToolUse(Bash, run_in_background)` acquires a lease keyed by `tool_use_id`; the `<task-notification>` `UserPromptSubmit` re-invocation releases it; a 60-minute TTL is the safety net. The reclaim watch gains one per-seat protection arm. Attention semantics (spinner, cards) are untouched.

**Tech Stack:** Flutter / `flutter_bloc` cubits, existing `RuntimeEventProjection` pipeline, `flutter_test`.

**Spec:** `docs/specs/2026-09-07-background-task-terminal-protection-design.md` — read it first; the event payload shapes and the two hard rules (`PostToolUse` is never the completion signal; real user prompts never release leases) come from the experiment recorded there.

## Global Constraints

- Run tests ONLY through the wrapper: `cd client && dart run tool/run_tests.dart <paths>` — **never raw `flutter test`** (corrupts the shared build cache).
- Before claiming done: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`.
- Logging via `AppLogger` (`appLogger`), never `print`.
- Soft file-size limits: services ~600, cubits ~500 lines.
- No UI strings in this feature → no l10n changes.

---

### Task 1: Background-task hook parse helpers

**Files:**
- Create: `client/lib/services/agent_status/background_task_latch.dart`
- Test: `client/test/services/agent_status/background_task_latch_test.dart`

**Interfaces:**
- Produces:
  - `bool isBackgroundTaskStart(Map<String, Object?> body)`
  - `String? taskNotificationToolUseId(String? prompt)`

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/agent_status/background_task_latch.dart';

void main() {
  group('isBackgroundTaskStart', () {
    test('true for PreToolUse Bash run_in_background with tool_use_id', () {
      expect(
        isBackgroundTaskStart({
          'hook_event_name': 'PreToolUse',
          'tool_name': 'Bash',
          'tool_input': {
            'command': 'ping -n 12 127.0.0.1',
            'run_in_background': true,
          },
          'tool_use_id': 'call_f766b261fd9f4358a902b8d1',
        }),
        isTrue,
      );
    });

    test('false for foreground Bash', () {
      expect(
        isBackgroundTaskStart({
          'hook_event_name': 'PreToolUse',
          'tool_name': 'Bash',
          'tool_input': {'command': 'echo hi', 'run_in_background': false},
          'tool_use_id': 'call_1',
        }),
        isFalse,
      );
    });

    test('false when run_in_background missing', () {
      expect(
        isBackgroundTaskStart({
          'hook_event_name': 'PreToolUse',
          'tool_name': 'Bash',
          'tool_input': {'command': 'echo hi'},
          'tool_use_id': 'call_1',
        }),
        isFalse,
      );
    });

    test('false for non-Bash tools (Task, Workflow, ScheduleWakeup, …)', () {
      for (final tool in ['Read', 'Task', 'Workflow', 'ScheduleWakeup']) {
        expect(
          isBackgroundTaskStart({
            'hook_event_name': 'PreToolUse',
            'tool_name': tool,
            'tool_input': {'run_in_background': true},
            'tool_use_id': 'call_1',
          }),
          isFalse,
          reason: tool,
        );
      }
    });

    test('false for PostToolUse even with the background flag', () {
      // HARD RULE (spec): PostToolUse timing is mode-dependent — it fires at
      // tool return in interactive mode and at completion in -p mode. It can
      // never start (or end) the latch.
      expect(
        isBackgroundTaskStart({
          'hook_event_name': 'PostToolUse',
          'tool_name': 'Bash',
          'tool_input': {'command': 'x', 'run_in_background': true},
          'tool_use_id': 'call_1',
        }),
        isFalse,
      );
    });

    test('false without a tool_use_id (pairing key is mandatory)', () {
      expect(
        isBackgroundTaskStart({
          'hook_event_name': 'PreToolUse',
          'tool_name': 'Bash',
          'tool_input': {'command': 'x', 'run_in_background': true},
        }),
        isFalse,
      );
    });
  });

  group('taskNotificationToolUseId', () {
    // Exact shape captured from claude 2.1.156 (spec experiment section).
    const notification = '<task-notification>\n'
        '<task-id>bi6wlgsf3</task-id>\n'
        '<tool-use-id>call_f766b261fd9f4358a902b8d1</tool-use-id>\n'
        '<output-file>C:\\tasks\\bi6wlgsf3.output</output-file>\n'
        '<status>completed</status>\n'
        '<summary>Background command completed (exit code 0)</summary>\n'
        '</task-notification>';

    test('extracts the tool-use-id from a task notification', () {
      expect(
        taskNotificationToolUseId(notification),
        'call_f766b261fd9f4358a902b8d1',
      );
    });

    test('extracts from a failed-status notification too', () {
      expect(
        taskNotificationToolUseId(
          notification.replaceFirst('completed', 'failed'),
        ),
        'call_f766b261fd9f4358a902b8d1',
      );
    });

    test('null for a real user prompt (never releases a lease)', () {
      // HARD RULE (spec): only notification-shaped prompts release.
      expect(taskNotificationToolUseId('run the tests please'), isNull);
      expect(taskNotificationToolUseId(''), isNull);
      expect(taskNotificationToolUseId(null), isNull);
      expect(
        taskNotificationToolUseId('here is a <tool-use-id>x</tool-use-id> '
            'inside a normal message'),
        isNull,
      );
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/services/agent_status/background_task_latch_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'teampilot' … background_task_latch.dart` (file does not exist).

- [ ] **Step 3: Write the implementation**

```dart
/// Claude-family background shell task hook parsing.
///
/// Start signal: `PreToolUse` (Bash) with `tool_input.run_in_background ==
/// true` and a non-empty `tool_use_id` (the lease pairing key). The tool
/// call returns immediately, so the turn's `Stop` may fire long before the
/// task finishes — the latch must survive it.
///
/// Completion signal: the CLI's re-invocation fires `UserPromptSubmit`
/// whose prompt is a `<task-notification>` block carrying the matching
/// `<tool-use-id>`. Real user prompts never release.
///
/// Payload shapes verified against claude 2.1.156 — see
/// docs/specs/2026-09-07-background-task-terminal-protection-design.md.

/// True when [body] is the start of a background shell task.
bool isBackgroundTaskStart(Map<String, Object?> body) {
  if (body['hook_event_name'] != 'PreToolUse') return false;
  if (body['tool_name'] != 'Bash') return false;
  final toolInput = body['tool_input'];
  if (toolInput is! Map) return false;
  if (toolInput['run_in_background'] != true) return false;
  return (body['tool_use_id']?.toString() ?? '').trim().isNotEmpty;
}

/// The `<tool-use-id>` inside a `<task-notification>` [prompt], or null when
/// the prompt is anything else (real user input).
String? taskNotificationToolUseId(String? prompt) {
  if (prompt == null) return null;
  final trimmed = prompt.trim();
  if (!trimmed.startsWith('<task-notification>')) return null;
  final match = RegExp(
    r'<tool-use-id>\s*([^<]+?)\s*</tool-use-id>',
  ).firstMatch(trimmed);
  return match?.group(1);
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/services/agent_status/background_task_latch_test.dart`
Expected: PASS (all).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/agent_status/background_task_latch.dart client/test/services/agent_status/background_task_latch_test.dart
git commit -m "feat(agent-status): background-task hook parse helpers"
```

---

### Task 2: Seat lease model + state owner

**Files:**
- Create: `client/lib/services/agent_status/seat_lease.dart`
- Create: `client/lib/cubits/seat_lease_cubit.dart`
- Test: `client/test/cubits/seat_lease_cubit_test.dart`

**Interfaces:**
- Consumes: `agentSeatKey({required String sessionId, required String memberId})` from `client/lib/services/agent_status/agent_attention_state.dart`.
- Produces:
  - `enum SeatLeaseKind { backgroundTask }`
  - `class SeatLease { const SeatLease({required this.kind, required this.id, required this.acquiredAt}); final SeatLeaseKind kind; final String id; final DateTime acquiredAt; }`
  - `Duration seatLeaseTtl(SeatLeaseKind kind)`
  - `class SeatLeaseState` — `leases` map, `seatHasLeases({required String sessionId, required String memberId})`, `sessionHasLeases(String sessionId)`, `pruned(DateTime now)`
  - `class SeatLeaseCubit` — `acquire({required String sessionId, required String memberId, required SeatLease lease})`, `release({required String sessionId, required String memberId, required String leaseId})`, `clearSeat({required String sessionId, required String memberId})`, `clearSession(String sessionId)`, `pruneStale()`, injectable `clock` and `pruneInterval` (null disables the timer — tests use this).

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/seat_lease_cubit.dart';
import 'package:teampilot/services/agent_status/seat_lease.dart';

SeatLease _lease(String id, [DateTime? at]) => SeatLease(
      kind: SeatLeaseKind.backgroundTask,
      id: id,
      acquiredAt: at ?? DateTime(2026, 1, 1),
    );

void main() {
  group('SeatLeaseCubit', () {
    test('acquire is idempotent per lease id', () {
      final cubit = SeatLeaseCubit(pruneInterval: null);
      addTearDown(cubit.close);
      cubit.acquire(sessionId: 's', memberId: 'm', lease: _lease('a'));
      cubit.acquire(sessionId: 's', memberId: 'm', lease: _lease('a'));
      expect(
        cubit.state.seatHasLeases(sessionId: 's', memberId: 'm'),
        isTrue,
      );
      expect(
        cubit.state.leases['s\u0000m'],
        containsPair('a', anything),
      );
    });

    test('release removes exactly the named lease', () {
      final cubit = SeatLeaseCubit(pruneInterval: null);
      addTearDown(cubit.close);
      cubit.acquire(sessionId: 's', memberId: 'm', lease: _lease('a'));
      cubit.acquire(sessionId: 's', memberId: 'm', lease: _lease('b'));
      cubit.release(sessionId: 's', memberId: 'm', leaseId: 'a');
      expect(cubit.state.leases['s\u0000m']?.keys, ['b']);
      cubit.release(sessionId: 's', memberId: 'm', leaseId: 'b');
      expect(cubit.state.seatHasLeases(sessionId: 's', memberId: 'm'), isFalse);
    });

    test('release for an unknown id is a no-op', () {
      final cubit = SeatLeaseCubit(pruneInterval: null);
      addTearDown(cubit.close);
      cubit.release(sessionId: 's', memberId: 'm', leaseId: 'ghost');
      expect(cubit.state.leases, isEmpty);
    });

    test('leases are per-seat, not session-wide', () {
      final cubit = SeatLeaseCubit(pruneInterval: null);
      addTearDown(cubit.close);
      cubit.acquire(sessionId: 's', memberId: 'm1', lease: _lease('a'));
      expect(cubit.state.seatHasLeases(sessionId: 's', memberId: 'm2'), isFalse);
      expect(cubit.state.sessionHasLeases('s'), isTrue);
      expect(cubit.state.sessionHasLeases('other'), isFalse);
    });

    test('clearSeat drops one seat; clearSession drops every seat', () {
      final cubit = SeatLeaseCubit(pruneInterval: null);
      addTearDown(cubit.close);
      cubit.acquire(sessionId: 's', memberId: 'm1', lease: _lease('a'));
      cubit.acquire(sessionId: 's', memberId: 'm2', lease: _lease('b'));
      cubit.clearSeat(sessionId: 's', memberId: 'm1');
      expect(cubit.state.seatHasLeases(sessionId: 's', memberId: 'm1'), isFalse);
      expect(cubit.state.seatHasLeases(sessionId: 's', memberId: 'm2'), isTrue);
      cubit.clearSession('s');
      expect(cubit.state.leases, isEmpty);
    });

    test('pruneStale drops leases past their kind TTL and keeps fresh ones', () {
      final clockBase = DateTime(2026, 1, 1, 12);
      var now = clockBase;
      final cubit = SeatLeaseCubit(
        pruneInterval: null,
        clock: () => now,
      );
      addTearDown(cubit.close);
      // Fresh: acquired "now".
      cubit.acquire(sessionId: 's', memberId: 'm', lease: _lease('fresh', now));
      // Stale: backgroundTask TTL is 60 minutes.
      cubit.acquire(
        sessionId: 's',
        memberId: 'm',
        lease: _lease('stale', now.subtract(const Duration(minutes: 61))),
      );
      now = clockBase.add(const Duration(seconds: 1));
      cubit.pruneStale();
      expect(cubit.state.leases['s\u0000m']?.keys, ['fresh']);
    });

    test('seatLeaseTtl — backgroundTask keeps a 60-minute safety net', () {
      expect(
        seatLeaseTtl(SeatLeaseKind.backgroundTask),
        const Duration(minutes: 60),
      );
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/cubits/seat_lease_cubit_test.dart`
Expected: FAIL — unresolved imports for `seat_lease_cubit.dart` / `seat_lease.dart`.

- [ ] **Step 3: Write the model**

`client/lib/services/agent_status/seat_lease.dart`:

```dart
import 'package:equatable/equatable.dart';

/// Why a seat's underlying CLI process must stay alive beyond the attention
/// turn (`working` / `waiting` / `done`). A `done` seat can hold leases —
/// e.g. its CLI answered, then parked waiting on a background shell task.
enum SeatLeaseKind { backgroundTask }

/// One keep-alive hold on a seat's CLI process.
class SeatLease extends Equatable {
  const SeatLease({
    required this.kind,
    required this.id,
    required this.acquiredAt,
  });

  final SeatLeaseKind kind;

  /// Pairing key — for [SeatLeaseKind.backgroundTask] the `tool_use_id` of
  /// the starting `PreToolUse`.
  final String id;

  final DateTime acquiredAt;

  @override
  List<Object?> get props => [kind, id, acquiredAt];
}

/// Safety net for leases whose terminal event never arrives (CLI crash
/// before re-invocation, task killed via TaskStop, hook POST lost).
/// Event-paired leases normally clear long before this.
Duration seatLeaseTtl(SeatLeaseKind kind) => switch (kind) {
      SeatLeaseKind.backgroundTask => const Duration(minutes: 60),
    };
```

- [ ] **Step 4: Write the state owner**

`client/lib/cubits/seat_lease_cubit.dart` (pattern: `AgentAttentionCubit` — Equatable state, injected clock, periodic prune):

```dart
import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../services/agent_status/agent_attention_state.dart' show agentSeatKey;
import '../services/agent_status/seat_lease.dart';
import '../utils/logging/logger.dart';

/// How often [SeatLeaseCubit] physically prunes TTL-expired leases.
const Duration seatLeasePruneInterval = Duration(minutes: 1);

class SeatLeaseState extends Equatable {
  const SeatLeaseState({this.leases = const {}});

  /// seatKey (`agentSeatKey`) → leaseId → lease.
  final Map<String, Map<String, SeatLease>> leases;

  bool seatHasLeases({
    required String sessionId,
    required String memberId,
  }) =>
      (leases[agentSeatKey(sessionId: sessionId, memberId: memberId)] ??
          const {}).isNotEmpty;

  bool sessionHasLeases(String sessionId) {
    final prefix = '${sessionId.trim()}\u0000';
    for (final e in leases.entries) {
      if (e.key.startsWith(prefix) && e.value.isNotEmpty) return true;
    }
    return false;
  }

  /// Drops leases past their kind TTL. Pure — the cubit logs the expiries.
  SeatLeaseState pruned(DateTime now) {
    var changed = false;
    final next = <String, Map<String, SeatLease>>{};
    for (final e in leases.entries) {
      final kept = <String, SeatLease>{};
      for (final lease in e.value.entries) {
        if (now.difference(lease.value.acquiredAt) <
            seatLeaseTtl(lease.value.kind)) {
          kept[lease.key] = lease.value;
        } else {
          changed = true;
        }
      }
      if (kept.isNotEmpty) next[e.key] = kept;
    }
    if (!changed && next.length == leases.length) return this;
    return SeatLeaseState(leases: next);
  }

  @override
  List<Object?> get props => [leases];
}

/// Holds per-seat keep-alive leases ("the CLI process must survive").
/// Driven by [seatLeaseProjection] from the runtime-event gateway; consumed
/// by the idle terminal reclaim. Independent of attention semantics.
class SeatLeaseCubit extends Cubit<SeatLeaseState> {
  SeatLeaseCubit({DateTime Function()? clock, Duration? pruneInterval})
      : _clock = clock ?? DateTime.now,
        super(const SeatLeaseState()) {
    final interval = pruneInterval ?? seatLeasePruneInterval;
    if (interval != null) {
      _pruneTimer = Timer.periodic(interval, (_) => pruneStale());
    }
  }

  final DateTime Function() _clock;
  Timer? _pruneTimer;

  /// Idempotent per lease id; refreshes `acquiredAt` on re-acquire.
  void acquire({
    required String sessionId,
    required String memberId,
    required SeatLease lease,
  }) {
    final key = agentSeatKey(sessionId: sessionId, memberId: memberId);
    final seats = Map<String, Map<String, SeatLease>>.of(state.leases);
    final seat = Map<String, SeatLease>.of(seats[key] ?? const {});
    seat[lease.id] = lease;
    seats[key] = seat;
    emit(SeatLeaseState(leases: seats));
  }

  /// No-op when the lease is absent (e.g. the start hook POST was lost).
  void release({
    required String sessionId,
    required String memberId,
    required String leaseId,
  }) {
    final key = agentSeatKey(sessionId: sessionId, memberId: memberId);
    final seat = state.leases[key];
    if (seat == null || !seat.containsKey(leaseId)) return;
    final seats = Map<String, Map<String, SeatLease>>.of(state.leases);
    final remaining = Map<String, SeatLease>.of(seat)..remove(leaseId);
    if (remaining.isEmpty) {
      seats.remove(key);
    } else {
      seats[key] = remaining;
    }
    emit(SeatLeaseState(leases: seats));
  }

  /// Drop one seat (PTY exit, disconnect, reclaim-discard).
  void clearSeat({required String sessionId, required String memberId}) {
    final key = agentSeatKey(sessionId: sessionId, memberId: memberId);
    if (!state.leases.containsKey(key)) return;
    final seats = Map<String, Map<String, SeatLease>>.of(state.leases)
      ..remove(key);
    emit(SeatLeaseState(leases: seats));
  }

  /// Drop every seat in a session (tab close, team-session restart).
  void clearSession(String sessionId) {
    final prefix = '${sessionId.trim()}\u0000';
    final seats = Map<String, Map<String, SeatLease>>.of(state.leases);
    final before = seats.length;
    seats.removeWhere((k, _) => k.startsWith(prefix));
    if (seats.length == before) return;
    emit(SeatLeaseState(leases: seats));
  }

  /// Physically prune TTL-expired leases, logging each expiry — a TTL
  /// expiry means the paired completion event never arrived (notification
  /// lost, CLI killed, task stopped without notifying).
  void pruneStale() {
    if (isClosed) return;
    final now = _clock();
    final next = state.pruned(now);
    if (next == state) return;
    for (final e in state.leases.entries) {
      for (final lease in e.value.values) {
        if (now.difference(lease.acquiredAt) >= seatLeaseTtl(lease.kind)) {
          appLogger.w(
            '[seat-lease] ttl-expired seat=${e.key} '
            'kind=${lease.kind.name} id=${lease.id}',
          );
        }
      }
    }
    emit(next);
  }

  @override
  Future<void> close() {
    _pruneTimer?.cancel();
    _pruneTimer = null;
    return super.close();
  }
}
```

Note: `acquire` refreshes `acquiredAt` on re-acquire (idempotent replay of the same `PreToolUse` hook delivery cannot artificially age or extend the lease beyond its TTL from first sight — it keeps the earliest-safe semantics simple: last delivery wins, TTL is 60 min, hook replays are deduplicated upstream by the gateway's native event ids anyway).

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/cubits/seat_lease_cubit_test.dart`
Expected: PASS (all).

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/agent_status/seat_lease.dart client/lib/cubits/seat_lease_cubit.dart client/test/cubits/seat_lease_cubit_test.dart
git commit -m "feat(agent-status): seat lease model + SeatLeaseCubit"
```

---

### Task 3: AgentStatusEvent fields + normalizer population

**Files:**
- Modify: `client/lib/services/agent_status/agent_status_event.dart`
- Modify: `client/lib/services/cli/registry/capabilities/claude_family_agent_status_normalizer.dart`
- Test: `client/test/services/cli/registry/capabilities/claude_family_agent_status_normalizer_test.dart` (append a group)

**Interfaces:**
- Consumes: `isBackgroundTaskStart` / `taskNotificationToolUseId` from Task 1.
- Produces (on `AgentStatusEvent`):
  - `final bool backgroundTaskStarted` (default `false`)
  - `final String? taskNotificationToolUseId` (default `null`)
  - plus `copyWith`, `==`, `hashCode` coverage for both.

- [ ] **Step 1: Write the failing tests**

Append to the normalizer test file (inside `main`, as a sibling `group`):

```dart
    group('background task lease signals', () {
      test('PreToolUse Bash run_in_background flags backgroundTaskStarted', () {
        final status =
            const ClaudeFamilyAgentStatusNormalizer().normalize({
          'hook_event_name': 'PreToolUse',
          'tool_name': 'Bash',
          'tool_input': {
            'command': 'ping -n 12 127.0.0.1',
            'run_in_background': true,
          },
          'tool_use_id': 'call_f766b261fd9f4358a902b8d1',
        });
        expect(status, isNotNull);
        expect(status!.state, AgentSeatAttention.working);
        expect(status.backgroundTaskStarted, isTrue);
        expect(status.toolUseId, 'call_f766b261fd9f4358a902b8d1');
        expect(status.taskNotificationToolUseId, isNull);
      });

      test('foreground Bash PreToolUse does not flag', () {
        final status =
            const ClaudeFamilyAgentStatusNormalizer().normalize({
          'hook_event_name': 'PreToolUse',
          'tool_name': 'Bash',
          'tool_input': {'command': 'echo hi'},
          'tool_use_id': 'call_1',
        });
        expect(status!.backgroundTaskStarted, isFalse);
      });

      test('UserPromptSubmit task notification carries the release id', () {
        final status =
            const ClaudeFamilyAgentStatusNormalizer().normalize({
          'hook_event_name': 'UserPromptSubmit',
          'prompt': '<task-notification>\n'
              '<task-id>bi6wlgsf3</task-id>\n'
              '<tool-use-id>call_f766b261fd9f4358a902b8d1</tool-use-id>\n'
              '<status>completed</status>\n'
              '</task-notification>',
        });
        expect(status, isNotNull);
        expect(status!.state, AgentSeatAttention.working);
        expect(status.hasExplicitPrompt, isTrue);
        expect(
          status.taskNotificationToolUseId,
          'call_f766b261fd9f4358a902b8d1',
        );
        expect(status.backgroundTaskStarted, isFalse);
      });

      test('real user prompt carries no release id', () {
        final status =
            const ClaudeFamilyAgentStatusNormalizer().normalize({
          'hook_event_name': 'UserPromptSubmit',
          'prompt': 'how is the test run going?',
        });
        expect(status!.taskNotificationToolUseId, isNull);
      });
    });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/registry/capabilities/claude_family_agent_status_normalizer_test.dart`
Expected: FAIL — `backgroundTaskStarted` / `taskNotificationToolUseId` are not defined on `AgentStatusEvent`.

- [ ] **Step 3: Extend `AgentStatusEvent`**

In `client/lib/services/agent_status/agent_status_event.dart`:

1. Constructor: add after `permissionRequest`:

```dart
    this.backgroundTaskStarted = false,
    this.taskNotificationToolUseId,
```

2. Fields: add after `permissionRequest`:

```dart
  /// Claude-family `PreToolUse` (Bash) with `run_in_background: true` —
  /// the seat's CLI now hosts a background shell task (lease start).
  final bool backgroundTaskStarted;

  /// Claude-family `UserPromptSubmit` carrying a `<task-notification>` —
  /// the `<tool-use-id>` of the background task that just finished (lease
  /// release). Null for real user prompts.
  final String? taskNotificationToolUseId;
```

3. `copyWith`: add parameters `bool? backgroundTaskStarted, String? taskNotificationToolUseId,` and assignments `backgroundTaskStarted: backgroundTaskStarted ?? this.backgroundTaskStarted, taskNotificationToolUseId: taskNotificationToolUseId ?? this.taskNotificationToolUseId,`.

4. `==`: add `backgroundTaskStarted == other.backgroundTaskStarted && taskNotificationToolUseId == other.taskNotificationToolUseId &&` before `permissionRequest == other.permissionRequest`.

5. `hashCode`: add `backgroundTaskStarted, taskNotificationToolUseId,` into `Object.hash(...)`.

- [ ] **Step 4: Populate in the normalizer**

In `client/lib/services/cli/registry/capabilities/claude_family_agent_status_normalizer.dart`:

1. Import: `import '../../../agent_status/background_task_latch.dart';`

2. In `normalize`, after the `permissionRequest` computation and before `build`, add:

```dart
    final backgroundTaskStarted = isBackgroundTaskStart(body);
    final taskNotification = backgroundTaskStarted
        ? null
        : taskNotificationToolUseId(prompt);
```

3. In `build`, add the two fields after `permissionRequest: permissionRequest,`:

```dart
          backgroundTaskStarted: backgroundTaskStarted,
          taskNotificationToolUseId: taskNotification,
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/registry/capabilities/claude_family_agent_status_normalizer_test.dart`
Expected: PASS (new group + all pre-existing tests).

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/agent_status/agent_status_event.dart client/lib/services/cli/registry/capabilities/claude_family_agent_status_normalizer.dart client/test/services/cli/registry/capabilities/claude_family_agent_status_normalizer_test.dart
git commit -m "feat(agent-status): lease start/release fields on AgentStatusEvent"
```

---

### Task 4: Gateway lease projection

**Files:**
- Create: `client/lib/services/agent_runtime/seat_lease_projection.dart`
- Test: `client/test/services/agent_runtime/seat_lease_projection_test.dart`

**Interfaces:**
- Consumes: `RuntimeEventProjection({required void Function(RuntimeEventEnvelope) onEvent})` and `RuntimeEventEnvelope` / `RuntimeSeatKey` / `RuntimeEventKind` from `client/lib/services/agent_runtime/runtime_event.dart`; `ChatInteractionCapability` from `client/lib/services/cli/registry/capabilities/chat_interaction_capability.dart`; `CliToolRegistry.capability<T>(cli)`; `SeatLeaseCubit` (Task 2); `AgentStatusEvent` fields (Task 3).
- Produces: `RuntimeEventProjection seatLeaseProjection({required SeatLeaseCubit leases, CliToolRegistry? registry})`

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/seat_lease_cubit.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/agent_runtime/runtime_event.dart';
import 'package:teampilot/services/agent_runtime/seat_lease_projection.dart';

RuntimeEventEnvelope _envelope(
  Map<String, Object?> raw, {
  RuntimeEventKind kind = RuntimeEventKind.statusReported,
  int sequence = 1,
}) =>
    RuntimeEventEnvelope(
      seat: const RuntimeSeatKey(sessionId: 's1', memberId: 'm1'),
      cli: CliTool.claude,
      kind: kind,
      occurredAt: DateTime(2026, 1, 1),
      sequence: sequence,
      raw: raw,
    );

void main() {
  group('seatLeaseProjection', () {
    test('PreToolUse background Bash acquires a lease keyed by tool_use_id',
        () {
      final cubit = SeatLeaseCubit(pruneInterval: null);
      addTearDown(cubit.close);
      final projection = seatLeaseProjection(leases: cubit);

      projection.apply(_envelope({
        'hook_event_name': 'PreToolUse',
        'tool_name': 'Bash',
        'tool_input': {'command': 'x', 'run_in_background': true},
        'tool_use_id': 'call_1',
      }));

      expect(cubit.state.seatHasLeases(sessionId: 's1', memberId: 'm1'), isTrue);
      expect(cubit.state.leases['s1\u0000m1']?.keys, ['call_1']);
    });

    test('task-notification UserPromptSubmit releases the matching lease',
        () {
      final cubit = SeatLeaseCubit(pruneInterval: null);
      addTearDown(cubit.close);
      final projection = seatLeaseProjection(leases: cubit);
      projection.apply(_envelope({
        'hook_event_name': 'PreToolUse',
        'tool_name': 'Bash',
        'tool_input': {'command': 'x', 'run_in_background': true},
        'tool_use_id': 'call_1',
      }, sequence: 1));

      projection.apply(_envelope({
        'hook_event_name': 'UserPromptSubmit',
        'prompt': '<task-notification>\n'
            '<task-id>t1</task-id>\n'
            '<tool-use-id>call_1</tool-use-id>\n'
            '<status>completed</status>\n'
            '</task-notification>',
      }, sequence: 2));

      expect(cubit.state.seatHasLeases(sessionId: 's1', memberId: 'm1'), isFalse);
    });

    test('real user prompt does not release', () {
      final cubit = SeatLeaseCubit(pruneInterval: null);
      addTearDown(cubit.close);
      final projection = seatLeaseProjection(leases: cubit);
      projection.apply(_envelope({
        'hook_event_name': 'PreToolUse',
        'tool_name': 'Bash',
        'tool_input': {'command': 'x', 'run_in_background': true},
        'tool_use_id': 'call_1',
      }, sequence: 1));

      projection.apply(_envelope({
        'hook_event_name': 'UserPromptSubmit',
        'prompt': 'status update?',
      }, sequence: 2));

      expect(cubit.state.seatHasLeases(sessionId: 's1', memberId: 'm1'), isTrue);
    });

    test('notification for an unknown lease is a no-op', () {
      final cubit = SeatLeaseCubit(pruneInterval: null);
      addTearDown(cubit.close);
      final projection = seatLeaseProjection(leases: cubit);
      projection.apply(_envelope({
        'hook_event_name': 'UserPromptSubmit',
        'prompt': '<task-notification>\n'
            '<task-id>t</task-id>\n'
            '<tool-use-id>ghost</tool-use-id>\n'
            '<status>completed</status>\n'
            '</task-notification>',
      }));
      expect(cubit.state.leases, isEmpty);
    });

    test('seatIdle does not clear leases', () {
      // A member reporting idle at turn end is exactly when a background
      // task is still running — leases must survive /idle. They clear on
      // the paired notification, TTL, or seat teardown only.
      final cubit = SeatLeaseCubit(pruneInterval: null);
      addTearDown(cubit.close);
      final projection = seatLeaseProjection(leases: cubit);
      projection.apply(_envelope({
        'hook_event_name': 'PreToolUse',
        'tool_name': 'Bash',
        'tool_input': {'command': 'x', 'run_in_background': true},
        'tool_use_id': 'call_1',
      }, sequence: 1));

      final idle = RuntimeEventEnvelope(
        seat: const RuntimeSeatKey(sessionId: 's1', memberId: 'm1'),
        cli: CliTool.claude,
        kind: RuntimeEventKind.seatIdle,
        occurredAt: DateTime(2026, 1, 1),
        sequence: 2,
      );
      projection.apply(idle);

      expect(cubit.state.seatHasLeases(sessionId: 's1', memberId: 'm1'), isTrue);
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/services/agent_runtime/seat_lease_projection_test.dart`
Expected: FAIL — unresolved `seat_lease_projection.dart`.

- [ ] **Step 3: Write the projection**

`client/lib/services/agent_runtime/seat_lease_projection.dart`:

```dart
import '../../cubits/seat_lease_cubit.dart';
import '../agent_status/seat_lease.dart';
import '../cli/registry/capabilities/chat_interaction_capability.dart';
import '../cli/registry/cli_tool_registry.dart';
import 'runtime_event.dart';
import 'runtime_event_projection.dart';

/// Projects normalized hook status into [SeatLeaseCubit]:
/// - `backgroundTaskStarted` → acquire a `backgroundTask` lease
///   (id = `tool_use_id`, `acquiredAt` = the envelope time).
/// - `taskNotificationToolUseId` → release that lease (any `<status>`; a
///   failed task is as finished as a completed one).
///
/// `seatIdle` envelopes are deliberately ignored: a member reporting idle
/// at turn end is exactly when a background task is still running. Leases
/// clear on the paired notification, their TTL, or seat teardown.
RuntimeEventProjection seatLeaseProjection({
  required SeatLeaseCubit leases,
  CliToolRegistry? registry,
}) {
  final effectiveRegistry = registry ?? CliToolRegistry.builtIn();
  return RuntimeEventProjection(
    onEvent: (event) {
      final raw = event.raw;
      if (raw == null) return;
      final status = effectiveRegistry
          .capability<ChatInteractionCapability>(event.cli)
          ?.normalize(raw);
      if (status == null) return;
      final startId = status.backgroundTaskStarted
          ? status.toolUseId?.trim() ?? ''
          : '';
      if (startId.isNotEmpty) {
        leases.acquire(
          sessionId: event.seat.sessionId,
          memberId: event.seat.memberId,
          lease: SeatLease(
            kind: SeatLeaseKind.backgroundTask,
            id: startId,
            acquiredAt: event.occurredAt,
          ),
        );
        return;
      }
      final releaseId = status.taskNotificationToolUseId?.trim() ?? '';
      if (releaseId.isNotEmpty) {
        leases.release(
          sessionId: event.seat.sessionId,
          memberId: event.seat.memberId,
          leaseId: releaseId,
        );
      }
    },
  );
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/services/agent_runtime/seat_lease_projection_test.dart`
Expected: PASS (all).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/agent_runtime/seat_lease_projection.dart client/test/services/agent_runtime/seat_lease_projection_test.dart
git commit -m "feat(agent-runtime): seat lease projection over runtime events"
```

---

### Task 5: Reclaim policy protection field

**Files:**
- Modify: `client/lib/services/terminal/terminal_reclaim_policy.dart`
- Test: `client/test/services/terminal/terminal_reclaim_policy_test.dart` (append)

**Interfaces:**
- Produces: `TerminalReclaimSnapshot.hasActiveLeases` (bool, default `false`); `TerminalReclaimPolicy.isProtected` returns true when set.

- [ ] **Step 1: Write the failing tests**

Append to `terminal_reclaim_policy_test.dart` (mirror the existing snapshot helper in that file — if it has a local builder function, extend it with the new optional named parameter instead of duplicating):

```dart
    test('a snapshot with an active seat lease is protected past idleAfter',
        () {
      final policy = TerminalReclaimPolicy(
        idleAfter: const Duration(seconds: 180),
      );
      final snapshot = TerminalReclaimSnapshot(
        sessionId: 's',
        memberId: 'm',
        shellRunning: true,
        shellConnecting: false,
        isTeamLead: false,
        isDisplayed: false,
        inTurn: false,
        hasUnread: false,
        hasActiveLeases: true,
      );
      expect(policy.isProtected(snapshot), isTrue);
      expect(
        policy.shouldReclaim(
          snapshot,
          DateTime(2026, 1, 1).subtract(const Duration(hours: 2)),
          DateTime(2026, 1, 1),
        ),
        isFalse,
      );
    });

    test('hasActiveLeases defaults to false (unrelated call sites unaffected)',
        () {
      final snapshot = TerminalReclaimSnapshot(
        sessionId: 's',
        memberId: 'm',
        shellRunning: true,
        shellConnecting: false,
        isTeamLead: false,
        isDisplayed: false,
        inTurn: false,
        hasUnread: false,
      );
      expect(snapshot.hasActiveLeases, isFalse);
    });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/services/terminal/terminal_reclaim_policy_test.dart`
Expected: FAIL — `hasActiveLeases` is not defined.

- [ ] **Step 3: Implement**

In `client/lib/services/terminal/terminal_reclaim_policy.dart`:

1. `TerminalReclaimSnapshot` constructor: add after `this.isSessionPinned = false,`:

```dart
    this.hasActiveLeases = false,
```

2. Field: add after `isSessionPinned`:

```dart
  /// Live seat lease (e.g. a background shell task hosted by the member's
  /// CLI) — the process must survive; never reclaim.
  final bool hasActiveLeases;
```

3. `isProtected`:

```dart
  bool isProtected(TerminalReclaimSnapshot s) =>
      !s.shellRunning ||
      s.shellConnecting ||
      s.isTeamLead ||
      s.isDisplayed ||
      s.inTurn ||
      s.hasUnread ||
      s.isSessionPinned ||
      s.hasActiveLeases;
```

4. Update the class doc comment's protection list: append "or a live seat lease".

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/services/terminal/terminal_reclaim_policy_test.dart`
Expected: PASS (new + pre-existing).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/terminal/terminal_reclaim_policy.dart client/test/services/terminal/terminal_reclaim_policy_test.dart
git commit -m "feat(terminal): reclaim protection for live seat leases"
```

---

### Task 6: Reclaim watch per-seat lease arm

**Files:**
- Modify: `client/lib/cubits/chat/tab_member_reclaim_watch.dart`
- Modify: `client/lib/cubits/chat/tab_session_runtime_coordinator.dart`
- Test: `client/test/cubits/chat/tab_member_reclaim_watch_test.dart` (append)

**Interfaces:**
- Consumes: `TerminalReclaimSnapshot.hasActiveLeases` (Task 5).
- Produces: `TabMemberReclaimWatch` named param `bool Function(String sessionId, String memberId)? seatHasActiveLeases`; `TabSessionRuntimeCoordinator` factory named param of the same type, threaded into the watch.

- [ ] **Step 1: Write the failing test**

Append to `tab_member_reclaim_watch_test.dart`, mirroring the existing test setup style in that file (it builds a `ChatTabStore` with a tab + member shell; reuse its local helpers):

```dart
    test('a member with a live seat lease is never discarded', () async {
      // Build the watch exactly like the existing idle-discard test in
      // this file, with the same tab/shell fixtures, plus:
      //
      //   TabMemberReclaimWatch(
      //     ...,
      //     seatHasActiveLeases: (sessionId, memberId) =>
      //         sessionId == 's' && memberId == 'm',
      //   )
      //
      // Drive tick() past idleAfter (use `now: () => ...` with a manual
      // clock as the existing tests do) and assert onDiscardMember was
      // NOT called and the member shell is still running.
      //
      // Then flip the callback to return false, tick again past the
      // threshold, and assert the discard DID fire — proving the arm,
      // not some other protection, held it back.
    });
```

**Note for the implementer:** the existing tests in this file already construct `TabMemberReclaimWatch` with fake tab stores and manual clocks — copy the closest one (the plain idle-discard case) verbatim as the base, add the `seatHasActiveLeases` parameter, and write both assertions from the comment above as real `expect` calls. Do not leave the comment in the final test.

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/cubits/chat/tab_member_reclaim_watch_test.dart`
Expected: FAIL — `seatHasActiveLeases` is not a parameter of `TabMemberReclaimWatch`.

- [ ] **Step 3: Implement the watch arm**

In `client/lib/cubits/chat/tab_member_reclaim_watch.dart`:

1. Constructor: add after `isSessionPinned`:

```dart
    bool Function(String sessionId, String memberId)? seatHasActiveLeases,
```

and initialize `.._seatHasActiveLeases = seatHasActiveLeases` in the initializer list. Field:

```dart
  /// Live seat lease lookup (background shell tasks) — per-seat, unlike the
  /// session-wide attention arm: one member's task must not keep a sibling
  /// member's idle terminal alive.
  final bool Function(String sessionId, String memberId)? _seatHasActiveLeases;
```

2. In `_snapshotFor`, add to the `TerminalReclaimSnapshot(...)` call after `isSessionPinned:`:

```dart
      hasActiveLeases: _seatHasActiveLeases?.call(sessionId, memberId) ?? false,
```

- [ ] **Step 4: Thread through the coordinator**

In `client/lib/cubits/chat/tab_session_runtime_coordinator.dart`:

1. Factory (the `TabSessionRuntimeCoordinator.create`-style factory that currently takes `sessionBusyFromAttention`, `sessionBusyFromDeliveryInFlight`, `isSessionPinned`, … around lines 30-110): add a named parameter:

```dart
    bool Function(String sessionId, String memberId)? seatHasActiveLeases,
```

2. Pass it into the `TabMemberReclaimWatch(...)` construction (beside `isSessionPinned: isSessionPinned`):

```dart
                seatHasActiveLeases: seatHasActiveLeases,
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/cubits/chat/tab_member_reclaim_watch_test.dart`
Expected: PASS (new + pre-existing).

- [ ] **Step 6: Commit**

```bash
git add client/lib/cubits/chat/tab_member_reclaim_watch.dart client/lib/cubits/chat/tab_session_runtime_coordinator.dart client/test/cubits/chat/tab_member_reclaim_watch_test.dart
git commit -m "feat(chat): reclaim watch consults per-seat leases"
```

---

### Task 7: ChatCubit + SessionLaunchHost wiring

**Files:**
- Modify: `client/lib/cubits/chat_cubit.dart` (constructor, field, host getter, coordinator wiring)
- Modify: `client/lib/cubits/chat/session_launch_host.dart` (interface getter + clear extensions)
- Test: `client/test/cubits/chat/session_launch_host_seat_lease_test.dart` (new)

**Interfaces:**
- Consumes: `SeatLeaseCubit` (Task 2); coordinator `seatHasActiveLeases` param (Task 6).
- Produces:
  - `SessionLaunchHost` getter: `SeatLeaseCubit? get seatLeaseCubit;`
  - `ChatCubit` constructor named param: `SeatLeaseCubit? seatLeaseCubit`
  - `clearAgentStatusSeat` also clears the seat's leases; `clearAgentStatusSessionSeats` clears the session's leases.

- [ ] **Step 1: Write the failing test**

`client/test/cubits/chat/session_launch_host_seat_lease_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/session_launch_host.dart';
import 'package:teampilot/cubits/seat_lease_cubit.dart';
import 'package:teampilot/services/agent_status/seat_lease.dart';

/// Minimal host: every interface member we do not care about forwards to
/// noSuchMethod (returns null / throws only if actually touched).
class _FakeHost implements SessionLaunchHost {
  _FakeHost(this.seatLeaseCubit);

  @override
  final SeatLeaseCubit? seatLeaseCubit;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  test('clearAgentStatusSeat drops the seat lease with attention', () {
    final cubit = SeatLeaseCubit(pruneInterval: null);
    addTearDown(cubit.close);
    cubit.acquire(
      sessionId: 's',
      memberId: 'm',
      lease: SeatLease(
        kind: SeatLeaseKind.backgroundTask,
        id: 'call_1',
        acquiredAt: DateTime(2026, 1, 1),
      ),
    );
    final host = _FakeHost(cubit);

    host.clearAgentStatusSeat(sessionId: 's', memberId: 'm');

    expect(cubit.state.leases, isEmpty);
  });

  test('clearAgentStatusSession drops every seat lease in the session', () {
    final cubit = SeatLeaseCubit(pruneInterval: null);
    addTearDown(cubit.close);
    cubit.acquire(
      sessionId: 's',
      memberId: 'm1',
      lease: SeatLease(
        kind: SeatLeaseKind.backgroundTask,
        id: 'a',
        acquiredAt: DateTime(2026, 1, 1),
      ),
    );
    cubit.acquire(
      sessionId: 's',
      memberId: 'm2',
      lease: SeatLease(
        kind: SeatLeaseKind.backgroundTask,
        id: 'b',
        acquiredAt: DateTime(2026, 1, 1),
      ),
    );
    final host = _FakeHost(cubit);

    host.clearAgentStatusSession('s');

    expect(cubit.state.leases, isEmpty);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/cubits/chat/session_launch_host_seat_lease_test.dart`
Expected: FAIL — `SeatLeaseCubit? get seatLeaseCubit` is not a member of `SessionLaunchHost` (compile error).

- [ ] **Step 3: Implement the host interface + extensions**

In `client/lib/cubits/chat/session_launch_host.dart`:

1. Import: `import '../../cubits/seat_lease_cubit.dart';` (adjust relative path to the file's own location: `import '../../cubits/seat_lease_cubit.dart';` — note the file already imports `../../cubits/agent_attention_cubit.dart`, mirror that).

2. Interface: add beside `AgentAttentionCubit? get agentAttentionCubit;` (around line 138):

```dart
  /// Seat keep-alive leases (background shell tasks); cleared with
  /// attention on seat/tab dispose (null in tests).
  SeatLeaseCubit? get seatLeaseCubit;
```

3. `clearAgentStatusSessionSeats`: add parameter `SeatLeaseCubit? seatLeaseCubit,` (beside `attention`) and body line `seatLeaseCubit?.clearSession(sessionId);`.

4. `clearAgentStatusSeat` extension: add `seatLeaseCubit?.clearSeat(sessionId: sessionId, memberId: memberId);` beside the attention clear.

5. `clearAgentStatusSession`: pass `seatLeaseCubit: seatLeaseCubit` through to `clearAgentStatusSessionSeats`.

- [ ] **Step 4: Implement ChatCubit**

In `client/lib/cubits/chat_cubit.dart`:

1. Import `seat_lease_cubit.dart`.

2. Constructor: add named param `SeatLeaseCubit? seatLeaseCubit,` beside `AgentAttentionCubit? agentAttentionCubit,` (line ~129) and field `_seatLeaseCubit = seatLeaseCubit` beside `_agentAttentionCubit` (line ~154); declare `final SeatLeaseCubit? _seatLeaseCubit;` beside `_agentAttentionCubit`'s declaration (line ~483).

3. Host getter (search for the `agentAttentionCubit` override implementing `SessionLaunchHost`): add

```dart
  @override
  SeatLeaseCubit? get seatLeaseCubit => _seatLeaseCubit;
```

4. Coordinator construction (the `TabSessionRuntimeCoordinator(...)` at line ~334): add beside `sessionBusyFromAttention:`:

```dart
        seatHasActiveLeases: (sessionId, memberId) =>
            _seatLeaseCubit?.state.seatHasLeases(
              sessionId: sessionId,
              memberId: memberId,
            ) ??
            false,
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/cubits/chat/session_launch_host_seat_lease_test.dart test/cubits/chat/`
Expected: PASS (new file + the whole chat cubit directory — guards against wiring regressions).

- [ ] **Step 6: Commit**

```bash
git add client/lib/cubits/chat_cubit.dart client/lib/cubits/chat/session_launch_host.dart client/test/cubits/chat/session_launch_host_seat_lease_test.dart
git commit -m "feat(chat): seat leases wired into reclaim + seat lifecycle"
```

---

### Task 8: App shell composition

**Files:**
- Modify: `client/lib/app/app_shell.dart` (~lines 1724-1763 gateway composition, ~1812 ChatCubit construction)

**Interfaces:**
- Consumes: `SeatLeaseCubit` (Task 2), `seatLeaseProjection` (Task 4), `ChatCubit(seatLeaseCubit: …)` (Task 7).

- [ ] **Step 1: Compose the cubit + projection + injection**

In `client/lib/app/app_shell.dart`:

1. Imports:

```dart
import '../cubits/seat_lease_cubit.dart';
import '../services/agent_runtime/seat_lease_projection.dart';
```

(relative paths as the file's existing import style dictates — it imports `agent_attention_cubit.dart` similarly.)

2. Beside `final agentAttentionCubit = AgentAttentionCubit();` (line ~1724), add:

```dart
    final seatLeaseCubit = SeatLeaseCubit();
```

3. In `runtimeProjections` (line ~1737), append after `generalPermissionProjection`:

```dart
      seatLeaseProjection(leases: seatLeaseCubit),
```

4. In the `ChatCubit(...)` construction (line ~1812), beside `agentAttentionCubit: agentAttentionCubit,` add:

```dart
      seatLeaseCubit: seatLeaseCubit,
```

- [ ] **Step 2: Analyze + run the affected suites**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: no new issues.

Run: `cd client && dart run tool/run_tests.dart test/services/agent_runtime/ test/services/agent_status/ test/cubits/chat/ test/services/terminal/`
Expected: PASS (all).

- [ ] **Step 3: Commit**

```bash
git add client/lib/app/app_shell.dart
git commit -m "feat(app): compose SeatLeaseCubit into the runtime event gateway"
```

---

### Task 9: Full verification

- [ ] **Step 1: Full analyze + test suite**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`
Expected: analyze clean, full suite PASS.

- [ ] **Step 2: Self-review the diff against the spec**

Re-read `docs/specs/2026-09-07-background-task-terminal-protection-design.md` and walk the checklist:
- PreToolUse acquires / notification releases / real prompt does not release (Tasks 1, 3, 4).
- PostToolUse never touches the latch (Task 1 test `PostToolUse even with the background flag`).
- Per-seat (not session-wide) reclaim arm (Task 6).
- TTL safety net + warning log (Task 2).
- Seat lifecycle clearing (Task 7).
- `seatIdle` does not clear leases (Task 4 test).

- [ ] **Step 3: Commit any leftovers + report**

```bash
git status
```

If anything is uncommitted that belongs to this feature, commit it. Report the final task list state, test counts, and any deviations from the plan taken during implementation.

---

## Self-Review (done at planning time)

- **Spec coverage:** parse helpers (T1), model/TTL (T2), event fields + normalizer (T3), projection incl. seatIdle + idempotence edge cases (T4), policy arm (T5), watch arm + coordinator (T6), lifecycle + ChatCubit wiring (T7), composition (T8), final gate (T9). Spec's "Non-goals" (no UI, no persistence, no new hooks) need no tasks. Open items stay open.
- **Type consistency:** `seatLeaseProjection` (T4) matches the name used in T8; `seatHasActiveLeases` callback signature `(String, String) → bool` identical in T6/T7; `SeatLeaseCubit.acquire/release/clearSeat/clearSession/pruneStale` signatures identical across T2/T4/T7.
- **Placeholder scan:** Task 6 Step 1 deliberately defers to the existing test file's fixtures via an explicit instruction with the exact parameter and both assertions spelled out — the implementer must materialize them as real `expect` calls; the note forbids leaving the comment in. All other steps carry full code.
