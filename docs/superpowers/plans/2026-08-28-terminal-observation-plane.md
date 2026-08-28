# Terminal Observation Plane Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace hardcoded PTY detect/scan/listen in `TerminalLaunchController` and `TerminalUserInputPipeline` with a seat-scoped observation bus that capabilities and session modules register onto.

**Architecture:** One `TerminalObservationBus` per member PTY. Output is read-only fan-out, input is ordered transforms plus pre-transform observers, screen is paint notify plus pull probe. Shared L1 scanners (`OscTitle`, `UserLineSubmitted`) run only while subscribed. `TerminalBehaviorCapability` keeps injection policy only. Cursor OSC attention and OSC 997 stripping become a `TerminalObservationContributor` on `CursorTerminalBehavior`.

**Tech Stack:** Dart / Flutter, `package:flutter_test`, existing `OscTitleExtractor`, `TerminalStartupFailureDetector`, `TerminalActivityTracker`, `BusUserLineCapture`, `EveryUserLineCapture`.

**Spec:** `docs/superpowers/specs/2026-08-28-terminal-observation-plane-design.md`

## Global Constraints

- Do not switch on `CliTool` in `TerminalLaunchController`, `TerminalSession`, or the observation bus. CLI differences enter only through `TerminalObservationContributor` on that CLI’s capability instances.
- Do not merge this plane into `HookCapability`, `RuntimeEvent`, or the agent-status HTTP path.
- No compatibility shims: delete `bindCursorTitleAttention`, `clearCursorTitleAttention`, `bindTitleAttention`, `forwardsColorSchemeReport`, and `TerminalUserInputPipeline`.
- Output observers receive `UnmodifiableUint8ListView`. Phase changes made during a dispatch apply on the **next** chunk, not the current one.
- Each L0 observer, L1 scanner, L2 handler, and input transform is try/catch isolated; failures log with `AppLogger` and must not skip `engine.feed`.
- A throwing transform is skipped; the next transform receives the last successful bytes.
- Handlers on the output hot path are synchronous. Async work captures `bus.generation` and no-ops if it changed.
- Tests run from `client/` with `flutter test <file>`. After wiring tasks, also `flutter analyze --no-fatal-infos --no-fatal-warnings`.
- Commit after every task. Do not push.

---

## File map

| Path | Responsibility |
|---|---|
| `client/lib/services/cli/registry/capabilities/terminal_observation_contributor.dart` | `TerminalObservationContributor` + `TerminalObservationBinding` |
| `client/lib/services/terminal/observation/terminal_observation_events.dart` | Derived events, observer/transform interfaces, subscriptions |
| `client/lib/services/terminal/observation/terminal_observation_seat.dart` | Seat context (ids, phase, attention, fail/confirm, policy) |
| `client/lib/services/terminal/observation/terminal_observation_bus.dart` | Register, dispatch, lazy L1, isolate errors, generation |
| `client/lib/services/terminal/observation/terminal_observation_installer.dart` | Bind session modules + CLI contributors |
| `client/lib/services/terminal/observation/scanners/osc_title_scanner.dart` | Output bytes → `OscTitle` |
| `client/lib/services/terminal/observation/scanners/user_line_scanner.dart` | Original input bytes → `UserLineSubmitted` |
| `client/lib/services/terminal/observation/modules/activity_observation_module.dart` | Running-phase output → `TerminalActivityTracker` |
| `client/lib/services/terminal/observation/modules/launch_start_module.dart` | Starting-phase classify then confirm |
| `client/lib/services/terminal/observation/modules/user_line_module.dart` | First / every / turn-start callbacks |
| `client/lib/services/terminal/observation/modules/team_bus_intercept_module.dart` | Input transform order 100 |
| `client/lib/services/cli/cursor/capabilities/terminal_behavior.dart` | Policy + Cursor contributor (OSC attention, strip OSC 997) |
| `client/lib/services/terminal/terminal_launch_controller.dart` | Spawn/phase/timers/`engine.feed`; calls bus only |
| `client/lib/services/terminal/terminal_session.dart` | Creates bus, installer.bind at connect |
| `client/lib/services/launch/session_shell_connector.dart` | Passes attention into `connect`; no Cursor bind |
| `client/lib/services/terminal/fullscreen_pty_delivery_port.dart` | Add `waitForPaint` |
| `client/lib/services/terminal/fullscreen_pty_automation.dart` | Wait on paint + poll-interval fallback |
| `docs/cli-architecture.md` | Observation plane + slim terminal behavior |

Delete: `client/lib/services/terminal/terminal_user_input_pipeline.dart`

---

### Task 1: Bus types and output fan-out

**Files:**
- Create: `client/lib/services/terminal/observation/terminal_observation_events.dart`
- Create: `client/lib/services/terminal/observation/terminal_observation_seat.dart`
- Create: `client/lib/services/terminal/observation/terminal_observation_bus.dart`
- Create: `client/lib/services/cli/registry/capabilities/terminal_observation_contributor.dart`
- Test: `client/test/services/terminal/observation/terminal_observation_bus_output_test.dart`

**Interfaces:**
- Consumes: `TerminalLaunchPhase` from `terminal_launch_controller.dart`
- Produces: `TerminalObservationBus.dispatchOutput`, `addOutputObserver`, `generation`, `dispose`, `TerminalObservationSeat.phase`, `TerminalObservationContributor.bind`

- [ ] **Step 1: Write the failing output tests.**

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/terminal/observation/terminal_observation_bus.dart';
import 'package:teampilot/services/terminal/observation/terminal_observation_events.dart';
import 'package:teampilot/services/terminal/observation/terminal_observation_seat.dart';
import 'package:teampilot/services/terminal/terminal_launch_controller.dart';

void main() {
  late TerminalObservationSeat seat;
  late TerminalObservationBus bus;

  setUp(() {
    seat = TerminalObservationSeat(
      sessionId: 's',
      memberId: 'm',
      phase: TerminalLaunchPhase.running,
    );
    bus = TerminalObservationBus(seat: seat);
  });

  tearDown(bus.dispose);

  test('two observers see the same chunk; mutation does not leak', () {
    final seen = <int>[];
    bus.addOutputObserver(
      _Capture(seen),
      phases: {TerminalLaunchPhase.running},
    );
    bus.addOutputObserver(
      _MutateThenCapture(seen),
      phases: {TerminalLaunchPhase.running},
    );
    bus.dispatchOutput(Uint8List.fromList([1, 2, 3]));
    expect(seen, [1, 1]);
  });

  test('throwing observer does not skip later observers', () {
    final later = <int>[];
    bus.addOutputObserver(_Throwing(), phases: {TerminalLaunchPhase.running});
    bus.addOutputObserver(
      _Capture(later),
      phases: {TerminalLaunchPhase.running},
    );
    bus.dispatchOutput(Uint8List.fromList([9]));
    expect(later, [9]);
  });

  test('observer phase filter skips non-matching chunks', () {
    final seen = <int>[];
    bus.addOutputObserver(
      _Capture(seen),
      phases: {TerminalLaunchPhase.confirming},
    );
    bus.dispatchOutput(Uint8List.fromList([1]));
    expect(seen, isEmpty);
    bus.setPhase(TerminalLaunchPhase.confirming);
    bus.dispatchOutput(Uint8List.fromList([2]));
    expect(seen, [2]);
  });

  test('phase change during dispatch applies on the next chunk', () {
    final running = <int>[];
    bus.setPhase(TerminalLaunchPhase.confirming);
    bus.addOutputObserver(
      _PhaseFlip(bus),
      phases: {TerminalLaunchPhase.confirming},
    );
    bus.addOutputObserver(
      _Capture(running),
      phases: {TerminalLaunchPhase.running},
    );
    bus.dispatchOutput(Uint8List.fromList([1]));
    expect(running, isEmpty);
    bus.dispatchOutput(Uint8List.fromList([2]));
    expect(running, [2]);
  });

  test('dispatch after dispose is a no-op', () {
    final seen = <int>[];
    bus.addOutputObserver(
      _Capture(seen),
      phases: {TerminalLaunchPhase.running},
    );
    bus.dispose();
    bus.dispatchOutput(Uint8List.fromList([1]));
    expect(seen, isEmpty);
  });

  test('empty chunks are ignored', () {
    var calls = 0;
    bus.addOutputObserver(
      _Callback((_) => calls++),
      phases: {TerminalLaunchPhase.running},
    );
    bus.dispatchOutput(Uint8List(0));
    expect(calls, 0);
  });
}
```

Implement the small `_Capture` / `_MutateThenCapture` / `_Throwing` / `_PhaseFlip` / `_Callback` helpers in the same test file. `_MutateThenCapture` casts or copies then writes `bytes[0] = 99` inside `onOutput`; the next observer must still see `1`. `_PhaseFlip.onOutput` calls `bus.setPhase(TerminalLaunchPhase.running)`.

- [ ] **Step 2: Run the test to verify it fails.**

Run: `cd client && flutter test test/services/terminal/observation/terminal_observation_bus_output_test.dart`

Expected: compilation failure naming `TerminalObservationBus` or `TerminalObservationSeat`.

- [ ] **Step 3: Implement types + bus output.**

`terminal_observation_contributor.dart`:

```dart
import '../../../terminal/observation/terminal_observation_bus.dart';
import '../../../terminal/observation/terminal_observation_seat.dart';

abstract interface class TerminalObservationContributor {
  TerminalObservationBinding bind(
    TerminalObservationBus bus,
    TerminalObservationSeat seat,
  );
}

abstract interface class TerminalObservationBinding {
  void unbind();
}

final class CallbackObservationBinding implements TerminalObservationBinding {
  CallbackObservationBinding(this._unbind);
  final void Function() _unbind;
  var _done = false;
  @override
  void unbind() {
    if (_done) return;
    _done = true;
    _unbind();
  }
}

final class CompositeObservationBinding implements TerminalObservationBinding {
  CompositeObservationBinding(this._parts);
  final List<TerminalObservationBinding> _parts;
  @override
  void unbind() {
    for (final part in _parts) {
      part.unbind();
    }
  }
}
```

`terminal_observation_events.dart` must define:

```dart
abstract interface class TerminalOutputObserver {
  void onOutput(Uint8List bytes, TerminalObservationSeat seat);
}

abstract interface class TerminalInputObserver {
  void onInput(Uint8List bytes, TerminalObservationSeat seat);
}

abstract interface class TerminalInputTransform {
  int get order;
  Uint8List transform(Uint8List bytes, TerminalObservationSeat seat);
}

abstract interface class TerminalScreenObserver {
  void onPainted(TerminalObservationSeat seat);
}

abstract interface class TerminalObservationSubscription {
  void cancel();
}

sealed class TerminalDerivedEvent {
  const TerminalDerivedEvent();
}

final class OscTitle extends TerminalDerivedEvent {
  const OscTitle(this.title);
  final String title;
}

final class UserLineSubmitted extends TerminalDerivedEvent {
  const UserLineSubmitted(this.line);
  final String line;
}
```

`TerminalObservationSeat` holds `sessionId`, `memberId`, `CliTool? cli`, `TerminalLaunchPhase phase`, `TerminalActivityTracker? activityTracker`, `AgentAttentionCubit? attention`, `bool Function()? skipPermissions`, `TerminalBehaviorCapability? policy`, `void Function(String message)? failLaunch`, `void Function()? confirmStarted`, `String startupExecutable`, `bool validateLaunch`. Defaults: `phase = idle`, callbacks/attention/cli/policy null, `startupExecutable = ''`, `validateLaunch = true`.

`TerminalObservationBus`:
- Constructor `TerminalObservationBus({required TerminalObservationSeat seat})`.
- `int generation` starts at 1; `dispose` increments generation and sets disposed.
- `setPhase` writes `seat.phase` immediately, but `dispatchOutput` snapshots `phase` into a local `dispatchPhase` at entry and uses that for observer filters.
- `addOutputObserver` returns a subscription; wrap bytes in `UnmodifiableUint8ListView` before each observer.
- Isolate observer exceptions with `AppLogger.e`.
- Ignore empty chunks.
- `notifyPainted` / input APIs may be empty stubs this task if tests do not call them; complete them in Task 2 rather than leaving `throw UnimplementedError`.

- [ ] **Step 4: Re-run tests.**

Run: `cd client && flutter test test/services/terminal/observation/terminal_observation_bus_output_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit.**

```bash
git add client/lib/services/terminal/observation client/lib/services/cli/registry/capabilities/terminal_observation_contributor.dart client/test/services/terminal/observation
git commit -m "$(cat <<'EOF'
feat(terminal): add observation bus output fan-out

EOF
)"
```

---

### Task 2: Input transforms, screen paint, process-exit notify

**Files:**
- Modify: `client/lib/services/terminal/observation/terminal_observation_bus.dart`
- Test: `client/test/services/terminal/observation/terminal_observation_bus_input_test.dart`

**Interfaces:**
- Consumes: Task 1 bus + `TerminalInputObserver` / `TerminalInputTransform` / `TerminalScreenObserver`
- Produces: `transformInput`, `addInputObserver`, `addInputTransform`, `notifyPainted`, `notifyProcessExited`, `onProcessExited` listener used by LaunchStart in Task 5

- [ ] **Step 1: Write the failing input/screen tests.**

```dart
test('input observers see original bytes before transforms', () {
  final seen = <int>[];
  bus.addInputObserver(_InputCapture(seen));
  bus.addInputTransform(_ZeroFirst(order: 100));
  final out = bus.transformInput(Uint8List.fromList([1, 2]));
  expect(seen, [1]);
  expect(out, [0, 2]);
});

test('transforms run by ascending order; equal order keeps bind sequence', () {
  bus.addInputTransform(_Append(order: 200, suffix: 2));
  bus.addInputTransform(_Append(order: 100, suffix: 1));
  bus.addInputTransform(_Append(order: 100, suffix: 9));
  expect(bus.transformInput(Uint8List.fromList([0])), [0, 1, 9, 2]);
});

test('throwing transform is skipped; later transform still runs', () {
  bus.addInputTransform(_ThrowingTransform(order: 100));
  bus.addInputTransform(_Append(order: 200, suffix: 7));
  expect(bus.transformInput(Uint8List.fromList([1])), [1, 7]);
});

test('empty transform result is returned as empty', () {
  bus.addInputTransform(_DropAll(order: 100));
  expect(bus.transformInput(Uint8List.fromList([1, 2])), isEmpty);
});

test('notifyPainted fans out to screen observers', () {
  var paints = 0;
  bus.addScreenObserver(_Paint(() => paints++));
  bus.notifyPainted();
  expect(paints, 1);
});

test('notifyProcessExited fans out after dispose no-ops', () {
  final codes = <int>[];
  bus.addProcessExitObserver((code) => codes.add(code));
  bus.notifyProcessExited(3);
  expect(codes, [3]);
  bus.dispose();
  bus.notifyProcessExited(4);
  expect(codes, [3]);
});
```

- [ ] **Step 2: Verify RED.**

Run: `cd client && flutter test test/services/terminal/observation/terminal_observation_bus_input_test.dart`

Expected: compilation failure for `transformInput` / `addInputTransform` / `notifyPainted` / `addProcessExitObserver` if still stubs, or FAIL on order assertions.

- [ ] **Step 3: Implement input + screen + exit on the bus.**

- Input observers run on an `UnmodifiableUint8ListView` of the original chunk, then transforms sort by `(order, bindSequence)`.
- UTF-8 decode once if any input observer or `UserLineSubmitted` subscriber exists; pass the same `String? decoded` into scanners in Task 3. For this task, observers still receive bytes; decoding can wait until Task 3 as long as observers do not each decode in the bus.
- `addProcessExitObserver(void Function(int code) observer)` — keep this on the bus (not a derived event). LaunchStart uses it.
- `Stream<void> get painted` broadcast stream; `notifyPainted` notifies screen observers then adds an event if there are listeners.

- [ ] **Step 4: Re-run Task 1 and Task 2 tests.**

Run: `cd client && flutter test test/services/terminal/observation/`

Expected: PASS.

- [ ] **Step 5: Commit.**

```bash
git add client/lib/services/terminal/observation client/test/services/terminal/observation
git commit -m "$(cat <<'EOF'
feat(terminal): add observation bus input and screen channels

EOF
)"
```

---

### Task 3: Lazy L1 scanners (OSC title, user line)

**Files:**
- Create: `client/lib/services/terminal/observation/scanners/osc_title_scanner.dart`
- Create: `client/lib/services/terminal/observation/scanners/user_line_scanner.dart`
- Modify: `client/lib/services/terminal/observation/terminal_observation_bus.dart`
- Test: `client/test/services/terminal/observation/terminal_observation_scanners_test.dart`

**Interfaces:**
- Consumes: `OscTitleExtractor`, `EveryUserLineCapture`
- Produces: `bus.subscribe<OscTitle>`, `bus.subscribe<UserLineSubmitted>` (install scanner on first subscriber, tear down on last cancel)

- [ ] **Step 1: Write the failing scanner tests.**

```dart
test('OscTitle scanner is not fed without a subscriber', () {
  final extractorFed = <String>[];
  // Use a spy later if needed; behavioral test:
  var titles = <String>[];
  bus.dispatchOutput(_osc('Cursor Agent'));
  expect(titles, isEmpty);
  final sub = bus.subscribe<OscTitle>((e) => titles.add(e.title));
  bus.dispatchOutput(_osc('Cursor - action required'));
  expect(titles, ['Cursor - action required']);
  sub.cancel();
  bus.dispatchOutput(_osc('ignored after unbind'));
  expect(titles, ['Cursor - action required']);
});

test('two OscTitle subscribers share one scan', () {
  final a = <String>[];
  final b = <String>[];
  bus.subscribe<OscTitle>((e) => a.add(e.title));
  bus.subscribe<OscTitle>((e) => b.add(e.title));
  bus.dispatchOutput(_osc('Hello'));
  expect(a, ['Hello']);
  expect(b, ['Hello']);
});

test('UserLineSubmitted fires on Enter from original input', () {
  final lines = <String>[];
  bus.subscribe<UserLineSubmitted>((e) => lines.add(e.line));
  bus.addInputTransform(_DropAll(order: 100));
  bus.transformInput(Uint8List.fromList(utf8.encode('hi\r')));
  expect(lines, ['hi']);
});
```

`_osc(title)` is `Uint8List.fromList(utf8.encode('\x1b]0;$title\x07'))`.

- [ ] **Step 2: Verify RED.**

Run: `cd client && flutter test test/services/terminal/observation/terminal_observation_scanners_test.dart`

Expected: compilation failure for `subscribe` or FAIL (no titles).

- [ ] **Step 3: Implement scanners + lazy subscribe.**

`OscTitleScanner` wraps `OscTitleExtractor`, `push`es UTF-8-decoded output (malformed allowed), emits `OscTitle` per title.

`UserLineScanner` wraps `EveryUserLineCapture` and emits `UserLineSubmitted` per line. It must run on **original** input bytes inside `transformInput`, before transforms.

Bus `subscribe<T>`:
- store handlers in `List<void Function(T)>` keyed by `T`
- first handler for `OscTitle` attaches `OscTitleScanner` to the output L1 list
- first handler for `UserLineSubmitted` attaches `UserLineScanner` to the input L1 list
- last `cancel` removes the scanner and resets extractor/capture state

Throwing L2 handlers must not prevent other subscribers or `engine.feed` (isolation already on dispatch).

- [ ] **Step 4: Re-run observation tests.**

Run: `cd client && flutter test test/services/terminal/observation/`

Expected: PASS.

- [ ] **Step 5: Commit.**

```bash
git add client/lib/services/terminal/observation client/test/services/terminal/observation
git commit -m "$(cat <<'EOF'
feat(terminal): add subscription-gated OSC and user-line scanners

EOF
)"
```

---

### Task 4: Installer bind order and workspace-shell filter

**Files:**
- Create: `client/lib/services/terminal/observation/terminal_observation_installer.dart`
- Test: `client/test/services/terminal/observation/terminal_observation_installer_test.dart`

**Interfaces:**
- Consumes: `CliToolRegistry`, `TerminalObservationContributor`, session module constructors (use fakes this task; real modules land in Tasks 5–6)
- Produces: `TerminalObservationInstaller.bind` / returned `TerminalObservationBinding`

Define `TerminalObservationConnectRequest`:

```dart
final class TerminalObservationConnectRequest {
  const TerminalObservationConnectRequest({
    required this.isWorkspaceShell,
    this.cliCapabilities = const [],
    this.sessionModules = const [],
  });

  final bool isWorkspaceShell;
  final Iterable<CliCapability> cliCapabilities;
  final List<TerminalObservationContributor> sessionModules;
}
```

Installer algorithm (locked):

1. Bind `request.sessionModules` in list order.
2. If `!isWorkspaceShell`, bind every `cliCapabilities.whereType<TerminalObservationContributor>()`.
3. Return `CompositeObservationBinding` of all bindings.
4. After `unbind`, those handlers must not fire.

`TerminalSession` resolves `cliCapabilities` as `registry.tryGet(cli)?.capabilities ?? const []`. Workspace shell passes `const []`. The installer never constructs a `CliToolRegistry`.

- [ ] **Step 1: Write the failing installer tests.**

```dart
test('binds session modules then CLI contributors in definition order', () {
  final order = <String>[];
  final session = [_NamedContributor('s1', order), _NamedContributor('s2', order)];
  final cliCaps = [_NamedContributor('c1', order), _NamedContributor('c2', order)];
  final binding = TerminalObservationInstaller().bind(
    bus: bus,
    seat: seat,
    request: TerminalObservationConnectRequest(
      isWorkspaceShell: false,
      cliCapabilities: cliCaps,
      sessionModules: session,
    ),
  );
  expect(order, ['s1', 's2', 'c1', 'c2']);
  binding.unbind();
  order.clear();
  bus.dispatchOutput(Uint8List.fromList([1]));
  expect(order, isEmpty);
});

test('workspace shell does not bind CLI contributors', () {
  final order = <String>[];
  TerminalObservationInstaller().bind(
    bus: bus,
    seat: seat,
    request: TerminalObservationConnectRequest(
      isWorkspaceShell: true,
      cliCapabilities: [_NamedContributor('cursor', order)],
      sessionModules: [_NamedContributor('session', order)],
    ),
  );
  expect(order, ['session']);
});
```

`_NamedContributor` implements `CliCapability` and `TerminalObservationContributor`. `bind` appends its name to `order` and registers an output observer that also appends the name (so unbind can be asserted).

- [ ] **Step 2: Verify RED.**

Run: `cd client && flutter test test/services/terminal/observation/terminal_observation_installer_test.dart`

Expected: compilation failure naming `TerminalObservationInstaller`.

- [ ] **Step 3: Implement the installer.**

Keep it free of session-module construction. Callers pass the module list. No `CliTool` switch.

- [ ] **Step 4: Re-run observation tests.**

Run: `cd client && flutter test test/services/terminal/observation/`

Expected: PASS.

- [ ] **Step 5: Commit.**

```bash
git add client/lib/services/terminal/observation client/test/services/terminal/observation
git commit -m "$(cat <<'EOF'
feat(terminal): add observation installer bind order

EOF
)"
```

---

### Task 5: Session modules — activity and launch-start

**Files:**
- Create: `client/lib/services/terminal/observation/modules/activity_observation_module.dart`
- Create: `client/lib/services/terminal/observation/modules/launch_start_module.dart`
- Test: `client/test/services/terminal/observation/launch_start_module_test.dart`
- Test: `client/test/services/terminal/observation/activity_observation_module_test.dart`

**Interfaces:**
- Consumes: `TerminalActivityTracker`, `TerminalStartupFailureDetector`
- Produces: modules implementing `TerminalObservationContributor`

- [ ] **Step 1: Write the failing launch-start tests.**

```dart
test('fatal startup chunk fails and does not confirm', () {
  final failures = <String>[];
  var confirmed = 0;
  seat = TerminalObservationSeat(
    sessionId: 's',
    memberId: 'm',
    phase: TerminalLaunchPhase.confirming,
    startupExecutable: 'claude',
    validateLaunch: false,
    failLaunch: failures.add,
    confirmStarted: () => confirmed++,
  );
  bus = TerminalObservationBus(seat: seat);
  LaunchStartModule().bind(bus, seat);
  bus.dispatchOutput(
    Uint8List.fromList(utf8.encode('cannot be used with root/sudo privileges')),
  );
  expect(failures, isNotEmpty);
  expect(confirmed, 0);
});

test('healthy starting chunk confirms and does not fail', () {
  var confirmed = 0;
  seat = TerminalObservationSeat(
    sessionId: 's',
    memberId: 'm',
    phase: TerminalLaunchPhase.confirming,
    confirmStarted: () => confirmed++,
    failLaunch: (_) {},
  );
  bus = TerminalObservationBus(seat: seat);
  LaunchStartModule().bind(bus, seat);
  bus.dispatchOutput(Uint8List.fromList(utf8.encode('ready')));
  expect(confirmed, 1);
});

test('process exit while starting fails launch', () {
  final failures = <String>[];
  seat = TerminalObservationSeat(
    sessionId: 's',
    memberId: 'm',
    phase: TerminalLaunchPhase.confirming,
    failLaunch: failures.add,
    confirmStarted: () {},
  );
  bus = TerminalObservationBus(seat: seat);
  LaunchStartModule().bind(bus, seat);
  bus.notifyProcessExited(1);
  expect(failures, isNotEmpty);
});
```

- [ ] **Step 2: Write the failing activity tests.**

```dart
test('running chunks fingerprint; confirming chunks do not', () {
  final tracker = TerminalActivityTracker();
  seat = TerminalObservationSeat(
    sessionId: 's',
    memberId: 'm',
    phase: TerminalLaunchPhase.confirming,
    activityTracker: tracker,
  );
  bus = TerminalObservationBus(seat: seat);
  ActivityObservationModule().bind(bus, seat);
  bus.dispatchOutput(Uint8List.fromList(utf8.encode('boot')));
  expect(tracker.isWorking, isFalse);
  bus.setPhase(TerminalLaunchPhase.running);
  bus.dispatchOutput(Uint8List.fromList(utf8.encode('hello world\n')));
  expect(tracker.isWorking || tracker.isBootFrameReady, isTrue);
});
```

Use whatever tracker assertion is stable (if `isWorking` needs time, call `notePtyBytes` behavior: after a running chunk, `_bootPtyObserved` equivalent is that a subsequent `isQuietAfterTurnPtyActivity` is not vacuously true). Minimum: spy by injecting a fake tracker if the real one is timing-sensitive.

If `TerminalActivityTracker` is hard to assert without time, give `ActivityObservationModule` no extra abstraction — test that `tracker` received bytes by subclassing:

```dart
class _SpyTracker extends TerminalActivityTracker {
  int notes = 0;
  @override
  void notePtyBytes(List<int> bytes, [DateTime? at]) {
    notes++;
    super.notePtyBytes(bytes, at);
  }
}
```

Expect `notes == 0` on confirming, `notes == 1` after a running chunk.

- [ ] **Step 3: Verify RED.**

Run: `cd client && flutter test test/services/terminal/observation/launch_start_module_test.dart test/services/terminal/observation/activity_observation_module_test.dart`

Expected: compilation failure naming the modules.

- [ ] **Step 4: Implement the modules.**

`ActivityObservationModule.bind`: `addOutputObserver` with `{TerminalLaunchPhase.running}` calling `seat.activityTracker?.notePtyBytes(bytes)`.

`LaunchStartModule`:
- Keep a `StringBuffer` of starting output.
- Output observer phases `{spawning, confirming}`.
- Same chunk: `classifyStartupFailure` → if non-null `seat.failLaunch(message)` and return; else `seat.confirmStarted?.call()`.
- `addProcessExitObserver`: if `seat.phase` is spawning or confirming, classify accumulated text or emit the existing launch-controller messages: `'[process exited unexpectedly during startup]'` for code 0, `'[process exited with code $code during startup]'` otherwise. Copy those two strings verbatim from `terminal_launch_controller.dart`.
- Do not treat a thrown classifier as a launch failure.

- [ ] **Step 5: Re-run module tests and commit.**

Run: `cd client && flutter test test/services/terminal/observation/`

Expected: PASS.

```bash
git add client/lib/services/terminal/observation client/test/services/terminal/observation
git commit -m "$(cat <<'EOF'
feat(terminal): add activity and launch-start observation modules

EOF
)"
```

---

### Task 6: User-line and TeamBus intercept modules

**Files:**
- Create: `client/lib/services/terminal/observation/modules/user_line_module.dart`
- Create: `client/lib/services/terminal/observation/modules/team_bus_intercept_module.dart`
- Test: `client/test/services/terminal/observation/user_line_and_bus_modules_test.dart`

**Interfaces:**
- Consumes: `UserLineSubmitted`, `BusUserLineCapture`, `BusUserInputRouting`, `PendingUserMessage`
- Produces: first/every/turn-start callbacks; parked submission stream; transform order 100

- [ ] **Step 1: Write the failing tests.**

```dart
test('user line is captured even when bus transform drops the bytes', () {
  final lines = <String>[];
  UserLineModule(onEveryUserLineSubmitted: lines.add).bind(bus, seat);
  TeamBusInterceptModule(
    routing: BusUserInputRouting(
      shouldIntercept: () => true,
      onTurnStart: () {},
      onUserLine: (line) => 'id-$line',
    ),
  ).bind(bus, seat);
  final forward = bus.transformInput(Uint8List.fromList(utf8.encode('hello\r')));
  expect(lines, ['hello']);
  expect(utf8.decode(forward), isNot(contains('hello')));
});

test('first-line callback fires only once', () {
  final first = <String>[];
  UserLineModule(onFirstUserLineSubmitted: first.add).bind(bus, seat);
  bus.transformInput(Uint8List.fromList(utf8.encode('one\r')));
  bus.transformInput(Uint8List.fromList(utf8.encode('two\r')));
  expect(first, ['one']);
});

test('parked submissions emit when intercept returns a non-empty id', () async {
  final module = TeamBusInterceptModule(
    routing: BusUserInputRouting(
      shouldIntercept: () => true,
      onTurnStart: () {},
      onUserLine: (_) => 'mid',
    ),
  );
  module.bind(bus, seat);
  expect(
    module.parkedUserSubmissions,
    emits(isA<PendingUserMessage>().having((m) => m.id, 'id', 'mid')),
  );
  bus.transformInput(Uint8List.fromList(utf8.encode('x\r')));
});
```

Read `BusUserLineCapture.filter` so the dropped-byte assertion matches real filter output (it may still forward some control bytes). Assert `lines` first; for forward, `expect(utf8.decode(forward, allowMalformed: true).contains('hello'), isFalse)` if that is true today, otherwise assert parked id instead of byte drop.

- [ ] **Step 2: Verify RED.**

Run: `cd client && flutter test test/services/terminal/observation/user_line_and_bus_modules_test.dart`

Expected: compilation failure naming the modules.

- [ ] **Step 3: Implement.**

`UserLineModule` constructor: `onFirstUserLineSubmitted`, `onEveryUserLineSubmitted`, `onTurnStart` — all optional. Bind `subscribe<UserLineSubmitted>`. On each line: first callback once, every callback always, `onTurnStart?.call()`.

`TeamBusInterceptModule`: wrap `BusUserLineCapture` exactly as `TerminalUserInputPipeline.install` does (including parking into a `StreamController<PendingUserMessage>.broadcast()`). Expose `parkedUserSubmissions` and `isUnreadParkedMessage`. Transform `order => 100`. `unbind` cancels the transform subscription; do not close the parked stream here if `TerminalSession` still listens — session `dispose` closes it. Module `close()` closes the controller; session calls that on dispose.

Move `isUnreadParkedMessage` onto the module using `routing.isUnread`.

- [ ] **Step 4: Re-run observation tests and commit.**

Run: `cd client && flutter test test/services/terminal/observation/`

Expected: PASS.

```bash
git add client/lib/services/terminal/observation client/test/services/terminal/observation
git commit -m "$(cat <<'EOF'
feat(terminal): add user-line and TeamBus observation modules

EOF
)"
```

---

### Task 7: Slim TerminalBehaviorCapability and Cursor contributor

**Files:**
- Modify: `client/lib/services/cli/registry/capabilities/terminal_behavior_capability.dart` (delete `bindTitleAttention`, `forwardsColorSchemeReport`)
- Modify: `client/lib/services/cli/claude/capabilities/terminal_behavior.dart`
- Modify: `client/lib/services/cli/codex/capabilities/terminal_behavior.dart`
- Modify: `client/lib/services/cli/cursor/capabilities/terminal_behavior.dart`
- Modify: `client/lib/services/cli/flashskyai/capabilities/terminal_behavior.dart`
- Modify: `client/lib/services/cli/opencode/capabilities/terminal_behavior.dart`
- Test: `client/test/services/cli/cursor/cursor_terminal_observation_test.dart`
- Modify any test that reads the deleted getters (grep first)

**Interfaces:**
- Consumes: `OscTitle`, `stripColorSchemeReport`, `detectCursorTitleAttention`, `isCursorNativeTitle`, `AgentAttentionCubit.applyEvent`
- Produces: `CursorTerminalBehavior implements TerminalObservationContributor`

- [ ] **Step 1: Grep and write the failing Cursor contributor tests.**

```bash
rg -n "bindTitleAttention|forwardsColorSchemeReport" client
```

Replace `terminal_launch_controller_cursor_title_test.dart` with contributor tests (delete the launch-controller file in Task 8 once launch controller no longer has the bind methods; this task can already add the new file).

```dart
test('action-required OSC title → waiting', () {
  const CursorTerminalBehavior().bind(bus, seat);
  bus.dispatchOutput(_osc('Cursor - action required'));
  expect(
    attention.state.attentionFor(sessionId: 's', memberId: 'm'),
    AgentSeatAttention.waiting,
  );
});

test('bare Cursor Agent never marks waiting', () { ... });

test('non-matching title after waiting clears to done', () { ... });

test('bare title after waiting does not clear', () { ... });

test('YOLO skipPermissions does not surface waiting', () { ... });

test('OSC 997 is stripped at transform order 200', () {
  const CursorTerminalBehavior().bind(bus, seat);
  final report = Uint8List.fromList([0x1b, 0x5d, 0x39, 0x39, 0x37, 0x3b, 0x31, 0x07]);
  expect(bus.transformInput(report), isEmpty);
});
```

Seat must include `attention` and `skipPermissions`. Copy the five attention cases verbatim from `client/test/services/terminal/terminal_launch_controller_cursor_title_test.dart`. Init rust lib is **not** required if the bus does not feed `TerminalEngine`.

- [ ] **Step 2: Verify RED.**

Run: `cd client && flutter test test/services/cli/cursor/cursor_terminal_observation_test.dart`

Expected: FAIL — `CursorTerminalBehavior` does not implement `TerminalObservationContributor` yet, or OSC 997 still forwarded.

- [ ] **Step 3: Slim the capability and implement Cursor bind.**

Delete the two getters from the interface and from all five CLI implementations.

`CursorTerminalBehavior.bind`:
- `subscribe<OscTitle>` with the exact `_applyCursorTitle` rules currently in `terminal_launch_controller.dart` (sticky waiting flag lives on the **binding closure**, not on the const capability).
- `addInputTransform` with `order == 200` calling `stripColorSchemeReport`.
- Return a binding that cancels both.

Other CLIs: do **not** add no-op contributors.

- [ ] **Step 4: Analyze + tests.**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`

Expected: errors wherever deleted getters are still referenced (`session_shell_connector.dart`, `terminal_session.dart`). Fix those call sites only enough to compile: temporarily stop reading the flags (connector: skip the `if (titleAttention)` block; session: stop passing `forwardsColorScheme`). Full wiring is Tasks 8–9. Do not leave `// ignore` comments.

Run: `cd client && flutter test test/services/cli/cursor/cursor_terminal_observation_test.dart test/services/cli/codex/codex_terminal_behavior_test.dart test/services/cli/registry/capabilities/opencode_terminal_behavior_test.dart test/services/terminal/observation/`

Expected: PASS.

- [ ] **Step 5: Commit.**

```bash
git add client/lib/services/cli client/lib/services/launch/session_shell_connector.dart client/lib/services/terminal/terminal_session.dart client/test
git commit -m "$(cat <<'EOF'
refactor(cli): move Cursor PTY observation onto a contributor

EOF
)"
```

---

### Task 8: Wire TerminalLaunchController to the bus

**Files:**
- Modify: `client/lib/services/terminal/terminal_launch_controller.dart`
- Delete: Cursor imports, `_observeCursorOscTitles`, `_applyCursorTitle`, `_cursor*` fields, `bindCursorTitleAttention`, `clearCursorTitleAttention`
- Delete: in-listener startup classification / `_startupOutput` (LaunchStartModule owns it)
- Test: rewrite or delete `client/test/services/terminal/terminal_launch_controller_cursor_title_test.dart`

**Interfaces:**
- Consumes: `TerminalObservationBus.dispatchOutput`, `notifyPainted`, `setPhase`, `notifyProcessExited`
- Produces: `attachObservation(TerminalObservationBus? bus)`, `feedPtyBytes` = dispatch + `engine.feed` + notifyPainted

- [ ] **Step 1: Write a failing controller wiring test.**

```dart
test('feedPtyBytes dispatches then feeds the engine', () {
  final seen = <int>[];
  final bus = TerminalObservationBus(seat: seat);
  bus.addOutputObserver(_Capture(seen), phases: {TerminalLaunchPhase.running});
  controller.attachObservation(bus);
  controller.feedPtyBytes(Uint8List.fromList([1, 2]));
  expect(seen, [1]);
  // engine accepted bytes: screen is non-empty or cursor moved — use a
  // unique OSC-free payload like 'Z' and assert engine has visible content.
});
```

Also test: without `attachObservation`, `feedPtyBytes` still `engine.feed`s (workspace tests / early construction).

- [ ] **Step 2: Verify RED.**

Run: `cd client && flutter test test/services/terminal/terminal_launch_controller_observation_test.dart`

Expected: FAIL on `attachObservation`.

- [ ] **Step 3: Implement wiring.**

`feedPtyBytes`:

```dart
void feedPtyBytes(Uint8List data) {
  if (data.isEmpty) return;
  _observation?.dispatchOutput(data);
  engine.feed(data);
  _observation?.notifyPainted();
}
```

Do **not** call `activityTracker.notePtyBytes` here.

Transport `output.listen`: empty-check, `feedPtyBytes` only. Remove `_startupOutput` and `TerminalStartupFailureDetector` from this callback.

`beginStartup`: `setPhase(spawning)` on the bus if attached.

`_enterConfirmingPhase`: `setPhase(confirming)`.

`_confirmProcessStarted`: `setPhase(running)` (already sets `_phase`).

`_handleStartFailure`: `setPhase(failed)`.

`transport.done`: if starting, `_observation?.notifyProcessExited(code)` **and** still call `failLaunch` only if LaunchStartModule is not attached. After Task 9, session always attaches LaunchStart, so the controller must **not** double-fail.

Locked split:
- If `_observation != null` and `_starting`, `notifyProcessExited` only (module calls `failLaunch`).
- If `_observation == null` and `_starting`, keep the old inline fail (should not happen in production after Task 9).
- If running and `code != 0`, keep the existing running-exit UI path on the controller.

`disconnect`: `attachObservation(null)`; do not call deleted Cursor clear.

`seat.confirmStarted` / `failLaunch` will be wired in Task 9 to `_confirmProcessStarted` / `_handleStartFailure`. This task only exposes:

```dart
void attachObservation(TerminalObservationBus? bus) {
  _observation = bus;
}
```

and public `void confirmFromObservation()` → `_confirmProcessStarted()`, or session passes those closures into the seat pointing at the controller methods. Prefer seat callbacks created by `TerminalSession`.

Delete `terminal_launch_controller_cursor_title_test.dart` once contributor tests exist.

- [ ] **Step 4: Run controller + observation tests.**

Run: `cd client && flutter test test/services/terminal/terminal_launch_controller_observation_test.dart test/services/terminal/observation/ test/services/cli/cursor/cursor_terminal_observation_test.dart`

Expected: PASS. No remaining references to `bindCursorTitleAttention`.

- [ ] **Step 5: Commit.**

```bash
git add client/lib/services/terminal/terminal_launch_controller.dart client/test/services/terminal
git commit -m "$(cat <<'EOF'
refactor(terminal): dispatch PTY output through the observation bus

EOF
)"
```

---

### Task 9: Wire TerminalSession; delete the input pipeline

**Files:**
- Modify: `client/lib/services/terminal/terminal_session.dart`
- Delete: `client/lib/services/terminal/terminal_user_input_pipeline.dart`
- Modify: `client/lib/services/terminal/terminal_session.dart` constructor (drop `inputPipeline`)
- Test: `client/test/services/terminal/terminal_session_observation_test.dart` (or extend an existing session connect test)

**Interfaces:**
- Consumes: installer, all four session modules, `CliToolRegistry.builtIn().tryGet(cli)?.capabilities`
- Produces: `connect(..., {TerminalObservationAttach? observation})`; `parkedUserSubmissions` from intercept module or an empty stream; `connectWorkspaceShell` binds Activity + LaunchStart only

Define:

```dart
final class TerminalObservationAttach {
  const TerminalObservationAttach({
    required this.sessionId,
    required this.memberId,
    this.cli,
    this.attention,
    this.skipPermissions,
  });
  final String sessionId;
  final String memberId;
  final CliTool? cli;
  final AgentAttentionCubit? attention;
  final bool Function()? skipPermissions;
}
```

- [ ] **Step 1: Write a failing session-level test if a lightweight harness exists.**

If constructing `TerminalSession` in unit tests already happens (search `TerminalSession(` in `client/test`), add:

```dart
test('CLI connect binds Cursor OSC; workspace shell does not', () async {
  // Use a fake TransportStarter that never emits, then feedPtyBytes through the session/launch.
});
```

If session tests always need rust lib + transport, prefer installer tests (already done) plus a focused test that `transformEngineToPty` path uses `bus.transformInput`.

The engine→PTY path in `_wireEngineOutput` must become:

```dart
_engineOutputSubscription = engine.output.listen((data) {
  final forward = _observation?.transformInput(data) ?? data;
  if (forward.isNotEmpty) {
    _launch.writeToPty(forward);
  }
});
```

- [ ] **Step 2: Implement session wiring.**

On `connect` / `connectWorkspaceShell`:
1. `disconnect()` previous generation (already).
2. Create `TerminalObservationBus` + `TerminalObservationSeat` (phase idle; `failLaunch: _launch.failLaunch`; `confirmStarted: ()` calling the controller confirm method — add `TerminalLaunchController.confirmProcessStartedForObservation()` that calls `_confirmProcessStarted` if you cannot reach it).
3. Build session module list:
   - always `ActivityObservationModule()`, `LaunchStartModule()`
   - CLI connect: `UserLineModule(...)` if any line callback is non-null; `TeamBusInterceptModule` if routing non-null
   - workspace shell: only Activity + LaunchStart
4. `installer.bind` with `isWorkspaceShell` accordingly and `cliCapabilities` from the launch CLI when `shellLaunch != null`.
5. `_launch.attachObservation(bus)` then `beginStartup` / `spawnTransport`.
6. Keep `pathDropBehavior` from `TerminalBehaviorCapability` (policy, not observation).

On `disconnect` / `dispose`: unbind composite binding, `bus.dispose()`, `attachObservation(null)`, close parked controller.

`parkedUserSubmissions`: from intercept module if bound, else a broadcast stream that never emits (session may own the controller always and pass it into the module).

Remove `_inputPipeline` entirely. Constructor param `inputPipeline` goes away; any test passing it must be updated (grep shows only `terminal_session.dart`).

`startupDeadline` on the session still comes from `TerminalBehaviorCapability.startupDeadline` at connect if not already — do not change that in this task unless the session already reads it.

- [ ] **Step 3: Analyze.**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`

Expected: 0 errors. Fix remaining `TerminalUserInputPipeline` imports.

- [ ] **Step 4: Run terminal + cursor tests.**

Run: `cd client && flutter test test/services/terminal/ test/services/cli/cursor/cursor_terminal_observation_test.dart test/utils/terminal/`

Expected: PASS.

- [ ] **Step 5: Commit.**

```bash
git add client/lib/services/terminal client/test
git commit -m "$(cat <<'EOF'
refactor(terminal): bind observation modules at session connect

EOF
)"
```

---

### Task 10: Pass attention through session_shell_connector

**Files:**
- Modify: `client/lib/services/launch/session_shell_connector.dart`
- Modify any other `shell.connect(` call sites that need `TerminalObservationAttach` (grep `\.connect(` on `TerminalSession`)

**Interfaces:**
- Consumes: `AgentAttentionCubit`, skipPermissions already resolved after SSH constraints
- Produces: `shell.connect(..., observation: TerminalObservationAttach(...))`

- [ ] **Step 1: Grep connect call sites.**

```bash
rg -n "shell\.connect\(|\.connectWorkspaceShell\(" client/lib
```

Every member-CLI `connect` must pass `observation` with `sessionId`, `memberId` (`agentStatusSeatMemberId`), `cli: launchCli`, `attention: _host.agentAttentionCubit`, `skipPermissions` using the same lookup the deleted `bindCursorTitleAttention` used.

Workspace shell connects pass no CLI attach (session binds Activity + LaunchStart only).

Delete leftover title-attention block if Task 7 left a hole.

- [ ] **Step 2: Implement.**

No `CliTool` check. Cursor contributor binds only because Cursor’s capability implements the interface.

- [ ] **Step 3: Analyze + launch/session tests.**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`

Run: `cd client && flutter test test/services/launch/ test/services/terminal/`

Expected: PASS.

- [ ] **Step 4: Commit.**

```bash
git add client/lib/services/launch/session_shell_connector.dart client/lib
git commit -m "$(cat <<'EOF'
refactor(launch): attach terminal observation at shell connect

EOF
)"
```

---

### Task 11: ScreenPainted wait for fullscreen paste ACK

**Files:**
- Modify: `client/lib/services/terminal/fullscreen_pty_delivery_port.dart`
- Modify: `client/lib/services/terminal/terminal_fullscreen_pty_port.dart`
- Modify: `client/lib/services/terminal/fullscreen_pty_automation.dart`
- Modify: `client/test/services/terminal/support/fake_fullscreen_pty_delivery_port.dart`
- Modify: every `implements FullscreenPtyDeliveryPort` in `client/test/services/terminal/fullscreen_pty_automation_test.dart`
- Test: add a case in `fullscreen_pty_automation_test.dart`

**Interfaces:**
- Produces: `Future<void> waitForPaint({required Duration timeout})` on the port
- Automation `_pollForNeedle` waits on paint, using `pollInterval` only as fallback

- [ ] **Step 1: Write the failing faster-ACK test.**

Add to `fullscreen_pty_automation_test.dart`:

```dart
test('paste ACK proceeds on waitForPaint without waiting pollInterval', () async {
  final port = _PaintWakePort();
  final automation = FullscreenPtyAutomation(
    timing: const PtyAutomationTiming(
      afterClear: Duration.zero,
      afterPaste: Duration.zero,
      afterCr: Duration.zero,
      afterReinject: Duration.zero,
      crMaxAttempts: 2,
      reinjectMaxAttempts: 1,
      nudgeMaxAttempts: 2,
      scanRows: 24,
      pollTimeout: Duration(seconds: 2),
      pollInterval: Duration(milliseconds: 200),
    ),
  );
  final sw = Stopwatch()..start();
  final outcome = await automation.deliverPasteAndSubmit(
    port: port,
    text: 'needle-text',
    pasteSettle: Duration.zero,
  );
  sw.stop();
  expect(outcome, FullscreenPtyDeliveryOutcome.submitted);
  expect(sw.elapsedMilliseconds, lessThan(150));
});
```

`_PaintWakePort`: first `locateNeedle` after paste returns null; `waitForPaint` completes immediately and flips visibility so the next locate hits. Copy other methods from `FakeFullscreenPtyDeliveryPort`. If the current `_pollForNeedle` still `delayed(pollInterval)` first, the test stays RED (>150ms). Instant timing tests must keep passing (`pollTimeout <= 0` still one-shot).

- [ ] **Step 2: Verify RED.**

Run: `cd client && flutter test test/services/terminal/fullscreen_pty_automation_test.dart --name "waitForPaint"`

Expected: compilation failure (`waitForPaint` missing) or elapsed ≥ 200ms.

- [ ] **Step 3: Implement.**

Port method:

```dart
Future<void> waitForPaint({required Duration timeout});
```

Fake / test ports: `async {}` (complete immediately).

`TerminalFullscreenPtyPort`: take `Stream<void> painted` (from `bus.painted`).

```dart
Future<void> waitForPaint({required Duration timeout}) {
  if (timeout <= Duration.zero) return Future<void>.value();
  return painted.first.timeout(timeout, onTimeout: () {});
}
```

Session constructs the real port with `painted: bus.painted` (find the `TerminalFullscreenPtyPort(` call site and pass the stream; if the port is created before connect, update it when the bus is attached).

`_pollForNeedle` after `minSettle`:

```dart
if (timeout <= Duration.zero) {
  await port.syncDisplayGrid();
  return _locatePasteAck(port, needle);
}
final deadline = DateTime.now().add(timeout);
while (DateTime.now().isBefore(deadline)) {
  if (port.isAborted) return null;
  await port.syncDisplayGrid();
  final anchor = _locatePasteAck(port, needle);
  if (anchor != null) return anchor;
  final remaining = deadline.difference(DateTime.now());
  if (remaining <= Duration.zero) break;
  final slice = remaining < _timing.pollInterval ? remaining : _timing.pollInterval;
  await Future.any<void>([
    port.waitForPaint(timeout: slice),
    if (_timing.pollInterval > Duration.zero) Future<void>.delayed(slice),
  ]);
}
return null;
```

Do not double-wait `pollInterval` plus paint if `waitForPaint` already times out at `slice` — `Future.any` with delayed(slice) and waitForPaint(timeout: slice) is enough. If `pollInterval` is zero, only waitForPaint.

Wire `TerminalSession` so `TerminalFullscreenPtyPort` sees the live bus painted stream after connect (store the port on the session or pass a `StreamController` owned by the session that the bus also notifies). Simplest: session owns `StreamController<void>.broadcast() _painted` and bus `notifyPainted` cannot reach it unless launch controller also adds to it.

Locked: `TerminalLaunchController.notifyPainted` already goes through the bus. Session input/probe port should subscribe to `bus.painted`. If the port is created in the session constructor, give it a `Stream<void> Function()? painted` getter that reads `_observation?.painted`.

- [ ] **Step 4: Run fullscreen tests.**

Run: `cd client && flutter test test/services/terminal/fullscreen_pty_automation_test.dart test/services/terminal/member_pty_inject_service_test.dart test/services/terminal/member_pty_inject_abort_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit.**

```bash
git add client/lib/services/terminal client/test/services/terminal
git commit -m "$(cat <<'EOF'
feat(terminal): ACK fullscreen paste on screen paint

EOF
)"
```

---

### Task 12: Docs, spec status, and full verification

**Files:**
- Modify: `docs/cli-architecture.md`
- Modify: `docs/superpowers/specs/2026-08-28-terminal-observation-plane-design.md` (Status: Approved)

**Interfaces:** none

- [ ] **Step 1: Update `docs/cli-architecture.md`.**

In the directory tree under `registry/capabilities/`, mention `terminal_observation_contributor.dart`.

Change the TerminalBehaviorCapability row from “turn interrupt、标题注意力、全屏输入” to “turn interrupt、全屏输入与注入策略（观测走 TerminalObservationContributor）”.

Add an optional-capability bullet:

`TerminalObservationContributor` — optional; scanned with `is` on `CliToolDefinition.capabilities`. PTY detect/scan/listen registers on `TerminalObservationBus`. Never `if (cli == …)` in `TerminalLaunchController`.

In “实现可选的能力”, add: if the CLI needs PTY observation, implement `TerminalObservationContributor` on an existing capability class (usually `terminal_behavior.dart`).

Add `TerminalObservationContributor` to the capability table as 基础设施, not required.

- [ ] **Step 2: Set spec status to Approved.**

- [ ] **Step 3: Grep for deleted APIs.**

```bash
rg -n "bindCursorTitleAttention|clearCursorTitleAttention|bindTitleAttention|forwardsColorSchemeReport|TerminalUserInputPipeline" client docs
```

Expected: only docs/spec/plan historical mentions, no Dart references.

- [ ] **Step 4: Full analyze + targeted tests + non-integration tests.**

Run:

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd client && flutter test test/services/terminal/ test/services/cli/cursor/ test/services/cli/codex/codex_terminal_behavior_test.dart test/services/cli/registry/capabilities/opencode_terminal_behavior_test.dart test/utils/terminal/
cd client && flutter test --exclude-tags integration
```

Expected: 0 analyze errors/warnings; all tests passed.

- [ ] **Step 5: Commit.**

```bash
git add docs/cli-architecture.md docs/superpowers/specs/2026-08-28-terminal-observation-plane-design.md
git commit -m "$(cat <<'EOF'
docs(cli): document the terminal observation plane

EOF
)"
```

---

## Spec coverage (self-review)

| Spec requirement | Task |
|---|---|
| Independent plane, not Hook/RuntimeEvent | Global constraints + Task 1 |
| Seat-scoped bus, generation, dispose | Task 1 |
| Output fan-out, unmodifiable, phase snapshot | Task 1 |
| Input observers then ordered transforms | Task 2, 6 |
| Screen paint + pull probe | Task 2, 11 |
| Lazy OscTitle / UserLine scanners | Task 3 |
| Contributor bind factory, const Cursor | Task 4, 7 |
| Installer order, workspace shell filter | Task 4, 9 |
| Activity + LaunchStart modules | Task 5 |
| UserLine + TeamBus modules | Task 6 |
| Delete observation flags | Task 7 |
| Cursor OSC + OSC 997 contributor | Task 7 |
| Launch controller has zero CLI knowledge | Task 8 |
| Connect receives observation attach | Task 9–10 |
| Delete input pipeline | Task 9 |
| Handler isolation / throwing transform | Task 1–2 |
| Fullscreen wait on paint | Task 11 |
| cli-architecture.md | Task 12 |
| Tests 1–12 in spec Testing section | Tasks 1–11 |

Out of scope (explicitly not tasked): OpenCode/Codex screen observers, merging `BusUserLineCapture` CSI parser with `UserLineScanner`, moving the bus into Host Session Runtime.
