# Session Launch Refactor Design

## Status

Approved design. This refactor may break internal and public-in-repository APIs; no backward-compatibility facade is required.

## Problem

Session launch behavior is split between `ChatCubit`, `SessionLaunchService`, `SessionLaunchBundle`, `SessionLaunchPipeline`, `SessionLaunchConnectPrepRunner`, `SessionMemberConnectScheduler`, `MemberConnectStage`, and `SessionShellConnector`.

The code has useful functional groupings, but the dependency direction is tangled:

- tab opening and member connection have separate asynchronous preparation paths;
- both paths eventually call `SessionShellConnector.connect()`;
- post-frame scheduling, duplicate-connect guards, pending markers, error handling, and cleanup are duplicated;
- `SessionLaunchService` is simultaneously a public facade, composition root, state adapter, and several delegate implementations;
- `SessionLaunchBundleDeps` and `SessionTabConnectPrepCallbacks` pass large collections of callbacks in both directions;
- `SessionLaunchBundle.create()` has a circular construction relationship between the materializer and pipeline.

The result is difficult to read and makes lifecycle changes prone to divergence between launch paths.

## Goals

1. Make the session launch entry point and execution flow obvious.
2. Ensure all member shell launches pass through one scheduling and execution path.
3. Remove duplicated post-frame, pending, validity, error, and cleanup logic.
4. Separate launch intent, tab surfacing, scheduling, runtime preparation, and shell attachment.
5. Keep runtime provisioning concerns such as runtime plans, workspace provisioning, manifests, SSH, and CLI configuration in their existing infrastructure layer.
6. Preserve user-visible launch behavior unless the existing behavior is demonstrably a bug.
7. Because compatibility is explicitly out of scope, remove obsolete internal APIs and composition layers instead of keeping adapters.

## Non-goals

- Rewriting `SessionConnectOrchestrator` or the manifest/provisioning subsystem.
- Changing the UI or launch preferences.
- Replacing the existing session lifecycle state model with a global event-sourced state machine.
- Adding new launch modes.

## Target architecture

```text
ChatCubit
  -> SessionLaunchService              public facade
    -> SessionLaunchCoordinator        create/open/select intent
      -> SessionTabSurfaceCoordinator  tab registration and activation
      -> SessionConnectScheduler       queue, dedupe, post-frame
        -> SessionConnectExecutor      one connection workflow
             -> SessionConnectOrchestrator
             -> lifecycle gate
             -> SessionShellConnector
```

### `ChatCubit`

`ChatCubit` remains the application-facing state owner. Its launch methods should be thin calls into `SessionLaunchService`; it should not contain a second launch implementation.

### `SessionLaunchService`

The service becomes a thin facade for the public session-launch operations. It adapts application state ports and forwards intent to the coordinator. It no longer assembles a callback-heavy bundle or implements the low-level shell connector delegate.

### `SessionLaunchCoordinator`

Add a coordinator under `services/launch` for intent-level operations:

- create a provisional session;
- open or reuse a session tab;
- choose the target team/member;
- materialize a default session when needed;
- construct a `SessionConnectJob` when a connection is requested.

It owns no PTY and no post-frame scheduling.

### `SessionConnectJob`

Add an immutable job value carrying the complete connection context:

- tab and session;
- workspace and optional team/member;
- launch generation;
- whether the session is newly staged;
- view-preservation intent;
- launch reason.

The job is the only input required by the scheduler/executor boundary. Personal and team launches use the same job shape; their differences remain in the resolved team/member and runtime strategy.

### `SessionConnectScheduler`

Create one scheduler responsible for:

- same-session/member de-duplication;
- pending markers;
- pre-session materialization serialization;
- post-frame execution;
- dropping jobs whose tab or generation is no longer valid.

It must not perform runtime provisioning or call `SessionShellConnector` directly.

### `SessionConnectExecutor`

Create one executor responsible for the common workflow:

```text
persist session if needed
  -> ensure launch readiness
  -> resolve team/member/CLI
  -> install team runtime when needed
  -> acquire or reuse shell
  -> prepare runtime through SessionConnectOrchestrator
  -> pass lifecycle gate
  -> attach shell through SessionShellConnector
```

The executor is the only component allowed to invoke `SessionShellConnector.connect()` after migration.

### Existing components

- `SessionTabSurfaceCoordinator`: only registers/reuses tabs, activates them, sets preview/view state, and notifies the workbench.
- `MemberConnectStage`: reduced to selecting/materializing the target and producing a job; it no longer owns a second connect algorithm.
- `SessionMemberConnectScheduler`: replaced by the unified scheduler after its useful de-duplication behavior is migrated.
- `SessionLaunchConnectPrepRunner`: its common preparation steps move into the executor and the class is removed.
- `SessionConnectOrchestrator`: retained as runtime preparation infrastructure.
- `SessionShellConnector`: retained as the low-level attachment adapter; its broad provider/SSH/MCP responsibilities are not part of this refactor.
- `SessionLaunchPipeline` and `SessionLaunchBundle`: removed after all callers migrate. They are currently a dispatcher and callback composition root rather than meaningful domain boundaries.

Composition of the launch graph moves to `launch_factory.dart` or the app composition root. It must construct concrete collaborators directly or through narrow typed ports rather than a large callback record.

## Data flow

### Create session

```text
SessionCreateRequest
  -> build provisional AppSession
  -> register ChatTab and notify workbench
  -> create SessionConnectJob when connect is requested
  -> SessionConnectScheduler.enqueue
  -> SessionConnectExecutor.execute
```

The tab remains immediately visible. Persistence and connection remain asynchronous.

### Open existing session

```text
SessionOpenRequest
  -> hydrate document
  -> validate workspace/team/member
  -> surface or reuse tab
  -> create SessionConnectJob only when connection is requested
```

History-only opens stop after tab surfacing.

### Open a team member

```text
team + member
  -> find active tab or materialize default session
  -> create SessionConnectJob
  -> SessionConnectScheduler.enqueue
```

This path must use the same executor as session-open connection rather than directly implementing its own preparation and attachment sequence.

## Error and cancellation semantics

### User-visible failures

Executor failures such as missing workspace/member, CLI failure, SSH failure, provisioning failure, or lifecycle rejection are converted to the existing session launch error state. Services do not show Toasts or construct localized UI messages. Diagnostics continue through `AppLogger`.

### Newly staged session failures

If a provisional tab has already surfaced, retain it with `launchError` so Retry remains possible. If failure occurs before the provisional session can be persisted, or placement validation rejects the staged launch, roll back the tab and snapshot using the current `_rollbackStagedLaunch` semantics.

### Stale and user-cancelled jobs

Closed tabs, stale generations, duplicate-owned connects, and explicit Stop actions are silent cancellations. They must clear pending/connect tokens and close temporary remote planes where necessary, without producing a user error.

### Cleanup invariant

The executor owns the single `try/catch/finally` boundary for a connection job:

```text
begin connect
  -> execute
  -> fail or succeed
  -> always clear pending markers, connect tokens, temporary remote resources
```

This consolidates the current scattered calls to `finishSessionConnect`, pending-member removal, agent-status cleanup, remote-plane cleanup, and `updateTabRunning`.

## Migration plan

1. Add `SessionConnectJob`, unified scheduler, and executor without changing runtime provisioning.
2. Move the shared persist/readiness/member-resolution/team-runtime/shell-acquisition steps into the executor.
3. Route the tab-open path through the unified scheduler and executor.
4. Route the member-connect path through the same scheduler and executor.
5. Move composition out of `SessionLaunchService` and remove callback records where typed ports are sufficient.
6. Reduce `SessionLaunchService` and `ChatCubit` to facade/state-owner responsibilities.
7. Delete `SessionLaunchBundle`, `SessionLaunchPipeline`, `SessionLaunchConnectPrepRunner`, and the old duplicate scheduler implementation.
8. Update tests and integration harnesses to the new APIs. No compatibility adapters are required.

## Testing strategy

Cover both unit and integration behavior for:

- personal and team session creation;
- history-only open and immediate-connect open;
- existing-tab reuse;
- single-member and all-member launch;
- duplicate same-member connect and concurrent different-session connect;
- tab close and generation invalidation during preparation;
- persistence, readiness, provisioning, SSH, and lifecycle-gate failures;
- retry after failure;
- mixed-workspace placement rejection and provisional rollback;
- remote-plane cleanup and pending/connect-token cleanup.

Tests should assert state and resource outcomes, not implementation details:

```text
tab presence
session snapshot presence
pending/connect state
launch error
shell state
remote-plane state
```

Use constructor injection and existing fakes. Run the repository test wrapper, never direct `flutter test`:

```bash
cd client
flutter analyze --no-fatal-infos --no-fatal-warnings
dart run tool/run_tests.dart <focused test file>
dart run tool/run_tests.dart
```

## Acceptance criteria

- There is one documented session-launch entry path from `ChatCubit` to the launch coordinator.
- There is exactly one production path that schedules and executes `SessionShellConnector.connect()`.
- No production launch code has duplicate post-frame connect/error/cleanup implementations.
- `SessionLaunchService` no longer constructs a large callback bundle or implements unrelated low-level delegates.
- `SessionLaunchPipeline` and `SessionLaunchBundle` are removed.
- Existing launch behavior and failure semantics are covered by focused tests and the full test suite passes.
