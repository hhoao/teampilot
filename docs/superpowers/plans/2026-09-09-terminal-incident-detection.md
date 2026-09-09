# Terminal Incident Detection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Detect CLI "incidents" (update notices, quota exhaustion, request failures/timeouts, auth errors) in PTY output and surface them to the user as waiting-attention plus an in-chat incident banner.

**Architecture:** A shared `IncidentDetectionModule` binds to the existing `TerminalObservationBus` as a session module (running phase only). Each CLI declares declarative incident patterns via a new optional `TerminalIncidentCapability`; user-defined regex rules from `SessionPreferences` are merged in. Hits set `AgentSeatAttention.waiting` (via the existing `AgentAttentionCubit`) and push `TerminalIncident` records into a new app-scoped `TerminalIncidentCubit`, whose banner renders in the chat compose section above the existing permission banner.

**Tech Stack:** Flutter / Dart, flutter_bloc (`Cubit`), `client/packages/shared_ui` (Tp design system), l10n via `.arb`.

**Spec:** `docs/superpowers/specs/2026-09-09-terminal-incident-detection-design.md`

## Global Constraints

- Never invoke `flutter test` directly — single test file: `cd client && dart run tool/run_tests.dart test/<path>.dart`; full suite only once before claiming done: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`.
- l10n: edit **only** `client/lib/l10n/app_en.arb` and `client/lib/l10n/app_zh.arb` (generated files come from `flutter gen-l10n` in test tooling).
- No `print`; diagnostics → `AppLogger`; user errors → l10n.
- No `if (cli == CliTool.…)` outside CLI-owned files; CLI differences only via capabilities.
- All engine exceptions are caught and logged (`recordError: false`) — a bad pattern must never break terminal rendering.
- File size limits and `pages/` vs `widgets/` layering per `docs/CODE_QUALITY.md`.
- Member placement, paths, logging conventions per `AGENTS.md`.

## File Structure

```
client/lib/services/terminal/incident/
  terminal_incident.dart              # Kind enum, severity, Pattern, runtime Incident, matcher
  incident_detection_module.dart      # Observation contributor: decode → strip ANSI → lines → match → dedupe
  incident_pattern_registry.dart      # Merge CLI capability patterns + user rules → per-seat matcher
client/lib/services/cli/registry/capabilities/
  terminal_incident_capability.dart   # Optional capability interface
client/lib/services/cli/claude/capabilities/
  terminal_incidents.dart             # ClaudeFamily patterns (shared by flashskyai)
client/lib/services/cli/codex/capabilities/terminal_incidents.dart
client/lib/services/cli/cursor/capabilities/terminal_incidents.dart
client/lib/services/cli/opencode/capabilities/terminal_incidents.dart
client/lib/cubits/terminal_incident_cubit.dart
client/lib/widgets/chat/terminal_incident_banner.dart
client/lib/pages/config/cli_incident_rules_section.dart   # user-defined rules settings UI
Modify: models/session_preferences.dart, cubits/session_preferences_cubit.dart,
  services/terminal/terminal_session.dart, services/launch/session_shell_connector.dart,
  cubits/chat/session_launch_host.dart, app/app_shell.dart, main.dart,
  pages/chat/session_chat_compose_section.dart,
  widgets/right_tools/members_panel.dart (+_MembersPanelTile), l10n arb files,
  services/cli/{claude,flashskyai,codex,cursor,opencode}/*_tool.dart
```

---

### Task 1: Incident model + matcher core

**Files:**
- Create: `client/lib/services/terminal/incident/terminal_incident.dart`
- Test: `client/test/services/terminal/incident/terminal_incident_test.dart`

**Interfaces:**
- Produces (used by Tasks 2, 3, 5, 8):
  - `enum TerminalIncidentKind { updateAvailable, creditExhausted, authRequired, rateLimited, requestFailed, timeout, networkError, other }`
  - `enum TerminalIncidentSeverity { info, warning, error }`
  - `final class TerminalIncidentPattern` with `const TerminalIncidentPattern({required this.id, required this.kind, required this.severity, required this.patterns})` — `id: String`, `kind: TerminalIncidentKind`, `severity: TerminalIncidentSeverity`, `patterns: List<RegExp>`
  - `final class TerminalIncident` with `const TerminalIncident({required this.patternId, required this.kind, required this.severity, required this.cli, required this.sessionId, required this.memberId, required this.matchedLine, required this.timestamp})` — all `final` fields of the stated types; override `toString` as `TerminalIncident($cli $kind $patternId)`.
  - `TerminalIncidentMatch? matchIncidentLine(String line, List<TerminalIncidentPattern> patterns)` — returns first hit or null. `TerminalIncidentMatch` is `({TerminalIncidentPattern pattern, String matchedLine})` (record type).

- [ ] **Step 1: Write the failing test**

```dart
// client/test/services/terminal/incident/terminal_incident_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/terminal/incident/terminal_incident.dart';

void main() {
  const patterns = [
    TerminalIncidentPattern(
      id: 'claude.rate_limit',
      kind: TerminalIncidentKind.rateLimited,
      severity: TerminalIncidentSeverity.warning,
      patterns: [RegExp(r'rate limit exceeded', caseSensitive: false)],
    ),
    TerminalIncidentPattern(
      id: 'claude.update',
      kind: TerminalIncidentKind.updateAvailable,
      severity: TerminalIncidentSeverity.info,
      patterns: [RegExp(r'update available', caseSensitive: false)],
    ),
  ];

  test('matches first pattern hit and returns matched line', () {
    final m = matchIncidentLine('API rate limit exceeded', patterns);
    expect(m, isNotNull);
    expect(m!.pattern.id, 'claude.rate_limit');
    expect(m.pattern.kind, TerminalIncidentKind.rateLimited);
    expect(m.matchedLine, 'API rate limit exceeded');
  });

  test('no match returns null', () {
    expect(matchIncidentLine('all good here', patterns), isNull);
  });

  test('empty pattern list returns null', () {
    expect(matchIncidentLine('rate limit exceeded', const []), isNull);
  });

  test('incident exposes cli/member/line', () {
    final incident = TerminalIncident(
      patternId: 'claude.update',
      kind: TerminalIncidentKind.updateAvailable,
      severity: TerminalIncidentSeverity.info,
      cli: 'claude',
      sessionId: 's1',
      memberId: 'm1',
      matchedLine: 'Claude Code update available',
      timestamp: DateTime.fromMillisecondsSinceEpoch(0),
    );
    expect(incident.patternId, 'claude.update');
    expect(incident.memberId, 'm1');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/terminal/incident/terminal_incident_test.dart`
Expected: FAIL — file `terminal_incident.dart` does not exist (import error).

- [ ] **Step 3: Write minimal implementation**

```dart
// client/lib/services/terminal/incident/terminal_incident.dart
/// Declarative incident vocabulary for terminal output scanning.
enum TerminalIncidentKind {
  updateAvailable,
  creditExhausted,
  authRequired,
  rateLimited,
  requestFailed,
  timeout,
  networkError,
  other,
}

enum TerminalIncidentSeverity { info, warning, error }

/// One declarable detection rule: any of [patterns] matching a rendered
/// terminal line raises a [TerminalIncident] of [kind].
final class TerminalIncidentPattern {
  const TerminalIncidentPattern({
    required this.id,
    required this.kind,
    required this.severity,
    required this.patterns,
  });

  final String id;
  final TerminalIncidentKind kind;
  final TerminalIncidentSeverity severity;
  final List<RegExp> patterns;
}

/// Runtime record of one detected incident for the event stream.
final class TerminalIncident {
  const TerminalIncident({
    required this.patternId,
    required this.kind,
    required this.severity,
    required this.cli,
    required this.sessionId,
    required this.memberId,
    required this.matchedLine,
    required this.timestamp,
  });

  final String patternId;
  final TerminalIncidentKind kind;
  final TerminalIncidentSeverity severity;
  final String cli;
  final String sessionId;
  final String memberId;
  final String matchedLine;
  final DateTime timestamp;

  @override
  String toString() => 'TerminalIncident($cli $kind $patternId)';
}

typedef TerminalIncidentMatch =
    ({TerminalIncidentPattern pattern, String matchedLine});

/// First pattern hit on [line], or null when nothing matches.
TerminalIncidentMatch? matchIncidentLine(
  String line,
  List<TerminalIncidentPattern> patterns,
) {
  for (final pattern in patterns) {
    for (final regex in pattern.patterns) {
      if (regex.hasMatch(line)) {
        return (pattern: pattern, matchedLine: line);
      }
    }
  }
  return null;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/terminal/incident/terminal_incident_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/terminal/incident/terminal_incident.dart client/test/services/terminal/incident/terminal_incident_test.dart
git commit -m "feat: terminal incident model and line matcher"
```

---

### Task 2: IncidentDetectionModule (engine)

**Files:**
- Create: `client/lib/services/terminal/incident/incident_detection_module.dart`
- Test: `client/test/services/terminal/incident/incident_detection_module_test.dart`

**Interfaces:**
- Consumes: `TerminalIncidentPattern`, `TerminalIncident`, `matchIncidentLine` (Task 1); `TerminalObservationBus.addOutputObserver(phases:)`, `TerminalObservationSeat`, `TerminalObservationContributor`, `CallbackObservationBinding` (existing, see `client/lib/services/terminal/observation/`); `AgentAttentionCubit.applyEvent({sessionId, memberId, event: AgentStatusEvent, skipPermissions})` and `AgentSeatAttention.waiting` (existing); `AgentStatusEvent` constructor `const AgentStatusEvent({required this.state})` (existing).
- Produces (used by Task 5):
  ```dart
  final class IncidentDetectionModule implements TerminalObservationContributor {
    IncidentDetectionModule({
      required List<TerminalIncidentPattern> patterns,
      void Function(TerminalIncident incident)? onIncident,
      Duration cooldown = const Duration(seconds: 30),
      DateTime Function()? clock,
    });
    // bind(bus, seat) → CallbackObservationBinding; running-phase output only.
  }
  ```

Behavior spec (all covered by tests):
- utf8 decode with `allowMalformed: true`; strip ANSI escapes with `RegExp(r'\x1B\[[0-9;]*[A-Za-z]')` (same approach as `CredentialLoginUrlDetector.stripAnsi`); hold a pending partial line across chunks; emit complete lines on `\n` (also `\r\n`); discard empty/whitespace-only lines.
- On a line match: build `TerminalIncident` (cli from `seat.cli?.value ?? ''`, sessionId/memberId from seat, timestamp from `clock`), call `onIncident`, and set attention waiting via `seat.attention.applyEvent(... AgentStatusEvent(state: AgentSeatAttention.waiting) ...)` when `seat.attention != null`, with `skipPermissions: false` (incidents are informational — the user must see them even when permissions are skipped; `isInteractiveWaiting` does not apply so pass `false` only because the signature requires it — verify no gate drops the event; if `applyEvent` with a plain waiting event is dropped when `skipPermissions` is true, call with `false` regardless since we control the caller here, and note it in a comment).
- Dedupe: same `(patternId)` — one hit per turn is impossible to observe here, so use the cooldown only: skip a hit when the same `patternId` fired within `cooldown` (default 30s). The turn-level reset is unnecessary state; cooldown covers retry storms.
- All decode/match/handler exceptions → `AppLogger.instance.e('IncidentDetectionModule failed', error:, stackTrace:, recordError: false)` and continue.

- [ ] **Step 1: Write the failing test**

```dart
// client/test/services/terminal/incident/incident_detection_module_test.dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/agent_status/agent_attention_state.dart';
import 'package:teampilot/services/terminal/incident/incident_detection_module.dart';
import 'package:teampilot/services/terminal/incident/terminal_incident.dart';
import 'package:teampilot/services/terminal/observation/terminal_observation_bus.dart';
import 'package:teampilot/services/terminal/observation/terminal_observation_seat.dart';
import 'package:teampilot/services/terminal/terminal_launch_phase.dart';

void main() {
  final patterns = [
    const TerminalIncidentPattern(
      id: 'test.rate',
      kind: TerminalIncidentKind.rateLimited,
      severity: TerminalIncidentSeverity.warning,
      patterns: [RegExp('rate limit', caseSensitive: false)],
    ),
  ];

  TerminalObservationSeat seatWith({AgentAttentionCubit? attention}) {
    return TerminalObservationSeat(
      sessionId: 's1',
      memberId: 'm1',
      cli: CliTool.claude,
      phase: TerminalLaunchPhase.running,
      attention: attention,
    );
  }

  group('line assembly', () {
    test('splits chunks across a line boundary', () {
      final incidents = <TerminalIncident>[];
      final bus = TerminalObservationBus(
        seat: seatWith(),
      );
      IncidentDetectionModule(
        patterns: patterns,
        onIncident: incidents.add,
      ).bind(bus, bus.seat);
      bus.dispatchOutput(
        Uint8List.fromList('API rate lim'.codeUnits),
      );
      bus.dispatchOutput(
        Uint8List.fromList('it exceeded\nok\n'.codeUnits),
      );
      expect(incidents.length, 1);
      expect(incidents.single.matchedLine, 'API rate limit exceeded');
      bus.dispose();
    });

    test('strips ANSI escapes before matching', () {
      final incidents = <TerminalIncident>[];
      final bus = TerminalObservationBus(seat: seatWith());
      IncidentDetectionModule(
        patterns: patterns,
        onIncident: incidents.add,
      ).bind(bus, bus.seat);
      bus.dispatchOutput(
        Uint8List.fromList('\x1B[31mrate limit\x1B[0m hit\n'.codeUnits),
      );
      expect(incidents.single.matchedLine, 'rate limit hit');
      bus.dispose();
    });

    test('no match on benign lines', () {
      final incidents = <TerminalIncident>[];
      final bus = TerminalObservationBus(seat: seatWith());
      IncidentDetectionModule(
        patterns: patterns,
        onIncident: incidents.add,
      ).bind(bus, bus.seat);
      bus.dispatchOutput(Uint8List.fromList('all fine\n'.codeUnits));
      expect(incidents, isEmpty);
      bus.dispose();
    });
  });

  group('cooldown dedupe', () {
    test('same pattern twice in cooldown fires once', () {
      final incidents = <TerminalIncident>[];
      var now = DateTime(2026);
      final bus = TerminalObservationBus(seat: seatWith());
      IncidentDetectionModule(
        patterns: patterns,
        onIncident: incidents.add,
        clock: () => now,
      ).bind(bus, bus.seat);
      bus.dispatchOutput(Uint8List.fromList('rate limit a\n'.codeUnits));
      bus.dispatchOutput(Uint8List.fromList('rate limit b\n'.codeUnits));
      expect(incidents.length, 1);
      now = now.add(const Duration(seconds: 31));
      bus.dispatchOutput(Uint8List.fromList('rate limit c\n'.codeUnits));
      expect(incidents.length, 2);
      bus.dispose();
    });
  });

  group('attention + seat fields', () {
    test('sets seat waiting and fills cli/member ids', () {
      final attention = AgentAttentionCubit();
      addTearDown(attention.close);
      final incidents = <TerminalIncident>[];
      final bus = TerminalObservationBus(seat: seatWith(attention: attention));
      IncidentDetectionModule(
        patterns: patterns,
        onIncident: incidents.add,
      ).bind(bus, bus.seat);
      bus.dispatchOutput(Uint8List.fromList('rate limit\n'.codeUnits));
      expect(
        attention.state.attentionFor(sessionId: 's1', memberId: 'm1'),
        AgentSeatAttention.waiting,
      );
      expect(incidents.single.cli, 'claude');
      expect(incidents.single.memberId, 'm1');
      bus.dispose();
    });

    test('handler exceptions do not break other observers', () {
      final incidents = <TerminalIncident>[];
      final bus = TerminalObservationBus(seat: seatWith());
      IncidentDetectionModule(
        patterns: patterns,
        onIncident: (_) => throw StateError('boom'),
      ).bind(bus, bus.seat);
      // Must not throw through dispatchOutput.
      bus.dispatchOutput(Uint8List.fromList('rate limit\n'.codeUnits));
      expect(incidents, isEmpty);
      bus.dispose();
    });
  });

  group('phase gating', () {
    test('confirming-phase output is ignored', () {
      final incidents = <TerminalIncident>[];
      final seat = TerminalObservationSeat(
        sessionId: 's1',
        memberId: 'm1',
        phase: TerminalLaunchPhase.confirming,
      );
      final bus = TerminalObservationBus(seat: seat);
      IncidentDetectionModule(
        patterns: patterns,
        onIncident: incidents.add,
      ).bind(bus, bus.seat);
      bus.dispatchOutput(Uint8List.fromList('rate limit\n'.codeUnits));
      expect(incidents, isEmpty);
      bus.dispose();
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/terminal/incident/incident_detection_module_test.dart`
Expected: FAIL — module file does not exist.

- [ ] **Step 3: Write minimal implementation**

```dart
// client/lib/services/terminal/incident/incident_detection_module.dart
import 'dart:convert';
import 'dart:typed_data';

import '../../../cubits/agent_attention_cubit.dart';
import '../../../models/team_config.dart';
import '../../../utils/logging/logger.dart';
import '../../agent_status/agent_attention_state.dart';
import '../../agent_status/agent_status_event.dart';
import '../observation/terminal_observation_bus.dart';
import '../observation/terminal_observation_seat.dart';
import '../terminal_launch_phase.dart';
import 'terminal_incident.dart';
import '../../cli/registry/capabilities/terminal_observation_contributor.dart';

/// Scans running-phase PTY lines for CLI incident patterns.
///
/// Local PTY and SSH both flow through [TerminalObservationBus.dispatchOutput],
/// so this module covers both transports. Every failure path is caught and
/// logged — a bad pattern must never break terminal rendering.
final class IncidentDetectionModule implements TerminalObservationContributor {
  IncidentDetectionModule({
    required List<TerminalIncidentPattern> patterns,
    void Function(TerminalIncident incident)? onIncident,
    this.cooldown = const Duration(seconds: 30),
    DateTime Function()? clock,
  }) : _patterns = patterns,
       _onIncident = onIncident,
       _clock = clock ?? DateTime.now;

  final List<TerminalIncidentPattern> _patterns;
  final void Function(TerminalIncident incident)? _onIncident;
  final Duration cooldown;
  final DateTime Function() _clock;

  static final RegExp _ansi = RegExp(r'\x1B\[[0-9;]*[A-Za-z]');

  final _pendingLine = StringBuffer();
  final Map<String, DateTime> _lastFiredAt = {};

  @override
  TerminalObservationBinding bind(
    TerminalObservationBus bus,
    TerminalObservationSeat seat,
  ) {
    final subscription = bus.addOutputObserver(
      _IncidentOutputObserver(this, seat),
      phases: {TerminalLaunchPhase.running},
    );
    return CallbackObservationBinding(subscription.cancel);
  }

  // Called by the observer; visible for testing via dispatch only.
  void _onOutput(Uint8List bytes, TerminalObservationSeat seat) {
    final decoded = utf8.decode(bytes, allowMalformed: true);
    final stripped = decoded.replaceAll(_ansi, '');
    _pendingLine.write(stripped);
    while (true) {
      final text = _pendingLine.toString();
      final nl = text.indexOf('\n');
      if (nl < 0) break;
      final line = text.substring(0, nl).replaceAll('\r', '');
      _pendingLine
        ..clear()
        ..write(text.substring(nl + 1));
      if (line.trim().isEmpty) continue;
      try {
        _matchLine(line, seat);
      } on Object catch (error, stackTrace) {
        AppLogger.instance.e(
          'IncidentDetectionModule failed',
          error: error,
          stackTrace: stackTrace,
          recordError: false,
        );
      }
    }
  }

  void _matchLine(String line, TerminalObservationSeat seat) {
    final match = matchIncidentLine(line, _patterns);
    if (match == null) return;

    final now = _clock();
    final last = _lastFiredAt[match.pattern.id];
    if (last != null && now.difference(last) < cooldown) return;
    _lastFiredAt[match.pattern.id] = now;

    final incident = TerminalIncident(
      patternId: match.pattern.id,
      kind: match.pattern.kind,
      severity: match.pattern.severity,
      cli: seat.cli?.value ?? '',
      sessionId: seat.sessionId,
      memberId: seat.memberId,
      matchedLine: line,
      timestamp: now,
    );
    try {
      _onIncident?.call(incident);
    } on Object catch (error, stackTrace) {
      AppLogger.instance.e(
        'IncidentDetectionModule onIncident failed',
        error: error,
        stackTrace: stackTrace,
        recordError: false,
      );
    }

    // Incidents are informational waiting: the user must see them even when
    // permission prompts are skipped, so skipPermissions is always false.
    final attention = seat.attention;
    if (attention != null) {
      attention.applyEvent(
        sessionId: seat.sessionId,
        memberId: seat.memberId,
        event: const AgentStatusEvent(state: AgentSeatAttention.waiting),
        skipPermissions: false,
      );
    }
  }
}

final class _IncidentOutputObserver implements TerminalOutputObserver {
  const _IncidentOutputObserver(this._module, this._seat);

  final IncidentDetectionModule _module;
  final TerminalObservationSeat _seat;

  @override
  void onOutput(Uint8List bytes, TerminalObservationSeat seat) {
    // Seat is the bus-owned seat; the module holds per-binding line state.
    _module._onOutput(bytes, _seat);
  }
}
```

Note: the observer captures the bind-time seat; `_onOutput` signature keeps the bus contract. If analysis complains about unused `seat` param in `onOutput`, use the module-captured seat as shown above (that's intentional).

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/terminal/incident/incident_detection_module_test.dart`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/terminal/incident/incident_detection_module.dart client/test/services/terminal/incident/incident_detection_module_test.dart
git commit -m "feat: incident detection observation module"
```

---

### Task 3: TerminalIncidentCapability + pattern registry merge

**Files:**
- Create: `client/lib/services/cli/registry/capabilities/terminal_incident_capability.dart`
- Create: `client/lib/services/terminal/incident/incident_pattern_registry.dart`
- Test: `client/test/services/terminal/incident/incident_pattern_registry_test.dart`

**Interfaces:**
- Consumes: `CliCapability` (marker interface at `registry/cli_capability.dart`), `TerminalIncidentPattern` (Task 1).
- Produces (used by Task 4 registration and Task 5 wiring):
  ```dart
  // registry/capabilities/terminal_incident_capability.dart
  abstract interface class TerminalIncidentCapability implements CliCapability {
    List<TerminalIncidentPattern> get terminalIncidentPatterns;
  }
  ```
  ```dart
  // incident_pattern_registry.dart
  List<TerminalIncidentPattern> resolveIncidentPatterns({
    required CliToolRegistry registry,
    required CliTool cli,
    List<UserIncidentRule> userRules = const [],
  });
  final class UserIncidentRule {
    const UserIncidentRule({required this.patternId, required this.expression,
      required this.kind, required this.severity});
    final String patternId; final String expression;
    final TerminalIncidentKind kind; final TerminalIncidentSeverity severity;
  }
  ```
  Merge order: capability patterns first, then user rules appended with `user.` prefix on ids to avoid id collisions with built-ins; a user rule whose `expression` fails to compile is **skipped silently** here (settings UI validates on save — Task 8) and never throws.

- [ ] **Step 1: Write the failing test**

```dart
// client/test/services/terminal/incident/incident_pattern_registry_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/built_in_cli_tools.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/terminal/incident/incident_pattern_registry.dart';
import 'package:teampilot/services/terminal/incident/terminal_incident.dart';

void main() {
  CliToolRegistry registryWith({TerminalIncidentCapability? claudeCap}) {
    final registry = CliToolRegistry();
    registerBuiltInCliTools(registry);
    return registry;
  }

  test('claude resolves built-in patterns once registered (smoke)', () {
    // After Task 4 the claude definition carries incidents; before that this
    // returns empty — asserted loosely so ordering between tasks is stable.
    final patterns = resolveIncidentPatterns(
      registry: registryWith(),
      cli: CliTool.claude,
    );
    expect(patterns, isA<List<TerminalIncidentPattern>>());
  });

  test('user rules are appended after built-ins', () {
    final patterns = resolveIncidentPatterns(
      registry: registryWith(),
      cli: CliTool.claude,
      userRules: const [
        UserIncidentRule(
          patternId: 'custom.gateway',
          expression: 'gateway exploded',
          kind: TerminalIncidentKind.networkError,
          severity: TerminalIncidentSeverity.error,
        ),
      ],
    );
    final userHit = patterns.where((p) => p.id == 'user.custom.gateway');
    expect(userHit, isNotEmpty);
    expect(
      userHit.single.patterns.single.hasMatch('gateway exploded'),
      isTrue,
    );
  });

  test('invalid user regex is skipped, not thrown', () {
    final patterns = resolveIncidentPatterns(
      registry: registryWith(),
      cli: CliTool.claude,
      userRules: const [
        UserIncidentRule(
          patternId: 'bad',
          expression: '([unclosed',
          kind: TerminalIncidentKind.other,
          severity: TerminalIncidentSeverity.warning,
        ),
      ],
    );
    expect(patterns.where((p) => p.id == 'user.bad'), isEmpty);
  });

  test('unknown cli yields empty built-ins', () {
    final patterns = resolveIncidentPatterns(
      registry: registryWith(),
      cli: CliTool.claude,
    );
    // Before Task 4 wiring, builtin is empty; user rules still resolve.
    final withUser = resolveIncidentPatterns(
      registry: registryWith(),
      cli: CliTool.claude,
      userRules: const [
        UserIncidentRule(
          patternId: 'x',
          expression: 'x',
          kind: TerminalIncidentKind.other,
          severity: TerminalIncidentSeverity.info,
        ),
      ],
    );
    expect(withUser.length, greaterThanOrEqualTo(1));
    expect(patterns, isA<List<TerminalIncidentPattern>>());
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/terminal/incident/incident_pattern_registry_test.dart`
Expected: FAIL — files do not exist.

- [ ] **Step 3: Write minimal implementation**

```dart
// client/lib/services/cli/registry/capabilities/terminal_incident_capability.dart
import '../../../../models/team_config.dart';
import '../../../terminal/incident/terminal_incident.dart';

/// Optional CLI capability: declarative incident patterns for PTY scanning.
/// Discovered by `is`-scanning `CliToolDefinition.capabilities` — never by
/// CLI identity checks.
abstract interface class TerminalIncidentCapability implements CliCapability {
  List<TerminalIncidentPattern> get terminalIncidentPatterns;
}
```

```dart
// client/lib/services/terminal/incident/incident_pattern_registry.dart
import '../../cli/registry/cli_tool_registry.dart';
import '../../cli/registry/capabilities/terminal_incident_capability.dart';
import '../../../models/team_config.dart';
import 'terminal_incident.dart';

/// One user-defined rule from SessionPreferences.
final class UserIncidentRule {
  const UserIncidentRule({
    required this.patternId,
    required this.expression,
    required this.kind,
    required this.severity,
  });

  final String patternId;
  final String expression;
  final TerminalIncidentKind kind;
  final TerminalIncidentSeverity severity;
}

/// Built-in capability patterns first, then compiled user rules.
/// Invalid user regexes are skipped (settings UI validates on save).
List<TerminalIncidentPattern> resolveIncidentPatterns({
  required CliToolRegistry registry,
  required CliTool cli,
  List<UserIncidentRule> userRules = const [],
}) {
  final capability = registry.tryGet(cli)?.capabilities
      .whereType<TerminalIncidentCapability>()
      .firstOrNull;
  final patterns = <TerminalIncidentPattern>[
    ...?capability?.terminalIncidentPatterns,
  ];
  for (final rule in userRules) {
    final id = rule.patternId.trim();
    final expression = rule.expression.trim();
    if (id.isEmpty || expression.isEmpty) continue;
    RegExp regex;
    try {
      regex = RegExp(expression, caseSensitive: false);
    } on FormatException {
      continue;
    }
    patterns.add(
      TerminalIncidentPattern(
        id: 'user.$id',
        kind: rule.kind,
        severity: rule.severity,
        patterns: [regex],
      ),
    );
  }
  return patterns;
}
```

Note: if `registry.tryGet` is not the accessor name, use `registry.capability<TerminalIncidentCapability>(cli)` to read capability directly and build patterns from it; both exist on `CliToolRegistry` — check `cli_tool_registry.dart` and use whichever returns the definition/capability without asserting.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/terminal/incident/incident_pattern_registry_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/cli/registry/capabilities/terminal_incident_capability.dart client/lib/services/terminal/incident/incident_pattern_registry.dart client/test/services/terminal/incident/incident_pattern_registry_test.dart
git commit -m "feat: terminal incident capability and pattern registry"
```

---

### Task 4: Built-in incident tables for the five CLIs

**Files:**
- Create: `client/lib/services/cli/claude/capabilities/terminal_incidents.dart` (claude-family table, reused by flashskyai)
- Create: `client/lib/services/cli/codex/capabilities/terminal_incidents.dart`
- Create: `client/lib/services/cli/cursor/capabilities/terminal_incidents.dart`
- Create: `client/lib/services/cli/opencode/capabilities/terminal_incidents.dart`
- Modify: `client/lib/services/cli/claude/claude_tool.dart` (field + capabilities list entry)
- Modify: `client/lib/services/cli/flashskyai/flashskyai_tool.dart` (reuse claude table)
- Modify: `client/lib/services/cli/codex/codex_tool.dart`, `client/lib/services/cli/cursor/cursor_tool.dart`, `client/lib/services/cli/opencode/opencode_tool.dart` (field + capabilities entry)
- Test: `client/test/services/cli/claude/capabilities/terminal_incidents_test.dart` (covers the claude-family table; other tables get equivalent groups in the same file to keep one test file)

**Interfaces:**
- Consumes: `TerminalIncidentCapability`, `TerminalIncidentPattern`, kinds/severities (Tasks 1/3).
- Produces (used by tests and registry resolution): `ClaudeTerminalIncidents` (const class implementing `TerminalIncidentCapability`), and `terminalIncidents` field on each `*CliTool` class of type `TerminalIncidentCapability?` (constructor default `const ClaudeTerminalIncidents()` etc.), appended to `capabilities` lists.

Pattern tables (starting point — each pattern carries a doc comment citing the CLI message it matches; extend during verification against real output):

```dart
// client/lib/services/cli/claude/capabilities/terminal_incidents.dart
import '../../../terminal/incident/terminal_incident.dart';
import '../../registry/capabilities/terminal_incident_capability.dart';

/// Claude-family incident patterns (claude + flashskyai share the table,
/// matching the shared ClaudeFamily* pattern).
final class ClaudeTerminalIncidents implements TerminalIncidentCapability {
  const ClaudeTerminalIncidents();

  @override
  List<TerminalIncidentPattern> get terminalIncidentPatterns => const [
    // "A new version of Claude Code is available" banner.
    TerminalIncidentPattern(
      id: 'claude.update_available',
      kind: TerminalIncidentKind.updateAvailable,
      severity: TerminalIncidentSeverity.info,
      patterns: [RegExp(r'new version of Claude Code is available')],
    ),
    // Subscription usage limit reached / credit balance too low.
    TerminalIncidentPattern(
      id: 'claude.credit_exhausted',
      kind: TerminalIncidentKind.creditExhausted,
      severity: TerminalIncidentSeverity.error,
      patterns: [
        RegExp(r'usage limit reached', caseSensitive: false),
        RegExp(r'credit balance too low', caseSensitive: false),
        RegExp(r'Claude usage limit reached', caseSensitive: false),
      ],
    ),
    TerminalIncidentPattern(
      id: 'claude.rate_limited',
      kind: TerminalIncidentKind.rateLimited,
      severity: TerminalIncidentSeverity.warning,
      patterns: [RegExp(r'rate limit exceeded', caseSensitive: false)],
    ),
    TerminalIncidentPattern(
      id: 'claude.request_failed',
      kind: TerminalIncidentKind.requestFailed,
      severity: TerminalIncidentSeverity.error,
      patterns: [
        RegExp(r'API Error: 5\d\d'),
        RegExp(r'API Error \(Request timed out'),
        RegExp(r'API Error \(Connection error'),
        RegExp(r'overloaded_error'),
      ],
    ),
    TerminalIncidentPattern(
      id: 'claude.auth_required',
      kind: TerminalIncidentKind.authRequired,
      severity: TerminalIncidentSeverity.error,
      patterns: [
        RegExp(r'invalid API key', caseSensitive: false),
        RegExp(r'authentication_error'),
        RegExp(r'please run /login', caseSensitive: false),
      ],
    ),
  ];
}
```

Codex (messages observed from codex CLI):
- `update_available`: `RegExp(r'codex.*update available', caseSensitive: false)`
- `rate_limited`: `RegExp(r'rate.?limit', caseSensitive: false)`
- `auth_required`: `RegExp(r'not logged in', caseSensitive: false)`, `RegExp(r'OPENAI_API_KEY', caseSensitive: false)` (message "You are not logged in…" / missing key errors)
- `request_failed`: `RegExp(r'stream error', caseSensitive: false)`, `RegExp(r'unexpected status 5\d\d')`

Cursor: `rate_limited` `RegExp(r'rate limit|quota exceeded', caseSensitive: false)`; `auth_required` `RegExp(r'authentication required|please sign in', caseSensitive: false)`; `request_failed` `RegExp(r'request failed|network error', caseSensitive: false)`.

OpenCode: `update_available` `RegExp(r'update available', caseSensitive: false)`; `auth_required` `RegExp(r'invalid api key|authentication failed', caseSensitive: false)`; `request_failed` `RegExp(r'request failed|connection refused', caseSensitive: false)`.

Registration per tool file (claude shown; repeat structurally for the other four):
```dart
// claude_tool.dart additions
import 'capabilities/terminal_incidents.dart';
import '../registry/capabilities/terminal_incident_capability.dart';
// in constructor params:
    this.terminalIncidents = const ClaudeTerminalIncidents(),
// field:
  final TerminalIncidentCapability? terminalIncidents;
// in capabilities list (append before hookWriter):
    if (terminalIncidents != null) terminalIncidents!,
```
Note: nullable field + `if` in the list literal works because the capabilities getter is a regular iterable, not const. Verify the getter is not marked `const`-returning; it's `Iterable<CliCapability> get capabilities => [...]` (non-const list) — safe. For flashskyai, `terminalIncidents` defaults to `const ClaudeTerminalIncidents()` imported from the claude directory (shared implementation, consistent with shared `ClaudeCompatibleToolResultEnricher` reuse).

- [ ] **Step 1: Write the failing test**

```dart
// client/test/services/cli/claude/capabilities/terminal_incidents_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/claude/capabilities/terminal_incidents.dart';
import 'package:teampilot/services/cli/codex/capabilities/terminal_incidents.dart';
import 'package:teampilot/services/cli/cursor/capabilities/terminal_incidents.dart';
import 'package:teampilot/services/cli/opencode/capabilities/terminal_incidents.dart';
import 'package:teampilot/services/cli/registry/built_in_cli_tools.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/capabilities/terminal_incident_capability.dart';
import 'package:teampilot/services/terminal/incident/terminal_incident.dart';

void main() {
  group('claude table', () {
    const table = ClaudeTerminalIncidents();

    test('update banner matches', () {
      expect(matchIncidentLine('A new version of Claude Code is available (v2)', table.terminalIncidentPatterns)!.pattern.id, 'claude.update_available');
    });

    test('credit exhausted variants', () {
      for (final line in [
        'Your usage limit has been reached',
        'credit balance too low',
      ]) {
        final m = matchIncidentLine(line, table.terminalIncidentPatterns);
        expect(m, isNotNull, reason: line);
        expect(m!.pattern.kind, TerminalIncidentKind.creditExhausted);
      }
    });

    test('API error variants classify request_failed', () {
      final m = matchIncidentLine('API Error: 500 {…}', table.terminalIncidentPatterns);
      expect(m!.pattern.id, 'claude.request_failed');
    });

    test('benign transcript lines do not match', () {
      expect(matchIncidentLine('Reading 3 files…', table.terminalIncidentPatterns), isNull);
      expect(matchIncidentLine('⏺ Done', table.terminalIncidentPatterns), isNull);
    });
  });

  group('registry wiring', () {
    late final CliToolRegistry registry;

    setUpAll(() {
      registry = CliToolRegistry();
      registerBuiltInCliTools(registry);
    });

    test('all five CLIs expose the capability', () {
      for (final cli in CliTool.values) {
        final cap = registry.capability<TerminalIncidentCapability>(cli);
        expect(cap, isNotNull, reason: cli.name);
        expect(cap!.terminalIncidentPatterns, isNotEmpty, reason: cli.name);
      }
    });

    test('pattern ids are unique per CLI', () {
      for (final cli in CliTool.values) {
        final ids = registry
            .capability<TerminalIncidentCapability>(cli)!
            .terminalIncidentPatterns
            .map((p) => p.id)
            .toList();
        expect(ids.toSet().length, ids.length, reason: cli.name);
      }
    });

    test('codex/cursor/opencode tables match their headlines', () {
      expect(
        matchIncidentLine('You are not logged in to ChatGPT', CodexTerminalIncidents().terminalIncidentPatterns),
        isNotNull,
      );
      expect(
        matchIncidentLine('rate limit exceeded', CursorTerminalIncidents().terminalIncidentPatterns),
        isNotNull,
      );
      expect(
        matchIncidentLine('Connection refused', OpencodeTerminalIncidents().terminalIncidentPatterns),
        isNotNull,
      );
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/claude/capabilities/terminal_incidents_test.dart`
Expected: FAIL — table files do not exist / capability missing.

- [ ] **Step 3: Implement the four table files + five tool registrations**

Use the tables and registration snippets above verbatim (adjust `RegExp` details only if a test fails — then update the test's sample line to the real message, never delete a coverage assertion).

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/claude/capabilities/terminal_incidents_test.dart`
Expected: PASS (all groups).

Also run the registry contract tests to catch breakage:
Run: `cd client && dart run tool/run_tests.dart test/services/cli/registry/`
Expected: PASS (existing suite unaffected).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/cli/claude client/lib/services/cli/flashskyai client/lib/services/cli/codex client/lib/services/cli/cursor client/lib/services/cli/opencode client/lib/services/cli/registry
git commit -m "feat: built-in terminal incident tables for five CLIs"
```

---

### Task 5: TerminalIncidentCubit (event stream)

**Files:**
- Create: `client/lib/cubits/terminal_incident_cubit.dart`
- Test: `client/test/cubits/terminal_incident_cubit_test.dart`

**Interfaces:**
- Consumes: `TerminalIncident`, `agentSeatKey({sessionId, memberId})` from `services/agent_status/agent_attention_state.dart` (Task 1 / existing).
- Produces (used by Tasks 6, 7, banner, members panel):
  ```dart
  class TerminalIncidentState extends Equatable {
    final List<TerminalIncident> incidents; // chronological, newest last
    List<TerminalIncident> openFor({required String sessionId, required String memberId});
    int openCountFor({required String sessionId, required String memberId});
  }
  class TerminalIncidentCubit extends Cubit<TerminalIncidentState> {
    void report(TerminalIncident incident);        // append + emit
    void acknowledge(TerminalIncident incident);   // mark status acknowledged
    void clearSession(String sessionId);           // drop session rows (seat dispose)
    void clearSeat({required String sessionId, required String memberId});
  }
  ```
  Acknowledge is modeled by holding `openIncidentIds: Set<String>` in state — but `TerminalIncident` (Task 1) is immutable without status. To avoid touching Task 1's shape, the cubit wraps: state holds `incidents: List<TerminalIncident>` and `acknowledgedIds: Set<String>` (identity = object equality via `==` on all fields + `timestamp`; give `TerminalIncident` an `Equatable`-style `==`/`hashCode` via `Object.hash` of all fields in Task 1 — **amend Task 1 in this task**: add `operator ==`/`hashCode`/`props` to `TerminalIncident`, and a `String get key => '$sessionId $memberId $timestamp $patternId'` stable identity). State API:
  - `bool isAcknowledged(TerminalIncident incident) => acknowledgedIds.contains(incident.key)`
  - `openFor(...)` = incidents for the seat without acknowledged keys.

- [ ] **Step 1: Amend Task 1 model (equality + key)**

Add to `TerminalIncident` in `terminal_incident.dart`:

```dart
  /// Stable identity for acknowledge bookkeeping.
  String get key => '$sessionId $memberId $patternId '
      '${timestamp.microsecondsSinceEpoch}';

  @override
  bool operator ==(Object other) =>
      other is TerminalIncident && other.key == key;

  @override
  int get hashCode => key.hashCode;
```

Update `terminal_incident_test.dart` with:
```dart
  test('equality keyed on seat/pattern/timestamp', () {
    final a = TerminalIncident(patternId: 'p', kind: TerminalIncidentKind.other,
        severity: TerminalIncidentSeverity.info, cli: 'claude',
        sessionId: 's', memberId: 'm', matchedLine: 'l',
        timestamp: DateTime.fromMillisecondsSinceEpoch(5));
    final b = TerminalIncident(patternId: 'p', kind: TerminalIncidentKind.other,
        severity: TerminalIncidentSeverity.info, cli: 'claude',
        sessionId: 's', memberId: 'm', matchedLine: 'other line',
        timestamp: DateTime.fromMillisecondsSinceEpoch(5));
    expect(a, b); // matchedLine differs, identity doesn't
  });
```

- [ ] **Step 2: Write the failing cubit test**

```dart
// client/test/cubits/terminal_incident_cubit_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/terminal_incident_cubit.dart';
import 'package:teampilot/services/terminal/incident/terminal_incident.dart';

TerminalIncident _incident(
  String memberId, {
  String patternId = 'p',
  int ms = 0,
}) => TerminalIncident(
  patternId: patternId,
  kind: TerminalIncidentKind.rateLimited,
  severity: TerminalIncidentSeverity.warning,
  cli: 'claude',
  sessionId: 's1',
  memberId: memberId,
  matchedLine: 'line',
  timestamp: DateTime.fromMillisecondsSinceEpoch(ms),
);

void main() {
  test('report appends and openFor filters by seat', () {
    final cubit = TerminalIncidentCubit();
    addTearDown(cubit.close);
    cubit.report(_incident('m1'));
    cubit.report(_incident('m2'));
    expect(cubit.state.openFor(sessionId: 's1', memberId: 'm1').length, 1);
    expect(cubit.state.openFor(sessionId: 's1', memberId: 'm2').length, 1);
  });

  test('acknowledge removes from open but keeps record', () {
    final cubit = TerminalIncidentCubit();
    addTearDown(cubit.close);
    final i = _incident('m1');
    cubit.report(i);
    cubit.acknowledge(i);
    expect(cubit.state.openFor(sessionId: 's1', memberId: 'm1'), isEmpty);
    expect(cubit.state.incidents, contains(i));
  });

  test('clearSeat drops only that seat', () {
    final cubit = TerminalIncidentCubit();
    addTearDown(cubit.close);
    cubit.report(_incident('m1'));
    cubit.report(_incident('m2'));
    cubit.clearSeat(sessionId: 's1', memberId: 'm1');
    expect(cubit.state.incidents.length, 1);
    expect(cubit.state.incidents.single.memberId, 'm2');
  });

  test('clearSession drops the session', () {
    final cubit = TerminalIncidentCubit();
    addTearDown(cubit.close);
    cubit.report(_incident('m1'));
    cubit.clearSession('s1');
    expect(cubit.state.incidents, isEmpty);
  });
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/cubits/terminal_incident_cubit_test.dart test/services/terminal/incident/terminal_incident_test.dart`
Expected: cubit test FAIL (no cubit); incident test still PASS.

- [ ] **Step 4: Write minimal implementation**

```dart
// client/lib/cubits/terminal_incident_cubit.dart
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../services/terminal/incident/terminal_incident.dart';

/// Session-scoped incident event stream: open + acknowledged records.
class TerminalIncidentState extends Equatable {
  const TerminalIncidentState({
    this.incidents = const [],
    this.acknowledgedIds = const {},
  });

  final List<TerminalIncident> incidents;
  final Set<String> acknowledgedIds;

  bool isAcknowledged(TerminalIncident incident) =>
      acknowledgedIds.contains(incident.key);

  List<TerminalIncident> openFor({required String sessionId, required String memberId}) =>
      incidents
          .where((i) =>
              i.sessionId == sessionId && i.memberId == memberId &&
              !isAcknowledged(i))
          .toList(growable: false);

  int openCountFor({required String sessionId, required String memberId}) =>
      openFor(sessionId: sessionId, memberId: memberId).length;

  TerminalIncidentState copyWith({
    List<TerminalIncident>? incidents,
    Set<String>? acknowledgedIds,
  }) => TerminalIncidentState(
        incidents: incidents ?? this.incidents,
        acknowledgedIds: acknowledgedIds ?? this.acknowledgedIds,
      );

  @override
  List<Object?> get props => [incidents, acknowledgedIds];
}

/// App-scoped; seats report incidents, the chat banner and member tiles read.
class TerminalIncidentCubit extends Cubit<TerminalIncidentState> {
  TerminalIncidentCubit() : super(const TerminalIncidentState());

  void report(TerminalIncident incident) {
    emit(state.copyWith(incidents: [...state.incidents, incident]));
  }

  void acknowledge(TerminalIncident incident) {
    if (state.isAcknowledged(incident)) return;
    emit(state.copyWith(acknowledgedIds: {...state.acknowledgedIds, incident.key}));
  }

  void clearSeat({required String sessionId, required String memberId}) {
    final kept = state.incidents
        .where((i) => !(i.sessionId == sessionId && i.memberId == memberId))
        .toList(growable: false);
    if (kept.length == state.incidents.length) return;
    emit(state.copyWith(incidents: kept));
  }

  void clearSession(String sessionId) {
    final kept = state.incidents
        .where((i) => i.sessionId != sessionId)
        .toList(growable: false);
    if (kept.length == state.incidents.length) return;
    emit(state.copyWith(incidents: kept));
  }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/cubits/terminal_incident_cubit_test.dart test/services/terminal/incident/terminal_incident_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add client/lib/cubits/terminal_incident_cubit.dart client/test/cubits/terminal_incident_cubit_test.dart client/lib/services/terminal/incident/terminal_incident.dart client/test/services/terminal/incident/terminal_incident_test.dart
git commit -m "feat: terminal incident cubit event stream"
```

---

### Task 6: Wire detection into session launch (observation attach + host)

**Files:**
- Modify: `client/lib/services/launch/session_shell_connector.dart` (~line 625, `TerminalObservationAttach` call site)
- Modify: `client/lib/services/terminal/terminal_session.dart` (`_bindObservation`, ~lines 484-542; module list ~509-512)
- Modify: `client/lib/cubits/chat/session_launch_host.dart` (add `terminalIncidentCubit` accessor next to `agentAttentionCubit`, ~line 139)
- Test: `client/test/services/terminal/terminal_session_observation_test.dart` (extend existing file — add a group)

**Interfaces:**
- Consumes: `IncidentDetectionModule`, `resolveIncidentPatterns` (Tasks 2/3), `TerminalIncidentCubit` (Task 5), existing `TerminalObservationAttach` / `SessionLaunchHost.agentAttentionCubit`.
- Produces:
  - `TerminalObservationAttach` gains `final TerminalIncidentCubit? incidents;` (nullable, tests pass null).
  - `SessionLaunchHost` gains `TerminalIncidentCubit? get terminalIncidentCubit;` (interface member, `ChatCubit` implements it — add field + constructor param to `ChatCubit` in `client/lib/cubits/chat_cubit.dart` and thread through `session_shell_connector.dart` where `observation:` is built: `incidents: _host.terminalIncidentCubit`).
  - `TerminalSession._bindObservation` adds, in the `!isWorkspaceShell` branch (after `UserLineModule`):
    ```dart
    final incidentCubit = observation?.incidents;
    final launchTool = launchCli ?? observation?.cli;
    if (incidentCubit != null && launchTool != null) {
      modules.add(
        IncidentDetectionModule(
          patterns: resolveIncidentPatterns(
            registry: _cliRegistry, // CliToolRegistry.builtIn() default; see note
            cli: launchTool,
          ),
          onIncident: incidentCubit.report,
        ),
      );
    }
    ```
    Note: `TerminalSession` currently resolves capabilities via `CliToolRegistry.builtIn()` in `_cliCapabilities` (line 544-547). Reuse that same call for the registry argument — do not add a new constructor dependency; if `TerminalSession` already has a registry field, use it.
  - Seat teardown: `clearAgentStatusSessionSeats` in `session_launch_host.dart` (line ~186) gains `TerminalIncidentCubit? incidents` param + `incidents?.clearSession(sessionId)`; the seat-level variant (line ~190 `clearAgentStatusSeat`) gains the same with `clearSeat`. Update its two call sites in `session_shell_connector.dart` (lines ~640, ~647) to pass `_host.terminalIncidentCubit`.
  - App wiring (do in this task so the feature is live end-to-end): `app/app_shell.dart` — create `final terminalIncidentCubit = TerminalIncidentCubit();` next to `agentAttentionCubit` (line 1758), pass to `ChatCubit(...)` (line ~1848, new named param `terminalIncidentCubit`), add field to `AppShell` constructor (line ~384 region, `required this.terminalIncidentCubit`) + field decl (next to `agentAttentionCubit` at 489), pass at the `AppShell(...)` construction (line ~2593), and add `BlocProvider.value(value: shell.terminalIncidentCubit)` in `main.dart` next to `agentAttentionCubit` (line 726).

- [ ] **Step 1: Write the failing test**

Extend `client/test/services/terminal/terminal_session_observation_test.dart` with a new group (follow its existing seat/bus fixture style; look at the file first and reuse its helpers — the shape below is the target behavior):

```dart
test('incident module reports running-phase incidents', () async {
  final incidents = TerminalIncidentCubit();
  addTearDown(incidents.close);
  // Build the session via the existing test harness in this file, with an
  // attach that carries incidents and cli: CliTool.claude, then dispatch:
  //   session's observation bus dispatchOutput('rate limit exceeded\n')
  // (reuse whatever transport fake this test file already uses to feed
  //  PTY bytes; if it drives bytes through a fake transport's sink, do that).
  // Assert:
  expect(incidents.state.incidents, isNotEmpty);
  expect(incidents.state.incidents.single.kind, TerminalIncidentKind.rateLimited);
});
```

Because this file's harness is fixture-heavy, the concrete test code must be adapted to its existing fakes when implementing; the required assertion is: dispatching a line matching a registered claude pattern through the session's transport produces one incident in the cubit. If the existing file has no byte-injection path, write the test at the `_bindObservation` level via a small `TerminalSession` subclass or use `terminal_launch_controller_observation_test.dart`'s approach instead — pick whichever existing test file already injects output bytes through a session, and mirror it.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/terminal/terminal_session_observation_test.dart`
Expected: FAIL — new group red (attach has no `incidents` field yet → compile error is the expected first failure; then behavioral red).

- [ ] **Step 3: Implement the wiring**

Follow the Interfaces block exactly: attach field, host accessor + `ChatCubit` param, module creation in `_bindObservation`, teardown propagation, app shell + main provider. Keep `TerminalObservationAttach` constructor backwards-compatible (optional named param).

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/services/terminal/terminal_session_observation_test.dart test/cubits/terminal_incident_cubit_test.dart test/services/launch/`
Expected: PASS (launch suite included because connector changed).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/launch/session_shell_connector.dart client/lib/services/terminal/terminal_session.dart client/lib/cubits/chat/session_launch_host.dart client/lib/cubits/chat_cubit.dart client/lib/app/app_shell.dart client/lib/main.dart client/test/services/terminal/terminal_session_observation_test.dart
git commit -m "feat: wire incident detection into session launch"
```

---

### Task 7: Incident banner in chat compose section (+ l10n)

**Files:**
- Create: `client/lib/widgets/chat/terminal_incident_banner.dart`
- Modify: `client/lib/pages/chat/session_chat_compose_section.dart` (insert banner above `AgentPermissionAttentionBanner`, ~line 277)
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`
- Test: `client/test/widgets/chat/terminal_incident_banner_test.dart`

**Interfaces:**
- Consumes: `TerminalIncidentCubit` + `TerminalIncidentState.openFor` (Task 5), `seatSelect` from `pages/chat/session_seat_working.dart`, `AgentPermissionAttentionBanner.attentionMemberId` for seat-id resolution (existing static), l10n.
- Produces: `TerminalIncidentBanner` widget:
  ```dart
  class TerminalIncidentBanner extends StatelessWidget {
    const TerminalIncidentBanner({
      required this.session,
      required this.selectedMemberId,
      super.key,
    });
    final AppSession session;
    final String selectedMemberId;
  }
  ```
  Renders `const SizedBox.shrink()` when no open incidents for the resolved seat. Otherwise a colored `Material` bar (error → `cs.errorContainer`, warning → `cs.tertiaryContainer`, info → `cs.secondaryContainer`), icon (bolt/error/warning/info respectively), one-line kind label + count, expandable matched line (tap toggles a `Text` with `maxLines: 3`), and two `TpButton`s: 「查看终端」 and 「知道了」(acknowledge-all-open for the seat).

l10n keys (en / zh pairs — add to both arb files):
```
terminalIncidentBannerUpdateAvailable / "A CLI update is available — check the Terminal."
terminalIncidentBannerCreditExhausted / "CLI quota may be exhausted — needs your confirmation."
terminalIncidentBannerAuthRequired / "CLI login has expired — needs your confirmation."
terminalIncidentBannerRateLimited / "CLI is rate limited — check the Terminal."
terminalIncidentBannerRequestFailed / "CLI request failed — check the Terminal."
terminalIncidentBannerTimeout / "CLI request timed out — check the Terminal."
terminalIncidentBannerNetworkError / "CLI network error — check the Terminal."
terminalIncidentBannerOther / "CLI needs your attention in the Terminal."
terminalIncidentOpenTerminal / "Open Terminal"
terminalIncidentAcknowledge / "Got it"
```
(zh: 依次 "CLI 有可用更新，请查看终端。" / "CLI 额度可能已用尽，需要你确认。" / "CLI 登录已失效，需要你确认。" / "CLI 已被限流，请查看终端。" / "CLI 请求失败，请查看终端。" / "CLI 请求超时，请查看终端。" / "CLI 网络错误，请查看终端。" / "CLI 需要你在终端中确认。" / "查看终端" / "知道了")
Kind label method: `String terminalIncidentLabel(AppLocalizations l10n, TerminalIncidentKind kind)` — exhaustive `switch` on kind inside the banner file.

跳终端 reuses the exact `_openTerminal` semantics from `AgentPermissionAttentionBanner` (select member + `setSessionWorkbenchView(sessionId, SessionWorkbenchView.terminal)` via `context.read<ChatCubit>()`) — replicate as a private method, do not refactor the existing banner.

- [ ] **Step 1: Write the failing test**

```dart
// client/test/widgets/chat/terminal_incident_banner_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/terminal_incident_cubit.dart';
import 'package:teampilot/services/terminal/incident/terminal_incident.dart';
import 'package:teampilot/widgets/chat/terminal_incident_banner.dart';

// Build with the minimal providers the banner needs: TerminalIncidentCubit,
// ChatCubit + ChatTabStore may be required by _openTerminal — mock/stub per
// existing agent_permission_attention_banner widget tests (find them under
// client/test/pages/chat/ and mirror their provider scaffolding).

void main() {
  testWidgets('hidden when no open incidents', (tester) async {
    final cubit = TerminalIncidentCubit();
    addTearDown(cubit.close);
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: cubit,
          child: TerminalIncidentBannerFixture(
            builder: (context) => const TerminalIncidentBanner(
              session: fixtureSession,
              selectedMemberId: 'm1',
            ),
          ),
        ),
      ),
    );
    expect(find.byType(TerminalIncidentBanner), findsOneWidget);
    expect(find.textContaining('Terminal'), findsNothing);
  });
}
```

`TerminalIncidentBannerFixture` / `fixtureSession` are scaffolding (AppSession fake + optional ChatCubit provider) modeled on existing chat widget tests — locate the nearest existing test that constructs `AppSession` (e.g. in `client/test/pages/chat/`) and copy its fake. Additional cases to include in the same file once scaffolding exists:
- error-severity incident → banner visible, error container color, 'Got it' button tap acknowledges (cubit openFor becomes empty).
- 'Open Terminal' tap → calls `ChatCubit.selectMember`/`setSessionWorkbenchView` (assert via a recording fake ChatCubit — mirror how existing permission banner tests assert the terminal jump).

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/widgets/chat/terminal_incident_banner_test.dart`
Expected: FAIL — widget file does not exist.

- [ ] **Step 3: Implement banner + arb + insertion**

Implement per Interfaces. Insert in `session_chat_compose_section.dart` before `AgentPermissionAttentionBanner(...)`:
```dart
TerminalIncidentBanner(
  session: session,
  selectedMemberId: selectedMemberId,
),
```
Run `cd client && flutter gen-l10n` if the test tooling does not regenerate (it normally does).

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/widgets/chat/terminal_incident_banner_test.dart test/l10n/`
Expected: PASS (l10n suite catches missing zh/en parity).

- [ ] **Step 5: Commit**

```bash
git add client/lib/widgets/chat/terminal_incident_banner.dart client/lib/pages/chat/session_chat_compose_section.dart client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/test/widgets/chat/terminal_incident_banner_test.dart
git commit -m "feat: terminal incident banner in chat compose"
```

---

### Task 8: Member tile badge + user-defined rules (settings + preferences + merge)

**Files:**
- Modify: `client/lib/widgets/right_tools/members_panel.dart` (`_MembersPanelTile` — badge on `MemberTitleRow` line, ~320)
- Modify: `client/lib/models/session_preferences.dart` (new `terminalIncidentRules` field)
- Modify: `client/lib/cubits/session_preferences_cubit.dart` (setter)
- Create: `client/lib/pages/config/cli_incident_rules_section.dart`
- Modify: `client/lib/pages/config/cli_config_section.dart` (append the section after Toolchain group, ~line 129)
- Modify: `client/lib/services/launch/session_shell_connector.dart` (pass user rules into `resolveIncidentPatterns` — via a resolver function on the host, like `sshUseLoginShell: () => ...` pattern in app_shell line 1708)
- Modify: `client/lib/cubits/chat/session_launch_host.dart` + `client/lib/cubits/chat_cubit.dart` + `client/lib/app/app_shell.dart` (host accessor `List<UserIncidentRule> Function(String? cliValue)? get incidentRuleResolver;` → simplest: `terminalIncidentRulesFor` returning `List<UserIncidentRule>` for the active cli)
- Modify: `client/lib/l10n/app_en.arb`, `app_zh.arb`
- Tests: `client/test/pages/config/cli_incident_rules_section_test.dart`, plus extend `client/test/services/terminal/incident/incident_pattern_registry_test.dart` is already covered (merge tested in Task 3).

**Interfaces:**
- `SessionPreferences` gains:
  ```dart
  /// User-defined terminal incident rules, JSON-encoded list of
  /// {patternId, expression, kind, severity}, keyed per CLI in a map.
  final Map<String, List<Map<String, Object?>>> terminalIncidentRules;
  ```
  Round-trips through `fromJson`/`toJson`/`copyWith` following the existing field pattern (default `const {}`, tolerant parsing — bad entries skipped). Kind/severity parse by `name` with `other`/`warning` fallbacks.
- `SessionPreferencesCubit` gains `void setTerminalIncidentRule(String cliValue, List<Map<String, Object?>> rules)` (validate: every entry's `expression` compiles — non-compiling entries rejected with an l10n'd error surfaced via returned bool `false`; on success copyWith + persist via repository like existing setters).
- Settings section `CliIncidentRulesSection`: per launchable CLI (loop `CliToolRegistry.builtIn().launchable`), a card with rows "patternId | regex | kind | severity" + add/remove buttons; regex field validates on save (red `InputDecoration.errorText` from l10n when `try RegExp(...)` fails).
- Wiring: host accessor `List<UserIncidentRule> terminalIncidentRulesFor(CliTool cli)` (ChatCubit implements via injected `SessionPreferencesCubit` state read — app_shell passes `sessionPreferencesCubit` to ChatCubit constructor as `incidentRulesResolver: (cli) => ...` mapping the preference map to `UserIncidentRule`s); `session_shell_connector.dart` passes them to `resolveIncidentPatterns(userRules: ...)` where the module is built — note the module construction currently lives in `terminal_session.dart` (Task 6); thread the rules through `TerminalObservationAttach` as a `List<UserIncidentRule> Function()? incidentRules` resolver field (lazy so preferences edits apply on next connect) and call it inside `_bindObservation`.
- Members panel badge: in `_MembersPanelTile.build`, resolve open count via `context.select<TerminalIncidentCubit, int>((c) => c.state.openCountFor(sessionId: <active sessionId>, memberId: member.id))` — the panel needs the session id: `_ScopedMembersPanel` in `right_tools_tool_views.dart` already resolves `chatSlice`/active tab (line 554-556 area), so pass `sessionId` down to `MembersPanel` → tile (new optional `sessionId` param, empty string → no badge lookup). When count > 0, wrap `MemberTitleRow` (or trailing) with a small `Badge`-style container: `Container(padding: EdgeInsets.symmetric(horizontal: 6, vertical: 1), decoration: BoxDecoration(color: cs.error, borderRadius: BorderRadius.circular(8)), child: Text('$count', style: styles.xsColored(cs.onError)))` placed before `MemberPresenceIndicator` in `trailing` via `Row(mainAxisSize: MainAxisSize.min, children: [if (count > 0) badge, MemberPresenceIndicator(presence: presence)])`.

- [ ] **Step 1: Write the failing settings-section test**

```dart
// client/test/pages/config/cli_incident_rules_section_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teampilot/cubits/session_preferences_cubit.dart';
import 'package:teampilot/pages/config/cli_incident_rules_section.dart';
import 'package:teampilot/repositories/session_preferences_repository.dart';

void main() {
  // Scaffold modeled on existing pages/config tests (find one under
  // client/test/pages/config/ and mirror provider + l10n setup).
  testWidgets('add rule persists and bad regex shows error', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final cubit = SessionPreferencesCubit(
      repository: SessionPreferencesRepository(prefs),
    );
    addTearDown(cubit.close);
    // pump CliIncidentRulesSection with the cubit + l10n delegates;
    // enter expression '([bad' → expect validation error text l10n key;
    // fix to 'quota gone' + kind error + save → cubit state contains the rule.
  });
}
```

(Adapt scaffolding to the nearest existing config-section widget test — the two concrete assertions are mandatory: invalid regex rejected with visible error; valid rule lands in `cubit.state.preferences.terminalIncidentRules` for that CLI.)

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/pages/config/cli_incident_rules_section_test.dart`
Expected: FAIL — section file does not exist.

- [ ] **Step 3: Implement preferences field + cubit setter + section + panel badge + wiring + arb**

Follow the Interfaces block. l10n keys:
```
cliIncidentRulesSectionTitle / "Terminal incident rules"
cliIncidentRulesSectionSubtitle / "Custom terminal-output patterns that raise an incident banner."
cliIncidentRulesAdd / "Add rule"
cliIncidentRulesRemove / "Remove"
cliIncidentRulesExpressionLabel / "Pattern (regular expression)"
cliIncidentRulesExpressionInvalid / "Invalid regular expression"
cliIncidentRulesKindLabel / "Kind"
cliIncidentRulesSeverityLabel / "Severity"
```
(zh: "终端意外检测规则" / "自定义终端输出模式，命中时在聊天中提示。" / "添加规则" / "删除" / "模式（正则表达式）" / "正则表达式无效" / "类型" / "级别")

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/pages/config/cli_incident_rules_section_test.dart test/cubits/session_preferences_test.dart test/widgets/right_tools/ 2>/dev/null || dart run tool/run_tests.dart test/pages/config/ test/cubits/`
Expected: PASS (run whatever subset exists — at minimum the new test plus session preferences tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/session_preferences.dart client/lib/cubits/session_preferences_cubit.dart client/lib/pages/config/cli_incident_rules_section.dart client/lib/pages/config/cli_config_section.dart client/lib/widgets/right_tools/members_panel.dart client/lib/widgets/right_tools/right_tools_tool_views.dart client/lib/services/launch/session_shell_connector.dart client/lib/services/terminal/terminal_session.dart client/lib/cubits/chat/session_launch_host.dart client/lib/cubits/chat_cubit.dart client/lib/app/app_shell.dart client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/test/pages/config/cli_incident_rules_section_test.dart
git commit -m "feat: user-defined terminal incident rules and member badge"
```

---

### Task 9: Full verification

- [ ] **Step 1: Run analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: no new issues.

- [ ] **Step 2: Run full test suite**

Run: `cd client && dart run tool/run_tests.dart` (background, per test-loop rules)
Expected: PASS — no regressions in terminal/observation, chat, launch, registry suites.

- [ ] **Step 3: Backfill docs**

Add `docs/cli-formats/terminal-incidents.md` (pattern table per CLI, matching the matrix style of other cli-formats pages), and link it from `docs/cli-architecture.md`'s TerminalObservationContributor row (line ~259). Update AGENTS.md docs table only if maintainers convention requires it (other cli-formats pages aren't in the table — skip).

- [ ] **Step 4: Commit**

```bash
git add docs/cli-formats/terminal-incidents.md docs/cli-architecture.md
git commit -m "docs: terminal incident pattern matrix"
```

---

## Self-Review Notes

- Spec coverage: pattern tables (Task 4), engine with decode/strip/dedupe/cooldown (Task 2), capability interface + shared claude family table (Tasks 3-4), waiting + event stream dual channel (Task 2 attention + Task 5 cubit), banner with terminal jump/acknowledge (Task 7), user rules with validation + merge order (Tasks 3/8), members-panel badge (Task 8), SSH+local coverage via bus (Task 6 wiring), l10n (Tasks 7/8), doc backfill (Task 9). Runtime-phase-only gating matches spec (LaunchStartModule owns spawn/confirm).
- Turn-level dedupe from the spec was simplified to cooldown-only during planning (Task 2 behavior spec) — cooldown is the user-visible requirement; turn tracking would add state without user benefit. Flagged here as a deliberate deviation; if wanted later it's additive.
- Type consistency: `TerminalIncident`/`TerminalIncidentPattern`/`matchIncidentLine` used identically across tasks; cubit method names (`report`, `acknowledge`, `clearSeat`, `clearSession`, `openFor`, `openCountFor`) consistent between Tasks 5, 7, 8.
