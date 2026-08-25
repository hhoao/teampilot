# SSH QR pairing — Design

**Date:** 2026-08-20
**Status:** Approved (design)
**Restored:** 2026-08-25 (original spec file was missing from the tree)

## Problem

Android TeamPilot already runs as a full SSH client (`SshProfile` +
`dartssh2` + `applyAndroidSshConnectHome`). Pairing a phone to “this
computer” still means typing host, port, user, and a key or password.

Orca’s scan-to-connect UX is the right shape, but Orca pairs a thin
mobile client to a desktop WebSocket RPC. TeamPilot’s phone is not a
thin viewer: after connect it must SSH into the machine that showed the
QR and use that host as the work runtime (same as today’s Android SSH
home).

There is no official TeamPilot cloud relay. Remote “scan and it works”
must still be possible when the user provides a self-hosted relay.
Official Connect later must not require a new offer format.

## Goals

1. Desktop shows a QR; Android scans (or pastes) it and becomes an SSH
   client of **that computer’s OpenSSH**, without typing credentials.
2. Same Wi-Fi / LAN works with no extra infrastructure.
3. Optional self-hosted relay lets the phone pair and reconnect off-LAN
   (cellular in the same room, or later from outside).
4. Offer schema reserves a `relay` object so an official Connect URL can
   be filled in later without a breaking change.
5. After a successful pair, Android binds SSH home to the desktop’s
   existing TeamPilot data root so the phone sees the same workspaces.
6. Passwords and private keys never appear in the QR.

## Non-goals

- Official TeamPilot-hosted Connect / cloud relay (schema only).
- Tailscale (or any overlay VPN) as a required dependency. A Tailscale
  `100.x` address may be pasted as an extra endpoint if the user has it.
- Orca-style WebSocket companion protocol, worktree monitor, or
  non-SSH mobile RPC.
- iOS. Android is the only mobile target.
- Replacing OpenSSH with a TeamPilot-implemented SSH server.
- Using the QR to encode a *different* SSH host than the machine showing
  the code (no “share my already-saved profile” flow).
- Exposing sshd to the public Internet as the default path.

## Product shape

Desktop is the SSH server host. The phone is the existing Android SSH
client. Scanning only creates or updates an `SshProfile` and connects.

```
Desktop TeamPilot ── Connect Agent ── OpenSSH (sshd)
        │                 │
        │ QR offer        │ optional outbound WSS
        ▼                 ▼
Android TeamPilot     self-hosted teampilot-relay
        │
        └─ dartssh2 ──► LAN / extra host / relay tunnel ──► sshd
```

Default policy is **Automatic**: try every configured reachability in
kind order (lan → extra → relay), skipping kinds that are absent. **LAN
only** tries `kind: lan` and nothing else. The page must not label
itself “Anywhere” / 远程 unless at least one `extra` or `relay`
endpoint exists; otherwise it says LAN only.

## Connect Agent (desktop)

A desktop-only service, not a settings-page side effect. UI talks to it
through a cubit; the agent owns sockets, tokens, and files.

| Unit | Responsibility |
|------|----------------|
| `SshPairingOffer` | Versioned offer encode/decode (`teampilot://pair-ssh?code=`). |
| `ConnectAgent` | Lifecycle: sshd probe, pairing TLS server, token mint, endpoint list, relay client. |
| `PairedDeviceStore` | Registry of accepted phones + tagged `authorized_keys` lines. |
| `SshdPresence` | Is OpenSSH listening; OS-specific enable hints. |
| `ConnectRelayClient` | Outbound WSS to a user-configured relay URL. |
| `ConnectRelayServer` | Self-hosted dumb byte-pipe (`tools/teampilot_connect_relay`). |

`ConnectAgent` starts with the desktop app when Connect is enabled
(default on). Two listeners have different lifetimes:

- **Relay client:** connected whenever a relay URL is saved and Connect
  is enabled (required for off-LAN reconnect without a QR on screen).
- **Pairing HTTPS:** bound only while the QR surface is visible, and
  only to the selected advertise address (not `0.0.0.0`). Closing the
  page stops it and invalidates the current token.

The agent does not implement SSH. It prepares OpenSSH (detect, write
keys) and optionally tunnels TCP to `127.0.0.1:22` (or the detected
sshd port).

## Pairing offer

Deep link (query, not fragment — Android camera intents drop hashes):

```
teampilot://pair-ssh?code=<base64url(JSON)>
```

The camera flow also accepts a bare `code` string (paste and some
scanners). `code` is UTF-8 JSON, base64url without padding.

### Schema (`v: 1`)

```json
{
  "v": 1,
  "hostId": "AbCdEf0123_-xyZ9",
  "username": "alice",
  "displayName": "alice-laptop",
  "appDataRoot": "/home/alice/.local/share/com.hhoa.teampilot",
  "endpoints": [
    { "kind": "lan", "host": "192.168.1.20", "port": 22 },
    { "kind": "extra", "host": "203.0.113.8", "port": 2222 },
    { "kind": "relay", "host": "relay.example.com", "port": 443 }
  ],
  "hostKeyFingerprints": ["SHA256:…"],
  "pairing": {
    "token": "<43-char base64url>",
    "expiresAt": 1770000000000,
    "url": "https://192.168.1.20:2768/pair",
    "tlsCertSha256": "<hex>"
  },
  "relay": {
    "v": 1,
    "url": "wss://relay.example.com",
    "hostId": "AbCdEf0123_-xyZ9",
    "inviteToken": "<43-char base64url>",
    "inviteExpiresAt": 1770000000000
  }
}
```

Rules:

- `v` is `1`. Unknown future `v` → phone rejects with “update the app”.
- `hostId` is always present: a stable 16-char base64url id for this
  desktop install. The phone stores it as `SshProfile.pairedDesktopId`.
- `username` is the desktop OS user that owns the `authorized_keys` file
  the agent writes (the logged-in user running TeamPilot).
- `displayName` is hostname (fallback: username). Used as the default
  `SshProfile.name`.
- `appDataRoot` is `AppPaths.basePath` on the desktop. The phone writes
  it to `SshProfile.lastAppDataRoot` so SSH home uses the same
  `<teampilotRoot>`.
- `endpoints[].kind` is `lan` | `extra` | `relay`. Unknown kinds are
  ignored (forward compatible). Phone tries **lan, then extra, then
  relay**, preserving list order within a kind.
- `hostKeyFingerprints` are SSH host-key SHA-256 fingerprints from the
  local sshd. Mismatch aborts the SSH connect.
- `pairing.token` is 32 random bytes, base64url, **single use**, TTL ≤
  10 minutes. Regenerating the QR invalidates the previous token.
- `pairing.url` is the TLS pairing endpoint advertised for this QR
  (LAN IP + pairing port). When a relay is active, the phone may submit
  the same POST through the relay’s pairing channel instead of this URL.
- `pairing.tlsCertSha256` pins the pairing server’s leaf certificate.
  There is no public CA.
- `relay` is omitted when no relay URL is configured or the desktop is
  not registered with the relay. Official Connect later sets this to a
  TeamPilot URL using the same object.
- `kind: relay` does **not** mean “sshd is listening on that host”.
  It names the relay so the phone can open WSS (`relay.url`). SSH always
  terminates on the desktop’s OpenSSH. The phone must pin
  `hostKeyFingerprints` of the desktop, never a relay certificate, for
  the SSH session.

Passwords, private keys, and `authorized_keys` material never appear in
the offer.

## Key exchange

1. Desktop Connect page visible → `ConnectAgent` checks sshd. If sshd is
   not listening, **do not mint an offer**; show a single enable action
   (Windows Optional Feature “OpenSSH Server”, macOS Remote Login,
   Linux `sshd` / `ssh` systemd unit). When sshd comes up, mint
   automatically.
2. Agent mints token + self-signed pairing cert, binds pairing HTTPS on
   the selected LAN address (user-picked interface), and renders the QR.
3. Android has one Ed25519 **device** keypair for the app install,
   stored in secure storage. If missing, generate before the POST.
4. Phone POSTs JSON to pairing (LAN URL with pinned TLS, or relay
   pairing channel):

   `{ "token", "deviceId", "deviceName", "publicKey" }`

   `publicKey` is OpenSSH authorized_keys form (`ssh-ed25519 AAAA…`).
5. Agent verifies token (present, unexpired, unused), marks it used,
   appends one line to `~/.ssh/authorized_keys` (Windows:
   `%USERPROFILE%\.ssh\authorized_keys`):

   `ssh-ed25519 AAAA… teampilot-pair device=<deviceId> name=<deviceName>`

   File mode `600`. Duplicate `device=` lines are replaced, not stacked.
6. Response `{ "ok": true, "profileHint": displayName, "relayGrant"?: string }`.
   `relayGrant` is present only when the desktop is registered with a
   relay. It is a long-lived desktop-issued token bound to `deviceId` +
   `hostId`, stored by the phone for later off-LAN SSH. It is not the
   QR invite. Revoke deletes the grant and the tagged authorized_keys
   line together.
7. Phone upserts `SshProfile`:
   - `authType: privateKey`
   - `host` / `port` = first endpoint that will be tried (updated to the
     last successful lan/extra candidate after connect)
   - optional `endpoints`, `hostKeyFingerprints`, `pairedDesktopId`
     (`offer.hostId`)
   - `lastAppDataRoot` = offer `appDataRoot`
   - copies the device private key into `SshCredentialStore` for that
     `profileId` so the existing SSH connect path is unchanged
8. Phone calls the existing connect + `applyAndroidSshConnectHome`
   pipeline. Host key must match `hostKeyFingerprints`.

Re-scanning the same desktop updates endpoints and `appDataRoot` on the
existing profile (match `pairedDesktopId`), and refreshes the
authorized_keys line.

## Reachability after pairing

`SshProfile` today has a single `host`/`port`. Pairing adds optional
fields (absent on manually created profiles):

- `endpoints`: copy of the offer list
- `hostKeyFingerprints`
- `pairedDesktopId` (desktop `hostId`)
- `relayUrl` (WSS URL; not a secret)
- `lastGoodKind`: `lan` | `extra` | `relay`

`relayGrant` is stored in `SshCredentialStore` under that `profileId`,
not in profile JSON. Invite tokens are not persisted after a successful
pair.

On each connect of a paired profile, the coordinator tries candidates in
kind order (lan → extra → relay) with short timeouts. For `lan` and
`extra`, `dartssh2` dials `host:port` directly. For `relay`, the phone
first opens WSS (`relay.url` + stored `relayGrant`, or the offer
`inviteToken` during first pair), then exposes a **loopback TCP port**
and points `dartssh2` at `127.0.0.1:<local>`. That loopback address is
never written to `SshProfile.host`. Last-good state is
`lastGoodKind` plus the winning `lan`/`extra` host:port when applicable.

Manual profiles are unchanged (single host, no tunnel).

Extra endpoints are authored on the desktop Connect page (host:port
list). They are included in every new offer. The phone only learns new
extra/relay addresses by scanning again.

## Self-hosted relay

`tools/teampilot_connect_relay` is a small WSS server on 443 (or a
user-chosen port). It is a **dumb byte pipe**. SSH provides session
confidentiality; the relay does not terminate SSH.

Protocol `relay.v = 1`. The relay selects a channel from the dial
message and splices bytes; it does not parse SSH or pairing JSON.

1. Desktop opens outbound `wss://<relay>/register` with `{ hostId }`.
   `hostId` is the same stable desktop install id as the offer.
2. Phone opens `wss://<relay>/dial` with
   `{ hostId, channel: "pair" | "ssh", inviteToken | relayGrant }`.
   First pair may use `inviteToken` (TTL ≤ 10 minutes, rotated with the
   QR). After a successful pair, reconnect uses `relayGrant` only.
3. Desktop Connect Agent accepts the splice:
   - `channel: "pair"` — only while the QR surface is visible; forwards
     to the local pairing HTTPS (cellular can POST without LAN
     `pairing.url`).
   - `channel: "ssh"` — whenever Connect is enabled and a grant or
     invite is valid; forwards to `127.0.0.1:<sshdPort>`.

The phone’s SSH client always talks OpenSSH on the desktop. WSS is only
a TCP pipe.

If the relay is down: LAN pairing and LAN SSH still work. The UI states
that remote is unavailable.

Official Connect later: same `relay` object, URL supplied by TeamPilot
instead of the settings field. No offer version bump if the object
shape is unchanged.

## UI

### Desktop (Settings → Phone / Connect)

- Connection policy: Automatic vs LAN only. Automatic is always
  selectable. The heading/status must say LAN only when there is no
  extra endpoint and no live relay registration.
- NIC picker + refresh (LAN advertise address).
- Optional extra `host:port` rows.
- Optional relay URL + status (disconnected / connected / error).
- QR + copy link + regenerate. QR is not shown until sshd is listening.
- Paired devices list: name, last seen, revoke (deletes the tagged
  authorized_keys line and the device grant).

### Android

- Connect / onboarding: **Scan QR** is the primary action; manual SSH
  form remains secondary.
- Paste `teampilot://pair-ssh?…` or bare code.
- After success, connect immediately and enter the workbench.
- Later sessions reuse the profile; no scan required.
- “Refresh pairing” re-opens the scanner to update endpoints.

Android registers the `teampilot://pair-ssh` intent so the system camera
can open the app with the code. First-pair path is in-app scanner/paste;
the intent filter still must be present.

## Error handling

| Condition | Behavior |
|-----------|----------|
| sshd not listening | No QR; enable CTA; retry probe. |
| Token expired / already used / QR regenerated | Phone shows expired; scan again. |
| TLS pin mismatch on pairing POST | Abort; treat as hostile network. |
| Host key mismatch on SSH | Abort; do not persist “last good” host. |
| LAN fail, no relay, no extra | Explain same Wi-Fi **or** configure a relay on desktop. |
| Relay registered but splice fails | Fall through remaining endpoints; then the same explanation. |
| Duplicate device | Replace authorized_keys line; update phone profile. |
| User revokes device | Next SSH fails auth; phone prompts to scan again. |
| Offer `v` unknown | Phone asks to update TeamPilot. |

Do not log tokens, invites, grants, private keys, or full authorized_keys lines.
`AppLogger` may log `deviceId`, endpoint kind, and failure class.

## Testing

Constructor-inject filesystem, process, sockets, and clocks. No real
camera, no real sshd, no real WAN in unit tests.

Must cover:

- Offer encode/decode, including bare code vs deep link, and ignoring
  unknown `endpoints[].kind`.
- Token TTL, single use, and invalidation on regenerate.
- Endpoint try order: lan → extra → relay.
- `authorized_keys` tag write, replace-by-`deviceId`, revoke.
- Pairing POST reject: bad token, expired, wrong TLS pin.
- SSH host-key pin reject.
- `SshProfile` upsert by `pairedDesktopId`; manual profiles untouched.
- `lastAppDataRoot` copied from `appDataRoot`.
- Relay register / invite / grant; grant lives in the credential store;
  pairing still succeeds on LAN when the relay client is disconnected.

Widget tests: desktop QR hidden while sshd is down; Android primary
Scan control; revoke removes the device row.

## Implementation phases

1. **LAN pair:** offer, pairing TLS, authorized_keys, Android scan,
   existing SSH connect + `appDataRoot`.
2. **Multi-endpoint:** extra hosts, last-good host, Automatic try order.
3. **Self-hosted relay:** `ConnectRelayServer`, desktop outbound client,
   cellular pairing channel, device grant for reconnect.

## File map

| Path | Role |
|------|------|
| `client/lib/services/connect/ssh_pairing_offer.dart` | Codec + validation. |
| `client/lib/services/connect/connect_agent.dart` | Desktop agent facade. |
| `client/lib/services/connect/sshd_presence.dart` | Probe / enable hints. |
| `client/lib/services/connect/paired_device_store.dart` | Devices + authorized_keys. |
| `client/lib/services/connect/connect_relay_client.dart` | Desktop WSS client. |
| `client/lib/models/ssh_profile.dart` | Optional pairing fields. |
| `client/lib/repositories/ssh_credential_store.dart` | Device key + `relayGrant`. |
| `client/lib/pages/connect/` | Desktop Connect settings + QR. |
| `client/lib/pages/ssh_profiles/` | Android scan / paste entry. |
| `tools/teampilot_connect_relay/` | Self-hosted relay. |

CLI registry and TeamBus are untouched. Connect is a transport for the
existing SSH home, not a new CLI.
