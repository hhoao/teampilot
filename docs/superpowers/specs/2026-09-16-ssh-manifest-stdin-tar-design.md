# SSH Manifest Flush: stdin + Overlay Tar

## Goal

SSH session launch must apply the launch manifest without putting file
payloads in an `exec` command string. Large scripts and file trees travel as
`CHANNEL_DATA` on stdin. Off-home file bodies are an overlay tarball extracted
under the work app-data root, not hundreds of shell heredocs.

A personal Cursor session on `ssh:home-server` currently dies during
`manifest flush via ssh ops=612` with `EPIPE` / `ECONNRESET` because the
expanded script is sent as one SSH `exec` request (32KB max packet, plus remote
`ARG_MAX`).

## Current failure

`ManifestExecutor._flushViaSsh` builds a POSIX script (`mkdir`, `cat <<'DELIM'`,
`ln`, `cp`, `rm`) and passes the entire script to
`SshWorkPlaneScriptRunner.runScript` → `SshClientFactory.runOnStorage` →
`SSHClient.runWithResult(command)`. dartssh2 puts `command` in a single
`SSH_MSG_CHANNEL_REQUEST exec`. Off-home `expandCopies` turns ~100 staging ops
into 600+ `writeFile` heredocs. The TCP connection drops; `connectShell` fails;
profile reconnect may log success even though the session is still down.

Same-host flushes that only `cp -R` / `ln` stay small and happen to work. They
still go through the same unsafe `exec(script)` path.

## Design

### 1. stdin is the only transport for large payloads

Add a storage-plane exec that can attach stdin:

- `execute(command)` with a **short** command string (well under 1KB);
- write bytes to `SSHSession.stdin` (CHANNEL_DATA, windowed, 32KB packets);
- close stdin (EOF);
- wait for exit and collect stdout/stderr as today.

`SshClientFactory.runOnStorage` keeps today's no-stdin path for short probes
(`echo`, CLI locate, one-line `cp`). New `runOnStorageWithStdin` is used
whenever the payload is a script or tar stream.

`SshWorkPlaneScriptRunner.runScript` always runs `bash -s` with the script on
stdin. It never passes the script as the exec command. Cursor home passthrough
and any other `runScript` caller get the fix for free.

If `bash` is missing, fail the operation with a clear error (remote work plane
already assumes GNU-ish `ln -sfn` / `mkdir -p`). Do not fall back to
`exec(script)`.

### 2. Off-home file overlay is a tar stream, not heredocs

When `sourceFs` is not the work filesystem (off-home / cross-machine), SSH
flush does **not** expand copy trees into heredoc `writeFile` entries for the
wire format.

Walk the **unexpanded** manifest in order and split into epochs:

- **Payload** (accumulate into an in-memory overlay, last write per path wins
  inside the epoch): `ensureDir`, `writeFile`, `symlink`, and
  `copyFile` / `copyTree` whose bytes are read from `sourceFs`.
- **Mutation** (short POSIX script): `removeRecursive`, `rename`, and
  same-host `copyFile` / `copyTree` (source already on the work machine).

On each kind switch, flush the pending tar and/or script before starting the
next epoch. After the last entry, flush both.

The overlay is a virtual tree relative to `symlinkProjectionRoot` (the work
`appDataRoot` already passed into `flush`). It is **not** the whole TeamPilot
home directory and is **not** a local on-disk clone of the remote root unless
an implementation detail needs a temp dir (prefer `package:archive` in memory).

Tar members:

- file bytes from `writeFile` (UTF-8) or from `sourceFs` reads (raw bytes, so
  plugin/skill trees stay binary-safe);
- directories for empty `ensureDir`;
- symlink members with the manifest target string;
- GNU/pax headers so long session plugin paths are legal;
- gzip-compressed (`package:archive` already in pubspec).

Before extracting a tar epoch, the mutation script for that boundary also
`rm -rf` each symlink `linkPath` that the tar is about to create, matching
today's `rm -rf` then `ln -sfn` (leftover directories break extract).

Tar extract must **not** use `bash -s`: stdin is the gzip stream, so it cannot
also be the shell script. The exec command is a short pipeline (sshd runs exec
via `shell -c`; the string stays under 1KB):

```sh
gzip -dc | tar -x -C '<workAppDataRoot>'
```

Do not rely on GNU `tar -z`. Paths in the archive are relative to
`workAppDataRoot`. Reject members that are absolute, contain `..`, or would
escape the root. Payload paths outside that root stay in the stdin `bash -s`
script as heredocs (rare; still safe because stdin is CHANNEL_DATA).

Same-host SSH (`identical(sourceFs, targetFs)`): no tar. Keep today's small
`cp` / `ln` / `mkdir` / `rm` script, delivered via `bash -s` stdin.

Local/WSL flush is unchanged (`_flushLocal`).

### 3. Do not evict a busy storage client

`clientForStorage` keepalive probe must not evict the pooled client while
another storage op is in flight. Probe timeout during a multi-megabyte stdin
write is what logged `deferring close inFlight=2` on the second attempt.

Rule: if `_inFlight[profileId] > 1` when considering a cached client, skip the
ping probe and reuse the client. The first tracked caller may still probe.
Failed probes must not close a client that still has in-flight ops; existing
drain-on-evict stays for explicit disconnects.

### 4. Session reconnect failure is not profile success

`SessionShellConnector.connect` returns `ConnectShellResult.failed` without
throwing. `SessionSshProfileReconnect._reconnectPersonalTab` currently ignores
that and lets `SshProfileConnectionCoordinator` log `reconnect succeeded`,
which stops further attempts.

If connect returns `failed` or `aborted`, the session-plane callback must
surface failure (throw or equivalent) so the coordinator records reconnect
failure and the existing 1/5…5/5 backoff can retry. Storage may already be
live; a failed session plane still counts as a failed reconnect attempt.

## Data flow

```text
stage-session (local overlay / LaunchManifest)
  -> ManifestExecutor.flush (sshProfileId set)
       same-host: bash -s < small cp/ln script
       off-home:  for each epoch
                    bash -s < rm/mv/symlink-prep   (if any)
                    gzip|tar -x -C workRoot < overlay.tar.gz (if any)
  -> native plugin install / post-flush hooks (runScript also stdin)
  -> member PTY
```

## Logging

Keep `[session-launch] manifest flush via ssh ops=…`. Add stdin payload size
in bytes, epoch counts (script vs tar), and `manifest-flush done` (this line
was missing on the failing traces because flush never returned).

## Out of scope

- Packing the entire local TeamPilot root or workspace tree;
- Replacing workspace provision SFTP with tar;
- Per-file SFTP apply of the launch manifest;
- Changing dartssh2 max-packet for CHANNEL_REQUEST;
- History cold-load timing.

## Tests

- `runScript` / stdin exec: captured SSH exec command is `bash -s` (or the
  tar pipeline), never contains file bodies; stdin length matches the payload;
  a payload larger than 32KB is accepted by the fake session stdin path;
- off-home `copyTree` becomes tar members with raw bytes, not `cat >` heredocs;
- same-host flush still contains `cp -R` and is sent on stdin;
- tar members escaping `workAppDataRoot` are rejected;
- write-then-rm vs rm-then-write keep epoch order;
- symlink replace still deletes the leftover directory before extract;
- `clientForStorage` does not probe-evict when `_inFlight > 1`;
- personal SSH reconnect with `ConnectShellResult.failed` does not mark the
  profile reconnect as succeeded;
- existing `manifest_executor_ssh_test` cases updated for stdin + tar.
