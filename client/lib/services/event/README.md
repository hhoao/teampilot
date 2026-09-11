# `services/event/` — central event dispatching

A YARN-style central event layer for the app: producers **dispatch** an event
and return immediately; consumers register a handler **per event family**; a
single dispatcher delivers everything in global FIFO order. This package is a
port of Hadoop YARN's `org.apache.hadoop.yarn.event` package to Dart, and is
the foundation the upcoming Runtime daemon will be built on (session lifecycle
events exist here precisely so the runtime can later consume them).

Design spec: `docs/superpowers/specs/2026-09-10-central-event-dispatcher-design.md`.

## YARN mapping

| YARN `org.apache.hadoop.yarn.event` | This package |
|---|---|
| `Event<TYPE extends Enum>` | `DispatcherEvent<K extends Enum>` (`eventKind` + `timestamp`) |
| `EventHandler<T>` | `EventHandler<T extends DispatcherEvent>` (`handle(T event)`) |
| `Dispatcher` interface | `Dispatcher` (`dispatch` / `registerFamily` / `unregister`) |
| `AsyncDispatcher` | `AsyncDispatcher` (unbounded queue + single consume loop + per-family routing with multicast; `stop()` drains) |
| `EventDispatcher` (per-family convenience queue) | Not ported — a separate queue per family has no use case in a single-isolate app (YAGNI) |

Vocabulary is per-family, like YARN's per-domain `*EventType` enums: each
family ships its own sealed class + kind enum, and the dispatcher itself is
generic over families and knows no concrete vocabulary.

Current families: `SessionLifecycleEvent` (`SessionLifecycleKind`),
`WorkspaceFsChangedEvent` (`WorkspaceFsKind`), the catalog mutations
relayed by `CatalogMutationBus` (vocabulary unchanged; the bus forwards to the
dispatcher internally and back-fills its existing `Stream` API, so existing
subscribers were untouched), and `AgentPresenceEvent` (`AgentPresenceKind`).

## Family: `AgentPresence` (`agent_presence_event.dart`)

Reports one agent seat's **availability** — `booting` / `working` / `idle`,
mirroring the model enum `MemberAvailability` one-to-one. Seat identity is
`PresenceSeatKey` (sessionId + memberId), deliberately its own type rather than
`agent_runtime`'s `RuntimeSeatKey` so the event package keeps no dependency on a
feature package.

Producers push from two latches in the terminal layer:

- **Turn latch** — `TerminalSession.markUserTurnStarted` / `markUserTurnIdle`
  flip `_userTurnActive` and call the session's re-pointable
  `onPresenceInputsChanged` callback.
- **Boot-frame latch** — `TerminalActivityTracker` pushes the `isBootFrameReady`
  false→true edge through a **one-shot timer** re-armed on every `notePtyBytes`.
  The timer is required because `isBootFrameReady` is a *lazy* getter driven
  purely by elapsed time: with no further PTY bytes, nothing else would observe
  the `bootQuietAfter` / `bootMaxWait` deadline. The listener is attachable per
  bind (`setBootFrameListener`), so a tracker reused across reconnects can be
  detached and revived.

### The publish edge takes the computed value, not the projected one

`PresenceEventBridge` is the deduping edge: producers report a seat's current
availability on each poll recompute, and the bridge publishes an
`AgentPresenceEvent` only when the value differs from the last one reported (a
first report always publishes; a `null` report clears the baseline without
publishing, since connection is not part of this family).

The value fed to the bridge is the **authoritative computed availability**
(`MemberCoordination`'s result), **not** the projected value the cubit emits.
That is load-bearing: the projection is what the bridge's publishes feed, so
reporting the projected value back into the edge would make it self-referential
— the projection's first value would become its own input and the loop would
freeze, never observing a fresh computation. The computed value is ground truth;
the projection is a downstream cache of it.

### Consumer

`AgentPresenceProjection` reduces the family to `Map<PresenceSeatKey,
AgentPresenceKind>` and exposes `availabilityFor` / `snapshot` plus a broadcast
`changes`. `MemberPresenceCubit` reads `availabilityFor(seat)` for the
availability dimension each tick, while keeping the **connection** dimension
poll-derived; `changes` requests a recompute so a push refreshes the UI without
waiting for the next poll.

### One-hop latency (not a bug)

The production sink only *enqueues* on `AsyncDispatcher`, so the projection
observes a publish on a later turn of the consume loop. A tick that detects an
availability change therefore still reads the *previous* projected value and
emits it for that one hop; the projection's `changes` listener then requests the
recompute that emits the fresh value. Latency is bounded to that single
enqueue -> consume -> projection -> `changes` -> recompute hop, not a stuck
one-hop-behind state — a recompute is only dropped while another tick is
mid-flight, and that in-flight tick re-reads the already-updated projection
after its `await`.

### Deliberately out of this family (this phase)

- The **connection** dimension — still poll-derived and unchanged.
- The **`agent_runtime` hook events** (`statusReported` / `seatIdle`) — they
  carry a seat's per-seat working/idle **attention/status**, which
  `RuntimeEventProjection.attention` projects into `AgentAttentionCubit`;
  availability is not what they write today, but they are the other producer for
  this same availability dimension, so they converge in phase 2.5, not here.
- `TerminalActivityTracker.isWorking` (the PTY byte heuristic) — **not** one of
  this family's push triggers, but it is *not* irrelevant to availability
  either. `MemberCoordination.resolve` selects an availability strategy per
  seat, and its `nativeShellActivity` (`usesShellActivity`) and `mixed` paths
  choose `working` vs `idle` **directly from `isWorking`**, while the shell-latch
  (personal / native single-CLI) and Claude-roster paths use `userTurnActive` or
  the roster flag instead.

The availability dimension therefore has several coordination strategies behind
one `availability()` call, and only the two latches above *push* (the turn
latch's `userTurnActive` edge and the boot latch's `isBootFrameReady` edge). The
other inputs — `isWorking` in the shell-activity / mixed strategies, the
Claude-roster flag, and the connection dimension — remain **poll-derived** inside
the cubit's `MemberPresenceService.compute()` -> `MemberCoordination.resolve()`
recompute; this family does not push events for them.

## Deliberate deviations from YARN

- **A throwing handler is logged and skipped, not a process exit.** YARN's
  default `exitOnDispatchException=true` kills the process; a desktop app
  must stay alive, so one bad handler only loses its own delivery.
- **The queue is unbounded, with a depth warning (default 1000), not a bounded
  blocking queue.** YARN bounds its queue because producers are
  multi-threaded; in a single isolate a blocking dispatch would deadlock, so
  we warn on depth instead.
- **The interface getter is named `eventKind`, not `kind`.** Event payloads
  commonly carry their own domain-typed `kind` field (e.g.
  `CatalogMutationEvent.kind` is the catalog domain kind, a `String`), which
  would collide with a `kind` getter on the event interface.
- **`registerFamily` takes an explicit `Type` argument.** Dart generics are
  erased at runtime, so `K` cannot reify the family's kind enum type; the
  runtime family identity has to be the explicit `kindType` parameter.

## Onboarding a new event family

1. **Define the family**: a kind enum plus a sealed class implementing
   `DispatcherEvent<YourKind>` (see `session_lifecycle_event.dart` for the
   pattern: const factories per kind, `eventKind`/`timestamp` final fields).
2. **Publish**: get a `Dispatcher` reference and call `dispatch(event)` at the
   source. App-wide sources publish through the `EventPublisher.instance`
   injection bridge (attach happens once in `app_shell.dart`); components
   constructed with a dispatcher use it directly.
3. **Consume**: implement `EventHandler<YourEvent>` and register it with
   `dispatcher.registerFamily<YourKind>(YourKind, handler)` — the kind enum's
   `Type` is the family key, so one `registerFamily` call covers every kind in
   the enum.

## What does NOT belong here

- **Queries / request-response** (file listings, git status, ...): use the
  existing service interfaces — events carry only invalidation signals and
  fact broadcasts.
- **High-frequency byte streams** (PTY frames): they would drown the shared
  queue; they keep their own channels.
- **`agent_runtime/`** (`RuntimeEventEnvelope`, `SeatEventStream`,
  `AgentEventGateway`): its vocabulary and journal stay as-is for now; it will
  be migrated onto the dispatcher in a later phase.
