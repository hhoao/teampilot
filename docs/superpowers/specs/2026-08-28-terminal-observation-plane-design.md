# Terminal Observation Plane — Design

**Date:** 2026-08-28
**Status:** Approved
**Supersedes:** `TerminalLaunchController` Cursor OSC special-case, `bindTitleAttention` / `forwardsColorSchemeReport` flags, hardcoded `TerminalUserInputPipeline` captures, launch-controller-owned startup classification and activity fingerprinting.

Related: [CLI capability consolidation](2026-08-14-cli-capability-consolidation-design.md) (policy vs observation), [Agent runtime event plane](2026-08-25-agent-runtime-event-plane-design.md) (HTTP hook plane — **not** this), [Host session runtime](2026-08-28-host-session-runtime-design.md) (PTY owner may move; this plane moves with the PTY).

## Problem

Member PTY observation is a hardcoded fan-out inside `TerminalLaunchController` and `TerminalUserInputPipeline`:

- `feedPtyBytes` always fingerprints activity, then runs Cursor-named OSC title parsing, then feeds the engine.
- `TerminalLaunchController` imports `cursor/capabilities/terminal_behavior.dart` and exposes `bindCursorTitleAttention`.
- `TerminalBehaviorCapability.bindTitleAttention` is a boolean the shell interprets as “call the Cursor method”.
- `forwardsColorSchemeReport` is another boolean the input pipeline interprets as “strip OSC 997”.
- First/every user line, turn-start, TeamBus intercept, and startup-failure classification each hang off a different private field.

Adding a new detector means editing the launch hot path and usually adding another CLI flag. That violates the capability rule: external code must not special-case `CliTool`. It also duplicates scanners (UTF-8 decode, OSC parse) per feature.

CLI native hooks (`HookCapability`) and the runtime-event plane (HTTP payloads → `RuntimeEvent`) are a different surface. They must not absorb PTY bytes.

## Decisions (locked)

1. **Independent terminal observation plane.** Register → dispatch → handle. Not `HookCapability`, not `RuntimeEvent`, not journaled.
2. **Seat-scoped bus.** One `TerminalObservationBus` per member PTY (and per workspace shell PTY). Connect binds; disconnect/dispose unbinds. Reconnect uses a new generation; old handlers are dead.
3. **Observation vs policy are split.** `TerminalBehaviorCapability` keeps injection/automation policy only. Observation flags are deleted. Capabilities that need PTY data implement `TerminalObservationContributor`.
4. **Three channels, one registry.** Output is read-only fan-out. Input is ordered transforms plus pre-transform observers. Screen is paint notify plus pull probe. Do not collapse these into one middleware pipe.
5. **Shared L1 scanners are subscription-gated.** OSC titles and user lines run only if something is subscribed. Multiple handlers share one scan. Activity and launch-start stay L0 modules (single consumer).
6. **CLI and session use the same contributor interface.** Cursor OSC attention is a CLI contributor. Activity, launch-start (classify then confirm), user-line capture, TeamBus intercept are session contributors. `TerminalLaunchController` has zero CLI knowledge.
7. **No compatibility shims.** Delete Cursor-named bind methods, observation booleans, and launch-controller imports of CLI packages. Tests target the bus and contributors.
8. **The plane lives with the PTY.** Today that is `TerminalSession`. When Host Session Runtime owns the PTY, the bus moves into that process unchanged. Capability contributors stay on `CliToolDefinition`.

## Goals

1. New CLI observation (status-bar scan, extra OSC, input filter) is a contributor on that CLI’s capability class. Launch controller does not change.
2. Cursor permission attention, startup errors, boot-frame readiness, user-line session titles, TeamBus intercept, and full-screen paste ACK stay correct and get faster where paint-driven wait replaces blind polling.
3. Hot path stays cheap: no unused scanners, observers must not mutate shared byte buffers, one handler crash does not blank the terminal.
4. Workspace shells bind Activity + LaunchStart only. They do not bind CLI contributors, user-line capture, or bus intercept.

## Non-goals

- Merging PTY observation into `RuntimeEvent` / `HookEntry` / agent-status HTTP.
- Changing CLI native hook protocols or managed hook file writers.
- Disk scans (`detectNativeId`, transcript tailers). Those stay on `AiHistoryCapability`.
- Replacing `TerminalBehaviorCapability` policy (interrupt plan, paste delay, path drop, composer prefix, CR ACK strategy, input readiness needles, startup deadline).
- A global app-wide bus. Observation is per seat.

## Architecture

```text
Connect (CLI seat)
  CliToolDefinition.capabilities
    (each cap is TerminalObservationContributor?)
  + SessionObservationModules
        |
        v
TerminalObservationInstaller.bind(seat, bus)
        |
        +-- L1 scanners attached on first subscribe
        +-- output observers / input observers+transforms / screen observers
        v
PTY transport.output  -->  bus.dispatchOutput  -->  engine.feed  -->  bus.notifyPainted
engine.output         -->  bus.transformInput  -->  transport.write
Fullscreen automation -->  seat.screen probe   <--  ScreenPainted

Connect (workspace shell): session modules only (activity, launch-start).
```

### Layers

| Layer | What | Examples |
|---|---|---|
| L0 | Raw I/O and lifecycle | `PtyOutputChunk`, `PtyInputChunk`, `ScreenPainted`, `LaunchPhaseChanged`, `ProcessExited` |
| L1 | Shared scanners (lazy) | `OscTitle`, `UserLineSubmitted` |
| L2 | Contributors / handlers | Cursor attention, activity tracker, bus intercept, strip OSC 997, session title |

L2 never reaches into another CLI package. L2 may call cubits/services through `TerminalObservationSeat`.

### Ownership

| Unit | Path | Does | Depends on |
|---|---|---|---|
| `TerminalObservationBus` | `services/terminal/observation/` | Register, dispatch, lazy L1, isolate handler errors | Nothing CLI-specific |
| `TerminalObservationSeat` | same | Session/member ids, phase, probe, attention, fail/confirm, policy | Terminal session + optional CLI policy |
| `TerminalObservationContributor` | `services/cli/registry/capabilities/` | `bind` → `TerminalObservationBinding` | Bus + seat |
| `TerminalObservationInstaller` | `services/terminal/observation/` | Collect CLI + session contributors, bind/unbind by generation | Registry + connect options |
| L1 scanners | `services/terminal/observation/scanners/` | Byte/grid → derived events | Bus subscribe interest |
| CLI contributors | `{cli}/capabilities/` | CLI-specific handle/transform | Contributor interface |
| Session modules | `services/terminal/observation/modules/` | App-wide PTY features | Contributor interface |
| `TerminalBehaviorCapability` | registry capabilities | Policy only | Fullscreen automation, inject |

## Core interfaces

```dart
abstract interface class TerminalObservationContributor {
  /// Registers seat-scoped handlers. Shared const contributors must not keep
  /// seat state; the returned binding is the unbind token.
  TerminalObservationBinding bind(
    TerminalObservationBus bus,
    TerminalObservationSeat seat,
  );
}

abstract interface class TerminalObservationBinding {
  void unbind();
}
```

Not a required `CliCapability`. The installer scans `CliToolDefinition.capabilities` with `is TerminalObservationContributor`. A class may implement `TerminalBehaviorCapability` and `TerminalObservationContributor` together (Cursor does).

Shared capability instances stay `const`. `bind` is a factory: it registers seat-scoped handlers the **bus** owns and returns a `TerminalObservationBinding`. The contributor object must not store per-seat fields. The installer holds the bindings and calls `unbind()` on teardown.

Session modules implement the same interface, are constructed **per seat**, and are **not** registered on the CLI definition.

```dart
abstract interface class TerminalOutputObserver {
  void onOutput(Uint8List bytes, TerminalObservationSeat seat);
}

abstract interface class TerminalInputObserver {
  void onInput(Uint8List bytes, TerminalObservationSeat seat);
}

abstract interface class TerminalInputTransform {
  /// Ascending. Session defaults: bus intercept = 100, strip OSC 997 = 200.
  int get order;
  Uint8List transform(Uint8List bytes, TerminalObservationSeat seat);
}

abstract interface class TerminalScreenObserver {
  void onPainted(TerminalObservationSeat seat);
}
```

Derived events are sealed and dispatched through `bus.subscribe<T>(...)`. First subscriber for a type installs the matching L1 scanner; last unsubscribe tears it down.

Output/input observers receive an `UnmodifiableUint8ListView` over the chunk (no copy on the hot path). Transforms that change bytes return a new list; unchanged transforms may return the incoming instance.

## Channels

### Output (PTY → engine)

Order is fixed:

1. Ignore empty chunks.
2. `bus.dispatchOutput(bytes)` — L0 observers, then L1 scanners with subscribers.
3. `engine.feed(bytes)` exactly once.
4. `bus.notifyPainted()`.

Nobody on this channel rewrites the stream. Activity fingerprinting, OSC attention, and startup classification all see the same bytes.

Observers declare launch phases they care about (`spawning` / `confirming` / `running`). Dispatch skips observers whose phase set does not contain `seat.phase`.

Today `TerminalActivityTracker.notePtyBytes` runs only when connected (`running`). That stays: the activity module subscribes to `running` only. Startup classification subscribes to `spawning` + `confirming`.

### Input (engine → PTY)

Order is fixed:

1. L0 input observers see the **original** bytes (and a single shared UTF-8 decode if any observer/scanner needs text). First user line, every user line, and turn-start run here so session title still sees a line that TeamBus later parks.
2. Transforms run by ascending `order`. Equal `order` is stable by bind sequence.
3. Resulting bytes (possibly empty) go to `transport.write`.

Locked default orders:

| Order | Transform | Source |
|---|---|---|
| 100 | TeamBus intercept (`BusUserLineCapture.filter`) | Session module, only if connect supplied routing |
| 200 | Strip OSC 997 color-scheme report | Cursor contributor (other CLIs omit this transform) |

Workspace shells bind neither.

### Screen (pull + paint)

`TerminalObservationSeat.screen` exposes the existing probe port (`locateNeedle`, composer chrome, CR ACK, `syncDisplayGrid`).

`ScreenPainted` fires after every `engine.feed`. Full-screen paste/CR automation waits on `ScreenPainted` or a timeout, instead of only a fixed poll interval. Policy for *what* to ACK (composer prefix, `FullscreenCrAckStrategy`, input-readiness needles, paste settle) remains on `TerminalBehaviorCapability`.

A CLI may also bind a `TerminalScreenObserver` for custom grid detection (for example a future OpenCode status row). The probe is the only grid reader; observers do not scrape `TerminalEngine` internals.

## L1 scanners

| Scanner | Input | Event | Installed when |
|---|---|---|---|
| `OscTitleScanner` | output bytes | `OscTitle(String title)` | any `OscTitle` subscriber |
| `UserLineScanner` | original input bytes | `UserLineSubmitted(String line)` | any `UserLineSubmitted` subscriber |

Activity and launch-start are L0 modules (single consumer, stateful). They do not go through derived events.

Scanners are shared modules, not per-CLI copies. CLI-specific *interpretation* (Cursor title → waiting) is L2.

`OscTitleScanner` owns the existing `OscTitleExtractor` chunked state. `UserLineScanner` replaces `FirstUserLineCapture` / `EveryUserLineCapture` / turn-start capture only — one scan, three callbacks in `UserLineModule`. TeamBus intercept stays a **transform** and keeps its own filter (`BusUserLineCapture`) in this landing; unifying CSI strippers is a follow-up, not a requirement here.

## Session modules (always considered at CLI connect)

| Module | Binds | Notes |
|---|---|---|
| `ActivityObservationModule` | output observer (running) → existing `TerminalActivityTracker` | Seat still exposes `activityTracker` for coordination / boot-frame / idle. Tracker is no longer called from `feedPtyBytes`. |
| `LaunchStartModule` | output + `ProcessExited` while `spawning`/`confirming` | One module, same-chunk order: classify with `TerminalStartupFailureDetector`; on hit `seat.failLaunch`; otherwise `seat.confirmStarted`. Do not split classify and confirm into two observers — they would race on the same chunk. |
| `UserLineModule` | `UserLineSubmitted` | First line, every line, turn-start callbacks from `connect(...)`. Absent on workspace shell. |
| `TeamBusInterceptModule` | input transform order 100 | Only when `BusUserInputRouting` is supplied. Parks submissions as today. |

Workspace shell bind set: Activity + LaunchStart.

## CLI contributors

Installer: if connect has a launch CLI, every `TerminalObservationContributor` on that tool’s `capabilities` is bound.

### Cursor

`CursorTerminalBehavior` implements `TerminalObservationContributor`:

- Subscribe `OscTitle`. Apply the current rules: bare `"Cursor Agent"` is a no-op; titles containing `action required` / `permission` / `waiting` map to `AgentSeatAttention.waiting`; a non-native non-waiting title clears sticky waiting. Uses `seat.attention` + `seat.skipPermissions`. Logic moves out of `TerminalLaunchController`.
- Input transform order 200: `stripColorSchemeReport`.

### Other built-in CLIs

No observation contributor until they have a real PTY detector. They do not register no-op contributors.

## Bind order

Installer binds in this sequence:

1. Session modules in the table order above (Activity, LaunchStart, UserLine, TeamBus).
2. CLI contributors in `CliToolDefinition.capabilities` iteration order.

Output observers and input transforms then follow their own rules (phase filter; transform `order`). Bind sequence only ties equal transform orders and same-phase L0 observers.

## `TerminalBehaviorCapability` after the split

Keep:

- `supportsTurnInterrupt` / `interruptPlan`
- `usesFullScreenInput`
- `fullScreenPasteSettleDelay`
- `usesGridPasteAck`
- `pathDropBehavior`
- `fullscreenCrAckStrategy`
- `fullscreenComposerPrefix`
- `inputReadiness`
- `startupDeadline`

Delete:

- `bindTitleAttention`
- `forwardsColorSchemeReport`

`session_shell_connector` no longer reads a title-attention flag or calls `bindCursorTitleAttention`. SSH constraints and agent-status seat registration already run before `shell.connect` today; that stays. `connect(...)` receives the full seat inputs in one shot (session/member ids, CLI, attention cubit, skipPermissions, line callbacks, bus routing). The installer binds session modules + CLI contributors inside `connect`. There is no second bind API.

`CtrlCTurnInterrupt` stays as a policy helper, not an observer.

## Lifecycle

```text
connect / connectWorkspaceShell
  disconnect previous generation if any
  create bus (generation++)
  build seat (ids, cli or null, probe, attention, policy, fail/confirm)
  installer.bind(session modules + CLI contributors)
  beginStartup / spawnTransport

transport.output.listen
  bus.dispatchOutput → engine.feed → notifyPainted
  (startup fail/confirm are handlers, not extra code in the listen callback)

disconnect / dispose / failed teardown
  installer.unbind
  bus.dispose
  activityTracker.reset (as today)
```

`TerminalSession.connect` passes observation extras (line callbacks, bus routing, attention, skipPermissions, CLI) into the installer. It does not call `_inputPipeline.install(...)` or Cursor bind methods.

`TerminalUserInputPipeline` is deleted. Its parked-submission stream moves to `TeamBusInterceptModule` / the session facade.

## Data flow (Cursor CLI seat, representative)

```text
PTY bytes
  → ActivityObservationModule (if running)
  → OscTitleScanner (Cursor subscribed) → Cursor attention handler
  → LaunchStartModule (if starting): classify then confirm
  → engine.feed
  → ScreenPainted → fullscreen automation waiters / optional CLI screen observers

Keystrokes / compose inject (engine.output)
  → UserLineModule (original)
  → TeamBus intercept (order 100)
  → Cursor strip OSC 997 (order 200)
  → PTY write
```

## Error handling

- Each L0 observer, L1 scanner, L2 handler, and input transform runs in a try/catch. Failures log (`AppLogger`) and do not prevent `engine.feed` or remaining handlers.
- A throwing transform is skipped; the next transform receives the bytes the previous successful transform produced.
- `LaunchStartModule` is the only observation path to `failLaunch` during start. An exception inside that module logs and does not itself count as a classified startup failure.
- After `bus.dispose`, dispatch is a no-op. In-flight fullscreen waits see abort via the existing port `isAborted` path.
- Handlers must be synchronous on the output hot path. Async work is scheduled with the seat generation captured; completions no-op if generation changed.

## Performance

- No UTF-8 decode on output unless an installed scanner or module needs text (`OscTitleScanner`, `LaunchStartModule`). Activity fingerprint stays byte-only.
- One decode per input chunk shared by all text observers/scanners.
- L1 scanners exist only while subscribed.
- `ScreenPainted` is a wake-up, not a grid copy. Probe still `syncDisplayGrid` when a waiter actually reads cells.
- Fullscreen automation’s poll interval becomes a fallback timeout around `ScreenPainted`, not the primary wait. Paste ACK should land on the first paint that contains the needle, which is the UX win for SSH TUIs that paint slower than the old interval but faster than `pollTimeout`.

## Testing

Replace Cursor-titled launch-controller tests with bus + contributor tests.

Required coverage:

1. Output fan-out: two observers see the same chunk; a mutating observer cannot change what the next observer or `engine.feed` sees (`UnmodifiableUint8ListView`).
2. Handler isolation: throwing observer still feeds the engine and later observers.
3. Generation: dispatch after dispose / after reconnect does not call old handlers.
4. Lazy L1: no `OscTitle` subscriber → extractor not fed; Cursor contributor bound → titles delivered; unbind → stop.
5. Cursor attention rules (native title no-op, waiting, sticky clear) via contributor + fake seat, not launch controller.
6. Input order: observers see original; bus intercept (100) before OSC strip (200); empty transform result is not written.
7. User line still captured when bus parks the line.
8. Launch start: glibc / exec / CLI fatal text calls `failLaunch` and does not confirm; first healthy chunk confirms; both decisions happen on the same module for the same chunk.
9. Activity: no fingerprint during starting; running chunks update tracker; boot-frame / idle APIs unchanged for coordination tests.
10. Workspace shell: CLI contributors not bound; no user-line / bus / OSC strip.
11. Screen: `notifyPainted` after feed; automation waiter proceeds on paint without waiting the full interval when the needle is already visible.
12. Registry: `TerminalBehaviorCapability` no longer has the two deleted getters; Cursor tool still registers policy + contributor.

## Files (target)

Add:

- `client/lib/services/terminal/observation/` — bus, seat, installer, events
- `client/lib/services/terminal/observation/scanners/`
- `client/lib/services/terminal/observation/modules/`
- `client/lib/services/cli/registry/capabilities/terminal_observation_contributor.dart`

Change:

- `terminal_launch_controller.dart` — spawn/phase/timers/`engine.feed` only; observation via bus
- `terminal_session.dart` — installer at connect (attention passed in); delete Cursor bind + input pipeline
- `session_shell_connector.dart` — pass attention/skipPermissions into `connect`; delete title-attention flag branch
- `cursor/capabilities/terminal_behavior.dart` — implement contributor; drop flags
- other CLI `terminal_behavior.dart` — drop flags
- `terminal_behavior_capability.dart` — policy-only
- `fullscreen_pty_automation.dart` — wait on `ScreenPainted` + timeout
- `docs/cli-architecture.md` — observation plane + slim terminal behavior

Delete:

- `bindCursorTitleAttention` / `clearCursorTitleAttention`
- `TerminalUserInputPipeline` as a separate owner of captures (logic lives in modules)
- Launch-controller import of Cursor capability

Keep in place (called from modules/scanners, not deleted):

- `OscTitleExtractor`, `TerminalStartupFailureDetector`, `TerminalActivityTracker`, `stripColorSchemeReport`, `BusUserLineCapture` (or its filter extracted into the intercept module), fullscreen probe types

## Documentation

Implementation updates `docs/cli-architecture.md`:

- New optional infrastructure: `TerminalObservationContributor`
- `TerminalBehaviorCapability` description drops title attention / color-scheme forwarding
- Explicit rule: PTY detect/scan/listen goes through the observation plane; never `if (cli == …)` in `TerminalLaunchController`

## Out of scope for this spec’s implementation follow-ups

These are valid extensions of the same plane, not part of the first landing unless they fall out naturally:

- Additional CLI screen observers (OpenCode/Codex status rows)
- Merging `BusUserLineCapture`’s CSI stripper with `UserLineScanner`
- Moving the bus into Host Session Runtime (depends on that spec landing)

The interfaces in this document are the ones that work must not need to revisit for those follow-ups.
