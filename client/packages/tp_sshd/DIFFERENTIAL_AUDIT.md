# tp_sshd differential audit — OpenSSH vs tp_sshd

Behavioral differential between the system OpenSSH sshd and the embedded
tp_sshd server, observed over real TCP through the raw audit driver
(`tool/differential/`). One row = one wire-level stimulus applied identically
to both servers; the observable is what the server sent back (message
sequence, `SSH_MSG_DISCONNECT` reason code + description, close behavior)
plus a crash-isolation check (the listener still serves a clean publickey
login afterwards).

## Method

- **Prediction first**: every row's OpenSSH expectation was written by
  reading the OpenSSH source *before* the row was ever run; actuals come from
  the live runs (`dart run tool/differential/run_audit.dart --area <x>`), and
  they never feed back into the expectation column.
- **Reference source**: `~/.cache/openssh-portable`, tag **V_10_2_P1**
  (Ubuntu-patched 10.2p1 binary as the live counterpart). Citations are
  `file:function` into that checkout. Note for readers of older trees: in
  10.2 the sshd monolith is split (`sshd.c` → `sshd-auth.c` / `sshd-session.c`),
  the version exchange lives in `kex.c:kex_exchange_identification`, and the
  packet length checks live in `packet.c:ssh_packet_read_poll2` (there is no
  `ssh_packet_read_structured` in this version).
- **Trace-recording caveat**: transport-layer message ids (1–34) are recorded
  from the dartssh2 transport's trace log, not from decoded packets. Row A05
  cross-checked its trace-recorded `UNIMPLEMENTED` against the sshd `DEBUG3`
  log (`AuditServers.sshdLogPath`) — confirmed, no under-recording. The same
  log cross-check carries the rows whose wire observable is a bare close or
  races an RST (A03, A04, A16).
- Pre-KEX rows run on the raw byte stream (`dialRaw` + `sendRawBytes`):
  before the first KEX every packet is plaintext, so both the stimulus and
  the server's `SSH_MSG_DISCONNECT` are hand-crafted/parsed at the byte
  level. Post-KEX rows ride a dartssh2 client transport that completes KEX
  (and, where the row needs it, publickey authentication) before the
  stimulus is injected.
- **Verdicts normalize cosmetic differences**: the banner software string
  (`SSH-2.0-OpenSSH_10.2p1 …` vs `SSH-2.0-DartSSH_2.0`) and sshd's ambient
  post-auth traffic (an unsolicited `hostkeys-00@openssh.com` GLOBAL_REQUEST
  plus a DEBUG message, which tp_sshd never sends) are excluded from the
  row comparison; both are recorded here once instead.
- The runner wraps the run in a guarded zone and reports **stray async
  errors** — errors that escaped a row's own guards. Because the tp_sshd
  server runs in-process, a leak in its wiring surfaces there; see A16.

## Verdict legend

| verdict | meaning |
|---------|---------|
| `match` | both servers behaved identically on this row's observable |
| `deliberate-divergence` | tp_sshd differs on a narrow surface, with a documented spec/rationale; not scheduled for fixing |
| `fix-divergence` | tp_sshd differs in a way a real client or attacker would feel (breaks clients, crashes instead of disconnecting, accepts what sshd rejects); acceptance criterion noted in the triage section |

## Area A — malformed input

| ID | 刺激 | OpenSSH 预期（源码出处） | OpenSSH 实测 | tp_sshd 实测 | 判定 |
|----|------|--------------------------|--------------|--------------|------|
| A01 | garbage line `xxxx\r\n` before the version string, then a real `SSH-2.0` handshake | Any non-`SSH-` line from a *client* is fatal: `client sent invalid protocol identifier` → plaintext `Invalid SSH identification string.` error line, then close (`SSH_ERR_INVALID_FORMAT`). [kex.c:kex_exchange_identification — server branch of the pre-banner loop] | banner + `line="Invalid SSH identification string."`, then closed — prediction confirmed | banner + KEXINIT bytes, connection stays **open**: the garbage line was discarded as a "pre-banner line" and the handshake proceeded | **fix-divergence** |
| A02 | version `SSH-1.99-DartSSH_2.0` | Accepted: `remote_major 1` with `remote_minor 99` leaves `mismatch = 0`, so the server proceeds with protocol 2 — banner + its own KEXINIT, connection stays open, no error line. [kex.c:kex_exchange_identification (switch on remote_major); compat.c:compat_banner] | banner + KEXINIT packet, connection open — prediction confirmed | identical shape (banner + KEXINIT, open) | **match** |
| A03 | pre-KEX plaintext packet, `packet_length = 40000` (> 35000, < 256 KiB), only the header sent | 40000 is below OpenSSH's `PACKET_MAX_SIZE` (256 KiB), so the length check passes; `need = 4 + 40000 − 8 = 39996` is not a multiple of the 8-byte block → "padding error" → `ssh_packet_start_discard` with `enc == NULL` → `DISCONNECT(2, "Packet corrupt")` + close. [packet.c:ssh_packet_read_poll2 (need % block_size); packet.c:ssh_packet_start_discard; PACKET_MAX_SIZE packet.c:102] | closed with **no DISCONNECT on the wire**; sshd log confirms the predicted path (`need 39996 block 8 mod 4` + `sshpkt_disconnect: … "Packet corrupt"`) — the DISCONNECT is queued but never flushed before teardown, so the wire observable is a silent close | closed, no DISCONNECT (dartssh2 rejects the length outright: `Packet too long: 40000` against its 35000 cap) | **match** (wire observable: both silently close; see triage notes 2–3) |
| A04 | pre-KEX plaintext packet, `packet_length = 0` | `packlen < 1 + 4` → "Bad packet length 0." → same discard path → `DISCONNECT(2, "Packet corrupt")` + close. [packet.c:ssh_packet_read_poll2] | closed with no DISCONNECT on the wire; sshd log confirms `Bad packet length 0.` + the queued "Packet corrupt" disconnect | closed, no DISCONNECT (`Packet too short: 0`) | **match** (same nuance as A03) |
| A05 | unknown message id 200 pre-auth (post-KEX, no service request) | `USERAUTH` dispatch table is initialized with `dispatch_protocol_error` as the default → reply `SSH_MSG_UNIMPLEMENTED(seq)`, connection stays open. [auth2.c:do_authentication2 (`ssh_dispatch_init`); dispatch.c:dispatch_protocol_error] | `msg:3(UNIMPLEMENTED)`, connection open — prediction confirmed; sshd log cross-check confirms the trace-recorded id (`dispatch_protocol_error: type 200`) | `msg:3(UNIMPLEMENTED)`, connection open | **match** |
| A06 | unknown message id 201 post-auth | Same default handler, registered again for the running phase → `SSH_MSG_UNIMPLEMENTED`, connection stays open. [serverloop.c:server_init_dispatch (`ssh_dispatch_init`); dispatch.c:dispatch_protocol_error] | `msg:3(UNIMPLEMENTED)` (plus sshd's ambient hostkeys GLOBAL_REQUEST + DEBUG), connection open — prediction confirmed | `msg:3(UNIMPLEMENTED)`, connection open | **match** |
| A07 | `SERVICE_REQUEST "audit-bogus-service"` | Only `ssh-userauth` is accepted; anything else → `ssh_packet_disconnect("bad service request …")` → `DISCONNECT(2, "bad service request audit-bogus-service")`. [auth2.c:input_service_request] | `disconnect:2("bad service request audit-bogus-service")` — prediction confirmed exactly | `disconnect:7("Service not available: audit-bogus-service")` — also fatal, different reason code (7 `service not available` vs 2 `protocol error`) and description | **deliberate-divergence** |
| A08 | `USERAUTH_REQUEST` (valid publickey probe) sent *before* any `SERVICE_REQUEST` | The `USERAUTH_REQUEST` dispatch entry is only registered after `ssh-userauth` is accepted; before that the default `dispatch_protocol_error` answers → `SSH_MSG_UNIMPLEMENTED`, connection stays open. [auth2.c:do_authentication2 + auth2.c:input_service_request] | `msg:3(UNIMPLEMENTED)`, connection open — prediction confirmed | `msg:60(USERAUTH_PK_OK)`: the request was **processed and answered** (probe accepted) with no service negotiation at all | **fix-divergence** |
| A09 | `USERAUTH_REQUEST` method `password` (config has `PasswordAuthentication no`) | Method not enabled → `authmethod_lookup` returns NULL → authenticated = 0 → `USERAUTH_FAILURE` listing the enabled methods (`publickey`), connection stays open. [auth2.c:input_userauth_request → authmethod_lookup; auth2.c:userauth_finish → authmethods_get] | `msg:51(USERAUTH_FAILURE, methods=[publickey])`, connection open — prediction confirmed | `msg:51(USERAUTH_FAILURE, methods=[])` — failure, but with an **empty** methods list | **fix-divergence** |
| A10 | `USERAUTH_REQUEST publickey` with an undecodable key blob | `sshkey_from_blob` fails ("parse key") → `goto done` with authenticated = 0 → `USERAUTH_FAILURE("publickey")`, connection stays open. [auth2-pubkey.c:userauth_pubkey; sshkey.c:sshkey_from_blob] | `msg:51(USERAUTH_FAILURE, methods=[publickey])`, connection open — prediction confirmed | `msg:51(USERAUTH_FAILURE, methods=[])` — same shape as A09 | **fix-divergence** (same fix as A09) |
| A11 | `USERAUTH_REQUEST publickey` with the real device key but an invalid signature | `sshkey_verify` fails → authenticated = 0 → `USERAUTH_FAILURE("publickey")`, connection stays open. [auth2-pubkey.c:userauth_pubkey (have_sig verify path)] | `msg:6(SERVICE_ACCEPT)`, `msg:51(USERAUTH_FAILURE, methods=[publickey])` — prediction confirmed | `msg:6(SERVICE_ACCEPT)`, `msg:51(USERAUTH_FAILURE, methods=[])` — same shape as A09 | **fix-divergence** (same fix as A09) |
| A12 | 7 consecutive publickey probe attempts with a distrusted key | `MaxAuthTries` defaults to 6 (`DEFAULT_AUTH_FAIL_MAX`): attempts 1–5 are answered `USERAUTH_FAILURE("publickey")`; on the 6th failure `failures >= 6` → `ssh_packet_disconnect("Too many authentication failures")` → `DISCONNECT(2, …)`. [servconf.h:39 DEFAULT_AUTH_FAIL_MAX; servconf.c:446; auth2.c:userauth_finish; auth.c:auth_maxtries_exceeded] | 5 × `USERAUTH_FAILURE(methods=[publickey])` then `disconnect:2("Too many authentication failures")` — prediction confirmed exactly (cap fires on the 6th failure) | 5 × `USERAUTH_FAILURE(methods=[])` then `disconnect:14("Too many failed authentication attempts")` — **same cap (6) and same count**, different disconnect reason code (14 vs 2) and text; also carries A09's empty methods list | **deliberate-divergence** (cap parity; the methods-list part is A09's fix) |
| A13 | `KEXINIT` mid-auth (after successful publickey login, via the client transport's `rekey()`) | A client KEXINIT outside an in-progress exchange is a normal rekey initiation (`kex_input_kexinit` stays registered after the first KEX): the server answers with its own `KEXINIT` and the rekey proceeds; connection continues. [kex.c:kex_input_newkeys re-registers `SSH2_MSG_KEXINIT → kex_input_kexinit`; kex.c:kex_input_kexinit] | `msg:20(KEXINIT)`, `msg:31(KEXDH_REPLY)`, `msg:21(NEWKEYS)` — the rekey completed end-to-end, connection open — prediction confirmed (plus one ambient DEBUG message) | `msg:20(KEXINIT)`, `msg:31(KEXDH_REPLY)`, `msg:21(NEWKEYS)` — identical rekey completion, connection open | **match** |
| A14 | `CHANNEL_OPEN "audit-bogus-channel"` post-auth | Unknown channel type → no handler matched → `CHANNEL_OPEN_FAILURE` with the initial reason `SSH2_OPEN_CONNECT_FAILED` (2) and description "open failed". [serverloop.c:server_input_channel_open; ssh2.h:172] | `msg:92(CHANNEL_OPEN_FAILURE, reason=2 "open failed")` — prediction confirmed exactly | `msg:92(CHANNEL_OPEN_FAILURE, reason=1 "Channel type 'audit-bogus-channel' is not supported")` — also refused, reason 1 (administratively prohibited) with a descriptive message | **deliberate-divergence** |
| A15 | `CHANNEL_DATA` to recipient channel 99999 (never opened) | Channel lookup fails → `ssh_packet_disconnect("data packet referred to nonexistent channel 99999")` → `DISCONNECT(2, …)`. [channels.c:channel_from_packet_id via channels.c:channel_input_data] | `disconnect:2("data packet referred to nonexistent channel 99999")` — prediction confirmed exactly | **no response at all**: the message is silently dropped (unknown recipient ids are ignored as indistinguishable from a racing channel close), connection stays open | **fix-divergence** |
| A16 | `CHANNEL_DATA` flood on an open **direct-tcpip** channel (a request-less *session* channel stays `SSH_CHANNEL_LARVAL` and its data is dropped before any window check — `serverloop.c:server_request_session`, `channels.c:channel_input_data` non-open type check): 320 × 32000 bytes ≈ 10 MiB — enough to first fill the target socket's kernel buffer, then exhaust the 2 MiB window + 10% grace | Each packet is under `local_maxpacket` (32 KiB) so the "rcvd big packet" ignore does not fire; once the window is exhausted the excess is logged, and past 10% of `local_window_max` (≈ 209 KiB) → `ssh_packet_disconnect("channel N: peer ignored channel window")` → `DISCONNECT(2, …)`. [channels.c:channel_input_data; CHAN_TCP_WINDOW_DEFAULT channels.h:232] | connection closed (the RST from the continuing flood beat the client's observation of the DISCONNECT); sshd log confirms the predicted path verbatim: `rcvd too much data … excess …` accumulating past the grace, then `channel 0: peer ignored channel window` + the disconnect | **no disconnect, ever**: the server kept granting window (`msg:93(CHANNEL_WINDOW_ADJUST)` × 55) and buffered all ~10 MiB; the teardown then leaked an **unhandled async error** (see triage note 6) | **fix-divergence** |
| A17 | `GLOBAL_REQUEST "audit-bogus@tp-sshd-differential"` with `want_reply = true` | Unknown request name → success stays 0 → `REQUEST_FAILURE`, connection stays open. [serverloop.c:server_input_global_request] | `msg:82(REQUEST_FAILURE)`, connection open — prediction confirmed | `msg:82(REQUEST_FAILURE)`, connection open | **match** |
| A18 | client `DISCONNECT(11)` sent right after the version exchange (mid-handshake, pre-KEX) | `SSH_MSG_DISCONNECT` is intercepted in the read loop in every phase: logged, no reply, clean teardown (`SSH_ERR_DISCONNECTED`); the listener serves the next login. [packet.c:ssh_packet_read_poll_seqnr] | banner + KEXINIT, then closed with no reply; sshd log records `Received disconnect … 11: tp-sshd differential audit A18`; listener served the next login — prediction confirmed | banner + KEXINIT, then closed with no reply; listener served the next login | **match** |

Row A16 first pass (recorded because the finding stands on its own): the
same flood against a request-less **session** channel was silently
**dropped** by sshd (LARVAL channels discard data before window accounting;
the DEBUG3 log shows the 2.56 MiB arriving with zero window messages) while
tp_sshd accepted and buffered all of it. A client that races data ahead of
its first CHANNEL_REQUEST gets its bytes dropped by sshd but delivered by
tp_sshd — related to Area C (window handling), noted there for follow-up.

## Area A triage

Verdicts: 7 match, 4 deliberate-divergence, 5 fix-divergence (A09–A11 share
one fix; every other fix-divergence row is its own fix).

### fix-divergence — acceptance criteria

1. **A01 — pre-banner garbage must be fatal.** Any non-`SSH-` line from a
   client before its identification string must terminate the connection:
   send the plaintext `Invalid SSH identification string.` line and close
   (kex.c:kex_exchange_identification, server branch). Today tp_sshd
   discards up to 1024 such lines and completes the handshake against a
   prober. (dartssh2-side change; the client-side pre-banner tolerance is
   legitimate, the server-side one is not.)
2. **A08 — no userauth before service negotiation.** A `USERAUTH_REQUEST`
   arriving before `SERVICE_ACCEPT` must not be processed (sshd answers
   `UNIMPLEMENTED` through the default dispatch). Acceptance: tp_sshd
   ignores or refuses it; in particular it must not answer `USERAUTH_PK_OK`
   or authenticate on a connection that never negotiated `ssh-userauth`.
3. **A09/A10/A11 — `USERAUTH_FAILURE` must advertise the enabled methods.**
   The failure packet's methods list must say `publickey` (RFC 4252 §8),
   not be empty. A client that consults the list to decide whether to offer
   a publickey sees "no methods available" and can give up on a login that
   would have succeeded. Also visible in A12's failure packets.
4. **A15 — data for a nonexistent channel must be a protocol error.**
   `CHANNEL_DATA` addressed to an unknown recipient channel must disconnect
   with reason 2, description `data packet referred to nonexistent channel
   <id>` (channels.c:channel_from_packet_id). The racing-close rationale
   covers at most a small window around a channel's own CLOSE; swallowing
   every unknown id indefinitely hides real client bugs (silent hang
   instead of an error).
5. **A16 — the granted window must be enforceable.** A peer that keeps
   sending past the granted window beyond a grace margin (sshd: 10% of the
   window) must be disconnected (`channel <id>: peer ignored channel
   window`, reason 2). Today tp_sshd refills its receive window on pure
   accounting rules (half-empty or 3 packets outstanding — regardless of
   consumption), so the window is never a bound and a peer can buffer
   unbounded data server-side (resource exhaustion). Fix belongs with Area
   C's window work.

### deliberate-divergence (documented, not scheduled for fixing)

- **A07** — unknown service: tp_sshd disconnects with reason 7
  (`serviceNotAvailable`) + `Service not available: <name>` where sshd uses
  reason 2 + `bad service request <name>`. Both fatal; reason 7 is arguably
  the more apt RFC 4253 §11.1 semantic; clients only surface the text.
- **A12** — auth-attempt cap parity (both cut at 6: five failures, then the
  disconnect on the sixth), but tp_sshd's disconnect carries reason 14
  (`noMoreAuthMethodsAvailable`, text `Too many failed authentication
  attempts`) where sshd uses reason 2 (`Too many authentication failures`).
  Both terminate auth at the same count; reason 14's RFC meaning
  ("no more authentication methods available") does not quite match
  "too many attempts", but no client branches on it.
- **A14** — unknown channel type: refused with reason 1
  (`administratively prohibited`) + a descriptive message where sshd uses
  reason 2 (`connect failed`) + `"open failed"`. RFC 4254 §5.1 actually
  suggests reason 3 for unknown types — both deviate; clients only display
  the string.

### findings recorded from the runner itself

6. **A16 teardown — unhandled async error in the forward pump.** When the
   row's forwarded TCP connection was reset, tp_sshd (in-process) leaked
   `SocketException: Connection reset by peer` past every guard — the
   runner's zone caught it (`Stray async errors: [A16: …]`). Root cause:
   `lib/src/server_forward.dart:pumpForwardConnection` drops the future
   returned by `connection.done.whenComplete(...)`, so an *errored*
   connection completion propagates to an unlistened future. Acceptance
   criterion: the pump must consume `connection.done`'s error channel
   (`.catchError`/`onError`) so a reset forwarded connection can never leak
   an unhandled error into the embedder's zone — in the app that is an
   unhandled exception. Fix candidate for Task 7.

### ambient differences (normalized out of the verdicts; no action)

- sshd sends an unsolicited `hostkeys-00@openssh.com` GLOBAL_REQUEST and a
  DEBUG message right after successful auth; tp_sshd sends neither. Benign
  either way.
- Banner software strings differ (`SSH-2.0-OpenSSH_10.2p1 …` vs
  `SSH-2.0-DartSSH_2.0`).
- **Packet-length caps**: OpenSSH accepts plaintext packet lengths up to
  256 KiB (`PACKET_MAX_SIZE`, packet.c:102) and rejects 40000 only via the
  block-alignment check; dartssh2 rejects anything over 35000
  (`SSHPacket.maxLength`). For a >35000 but 8-aligned length, tp_sshd
  closes immediately where sshd would wait for the rest of the packet —
  same outcome class (reject/timeout), tighter bound, no client impact;
  treated as part of A03's match.
- **OpenSSH nuance, not a tp_sshd issue**: for A03/A04 the DISCONNECT that
  the source clearly queues ("sshpkt_disconnect: sending … Packet corrupt"
  in the log) never reaches the wire — the error path tears the connection
  down unflushed. The prediction's wire observable was therefore wrong in
  OpenSSH itself; both servers' silent close is the real behavior.
- During A13's development, an accidental duplicate-KEXINIT probe showed
  sshd answering a *second* KEXINIT mid-exchange with `UNIMPLEMENTED`
  (kex.c:kex_protocol_error — the strict-KEX fatal case applies only to the
  initial KEX); recorded for Area B, where rekey edge cases belong.
