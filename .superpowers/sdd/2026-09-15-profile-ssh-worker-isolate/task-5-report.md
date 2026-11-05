# Task 5 report — worker member and PTY lifecycle hardening

## Status

Task 5 final review P1 is fixed. The production member session, PTY paths, and
non-PTY process handles use primitive worker proxies; the existing direct
dartssh2 adapter remains only for injected test seams.

## Implemented

- Worker-owned PTY output now uses `SshWorkerPtyPump`, which drains paused
  output after session completion, sends exactly one ordered final event, and
  lets close await the same completion future.
- UI member transport buffers output/final events that arrive before the
  `openPty` reply, rejects a channel opened after member close, and preserves
  normal final output/done behavior during PTY and member teardown.
- PTY proxy validates output sequence numbers and treats output ACKs as
  best-effort, so an ACK racing final event/worker cleanup cannot become an
  unhandled async error.
- `SshClientFactory.startProcess` now starts a worker exec channel that returns
  before the command exits and forwards separate stdout/stderr events until a
  final event closes the handle.
- `killMemberExec` calls `SSHSession.kill(SSHSignal.KILL)` in the worker and
  falls back to closing the session if the remote implementation rejects the
  signal.
- Exec events are sequence-numbered and buffered while the start reply is in
  flight. Streaming stdout/stderr is chunked only at the protocol frame limit;
  it has no cumulative 1 MiB cap and never self-kills on long output. The 1 MiB
  limit remains in the aggregate `runMember`/result DTO path.
- Regression coverage verifies first stdout before exit, stderr forwarding,
  KILL dispatch, protocol round-tripping, and streaming output beyond 1 MiB
  without a remote KILL.
- The existing narrow reverse-tunnel seam is retained for compatibility; the
  full worker/event-transport reverse-tunnel migration remains Task 6.

## Verification

```text
cd client && dart format \
  lib/services/ssh/ssh_client_factory_narrow_operations.dart \
  lib/services/ssh/worker/ssh_worker_protocol.dart \
  lib/services/ssh/worker/ssh_worker_exec_pump.dart \
  lib/services/ssh/worker/ssh_worker_exec_proxy.dart \
  lib/services/ssh/worker/ssh_worker_member_core.dart \
  lib/services/ssh/worker/ssh_profile_worker.dart \
  lib/services/ssh/worker/ssh_worker_member_session.dart \
  test/services/ssh/worker/ssh_worker_protocol_test.dart \
  test/services/ssh/ssh_client_factory_worker_test.dart \
  test/services/ssh/worker/ssh_worker_member_core_test.dart \
  test/services/ssh/worker/ssh_worker_member_session_test.dart \
  test/cubits/chat/chat_tab_remote_plane_test.dart
Formatted 12 files (0 changed)

cd client && dart run tool/run_tests.dart \
  test/services/ssh/worker/ssh_worker_member_session_test.dart \
  test/services/ssh/worker/ssh_worker_output_batcher_test.dart \
  test/services/terminal/ssh_pty_transport_test.dart \
  test/services/terminal/terminal_transport_factory_test.dart \
  test/services/ssh/ssh_client_factory_worker_test.dart \
  test/services/ssh/worker/ssh_worker_member_core_test.dart \
  test/services/ssh/worker/ssh_worker_protocol_test.dart \
  test/cubits/chat/chat_tab_remote_plane_test.dart
00:06 +39: All tests passed!

cd client && dart analyze \
  lib/services/ssh/ssh_client_factory_narrow_operations.dart \
  lib/services/ssh/worker/ssh_worker_protocol.dart \
  lib/services/ssh/worker/ssh_worker_exec_pump.dart \
  lib/services/ssh/worker/ssh_worker_exec_proxy.dart \
  lib/services/ssh/worker/ssh_worker_member_core.dart \
  lib/services/ssh/worker/ssh_profile_worker.dart \
  lib/services/ssh/worker/ssh_worker_member_session.dart \
  test/services/ssh/worker/ssh_worker_protocol_test.dart \
  test/services/ssh/ssh_client_factory_worker_test.dart \
  test/services/ssh/worker/ssh_worker_member_core_test.dart \
  test/services/ssh/worker/ssh_worker_member_session_test.dart \
  test/cubits/chat/chat_tab_remote_plane_test.dart
No issues found!

git diff --check
passed
```

The late-ACK regression was first run against the partial and failed with
`SshWorkerMemberException(channel_not_found)`; it passes after the
best-effort ACK handling fix.

## Final review P1 follow-up

Changed `ssh_worker_exec_pump.dart` so streaming `startProcess` forwards all
output in protocol-sized frames without `_capturedBytes` or an automatic KILL.
The focused Task 5 suite passed with 39 tests, the changed files pass `dart
analyze`, and `git diff --check` passed. Full `dart run tool/run_tests.dart`
was started but stopped after about 7,673 tests because it had accumulated
five failures in unrelated areas; none were in the focused SSH worker tests.
