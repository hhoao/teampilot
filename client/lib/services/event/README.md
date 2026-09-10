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
`WorkspaceFsChangedEvent` (`WorkspaceFsKind`), and the catalog mutations
relayed by `CatalogMutationBus` (vocabulary unchanged; the bus forwards to the
dispatcher internally and back-fills its existing `Stream` API, so existing
subscribers were untouched).

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
