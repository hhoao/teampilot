# dartssh2: switch upstream to TerminalStudio

## Goal

Retarget `hhoao/dartssh2` (TeamPilot submodule) from `lollipopkit/dartssh2` to `TerminalStudio/dartssh2`, keep app-required patches, and port one low-risk lollipopkit improvement.

## Non-goals

- Port SFTP 16MB packet cap (app-layer concern)
- Default-enable AES-GCM / ChaCha
- Preserve lollipopkit merge history

## Base

- Upstream remote: `https://github.com/TerminalStudio/dartssh2.git` (`master`, currently 2.22.x)
- Keep `lollipopkit` as a secondary remote for archaeology only

## Patches on top of TerminalStudio

1. **`onKeepAliveFailed` / `onPingFailed`** — surface keepalive ping failures so TeamPilot reconnect can run. Preserve TerminalStudio’s overlapping-ping guard (`_isPinging`); call the callback instead of swallowing errors.
2. **`await cancelForwardRemote` in `SSHRemoteForward.close`** — `Future<void> close()` with idempotent guard; TeamBus reverse tunnel already awaits close.
3. **TCP `noDelay`** — `SocketOption.tcpNoDelay = true` in native socket connect.

## TeamPilot follow-ups

- Host-key fingerprint bytes are OpenSSH `SHA256:<base64>` (UTF-8) since TerminalStudio 2.18; trust-store display/compare may need a small adaptation; existing MD5-era pins will re-prompt once.
- Bump submodule pointer after fork push.

## Success

- Fork `master` is TerminalStudio + the three patches
- TeamPilot builds against the submodule
- Keepalive failure still reaches `SshClientFactory` / reconnect coordinator
