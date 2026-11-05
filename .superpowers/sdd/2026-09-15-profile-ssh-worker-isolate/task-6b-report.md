# Task 6B report — profile-scoped SSH worker forwards

## Scope

Implemented worker-owned local forwarding and reverse-tunnel proxies. Normal
`SshClientFactory` forwarding paths now lease the profile worker; raw dartssh2
clients, remote forwards, and forward channels remain worker-local. Injected
`memberReverseTunnelFactory` and connector-backed direct adapters remain
available only as test seams.

## Changed files

- `client/lib/services/ssh/worker/ssh_worker_protocol.dart`
- `client/lib/services/ssh/worker/ssh_worker_forward_pump.dart`
- `client/lib/services/ssh/worker/ssh_worker_forward_core.dart`
- `client/lib/services/ssh/worker/ssh_worker_forward_proxy.dart`
- `client/lib/services/ssh/worker/ssh_profile_worker.dart`
- `client/lib/services/ssh/ssh_client_factory.dart`
- `client/lib/services/ssh/ssh_client_factory_narrow_operations.dart`
- Focused forwarding, protocol, worker-dispatch, and pump tests under
  `client/test/services/ssh/`.

## Protocol and lifecycle decisions

Added primitive forward open/write/ack/close operations plus primitive remote
channel-open and forward-closed events. Byte events use bounded chunks,
monotonic per-channel sequences, and ACK-window flow control. The worker owns
the SSH client, `SSHRemoteForward`, `SSHForwardChannel`, subscriptions, and
their shutdown; UI proxies expose only `ReverseTunnel`, `TunnelChannel`, and
`SshForwardByteChannel` semantics. Local forward close closes its owning
forward session; reverse child channels and tunnel close are idempotent.
Worker close/error events finish matching proxies and release their profile
lease. Production factory paths do not call `createMemberClient` for forwards.

## Verification

Focused test command passed: 22 tests across forwarding factory routing,
reverse channel delivery/cleanup, local bytes/writes/failure/timeout,
event transport, protocol decoding, worker dispatch, and pump finalization.

`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings` completed
with 463 existing diagnostics and failed on an unrelated existing error:
`test/services/session/remote_ssh_launch_constraints_test.dart:585` passes an
undefined `launchSecurityPolicy` parameter. No analyzer errors were reported
from Task 6B files.

## Concerns

The repository-wide analyzer remains blocked by that unrelated test compile
error. No real SSH integration host was available in this task, so forwarding
transport behavior is covered by the primitive worker protocol and injected
worker launchers rather than a live SSH server.

## Round 1 fixes

Addressed review findings: forward and request IDs now come from the shared
worker-generation lease sequence; the forward pump queues and drains only
within its ACK window and drains pending bytes exactly once during close;
channel final frames carry primitive error codes and proxies surface them as
stream errors; factory reverse opens retain the session and recheck closure
after every await; and worker shutdown tracks and awaits in-flight forward
dispatches. Expanded forwarding coverage now has 27 passing tests, including
two simultaneous reverse tunnels, close/shutdown races, channel errors,
multi-chunk ACK behavior, and the injected tunnel seam.

The final analyzer still reports the same unrelated compile error at
`test/services/session/remote_ssh_launch_constraints_test.dart:585` for the
undefined `launchSecurityPolicy` parameter (465 total existing diagnostics).

## Round 2 fixes

Addressed the remaining review findings without widening the forwarding
surface. Forward dispatch futures are now registered in the worker's shutdown
barrier, and the forward core stops accepting registrations before teardown,
rechecks its stopped state after each asynchronous client/forward acquisition,
and closes newly acquired channels or remote forwards before disconnecting the
client. Forward IDs remain worker-generation unique; dead local-channel and
request-sequence state was removed from the UI proxy.

The shutdown regression now uses a faithful worker launcher that marks itself
stopping, waits for in-flight opens, rejects a late open, clears active forward
registrations, and only then acknowledges shutdown. The worker pump tests now
cover ACK-window ordering and input `onError` conversion to a primitive final
event with an error code; the forwarding test verifies that the UI proxy ends
with `SshWorkerForwardException` rather than normal completion. The injected
raw reverse-tunnel factory seam remains covered.

Round 2 verification passed: 11 focused forwarding/pump tests and 4 focused
worker-dispatch tests via `dart run tool/run_tests.dart`. Targeted analyzer
passed with no errors. The repository-wide command
`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings` still exits
1 on the unrelated pre-existing error
`test/services/session/remote_ssh_launch_constraints_test.dart:585`:
undefined named parameter `launchSecurityPolicy` (462 diagnostics reported).

## Round 2 concerns

No live SSH integration host was available; transport coverage remains based
on worker primitive adapters and faithful injected launchers. The full
repository analyzer remains blocked only by the unrelated error recorded
above.

## Round 3 fixes and final local verification

Closed the pending-close race: a close received before a local or remote
forward is registered is now remembered and awaited, and the worker closes
late-created channels/remote forwards and disconnects their client. The
forward core shutdown barrier covers the actual forward dispatches. Added
production-core tests using `SshProfileWorker` with injected worker-local
forward clients for close/open and shutdown/open races, plus an end-to-end
worker pump error-to-UI-proxy test. Removed obsolete proxy state.

The final focused command passed 15 forwarding/pump tests, and targeted
`flutter analyze --no-fatal-infos --no-fatal-warnings` passed with no issues.
The repository-wide analyzer remains blocked by the unrelated
`test/services/session/remote_ssh_launch_constraints_test.dart:585`
`launchSecurityPolicy` compile error.
