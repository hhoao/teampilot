# Connect System sshd Backend Design

Date: 2026-09-15
Status: Approved (design phase)

## Goal

On Linux and macOS desktops, Connect can serve the full phone pairing loop
through either the embedded `tp_sshd` or the host's OpenSSH `sshd` on port 22.
The switch exists so a developer can A/B the two servers when diagnosing
whether `tp_sshd` is at fault. Windows stays embedded-only. Default remains
embedded.

## Current behavior

Desktop Connect always starts `EmbeddedSshServer` (`tp_sshd` on a persisted
high port). `ConnectAgent` mints offer `v:2` with `emb: true`, authenticates
against `PairedDeviceStore`, and splices relay SSH to that port. The old
system-sshd path (`SshdPresence`, `AuthorizedKeysFile`, port-22 probe) was
deleted by the embedded-server replacement. Manual SSH profiles can still
point at a remote OpenSSH, but they are not Connect pairing.

## Decision

Introduce a `ConnectSshBackend` in front of Connect. One backend is live at a
time. Embedded is today's `EmbeddedSshServer`. System probes `127.0.0.1:22`
and uses `~/.ssh/authorized_keys`. This is a diagnostic toggle, not a
fallback: a down system sshd does not start `tp_sshd`.

## Non-goals

- No Windows system-sshd mode (OpenSSH-on-Windows is why the embedded server
  exists).
- No configurable sshd port; system mode is port 22 only.
- No automatic fallback from system to embedded.
- No starting or stopping the OS sshd for the user.
- No migration of existing pairings when switching backends (re-scan).
- No writing paired keys into `authorized_keys` on switch, and no copying
  `authorized_keys` back into `PairedDeviceStore`.

## Architecture

```
ConnectSettingsStore.sshBackend   embedded | system
        │
        ▼
ConnectBackendHost (app-lifetime)
  ├─ EmbeddedSshServer        start/stop tp_sshd; authorize/revoke no-op
  └─ SystemSshdBackend        probe :22 + host keys; authorize/revoke
                              ~/.ssh/authorized_keys
        │
        ▼
ConnectAgent                  offer port / emb / fingerprints / relay splice
        │
        ▼
PairedDeviceStore             always: device list + relay grants
```

### `ConnectSshBackend`

Replace `EmbeddedSshServerHandle` with this interface in
`connect_ssh_backend.dart`. Keep the existing getters and add `isEmbedded`,
`start`/`stop`, and authorize/revoke. `EmbeddedSshServer` implements it;
`SystemSshdBackend` is the second implementation. Call sites that took
`EmbeddedSshServerHandle` take `ConnectSshBackend`.

| Member | Embedded | System |
| --- | --- | --- |
| `isListening` | `tp_sshd` bound | TCP connect to `127.0.0.1:22` succeeded |
| `port` | bound high port | `22` |
| `hostKeyFingerprints` | embedded host key | OpenSSH `SHA256:` fingerprints of keys from `ssh-keyscan` of `127.0.0.1:22` (same encoding as the embedded host key; `ssh-keyscan` prints keys, not fingerprints) |
| `isEmbedded` | `true` | `false` |
| `start` / `stop` / `restart` | bind / unbind listener | probe / forget probe / probe again |
| `authorizePublicKey` | no-op | append OpenSSH line to `authorized_keys` |
| `revokePublicKey` | no-op | delete matching key blob line(s) |

`ConnectAgent` depends on `ConnectSshBackend`, not `EmbeddedSshServer`.
`canPair` stays `isListening && fingerprints.isNotEmpty`.

### `ConnectBackendHost`

Owned by `app_shell` (same lifetime as today's embedded server). Holds both
concrete backends on Linux/macOS, only the embedded backend on Windows.

- Starts the selected backend at boot; the other stays stopped.
- `select(kind)`: persist, `stop` the live backend, `start` the other, point
  `ConnectAgent` at it. If a QR session is visible, **stop and start** it so
  `_QrSession` is rebuilt from the new port, fingerprints, and `emb`. Do not
  `_regenerateQr` on the old session — it caches those values at start.
- Windows: `system` in the JSON file is ignored at runtime; the file is not
  rewritten. A Linux/macOS preference survives a Windows run.

Constructor-inject probe, `ssh-keyscan` runner, and `authorized_keys` IO so
tests never launch a real sshd. There is no background poll: presence is
sampled on `start`, `restart`, and Connect refresh / Retry.

`ConnectCubit` receives `systemSshdSelectable` from `app_shell` (true on
Linux/macOS). The widget does not read `Platform`.

### Persistence

`connect/settings.json` gains `sshBackend`: `"embedded"` | `"system"`.
Missing, unknown, or empty → `embedded`. Reachability `save` must preserve
the field (it already merges the existing JSON). The selector calls a
dedicated `saveSshBackend` that writes only that key and does not wait for
the reachability Save button.

## Data flow

### Startup

1. Load settings.
2. Effective kind = `system` only when `Platform.isLinux || Platform.isMacOS`
   and the stored value is `system`; otherwise `embedded`.
3. Embedded path: identical to today (`EmbeddedSshServer.start`, offer
   `emb: true`, relay splice to the high port).
4. System path: do not bind `tp_sshd`. `SystemSshdBackend.start` probes
   `127.0.0.1:22` (short timeout) and runs `ssh-keyscan -t ed25519,ecdsa,rsa
   -p 22 127.0.0.1`. Hash each scanned public key into the same OpenSSH
   `SHA256:` fingerprint string the embedded server already emits. If the
   probe fails, the scan is empty, or `ssh-keyscan` is missing → not
   listening, no fingerprints.
5. Relay SSH target is always `127.0.0.1` + the live backend's port.

### Offer

Same offer `v: 2`. System mode sets `emb: false`, LAN endpoint port `22`,
and system fingerprints. Pairing HTTPS is unchanged. Phone
`PairedProfileWriter` already maps `offer.emb` onto `SshProfile.embeddedTarget`,
so a system pairing uses POSIX exec strings, not `tp1:`.

### Pairing POST

1. `PairedDeviceStore.issueDevice` (list + relay grant), as today.
2. `backend.authorizePublicKey(publicKey)`.
3. If step 2 throws: `revokeDevice` the just-issued id and fail the POST.
   No half-authorized device.

`authorized_keys` path is `<nativeHome>/.ssh/authorized_keys` using the same
home TeamPilot already resolves for Connect. Create `.ssh` if needed. Append
the OpenSSH one-line key if that key blob is not already present. `chmod 600`.
Leave unrelated lines untouched. Custom `sshd_config` `AuthorizedKeysFile`
paths are out of scope.

### Revoke

1. Load the device's public key from the store, then `revokeDevice`.
2. `backend.revokePublicKey`.
3. Embedded: existing live-connection teardown still runs via the device
   registry subscription.
4. System: new logins fail; already-established OpenSSH sessions typically
   stay up. Surface that in the revoke copy.

### Switching

Connect UI changes the selector → `ConnectBackendHost.select` as above.
If the pairing card is open, rebuild the QR session from the new backend
(fresh port, fingerprints, `emb`). Existing `PairedDeviceStore` entries
remain for the list UI but will not authenticate on the new server until
the phone re-scans. Show a re-pair notice. Do not copy keys between store
and `authorized_keys`.

## UI

Linux/macOS only, on the pairing card, below the network-interface picker:

- Label: SSH server
- Choices: Embedded / System OpenSSH (22)
- Helper: diagnostic comparison; switching requires re-scanning the pairing
  code
- Changing the selector saves and switches immediately

Windows: no selector.

QR down-state (`!canPair`) uses backend-specific copy plus the existing Retry
button (`restart()` on the live backend):

| Backend | Down copy |
| --- | --- |
| Embedded | existing `connectSshdDown` |
| System / macOS | enable Remote Login (Sharing settings), then retry |
| System / Linux | start the OpenSSH `sshd` service on port 22, then retry |

After a successful switch, a short notice: paired phones must re-scan.

l10n: `client/lib/l10n/app_en.arb` and `app_zh.arb` only. Put the selector in
`pages/connect/` (do not grow `connect_section.dart` further if the addition
does not fit cleanly).

## Error handling

| Scenario | Behavior |
| --- | --- |
| System 22 closed / filtered | `canPair = false`; no embedded fallback |
| `ssh-keyscan` missing or empty | same as not listening |
| `authorized_keys` write fails | pairing POST fails; store row rolled back |
| Embedded bind conflict | existing re-pick + persist + notice; only in embedded mode |
| Switch while QR open | stop/start backends, then stop+start the QR session from the new backend |
| `system` stored on Windows | ignored; embedded runs |

## Testing

Inject probe, scanner, and `authorized_keys` filesystem. Unit tests must not
start a real sshd.

- Settings round-trip; missing key defaults to `embedded`.
- Windows effective kind is `embedded` even when JSON says `system`.
- System backend: listening true/false; fingerprints from scanner; port 22.
- `ConnectAgent` with a system backend: offer `emb: false`, LAN port 22,
  relay SSH splice to 22; `canPair` false when the backend is down.
- Pairing: store + `authorized_keys` append; duplicate key is a no-op;
  authorize failure rolls back the store.
- Revoke removes the matching `authorized_keys` line and leaves others.
- Switch: stops embedded, starts system (and the reverse); rebuilds the QR
  session from the new backend when it is open.
- Connect page: selector present when the cubit exposes system mode as
  available; down copy follows backend kind.

Existing embedded pairing integration tests stay on the default embedded
backend and must not change behavior.

## File map (expected)

| File | Change |
| --- | --- |
| `services/connect/connect_ssh_backend.dart` | new `ConnectSshBackend`; replaces `EmbeddedSshServerHandle` |
| `services/connect/system_sshd_backend.dart` | new |
| `services/connect/authorized_keys_file.dart` | new (append / dedupe / remove / 600) |
| `services/connect/sshd_presence.dart` | new (TCP :22 + injectable `ssh-keyscan`) |
| `services/connect/connect_backend_host.dart` | new, app-lifetime swap |
| `services/connect/connect_settings_store.dart` | `sshBackend` field + `saveSshBackend` |
| `services/connect/connect_agent.dart` | `ConnectSshBackend`, `emb`, port, authorize-on-pair, replace backend |
| `services/connect/embedded_ssh_server.dart` | implement `ConnectSshBackend`; authorize/revoke no-op |
| `cubits/connect_cubit.dart` | kind in state, `selectSshBackend`, down copy |
| `pages/connect/connect_section.dart` (+ small selector widget) | Linux/macOS selector |
| `pages/connect/connect_qr_panel.dart` | backend-specific down copy |
| `app/app_shell.dart` | construct host; start selected backend only |
| `l10n/app_en.arb`, `app_zh.arb` | new strings |

## Relation to the embedded-server spec

[2026-09-08-embedded-ssh-server-design.md](../../specs/2026-09-08-embedded-ssh-server-design.md)
remains the default path on every desktop. This spec adds an opt-in Linux/macOS
diagnostic that restores a system-sshd pairing loop without making it the
default or a silent fallback.
