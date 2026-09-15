# Profile-Scoped SSH Worker Isolate Design

## Goal

Move the complete SSH protocol and remote I/O lifecycle for one SSH profile
into a long-lived worker isolate. The UI isolate keeps a small facade and
continues to own Flutter state, host-key prompts, credential/plugin bridges,
and terminal rendering.

The design targets three related problems:

- UI jank while SSH protocol, SFTP, or remote-session processing is active;
- terminal output bursts that cause excessive UI callbacks and rebuild pressure;
- large or concurrent SFTP operations that currently compete with UI work.

The worker is scoped to an SSH profile, not to one `SSHClient`. It owns one
profile's storage connection and any number of member/session connections.

## Current constraints

`SshClientFactory` currently owns a pooled storage `SSHClient`, separate member
clients, SFTP clients, handshake limiting, host-key verification, connection
events, and close/reconnect interactions. `SshMemberSession` and
`SshPtyTransport` expose dartssh2 objects directly to callers. `RemoteFileStore`
also reads some files into one in-memory byte array.

The migration must preserve these higher-level behaviors:

- storage and member/session planes remain distinct logical uses;
- profile-level close, keepalive, reconnect, and user-disconnect policy remains
  authoritative;
- host-key verification and credential access continue to use the existing
  repositories and user prompt flow;
- tests can continue to use injected connectors/fakes without opening real
  network connections by default.

## Non-goals

- one isolate per TCP connection;
- moving xterm/Flutter rendering out of the UI isolate;
- changing SSH algorithms or the dartssh2 protocol implementation;
- replacing the existing profile reconnect policy;
- using an isolate as a substitute for terminal-output batching or SFTP
  backpressure;
- introducing a new plugin/platform-channel dependency inside the worker.

## Architecture

### UI-side manager and facade

`SshProfileWorkerManager` is created by application bootstrap and injected into
`SshClientFactory`. It maintains a map keyed by `SshProfile.id` and owns the
worker lifecycle:

1. create a worker on the first operation for a profile;
2. send immutable profile connection data and a worker bootstrap port;
3. reuse the worker for storage, exec, SFTP, and member session operations;
4. maintain consumer/reference counts and a bounded idle shutdown timer;
5. explicitly shut down workers during profile disconnect, profile removal, or
   application teardown.

`SshClientFactory` remains the public application-facing facade during the
migration. Its existing methods delegate to a profile worker transport rather
than exposing worker internals. Callers do not receive `SSHClient`,
`SftpClient`, or `SSHSession` instances in production code after migration.

### Worker isolate

`SshProfileWorker` runs in a dedicated isolate with a named debug isolate such
as `ssh-profile-worker:<profileId>`. It owns:

- the resolved socket target and all `SSHSocket` instances;
- the pooled storage `SSHClient` and SFTP channel;
- member/session `SSHClient` instances keyed by member/session id;
- PTY channels and their stdout/stderr subscriptions;
- per-request cancellation, stream state, and bounded output queues;
- worker-local transport lifecycle observation.

The worker has no Flutter widget, Cubit, repository, or platform-channel
dependency. It uses pure Dart and injected worker ports for external decisions.

### Serializable boundary

Messages crossing the isolate boundary use explicit DTOs only. They contain
request ids, profile/member/channel ids, strings, numbers, booleans, lists/maps
of primitive values, error records, and binary chunks. Large binary chunks use
`TransferableTypedData` where supported. No dartssh2 object, socket, repository,
`BuildContext`, or arbitrary callback crosses the boundary.

The boundary is split into three small contracts:

- `SshWorkerCommand`: request/response operations such as connect, exec,
  SFTP metadata, read/write chunk, open PTY, resize, input, and close;
- `SshWorkerEvent`: connection state, host-key challenge, output chunk, exit,
  progress, and transport-close events;
- `SshWorkerReply`: request success, structured failure, cancellation, and
  stream completion.

Every request has a `requestId`. Long-lived PTY/SFTP transfers additionally
have a `streamId`, allowing independent cancellation and cleanup.

## Data flow

### Connection and authentication

The UI manager sends a serializable profile snapshot and asks the worker to
connect. The worker opens the socket and starts the dartssh2 client. When host
key verification or credential material is required, it sends a challenge to
the UI facade and awaits a one-shot reply. The UI facade invokes the existing
known-host repository, credential store, and prompt callback, then returns only
the decision or required secret material.

Successful authentication is reported as a profile worker state. The existing
storage/member plane distinction is represented by worker-owned handles rather
than separate UI-owned clients.

### Exec and SFTP

Short exec requests return a bounded result DTO containing stdout/stderr,
exit code, and exit signal. SFTP metadata operations remain request/response
calls. File content uses chunked streams:

- reads emit bounded chunks and a completion event;
- writes accept bounded chunks with an explicit acknowledgement window;
- the worker pauses remote reads when the UI-side consumer has exhausted its
  window;
- cancellation closes the remote file handle and removes stream state.

`RemoteFileStore` keeps its path, retry, and filesystem semantics while its
transport implementation changes from direct `SftpClient` calls to the proxy.
Large-file helpers must not call an unbounded `readBytes()` across the public
transport boundary.

### PTY and terminal output

The worker opens the remote PTY and owns the `SSHSession`. Input, resize, and
close commands flow from the UI proxy to the worker. stdout and stderr are
merged in the worker and emitted as output frames.

Output is coalesced by both time and size: flush at a small frame interval
(initial target 8–16 ms) or when the byte limit is reached. The UI writes one
frame at a time to the existing terminal transport. This reduces per-event
work without adding an unbounded latency to interactive input.

The worker's queue is bounded. If the UI cannot consume output, the worker
applies backpressure rather than allowing isolate messages and terminal state
to grow without limit.

## Error and lifecycle behavior

Worker startup failure is a local worker error and does not automatically
trigger remote reconnect. Authentication, host-key, and network failures are
mapped back to the existing SSH error categories.

When a worker transport closes unexpectedly:

1. fail all pending requests and complete all output/file streams with the
   same structured close cause;
2. notify the UI facade once for the profile;
3. let `SshProfileConnectionCoordinator` apply the existing coalescing and
   reconnect policy;
4. keep the worker object invalid until a fresh worker generation is ready.

User disconnect, profile removal, host identity invalidation, and runtime
context eviction send an explicit shutdown command. The worker stops accepting
new requests, closes PTYs/SFTP/SSH clients, reports completion, and exits. A
shutdown timeout forcefully terminates the isolate after all safe cleanup has
been attempted.

Worker generations prevent stale replies from an old worker from completing a
request on a newly created worker. Every proxy stores the generation and
ignores mismatched events after teardown.

## Migration plan

The implementation is incremental:

1. Define DTOs, command/event codecs, worker state, and an injectable worker
   launcher. Add protocol unit tests without changing production SSH behavior.
2. Add the profile worker manager and a direct-mode adapter so existing tests
   can exercise the facade without spawning an isolate.
3. Migrate storage connect/probe/exec/SFTP operations behind the proxy. Add
   chunked read/write and preserve current retry and close semantics.
4. Migrate member sessions and PTY operations. Replace direct dartssh2 types in
   `SshMemberSession`/`SshPtyTransport` with proxy channel types.
5. Remove production-only direct dartssh2 ownership from UI-facing services;
   retain explicit testing seams where a fake transport is more useful than a
   real worker.
6. Add performance capture and compare worker mode against the direct-mode
   baseline before making worker mode the only production path.

No unrelated SSH algorithm, storage-layout, or terminal UX change belongs in
this migration.

## Testing strategy

### Unit tests

- DTO encode/decode, request ids, stream ids, and malformed-message handling;
- worker manager reuse, idle shutdown, reference counting, and generation
  guards;
- fake worker command handling, cancellation, backpressure, and pending
  request failure;
- host-key/credential challenge round trips;
- storage and member close/reconnect event mapping;
- terminal output coalescing and maximum queue bounds;
- SFTP chunk acknowledgements and cancellation.

### Integration tests

Use the existing Docker SSH and embedded SSH test infrastructure to verify:

- real profile worker login and host-key acceptance;
- pooled storage SFTP read/write and reconnect behavior;
- multiple member PTYs under one profile worker;
- terminal input, resize, output, exit, and disconnect;
- large-file chunked transfer without an unbounded buffer.

### Performance acceptance

Capture comparable scenarios before and after migration:

- sustained high-volume PTY output;
- concurrent SFTP reads/writes;
- several member sessions on one profile;
- cold connect and reconnect;
- app memory with idle and active workers.

Record UI frame p50/p95/p99, janky-frame count, terminal bytes per second,
SFTP bytes per second, connection latency, pending-message high-water mark,
and active worker/isolate count. The migration is successful only if UI jank
decreases in the target scenarios without unacceptable latency, throughput, or
memory regression.

## Risks and mitigations

- **Message-copy overhead:** use bounded binary chunks and
  `TransferableTypedData`; do not send one message per byte or terminal token.
- **Plugin access from worker:** keep platform-channel and secure-storage
  operations behind UI-side challenge RPCs.
- **Reconnect races:** use profile worker generations and preserve the existing
  coordinator's serialized reconnect behavior.
- **Isolate leaks:** reference count consumers, use idle shutdown, and verify
  worker exit in tests and DevTools.
- **Hard-to-debug failures:** attach profile id, worker generation, request id,
  plane, and stream id to `AppLogger` diagnostics; never log private keys or
  credential contents.
- **Unchanged bottleneck in xterm:** treat output batching and terminal rebuild
  reduction as a first-class part of the migration rather than assuming the
  worker alone solves rendering jank.
