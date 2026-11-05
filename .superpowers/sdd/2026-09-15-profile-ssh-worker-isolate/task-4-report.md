# Task 4B2 review follow-up — storage operation deadlines

## Status

Complete for the 4B2 review findings. The worker storage transport, client, and
facade now accept caller deadlines for connect/run, metadata/path operations,
and every SFTP stream open/read/write/ack/close/cancel request. Each lease
request carries `timeoutMs` to the worker and has a UI-side timeout; timed-out
stream requests best-effort cancel their stream, while the factory evicts the
affected worker storage connection. `storageFor(timeout:)` passes the timeout
into both the transport and storage client.

The Docker CLI install and mixed-team harness no longer call raw
`clientForStorage()`; they use `runnerForStorage` and `runOnStorage`. The only
remaining `clientForStorage()` references under `client/lib` are the injected
legacy compatibility seam and its internal helper calls.

## Verification before integration run

```text
cd client && dart format \
  lib/services/ssh/worker/ssh_worker_storage_client.dart \
  lib/services/ssh/ssh_client_factory_storage.dart \
  lib/services/storage/remote_file_store.dart \
  test/services/ssh/ssh_client_factory_worker_test.dart \
  test/services/ssh/worker/ssh_worker_storage_client_test.dart \
  test/services/storage/remote_file_store_test.dart \
  test/integration/remote_cli_install_docker_test.dart \
  test/integration/support/mixed_team_integration_harness.dart
Formatted 8 files (0 changed)

cd client && dart analyze \
  lib/services/ssh/worker/ssh_worker_storage_client.dart \
  lib/services/ssh/ssh_client_factory.dart \
  lib/services/ssh/ssh_client_factory_storage.dart \
  lib/services/storage/remote_file_store.dart \
  test/services/ssh/ssh_client_factory_worker_test.dart \
  test/services/ssh/worker/ssh_worker_storage_client_test.dart \
  test/services/storage/remote_file_store_test.dart \
  test/integration/remote_cli_install_docker_test.dart \
  test/integration/support/mixed_team_integration_harness.dart
No issues found!

cd client && dart run tool/run_tests.dart \
  test/services/ssh/worker/ssh_worker_storage_client_test.dart \
  test/services/ssh/ssh_client_factory_worker_test.dart \
  test/services/storage/remote_file_store_test.dart
00:06 +27: All tests passed!

git diff --check
passed
```

The focused regression includes caller timeout propagation, UI-side timeout,
best-effort stream cancellation, factory timeout injection, and the bounded
RemoteFileStore tracked-operation timeout. Docker integration verification is
run after the review-fix commit and will be recorded below.

# Task 4B2 report — finish storage caller migration

## Status

Complete as a follow-up to commit `a7efb4dfe`; the production cutover itself
was not rewritten. This follow-up keeps the direct dartssh2 factory methods
only as an injected-connector test seam and extracts that seam into
`ssh_client_factory_legacy_storage.dart`. No production caller under
`client/lib` invokes `clientForStorage` or `sftpFor`.

The remaining uncommitted changes were all necessary follow-up work, not a
draft experiment:

- Split the legacy compatibility seam from the worker-backed factory so the
  factory remains reviewable and existing direct-connector tests keep their
  contract.
- Route coordinator readiness and reconnect through
  `ensureStorageConnected`; injected connector tests therefore stay on the
  legacy seam while production uses the profile worker.
- Mark member process/forward teardown as intentional before disconnect, and
  suppress best-effort cleanup errors after the process result is available.
- Add focused range-read, chunk-splitting, and caller-timeout coverage.

## Verification

```text
cd client && dart analyze \
  lib/services/host/process_run_handle.dart \
  lib/services/ssh/ssh_client_factory.dart \
  lib/services/ssh/ssh_client_factory_legacy_storage.dart \
  lib/services/ssh/ssh_client_factory_narrow_operations.dart \
  lib/services/ssh/ssh_forward_channel.dart \
  lib/services/ssh/ssh_profile_connection_coordinator.dart \
  lib/services/ssh/worker/ssh_worker_storage_client.dart \
  test/services/ssh/ssh_client_factory_worker_test.dart \
  test/services/ssh/worker/ssh_worker_storage_client_test.dart
No issues found!

cd client && dart run tool/run_tests.dart \
  test/services/ssh/ssh_client_factory_worker_test.dart \
  test/services/ssh/worker/ssh_worker_storage_client_test.dart \
  test/services/ssh/ssh_profile_connection_coordinator_test.dart \
  test/services/ssh/ssh_transport_close_test.dart
00:01 +37: All tests passed!

git diff --check
passed
```

Changed production analysis was run with `dart analyze` over the factory,
storage pool/worker, process, forward, and coordinator files. It reported no
warnings or errors; one existing `curly_braces_in_flow_control_structures`
info remains in unchanged `ssh_worker_storage_types.dart`.

The required full Flutter analysis and repository test suite remain the final
pre-commit checks.

# Task 4A report — worker storage protocol core

## Status

Complete for the Task 4A review-fix scope, including the final re-review fixes.
Storage transfers now own an
independent worker stream from open through close/cancel, including repeated
transfers of the same path. The profile worker has one storage dispatcher:
`SshWorkerStorageCore` and its worker-local backend; the partial direct SFTP
dispatcher and its fields/imports were removed. No dartssh2 object crosses the
worker lease boundary.

## Implemented

- Primitive storage DTOs for binary chunks, exec results, file stats, directory
  entries, and sanitized transport failures.
- Protocol enum wiring for connect, exec, metadata, stream open/read/write,
  per-chunk ACK, cancel, close, and shutdown.
- Worker-side bounded read credits, write persistence ACKs, failed-chunk stop,
  stream cleanup, cancellation, shutdown cleanup, and transport timeout
  invalidation.
- Production lease transport plus storage facade for connect/exec/stat/list,
  path operations, bounded concurrent reads, and acknowledged writes. Each
  read/write transfer has a fresh stream ID and a best-effort cancel if open
  returns a malformed result.
- Storage DTO decoders reject malformed field types with `FormatException`;
  transfer chunk/window limits are enforced at runtime in both client and
  worker core.
- Focused tests for the concurrent read window, normal/error/callback/cancel
  cleanup, failed writes, repeated same-path transport lifecycles, protocol
  stream ACK/cancel/close behavior, binary DTO use, unsafe limits, bounded
  cleanup with original-error preservation, and invalid-first-request recovery.
- The worker now replies to every invalid first storage request without caching
  a rejected backend; a later valid `connectStorage` can initialize the core.
- Malformed storage request wires with a recoverable `requestId` now receive an
  `invalid_storage_request` failure reply instead of being silently dropped.
- Storage connect validates the profile schema, worker profile ownership, and
  dial target before creating or caching a storage core.
- Storage `stderr`, `directory`, and `append` arguments accept only booleans or
  their documented defaults.
- Storage close/cancel cleanup is best-effort and bounded by a timeout, so a
  cleanup failure cannot replace the original transfer or callback error.
- First `connectStorage` initialization is shared through one in-flight Future;
  concurrent connects reuse the same worker-held core, and shutdown waits for
  initialization before closing that core. Failed validation or connection
  initialization is cleared and does not poison later valid connects.
- `_open` validates every argument, including `append`, before registering its
  stream state or idle timer; invalid opens therefore leave no reusable stream
  reservation behind.

## Verification

```text
cd client && dart run tool/run_tests.dart \
  test/services/ssh/worker/ssh_worker_protocol_test.dart \
  test/services/ssh/worker/ssh_worker_storage_client_test.dart \
  test/services/ssh/worker/ssh_worker_storage_core_test.dart \
  test/services/ssh/worker/ssh_profile_worker_storage_dispatch_test.dart
00:00 +32: All tests passed!

cd client && dart analyze lib/services/ssh/worker
10 info issues, 0 warnings or errors

cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
496 existing issues remain elsewhere in the repository, including unresolved
`package:test` matcher errors in prior worker manager tests; no error was
reported in the changed worker production/test files.

The required full-suite verification was started before this commit. It had
reached 2,864 tests with 3 existing failures in unrelated repository/SSH
tests when the fix was committed; the process was still running at handoff.

git diff --check
passed
```

The full repository suite was not run because this subtask is limited to the
worker storage core and the repository contains unrelated existing analysis
errors in prior worker tests and another SSH test. No caller, factory, or
`RemoteFileStore` migration was included.

# Task 4B1 report — factory storage ownership

## Status

Complete for the factory-layer scope. Production factory storage ownership now
uses one profile worker lease and `SshWorkerStorageClient`; the direct
dartssh2 connector and raw client compatibility methods remain test seams only.
`RemoteFileStore` and its callers were intentionally left for the next
subtask.

## Implemented

- Added a profile-scoped worker storage pool that owns leases, deduplicates
  openings, probes cached storage, handles host-identity changes, and retires
  storage on worker transport-close events.
- Routed `storageFor` and `runOnStorage` through `SshWorkerStorageClient` in
  production, adapting the worker run DTO back to `SSHRunResult` without
  exposing a worker-held `SSHClient`, `SftpClient`, or `SftpFile`.
- Preserved direct connector behavior as a compatibility test seam; raw
  `clientForStorage` and `sftpFor` calls reject production use when no direct
  connector was injected.
- Preserved `hasLiveStorageClient`, `storagePoolChanges`, `runTracked`,
  `disconnectProfile`, and `disconnectAll` behavior for both the worker path
  and legacy injected-connector tests.
- Worker disconnect removes pool visibility immediately, waits for tracked
  storage operations to drain, then shuts down the retired worker generation.
- Worker transport timeouts retain the existing `TimeoutException` behavior
  and evict the affected storage connection.
- Added focused factory tests for lease reuse, exec result adaptation,
  transport-close eviction, tracked-operation drain, raw-client seam guards,
  and timeout eviction.

## Verification before review commit

```text
cd client && dart format \
  lib/services/ssh/ssh_client_factory.dart \
  lib/services/ssh/ssh_client_factory_storage.dart \
  lib/services/ssh/worker/ssh_profile_worker_manager.dart \
  lib/services/ssh/worker/ssh_worker_storage_client.dart \
  test/services/ssh/ssh_client_factory_worker_test.dart \
  test/services/ssh/worker/ssh_worker_storage_client_test.dart \
  test/services/ssh/worker/ssh_profile_worker_manager_test.dart
Formatted 7 files (1 changed)

cd client && dart run tool/run_tests.dart \
  test/services/ssh/ssh_client_factory_worker_test.dart \
  test/services/ssh/worker/ssh_profile_worker_manager_test.dart
00:00 +14: All tests passed!

cd client && dart analyze \
  lib/services/ssh/ssh_client_factory.dart \
  lib/services/ssh/ssh_client_factory_storage.dart \
  lib/services/ssh/worker/ssh_profile_worker_manager.dart \
  lib/services/ssh/worker/ssh_worker_storage_client.dart
No issues found!

git diff --check
passed
```

The broader factory/worker focused set also passed with `+49` tests, including
the existing raw-connector pool/transport tests and Task 4A worker storage
tests. The full repository suite and full Flutter analysis remain to be run
after this review commit.
