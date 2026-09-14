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
- **Areas C+D plumbing**: the probe scaffolding was promoted to
  `tool/differential/row_plumbing.dart` from Area C on (the Task 3 review
  ruling); `area_a_malformed.dart` and `area_b_rekey.dart` keep their
  local copies untouched so the completed areas' runners do not churn.
- **Area E (timing rows)**: timing rows are judged `match-in-kind` — both
  servers uniform, or both variable — never by numeric equality (wall-clock
  µs over loopback TCP are not comparable across processes); what IS a
  finding is an oracle, a failure class one server makes indistinguishable
  that the other answers at measurably different speeds. Latencies come
  from µs timestamps the raw driver stamps on every observation
  (`raw_driver.dart`), not from poll granularity. E01/E02/E04 run on
  dedicated harness pairs (`startAuditServers(sshdConfigExtras: …)`) so
  their sshd config knobs (`PerSourcePenalties no`, `LoginGraceTime 3`,
  `MaxStartups 3:100:6`) apply without touching the shared pair or its
  per-source penalty state.
- **sshd exec stderr noise** (Areas C+D): every sshd exec via the harness
  user's shell emits one 45-byte `tput: No value for $TERM and no -T
  specified\n` EXTENDED_DATA burst (the user's rc running tput on a
  TERM-less, pty-less exec; tp_sshd's `/bin/sh -c` execs emit none).
  The bytes count against the channel window on sshd, so byte-exact
  window rows see e.g. 4051+45 of a 4096 grant; normalized in the
  verdicts below.
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
| A19 | strict-kex violation (RFC 9142 §3.2): a hand-driven client `KEXINIT` that advertises `kex-strict-c-v00@openssh.com` (so the server enables strict kex), then a non-KEX packet — `SERVICE_REQUEST` (id 5) — injected while the exchange is in progress, before any `NEWKEYS` (all plaintext, raw bytes) | During the initial KEX in strict mode nothing is implicitly handled, and the whole transport range (ids 1–49) dispatches to `kex_protocol_error`, whose strict branch (`KEX_INITIAL && kex_strict`) is fatal: `ssh_packet_disconnect("strict KEX violation: unexpected packet type 5 (seqnr 1)")` → `sshpkt_disconnect` emits `SSH_MSG_DISCONNECT` with `SSH2_DISCONNECT_PROTOCOL_ERROR` (2, ssh2.h:153) and `ssh_packet_disconnect` waits for the write (unlike the A03/A04 path, this DISCONNECT reaches the wire), then close. Strict mode is only on because our KEXINIT carries the `kex-strict-c-v00@openssh.com` marker (kex.c:kex_choose_conf); without it the same packet draws only `UNIMPLEMENTED`. [packet.c:ssh_packet_read_poll_seqnr; kex.c:kex_protocol_error; packet.c:ssh_packet_disconnect → packet.c:sshpkt_disconnect; ssh2.h:153] | banner + KEXINIT, then `disconnect:2("strict KEX violation: unexpected packet type 5 (seqnr 1)")`, then closed — prediction confirmed exactly (message, type, reason code and seqnr); sshd log confirms the `strict KEX violation` path | banner + KEXINIT, then closed with **no DISCONNECT on the wire**: the strict-kex check did fire and tore the connection down (the violation was neither accepted nor ignored), but via `SSHHandshakeError` → `SSHTransport.closeWithError` → `socket.destroy()` (dartssh2 `ssh_transport.dart`), so the client sees an unexplained TCP close instead of the protocol-error DISCONNECT | **fix-divergence** |

Row A16 first pass (recorded because the finding stands on its own): the
same flood against a request-less **session** channel was silently
**dropped** by sshd (LARVAL channels discard data before window accounting;
the DEBUG3 log shows the 2.56 MiB arriving with zero window messages) while
tp_sshd accepted and buffered all of it. A client that races data ahead of
its first CHANNEL_REQUEST gets its bytes dropped by sshd but delivered by
tp_sshd — related to Area C (window handling), noted there for follow-up.

## Area A triage

Verdicts: 8 match, 3 deliberate-divergence, 8 fix-divergence, 19 rows
(A09–A11 share one fix; every other fix-divergence row is its own fix).

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
6. **A19 — strict-kex violations must carry a wire DISCONNECT.** A non-KEX
   packet arriving between `KEXINIT` and `NEWKEYS` under negotiated strict
   kex (RFC 9142 §3.2) must be answered with `DISCONNECT(2, "strict key
   exchange violation: …")` before the connection closes, the way sshd does
   (kex.c:kex_protocol_error → packet.c:ssh_packet_disconnect →
   `SSH2_DISCONNECT_PROTOCOL_ERROR`). tp_sshd's transport does tear the
   connection down — the violation is neither accepted nor ignored, so the
   Terrapin countermeasure itself is enforced — but the error path
   (`SSHHandshakeError` → `SSHTransport.closeWithError` →
   `socket.destroy()` in dartssh2 `ssh_transport.dart`) never emits the
   DISCONNECT, so a client sees an unexplained TCP close where sshd
   delivers a protocol-error reason. Acceptance: a strict-kex violation
   produces a decodable `SSH_MSG_DISCONNECT` (reason 2, description naming
   the strict-key-exchange violation) on the wire before the close.
   (dartssh2-side change: the strict-kex throw paths —
   `_handleMessage`'s forbidden-message check, `_handleUnexpectedKexMessage`,
   `_negotiateStrictKex` — should send the DISCONNECT before closing.)

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

7. **A16 teardown — unhandled async error in the forward pump.** When the
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

## Area B — rekey timing

Anchor finding (pre-confirmed): **tp_sshd never initiates a rekey.**
dartssh2's `rekey()` (ssh_transport.dart:2054) is a client-role API no
server code calls, and `server_connection.dart` has no byte counter and no
timer — a long-lived pairing session keeps its keys forever unless the peer
chooses to rotate them. Every runnable row therefore drives the exchange
from the client side.

- **B05–B07 are source-only rows** (a host-key change needs a MITM proxy
  that owns a second host key; the rekey thresholds need a 64 GiB /
  configured-interval session): their columns record source-verified facts
  instead of live runs, and are marked `source-only`.
- **B02 is a distribution row**: whether the channel teardown races into
  the exchange window is a sub-millisecond timing question, so the row runs
  five rounds per server and the observable is the outcome distribution.
- Rows B03/B04/B08 inject crafted packets through the raw driver's
  transport around a client-initiated rekey; post-auth observations filter
  sshd's ambient hostkeys GLOBAL_REQUEST + DEBUG (normalized once in the
  method section above). The rekey-driven stimulus is always a *rekey* —
  the strict-KEX fatal rules of A19 apply only to the initial KEX
  (kex.c:kex_protocol_error:239 requires `KEX_INITIAL`, cleared in
  kex.c:kex_input_newkeys:561).

| ID | 刺激 | OpenSSH 预期（源码出处） | OpenSSH 实测 | tp_sshd 实测 | 判定 |
|----|------|--------------------------|--------------|--------------|------|
| B01 | 对端主动 rekey（真实 dartssh2 SSHClient，开着 `cat` exec 通道，两次 stdin 回显之间调用 `rekey()`，之后再执行一条命令） | 正常 rekey：服务器应答自己的 KEXINIT，交换走到 NEWKEYS，已开通道在新密钥下继续工作。[kex.c:kex_send_newkeys; kex.c:kex_input_kexinit; packet.c:ssh_packet_send2（rekey 期间非 KEX 出站包排队）] | rekey completed; 通道 rekey 前后回显均成功；rekey 后新 exec `"echo post" -> "post"`；通道干净关闭（exit 0） — prediction confirmed | 完全相同（rekey completed; 前后回显 ok; 新 exec ok; exit 0） | **match** |
| B02 | rekey 期间有数据在途（×5 轮）：1 MiB exec 流（`head -c 1048576` 模式文件）流动中客户端在收到 ≥ 64 KiB 时 `rekey()`；流必须逐字节完整、通道必须正常收尾 | 两边都在交换期间把非 KEX 出站包排队、NEWKEYS 后按序冲刷：流短暂停顿后继续，不丢、不乱序。[packet.c:ssh_packet_send2（"During rekeying we can only send key exchange messages. Queue everything else."）] | 5/5 轮：流逐字节完整、按序；通道干净关闭（exit 0） — prediction confirmed | 4/5 轮干净；1 轮流完整但**通道永远不关闭**：exec 收尾（exit-status/EOF/CLOSE）落进交换窗口被丢弃，会话挂死（追踪证实：客户端对 packet 40/41/42 回 UNIMPLEMENTED，即 ssh_transport.dart `_handleMessage` 的 `_kexInProgress` default 分支丢包；单独 8 轮测量中挂死 1–2 轮，OpenSSH 侧 0/8） | **fix-divergence** |
| B03 | 交换进行中注入第二个 KEXINIT（rekey 刚发起、NEWKEYS 之前，算法列表与首个相同） | 重复 KEXINIT 不重新协商：它落入 `kex_protocol_error`（kex_input_kexinit 收到首个 KEXINIT 时把 KEXINIT 重注册为 kex_protocol_error），非首次交换的 strict 分支不触发 → 回 `UNIMPLEMENTED`，进行中的交换照常完成，连接继续。[kex.c:kex_input_kexinit:621; kex.c:kex_protocol_error:234-247（fatal 需 KEX_INITIAL）; kex.c:kex_input_newkeys:561] | `msg:20(KEXINIT), msg:3(UNIMPLEMENTED), msg:31(KEXDH_REPLY), msg:21(NEWKEYS), msg:82(REQUEST_FAILURE)` — rekey 完成、请求 ping 仍被应答，prediction confirmed；sshd log 证实 `kex_protocol_error: type 20 seq 3` | `msg:20(KEXINIT), msg:31(KEXDH_REPLY), closed` — 重复 KEXINIT **被静默并入协商**（无 UNIMPLEMENTED）：`_handleMessageKexInit` 用它覆盖 `_remoteKexInit` 并替换临时 kex，交换哈希失同步，客户端验证 KEXDH_REPLY 签名失败（"The message is forged or malformed or the signature is invalid"）→ 连接关闭，rekey 永不完成 | **fix-divergence** |
| B04 | rekey KEXINIT 只提议不支持的 kex 算法（kex 列表 = `tp-sshd-audit-bogus-kex`，其余字段合法） | 服务器先发自己的 KEXINIT，协商失败为致命：`choose_kex` 失败 → `kex->failed_choice` → `sshpkt_vfatal` 的 `SSH_ERR_NO_KEX_ALG_MATCH` 分支 → `logdie "Unable to negotiate … Their offer: …"` 退出 — 线上无 DISCONNECT，只有 sshd log 可见。[kex.c:kex_choose_conf:980-984; packet.c:sshpkt_vfatal:2043-2050] | 裸 `closed`，无 DISCONNECT；sshd log 证实 `Unable to negotiate … Their offer: tp-sshd-audit-bogus-kex`（其 KEXINIT 已发出但 logdie 退出时未冲上线，与 A03/A04 同类） | `msg:20(KEXINIT), closed` — 同样致命、同样无 DISCONNECT；区别仅在 tp_sshd 的 KEXINIT 先到达了线上（`_sendKexInit` 在协商抛 `StateError('No matching key exchange algorithm')` 之前已写出） | **match**（裸关闭这一结果类一致；线上形状的差别见 triage 注记 5） |
| B05 | rekey 时服务器换主机密钥（客户端策略镜像，需 MITM 才能差分运行 — source-only） | OpenSSH 客户端在**每次**交换中重新验证服务器主机密钥，密钥变化即致命。[kexgen.c:167 → kex.c:kex_verify_host_key:1183-1196 → sshconnect2.c:verify_host_key_callback:94-103（fatal "Host key verification failed."）] | source-only — 机制在源码中确认（kexgen.c:167 → kex.c:1183-1196 → sshconnect2.c:94-103） | source-only — dartssh2 客户端同样：ssh_transport.dart:1903-1913 在每次 rekey 重比对已接受密钥的指纹，变化即以 `SSHHostkeyError "Host key changed during rekey: …"` 关闭（刻意不再询问 onVerifyHostKey） | **match**（客户端行为参照行） |
| B06 | 长会话字节阈值：服务器自己会不会发起 rekey — source-only（10.2 默认阈值为密码学几何量级，回环打满需数小时） | sshd 的触发机制**始终在岗**：`max_blocks` 取密码几何界（block≥16 → 2^(block×2) 块；RekeyLimit 取 min；另有 MAX_PACKETS 2^31 硬顶），每次发包与主循环检查，超限即服务器自发 KEXINIT（`kex_start_rekex`），非 KEX 出站包排队到 NEWKEYS。[packet.c:1046-1063; packet.c:1070-1123 + 1366-1399; serverloop.c:385-387；sshd_config.5:1788-1812（默认 "default none"）] | source-only — 机制在源码中确认；10.2 默认仅字节界（RekeyLimit "default none"，servconf.c:398-401 → rekey_limit=0/interval=0），本 harness 实测 sshd 每连接打日志 `rekey in after 4294967296 blocks`（= 2^32 块，AES 16 字节块即 64 GiB） | source-only — **无任何触发机制**：server_connection.dart 无字节计数器、无定时器（"rekey" 零引用）；dartssh2 的 `rekey()`（ssh_transport.dart:2054）是客户端角色 API，服务器代码从不调用 — 密钥只在客户端主动时才轮换 | **fix-divergence** |
| B07 | 时间阈值 rekey（sshd 每小时）— source-only（等 1 小时不现实，且 10.2 默认根本没有时间阈值） | 时间 rekey 仅在 RekeyLimit 配置了 interval 时生效（serverloop.c:171 只在 `rekey_interval > 0` 时排定 deadline，packet.c:1095-1097 触发）；默认（"default none"）sshd 从不按时间 rekey | source-only — 可配置（`RekeyLimit <bytes> <interval>`）但默认关闭：servconf.c:400-401 默认 interval=0 | source-only — 与 B06 同一无：服务器侧不存在任何定时器，配置等价物也无从触发 | **fix-divergence**（与 B06 同一缺失机制） |
| B08 | strict-kex 的 rekey 变体：rekey KEXINIT 之后、NEWKEYS 之前注入乱序 NEWKEYS（strict kex 已协商 — dartssh2 客户端首包带 `kex-strict-c-v00@openssh.com`） | 乱序 NEWKEYS 不被采纳：交换期 dispatch 指向 `kex_protocol_error` → 回 `UNIMPLEMENTED`；但 strict 的读序号复位**照发**（packet.c:1804-1808 对每个收到的 NEWKEYS 复位 p_read.seqnr，rekey 也算），于是客户端下一包 MAC 校验失败（"Corrupted MAC on input."）→ 拆连接、无 DISCONNECT。[kex.c:kex_input_newkeys:531; packet.c:1804-1808; packet.c:1697/1717; packet.c:sshpkt_vfatal] | `msg:20(KEXINIT), msg:3(UNIMPLEMENTED), msg:31(KEXDH_REPLY), msg:21(NEWKEYS)` — 交换**完成**、连接存活；sshd log：复位两次（`resetting read seqnr 4` / `…3`）但**无** "Corrupted MAC" — 预测的 MAC 失效半段未发生：协商出的 aes256-gcm 不把序号绑进 AEAD nonce（只有 chacha20-poly1305 绑，cipher.c:336-340 / cipher-chachapoly.c:69-82），复位因此无害 | `msg:20(KEXINIT), closed` — 乱序 NEWKEYS **被直接采纳**：`_handleMessageNewKeys`（ssh_transport.dart:2016）无进行中检查，用陈旧交换哈希重新推导密钥并终结交换状态；客户端真正的 KEXDH_INIT 随后命中 kex 为空的 `SSHStateError`（ssh_transport.dart:1951-1960）→ 连接被拆，无 DISCONNECT，rekey 永不完成 | **fix-divergence** |

## Area B triage

Verdicts: 3 match (B01, B04, B05), 5 fix-divergence (B02, B03, B06+B07,
B08), 0 deliberate-divergence, 8 rows.

### fix-divergence — acceptance criteria

1. **B02 — rekey 交换窗口内到达的会话流量不得被丢弃。** The shared
   transport (used by BOTH the tp_sshd server and the dartssh2 client)
   answers every incoming non-KEX message that is processed while a key
   exchange is in progress with `UNIMPLEMENTED` and drops it
   (ssh_transport.dart:1625-1627: `_handleMessage` default case →
   `_handleUnexpectedKexMessage` → `_sendUnimplemented`). OpenSSH keeps
   dispatching ids ≥ 50 through a rekey — `kex_reset_dispatch` only guards
   the transport range 1-49 (kex.c:252-256). Both servers queue their
   *outgoing* non-KEX traffic during an exchange, so bulk data is safe; the
   casualties are packets that were sent before the peer's KEXINIT arrived
   and land inside the window. In the audit driver (in-process server, so
   the exec teardown trails the data by event-loop turns) that happens for
   the exit-status/EOF/CLOSE teardown in 1-2 of 8 rounds — the channel then
   hangs forever (the client answered UNIMPLEMENTED for packets 40/41/42;
   both server and client carry the same drop, so any peer whose traffic
   trails its rekey KEXINIT can hit the server half too). Acceptance:
   a non-KEX message racing into the exchange window is processed, or
   buffered and re-dispatched after NEWKEYS — never silently dropped; in
   particular a channel teardown must always survive a rekey.
   (dartssh2-side change.)
2. **B03 — 交换进行中的重复 KEXINIT 必须被拒绝而不是并入协商。**
   Acceptance: while an exchange is in progress, a second KEXINIT draws
   `UNIMPLEMENTED` and the in-flight exchange completes, the way sshd does
   (kex.c:kex_input_kexinit:621 re-registers KEXINIT → kex_protocol_error
   for the duration of the exchange). Today `_handleMessageKexInit` has no
   in-progress guard: it overwrites `_remoteKexInit` and replaces the
   ephemeral kex with a fresh one, the exchange hashes desynchronize, the
   client's verification of KEXDH_REPLY fails ("signature is invalid") and
   the connection dies. (dartssh2-side change: reject or ignore a KEXINIT
   while `_kexInProgress` is true.)
3. **B06/B07 — 服务器必须能主动 rekey。** Acceptance criterion (Task 7):
   a server whose session exceeds `rekeyBytes`/`rekeyInterval` initiates
   KEXINIT unprompted; open channels survive; strict-kex ordering holds;
   an incompatible client gets a clean disconnect. Source truth recorded
   for the fix's defaults: OpenSSH 10.2's default is byte-bound-only —
   `RekeyLimit default none` (sshd_config.5:1788-1812; servconf.c:398-401),
   the bound is cipher geometry (2^(block×2) blocks, observed in the
   harness log as `rekey in after 4294967296 blocks` ≈ 64 GiB at AES's
   16-byte blocks) with a 2^31-packet hard cap, and time-based rekey fires
   only when an interval is configured (serverloop.c:171,
   packet.c:1095-1097). tp_sshd has no trigger of any kind
   (server_connection.dart), so a pairing session's keys never rotate
   unless the client asks.
4. **B08 — 交换外/交换中的 NEWKEYS 不得被无条件采纳。** Acceptance: an
   unsolicited NEWKEYS (mid-exchange, or with no exchange in progress) is
   not applied — it draws `UNIMPLEMENTED` like sshd (kex.c:
   kex_input_newkeys:531 leaves NEWKEYS dispatched to kex_protocol_error
   outside a completed exchange) and the session survives. Today
   `_handleMessageNewKeys` (ssh_transport.dart:2016) applies remote keys
   unconditionally: mid-exchange it re-derives keys from the *stale*
   exchange hash, ends the exchange state and resets the strict-kex
   receive sequence number, after which the peer's real KEXDH_INIT hits
   the kex-null `SSHStateError` (ssh_transport.dart:1951-1960) and the
   connection is torn down without a DISCONNECT (A19's missing-DISCONNECT
   family).

### notes (no action)

5. **B04 — 关闭前的 KEXINIT 是否冲上线是实现差异，不是语义差异。** sshd
   的 log 显示它先排了自己的 KEXINIT（`SSH2_MSG_KEXINIT sent`），
   `logdie` 退出时未冲刷（与 A03/A04 的未冲刷 DISCONNECT 同类），线上
   只见裸 close；tp_sshd 的 KEXINIT 在抛 `StateError` 前已写入 socket，
   线上是 `msg:20` 后 close。两边的致命性、无 DISCONNECT 一致，判定按
   结果类记 match。
6. **B08 的 OpenSSH 半边 — 预测的 MAC 失效依赖协商出的密码套件。**
   strict-kex 的读序号复位在收到乱序 NEWKEYS 时确实触发（log:
   `resetting read seqnr 4`，packet.c:1804-1808），但该连接协商的是
   aes256-gcm@openssh.com — OpenSSH 中只有 chacha20-poly1305 把序号绑进
   AEAD nonce（cipher.c:336-340 → cipher-chachapoly.c:69-82），故复位
   无害、交换照常完成。若协商出 chacha20-poly1305，同一复位会使下一包
   认证失败（"Corrupted MAC on input."）并拆连接。预测的前半段
   （UNIMPLEMENTED + 不采纳）完全证实；后半段按套件记录于此。

## Area C — window handling

All rows run on a real dartssh2 client transport that hand-crafts the
channel messages (the raw driver), so the client-side window the SERVER
sees is the probe's own `CHANNEL_OPEN`/`WINDOW_ADJUST` arithmetic, and
every server channel id is parsed from the confirmation, never assumed.
C01/C02/C10 are observational rows (the window policy itself is the
subject); the sshd `tput` stderr noise from the method section is
normalized out of the byte-exact comparisons. In 10.2 the session
channel's window is only granted when the program starts
(`session_set_fds` → `channel_set_fds`, 2 MiB = `CHAN_SES_WINDOW_DEFAULT`,
channels.h:230), which is the anchor of C02.

| ID | 刺激 | OpenSSH 预期（源码出处） | OpenSSH 实测 | tp_sshd 实测 | 判定 |
|----|------|--------------------------|--------------|--------------|------|
| C01 | 客户端只授 2048 字节接收窗口的 session 通道 + `cat` exec，灌入 1 MiB：回声停在授权窗口处吗？随后 +1024 的 adjust 精确放行多少？服务端对入流的 WINDOW_ADJUST 节奏 | 回声停在恰好授权的窗口字节，直到客户端 adjust；每个 +1024 精确放行 1024；服务端绝不超发；入流 adjust 只在阈值越过时发。[channels.c:channel_output_poll_input_open（remote_window 0 即停读子进程）；channels.c:channel_check_window（低于半窗或 > 3×maxpacket 未消费，且只对真正消费掉的字节）] | 回声停在 2003+45(stderr) 字节（= 2048 窗口，tput 噪声也计入窗口）；+1024 adjust → 3027（+1024 精确）；入流 adjust：11 次共 983040 字节（消费尾随，停测时 64 KiB 尚未消费）— prediction confirmed | 回声停在恰好 2048；+1024 → 3072（+1024 精确）；入流 adjust：8 次共 1048576 字节（记账式，收多少补多少） | **match**（窗口边界与 adjust 精确度一致；adjust 节奏差异为观测记录，见 triage 注 1） |
| C02 | 观测行：两个服务端在 session 通道上的初始窗口授予（confirmation 携带值）+ exec 时刻的 adjust 序列 + 1 MiB 入流的 adjust 节奏 | sshd 的 session 通道 LARVAL 期窗口为 0，confirmation 带 0；程序启动时 session_set_fds → channel_set_fds 以 WINDOW_ADJUST 授 2 MiB。[serverloop.c:server_request_session（channel_new window 0）；session.c:session_set_fds；channels.h:230 CHAN_SES_WINDOW_DEFAULT] | confirmation window=0 maxpacket=32768；exec 后 1 次 adjust 2097152；1 MiB 入流 8 次 adjust 共 1048576 — prediction confirmed | confirmation window=2097152（2 MiB 平铺），exec 后无 adjust；1 MiB 入流 8 次 adjust 共 1048576 | **deliberate-divergence**（tp_sshd 开通道即授 2 MiB 平铺，server_channel.dart initialReceiveWindow — 等效授权，少一次往返） |
| C03 | 32768 字节客户端窗口 + 产出 1 MiB 的 exec（`head -c 1048576 /dev/zero`），客户端永不读取、永不 adjust | 服务端在窗口耗尽后停读子进程（子进程阻塞在 stdout 管道上）；无定时器、无断连；通道停摆、连接存活。[channels.c:channel_output_poll_input_open（remote_window <= 0 即 return）] | 32723+45(stderr) 字节即停（= 32768 窗口），3 秒后再无字节；连接存活；子进程被冻结，无 exit-status | 32768 字节即停；但服务端无背压地读完了子进程全部输出（内存队列），子进程退出 → exit-status → ~2 秒后 EOF+CLOSE（超出授权窗口的尾部被丢弃） | **deliberate-divergence**（bounded-flush 家族，D02：tp_sshd 的 2 s 关闭冲刷界 + 无界写队列 vs sshd 冻结子进程；见 triage 注 2） |
| C04 | 单个 33000 字节 CHANNEL_DATA（> 服务端授予的 32768 maxpacket，但 < 35000 传输层包上限，故观测的是通道策略而非 A03 的长度上限）发到 `cat` exec 通道，随后一个小的界内探测块 | 超大包被丢弃：logit "rcvd big packet" + return 0，无回复，通道与连接都活着，后续探测块照常回显。[channels.c:channel_input_data（win_len > local_maxpacket 分支）] | 33000 字节块后无任何回复；后续 6 字节探测回显（通道活着）— prediction confirmed | 33000 字节块后 `msg:97(CHANNEL_CLOSE)`：整个通道被关闭；后续探测无回显（通道已死）；连接存活 | **deliberate-divergence**（越界包：sshd 静默丢弃 vs tp_sshd 关闭该通道 — `_handleIncoming` 的边界检查；连接两边都不受影响；见 triage 注 3） |
| C05 | 窗口耗尽 + 1 字节：向 `sleep 30`（永不读 stdin 的程序）灌 2 MiB + 32768 + 1 字节，再补 ~320 KiB 越过 10% 宽限 | 首次越界被容忍（local_window_exceeded 累计、窗口清零、数据仍入缓冲、不回包）；越过 local_window_max/10 后 DISCONNECT(2, "channel N: peer ignored channel window")。[channels.c:channel_input_data] | 阶段 1：1 次 adjust 65536（管道消费），无断连（管道 64 KiB 余量吸收了首次越界）；阶段 2 (+320 KiB)：`msg:93, closed` — DISCONNECT 入队但未冲上线（A03 家族），sshd log 证实 `peer ignored channel window` — 机制证实 | 阶段 1：16 次 adjust 共 2097152（记账式回补，窗口从未真正耗尽）；阶段 2：19 次 adjust 共 2457601，永不断连，无界缓冲 | **fix-divergence**（A16 的 session 通道正式化：接收窗口纯按记账回补、无消费要求、无 10% 宽限强制 — 服务端可被无界缓冲；验收标准见 triage 注 4） |
| C06 | 三个 WINDOW_ADJUST 异常依次：发给未创建通道 99999 的 adjust、对已开通道的 adjust 0、以及在 send window 已为 0xffffffff 的通道上 +1（溢出） | 未知通道：logit 后忽略，无回复；adjust 0：no-op 无回复；溢出：fatal "channel %d: adjust %u overflows remote window %u" — 线上无 DISCONNECT 的拆连接。[channels.c:channel_input_window_adjust] | 未知通道与 adjust 0 均无回复（prediction confirmed）；溢出 adjust：裸 `closed`，sshd log 证实 `overflows remote window` | 未知通道与 adjust 0 同样无回复；溢出 adjust：`msg:97(CHANNEL_CLOSE)` — 只关闭该通道（`_failChannel`），连接存活 | **deliberate-divergence**（前两项一致；溢出的处置范围不同：sshd fatal 杀整条连接 vs tp_sshd 只关该通道 — fork 客户端策略的镜像；见 triage 注 5） |
| C07 | rekey 下的窗口压力（B01 变体，×3 轮）：65536 字节客户端窗口的 `cat` exec，灌 512 KiB，客户端以 50 ms 泵调整窗口，echo ≥ 64 KiB 时 rekey()；回声必须逐字节完整、通道必须收尾 | 两边都在交换期排队非 KEX 出站包、NEWKEYS 后按序冲刷；入站通道消息照常分发；流完整收尾。[packet.c:ssh_packet_send2；channels.c:channel_check_window] vs dartssh2 共享传输层的 UNIMPLEMENTED 丢弃（B02 记录） | 1/3 轮干净；失败轮：echo 冻结在 130982/524288（前缀完整）、通道永不关闭、0 次 UNIMPLEMENTED — 失败由驱动侧客户端半边丢弃在途 DATA 造成（B02 客户端半） | 0/3 轮干净；每轮 echo 冻结在恰好 65536（首个窗口边界）、通道经 2 s 界收尾、0 次 UNIMPLEMENTED — adjust/数据包竞进服务端交换窗口被丢弃后发送窗口饿死（B02 服务端半） | **fix-divergence**（B02 家族：交换窗口内到达的非 KEX 消息被静默丢弃；C07 补充了两个方向的证据与窗口压力下的确定性死锁形态；验收标准同 B02） |
| C08 | max-channels 洪泛：一条连接开 11 个 session 通道（tp_sshd maxChannels 10；sshd MaxSessions 默认 10） | 前 10 个确认，第 11 个失败：session_new 达到 max_sessions 返回 NULL → CHANNEL_OPEN_FAILURE，reason 保持初值 SSH2_OPEN_CONNECT_FAILED(2)，描述 "open failed"。[session.c:session_new；serverloop.c:server_request_session + server_input_channel_open；servconf.h:40 DEFAULT_SESSIONS_MAX 10] | 10/11 确认；第 11 个 `reason=2 "open failed"` — prediction confirmed | 10/11 确认；第 11 个 `reason=4 "Too many open channels (10/10)"` | **deliberate-divergence**（上限数量一致（10=10）；拒绝码不同：reason 4（resource shortage）恰是 RFC 4254 §5.1 为此情形建议的码 — tp_sshd 的更贴切） |
| C09 | 第 11 个通道的确切拒绝观测 + 槽位回收：拒绝后关掉一个已确认通道，再开一个 | 已关闭通道的槽位归还：新开被确认（sshd 经 cleanup 回调释放 session；上限计的是活通道）。[channels.c:channel_free；serverloop.c] | 10/11 确认后拒绝（reason=2）；关闭一个通道后新开：confirmed（槽位回收）— prediction confirmed | 10/11 确认后拒绝（reason=4）；关闭一个通道后新开：confirmed（槽位回收） | **match**（拒绝码差异属 C08；本行问题 — 槽位回收 — 行为一致） |
| C10 | 观测行：真实 dartssh2 SftpClient 的 4 MiB SFTP 往返（流水线 WRITE 后流水线 READ） | 双端完成往返、字节完整；流水线请求受 session 通道 2 MiB 窗口约束，无停顿无错误。[sftp-server.c process() 循环；channels.h:230 经 session_set_fds] | 4 MiB 往返：上传 3817ms，下载 3736ms，4194304 字节读回，字节完整 | 4 MiB 往返：上传 7482ms，下载 7446ms，4194304 字节读回，字节完整 | **match**（观测行：完成与完整性一致；tp_sshd 每方向约慢 2×，记录为观测差距，见 triage 注 6） |

## Area C triage

Verdicts: 3 match (C01, C09, C10), 5 deliberate-divergence (C02, C03,
C04, C06, C08), 2 fix-divergence (C05, C07), 10 rows.

### fix-divergence — acceptance criteria

1. **C05 — the granted window must be enforceable (A16's finding, extended
   to session channels).** A peer that keeps sending past the granted
   window beyond the grace margin (sshd: 10% of `local_window_max`) must
   be disconnected (`channel <id>: peer ignored channel window`, reason
   2; the DISCONNECT may be queued-unflushed exactly like sshd's — the
   acceptance observable is the teardown + the bound). Today
   `_grantReceiveWindowIfNeeded` (server_channel.dart) refills on pure
   receipt accounting (below half or > 3 packets — regardless of
   consumption), so against a non-reading program the window is never a
   bound and the server buffers unboundedly (this row: 2.4 MiB into a
   `sleep`). One fix serves A16 + C05 + C03's receive half.
2. **C07 — non-KEX messages racing into the exchange window must not be
   dropped (B02's acceptance criterion, unchanged).** Under window
   pressure the drop is a deterministic deadlock: tp_sshd 0/3 rounds
   froze at exactly the client's initial window (the WINDOW_ADJUST that
   would reopen the server's send window was dropped mid-exchange; the
   channel then only finished via the 2 s close-flush bound). The sshd
   side also lost rounds (1/3) to the same shared-transport drop in its
   client half — in-flight echo DATA discarded while the client was
   exchanging — which is why this is one cross-cutting dartssh2-side fix
   (buffer and re-dispatch after NEWKEYS) and not a per-server behavior
   gap.

### deliberate-divergence (documented, not scheduled for fixing)

- **C02** — initial grant: sshd confirms session channels with window 0
  (LARVAL) and grants the 2 MiB via WINDOW_ADJUST when the program
  starts; tp_sshd confirms with the full 2 MiB immediately. Same effective
  grant, one round-trip cheaper; both stay at 2 MiB (no dynamic growth on
  either server — OpenSSH's client-side dynamic window is a client
  policy, not a server one).
- **C03** — non-reading client: sshd stops reading the child at window 0
  (the child freezes on its stdout pipe; the channel is held open
  indefinitely); tp_sshd has no send-side backpressure — the child's
  whole output is queued in memory, the process exits, and the channel
  finishes (exit-status, then EOF + CLOSE after the 2 s close-flush
  bound), dropping everything past the client's grant. Recorded with the
  D02 bounded-flush choice; the client-visible edge (a client that pauses
  > 2 s after process exit loses the tail it had not granted) is noted
  under D02's triage entry as the recorded risk of that bound.
- **C04** — a single data chunk over the granted maximum packet size:
  sshd drops the packet silently ("rcvd big packet") and the channel
  lives on; tp_sshd closes the channel (connection unaffected). A sender
  violating the advertised maxpacket is misbehaving either way; tp_sshd's
  channel-scope teardown is the documented `_handleIncoming` bound check.
  Candidate to revisit: matching sshd's tolerant drop would keep
  buggy-but-recoverable clients alive.
- **C06** — an overflowing WINDOW_ADJUST (uint32 wrap): sshd's `fatal`
  kills the whole connection (no wire DISCONNECT, log-only); tp_sshd
  closes just the offending channel (`_failChannel`, mirroring the fork's
  client-side policy of failing a channel without taking the connection
  down). The unknown-channel and zero adjust halves are identical (both
  silent).
- **C08** — channel/session cap: both cap at 10; the refusal differs —
  sshd reason 2 "open failed" vs tp_sshd reason 4 "Too many open channels
  (10/10)". RFC 4254 §5.1's reason 4 (resource shortage) is exactly this
  case, so tp_sshd's reply is the more spec-apt of the two.

### notes (no action)

1. **C01 adjust cadence** — sshd granted the inbound stream back in 11
   consumption-trailing adjusts (983040 of 1048576 bytes by the time the
   row stopped; the last 64 KiB was still unconsumed in the pipe), while
   tp_sshd granted all 1048576 in 8 receipt-accounting adjusts. Both end
   with the window effectively restored; the cadence difference is the
   same accounting-vs-consumption distinction as C05, observed here
   without any enforcement consequence.
2. **C03's sshd half** — the child freeze means sshd never delivers
   exit-status while the window is exhausted (the process cannot exit);
   this is the same mechanism D02 phase 2 records from the exit-path
   angle.
3. **C04's transport cap interplay** — a chunk larger than ~34990 bytes
   never reaches the channel layer on tp_sshd at all: the shared
   dartssh2 transport rejects packets over 35000 bytes (`SSHPacket.
   maxLength`) and tears the connection down (A03's ambient difference).
   The row therefore uses 33000 bytes to observe the channel policy.
4. **C05's sshd nuance** — the "1 byte past the window" overage was
   absorbed by the child's 64 KiB stdin-pipe slack (consumed = 65536), so
   the excess counter only crossed the 10% grace in phase 2; the
   disconnect itself arrived queued-unflushed (bare close), confirmed by
   the sshd log — the same unflushed-DISCONNECT shape as A03/A04.
5. **C10 throughput** — tp_sshd's SFTP is ~2× slower per direction
   (7.4 s vs 3.7 s for 4 MiB): the harness `LocalSftpFileSystem`
   serializes position+read/write pairs per handle while sshd's
   internal-sftp reads with larger concurrency. Correctness identical
   (byte-intact both ways); recorded as an observation for Task 7's
   performance candidates, not a divergence.

## Area D — channel close races

In 10.2 the channel teardown state machine lives in nchan.c
(`chan_rcvd_ieof` / `chan_rcvd_oclose` / `chan_is_dead`), and the session
exit path in session.c (`session_close_by_pid` → `session_exit_message`)
— that is where these citations point. All rows hand-craft the channel
messages on the raw driver; the sshd `tput` stderr noise is normalized
(method section).

| ID | 刺激 | OpenSSH 预期（源码出处） | OpenSSH 实测 | tp_sshd 实测 | 判定 |
|----|------|--------------------------|--------------|--------------|------|
| D01 | 客户端 EOF 后继续发 DATA：`cat > /dev/null; sleep 30` exec 在 EOF 后仍活着（cat 半程结束、sleep 半程撑住通道），客户端再发 10 字节 | EOF 后的普通 DATA 无 EOF 检查：ostate != OPEN 分支假消费（仅记账，字节丢弃），无回复、连接存活；只有 EOF 后的 EXTENDED data 才断连。[channels.c:channel_input_data；channel_input_extended_data] | EOF 后 10 字节：无任何回复，连接存活 — prediction confirmed | EOF 后 10 字节：连接被整个拆掉（裸 `closed`，无 DISCONNECT）— `handleEof` 关闭输入控制器后 `_handleIncoming` 对已关控制器 add 抛错，经传输层 dispatch 传播到 closeWithError | **fix-divergence** |
| D02 | 输出仍在等窗口信用时收尾。阶段 1：4096 字节客户端窗口 + 256 KiB 输出，首批发到后客户端发 CHANNEL_CLOSE；阶段 2：同样压力但不关 — exit-status/EOF/CLOSE 相对进程退出何时落地 | 阶段 1：chan_rcvd_oclose → ostate WAIT_DRAIN — 无信用则永远等待，不回 CLOSE。阶段 2：进程退出路径丢弃挂起输出（chan_write_failed 重置缓冲）：exit-status → EOF → CLOSE 立即连发。[nchan.c:chan_rcvd_oclose；session.c:session_exit_message] | 阶段 1：0 个后续数据字节，`exit-signal(PIPE) → CLOSE`（关闭读端使 head SIGPIPE 死亡，子进程退出路径收尾 — 与预测的"沉默挂起"不同，预测被证伪）；阶段 2：10 秒内 exit-status 未到（子进程被窗口冻结，无法退出 — C03 机制） | 阶段 1：0 个后续数据字节，立即 `CLOSE`（队列丢弃、进程杀死、无退出报告）；阶段 2：exit-status 立即到达，EOF + CLOSE 在 1974 ms 后（2 s closeFlushTimeout 界），尾部丢弃 | **deliberate-divergence**（bounded-flush 2 s 界；两阶段的完整差异见 triage 注 1） |
| D03 | 双方 EOF：`echo done` exec，客户端在 exec 应答后立即发 CHANNEL_EOF（从不发 CLOSE）— 谁先发 CLOSE、收尾顺序 | 客户端 EOF 后服务端输出进入 WAIT_DRAIN；子进程退出驱动 exit-status → EOF → CLOSE；CLOSE 由服务端发出。[nchan.c:chan_rcvd_ieof；chan_is_dead/chan_send_close2；session.c:session_close_by_pid] | `data:5 → CHANNEL_SUCCESS → stderr(45) → EOF → exit-status(0) → CLOSE`；CLOSE 来自服务端 — prediction confirmed（EOF 先于 exit-status，见 D04） | `data:5 → CHANNEL_SUCCESS → exit-status(0) → EOF → CLOSE`；CLOSE 来自服务端 | **match**（关闭发起者与收尾完成一致；exit-status/EOF 顺序差是 D04 的记录项） |
| D04 | 无任何客户端 EOF 的 exit-status 排序：`echo ok` exec，客户端只等 — 观测 exit-status/EOF/CLOSE 顺序与退出码 | session_close_by_pid → session_exit_message 先发 exit-status，再 chan_write_failed；EOF 由子进程 stdin 管道排空驱动，CLOSE 最后。[session.c:session_exit_message；nchan.c:chan_ibuf_empty → chan_send_eof2；chan_is_dead → chan_send_close2] | `data:3 → CHANNEL_SUCCESS → stderr(45) → EOF → exit-status(0) → CLOSE` — EOF 抢在 exit-status 之前（管道 EOF 与 SIGCHLD 路径竞速，观测两次一致）；CLOSE 最后 — 预测的前半段被实测修正 | `data:3 → CHANNEL_SUCCESS → exit-status(0) → EOF → CLOSE` — exit-status 严格先于 EOF/CLOSE | **deliberate-divergence**（顺序：tp_sshd 刻意先发 exit-status — `_pipeProcess` 注释"a client that sees EOF first may stop waiting for it"；两种顺序都为 RFC 所容，sshd 的 EOF 先行是其两条异步路径的竞速结果） |
| D05 | 通道彻底死亡后再发 CHANNEL_REQUEST（echo ok 通道完全关闭并确认后，对其再发一个 want_reply 的 `env` 请求） | 通道已释放：channel_lookup 失败 → DISCONNECT(2, "server_input_channel_req: unknown channel <id>")，连接被拆。[serverloop.c:server_input_channel_req] | `disconnect:2("server_input_channel_req: unknown channel 0")`，log 证实 — prediction confirmed | 无任何回复，连接存活（通道已从表中移除，静默忽略 — A15 家族） | **fix-divergence**（A15 的同类：验收标准并入 A15 — 通道作用域消息对不存在通道应回协议错误，涵盖 DATA 与 REQUEST） |
| D06 | 通道中途的 TCP RST（观测行）：exec 流式输出 1 MiB 中客户端以 SO_LINGER 0 硬拆 socket | 读错误路径拆连接、收尸子进程、监听器无恙；sshd log 记录 reset。[sshd-session.c 会话主循环读错误路径；serverloop.c] | RST 发出（已收 1 MiB 且仍在流）；sshd log 证实 `Connection reset`；监听器存活 | RST 发出；进程内服务端存活，运行器 zone 无 stray async error；监听器存活 | **match** |
| D07 | 客户端在子进程（`sleep 2`）仍运行时、未发任何 EOF 就发 CHANNEL_CLOSE | chan_rcvd_oclose 后 channel_garbage_collect 因 session cleanup 回调 force=0 而持有"almost dead"通道：子进程活着时不回 CLOSE；子进程退出时 session_close_by_pid 仍交付 exit-status 与 CLOSE（无 EOF）。[nchan.c:chan_rcvd_oclose；channels.c:channel_garbage_collect；serverloop.c:server_request_session] | `exit-status(0) → CLOSE`，CLOSE 在子进程退出时（~2 s）才回，此前沉默 — prediction confirmed | 立即 `CLOSE`（handleClose → _finish：队列丢弃、进程杀死），无 exit-status | **deliberate-divergence**（提前 CLOSE 的语义：sshd 持通道至子进程退出并补报 exit-status vs tp_sshd 立即收尾并杀进程；客户端已声明不再需要通道，两种读法皆合规；见 triage 注 2） |
| D08 | 服务端发起的 `forwarded-tcpip` 通道（tcpip-forward 到 127.0.0.1:0 后拨入一条连接）被客户端以 CHANNEL_CLOSE 回应而非确认 — pending-open 竞态；随后控制连接正常确认 | OPENING 通道收 CLOSE 应被拆除：接受 socket 随 fd 关闭 — 拨入连接被服务端关闭。[channels.c:channel_post_port_listener；nchan.c:chan_rcvd_oclose] | CLOSE 后无任何回复；拨入连接保持打开（**通道僵尸**：SSH_CHANNEL_OPENING 在 channel_handler_init 的 pre/post 表中无处理项，ostate 停在 WAIT_DRAIN，永不释放 — 预测被证伪）；控制连接：echo 正常（转发仍活） | CLOSE 后无任何回复；拨入连接保持打开（pending open 永不裁决，连接被持有到 SSH 连接结束）；控制连接：echo 正常（转发仍活） | **match**（两端都持有被 CLOSE 的 pending open、都不回包、转发都存活；sshd 的僵尸机制记录于 triage 注 3） |
| D09 | pty 会话（pty-req + shell）键入 `exit` 退出：exit-status/EOF/CLOSE 排序与 pty 清理 | session_close_by_pid：exit-status 经 session_exit_message，随后 session_pty_cleanup 释放 tty；EOF/CLOSE 由 nchan 状态机收尾。[session.c:session_close_by_pid / session_pty_cleanup] | `data:588 → EOF → exit-status(0) → CLOSE`，通道即时收尾 | `data:342 → exit-status(0) → EOF → CLOSE`，通道即时收尾 | **match**（收尾完成、退出码、及时性一致；exit-status/EOF 顺序差是 D04 的记录项；data 字节数差异为两边 shell 启动噪声） |
| D10 | 对 `sleep 30` exec 通道发带 `SIGBOGUS` 名字的 `signal` 请求（want_reply = true） | name2sig 失败 → error "unsupported signal" → success 0 → CHANNEL_FAILURE；连接存活。[session.c:session_input_channel_req → session_signal_req] | `msg:100(CHANNEL_FAILURE)`，log 证实 `unsupported signal` — prediction confirmed | 无任何回复，连接存活 — 共享 dartssh2 解码器的 `.signal` 工厂把 wantReply 硬编码为 false（msg_channel.dart:781-791），服务端根本看不到该标志位 | **deliberate-divergence**（RFC 4254 §6.9 的报文格式本身把 signal 的 want reply 钉为 FALSE，合规客户端不会等待回复；sshd 的 CHANNEL_FAILURE 是其通用 want_reply 处理。解码器丢标志位是潜在的 dartssh2 缺陷，随信号功能一并修 — triage 注 4） |

## Area D triage

Verdicts: 4 match (D03, D06, D08, D09), 4 deliberate-divergence (D02,
D04, D07, D10), 2 fix-divergence (D01, D05), 10 rows.

### fix-divergence — acceptance criteria

1. **D01 — data after EOF must not kill the connection.** A
   `CHANNEL_DATA` arriving after the client's `CHANNEL_EOF` on a live
   channel must be tolerated the way sshd tolerates it (dropped with
   window accounting only, channels.c:channel_input_data's
   `ostate != CHAN_OUTPUT_OPEN` branch) — or delivered — but never
   allowed to throw. Today `handleEof` closes the channel's input
   `StreamController` and `_handleIncoming`'s `controller.add` on the
   closed controller throws synchronously; the error escapes the
   transport dispatch into `closeWithError` and the WHOLE connection is
   torn down with nothing on the wire (one misbehaving channel kills
   every other channel on the connection). Acceptance: post-EOF data on
   a live channel leaves the connection serving (drop it like sshd, or
   close just that channel). (tp_sshd-side change: guard
   `_handleIncoming` on `_receivedEof`.)
2. **D05 — requests for a nonexistent channel must be a protocol error
   (the A15 fix, extended).** Same acceptance criterion as A15, with the
   class widened: every channel-scoped message (DATA, REQUEST, EOF, …)
   addressed to an unknown recipient draws
   `DISCONNECT(2, "<what> packet referred to nonexistent channel <id>")`
   the way sshd does (serverloop.c:server_input_channel_req's
   "unknown channel" disconnect), instead of being silently ignored.

### deliberate-divergence (documented, not scheduled for fixing)

- **D02 — the bounded close flush.** tp_sshd gives pending outgoing data
  a 2 s window-credit wait (`closeFlushTimeout`, server_channel.dart)
  before finishing the channel; sshd has no bound at all — on the exit
  path it drops the tail instantly (`chan_write_failed` resets the
  output buffer), and on a received CLOSE it either waits for a drain
  that may never come (frozen child) or lets the child die of SIGPIPE
  (observed: `exit-signal(PIPE)` → CLOSE, because `chan_shutdown_read`
  closes the child's stdout read end). The recorded risk of tp_sshd's
  2 s bound: a healthy-but-slow client that does not grant the tail's
  credit within 2 s of process exit loses data it had every intention of
  reading (C03's manifestation). A future refinement could keep the
  bound only for peers that have actually gone quiet, but the bound
  itself is the documented spec choice.
- **D04 — exit-status strictly before EOF.** tp_sshd deliberately sends
  `exit-status` before EOF/CLOSE (`_pipeProcess`: "a client that sees
  EOF first may stop waiting for it"); sshd's EOF is driven by the
  stdout-pipe EOF and raced ahead of the SIGCHLD exit path in every
  observed round. Both orders are legal; clients must accept either.
- **D07 — early client CLOSE.** sshd holds the channel "almost dead"
  until the child exits (the session cleanup callback is registered with
  force=0) and still delivers `exit-status` + CLOSE then; tp_sshd
  finishes immediately (`handleClose` → `_finish`), kills the process,
  and sends no exit-status. The client has declared the channel
  unneeded; tp_sshd trades the late exit report for immediate teardown
  and no orphaned process.
- **D10 — signal with a bogus name.** sshd answers `CHANNEL_FAILURE` (its
  generic want_reply handling; the name lookup failed with "unsupported
  signal"); tp_sshd sends nothing because the shared dartssh2 decoder's
  `.signal` factory hardcodes `wantReply: false` (msg_channel.dart), so
  the server never sees the flag. RFC 4254 §6.9 pins `want reply FALSE`
  in the signal message format itself, so no compliant client waits for
  a reply — recorded as deliberate, with the decoder flag-loss noted as
  a latent dartssh2 issue to fix alongside any signal work.

### notes (no action)

1. **D02 phase-by-phase summary** — phase 1 (client CLOSE, 252 KiB
   pending credit): both servers sent 0 more data bytes and finished the
   channel, by different routes — sshd via the child's SIGPIPE death
   (`exit-signal(PIPE)` → CLOSE), tp_sshd by dropping the queue
   immediately (CLOSE only, no exit report). Phase 2 (server exit under
   the same pressure): sshd's child froze on its stdout pipe (no
   exit-status within 10 s — C03's mechanism seen from the exit path);
   tp_sshd's unbounded queue let the process exit immediately, with
   exit-status → EOF → CLOSE landing 1974 ms later (the 2 s bound).
2. **D07/D02 phase 1's exit reports** — where sshd reports the child's
   death (`exit-signal(PIPE)` after a CLOSE-induced read-end shutdown;
   `exit-status` at child exit after an early CLOSE), tp_sshd kills the
   process silently on channel close (`_pipeProcess` teardown). The
   exit-report-after-close family is part of the same early-CLOSE policy
   divergence as D07.
3. **D08's sshd half — the prediction was wrong, and the actual is
   interesting.** `chan_rcvd_oclose` tears down `SSH_CHANNEL_LARVAL`
   channels immediately, but a pending server-initiated open is
   `SSH_CHANNEL_OPENING`, and `channel_handler_init` (channels.c) has no
   pre/post handler for OPENING — so on sshd 10.2 a CLOSE addressed to
   an unconfirmed forwarded-tcpip channel leaves it in
   istate-CLOSED/ostate-WAIT_DRAIN forever: no reply, no free, the
   accepted socket never closed. tp_sshd's pending-open map holds the
   same connection for the same observable outcome; both release
   everything only when the SSH connection ends. The control connection
   round-trips on both, so forwarding itself never degrades.
4. **D10's decoder detail** — the want_reply flag loss is in the shared
   dartssh2 `SSH_Message_Channel_Request.signal` factory (decode path),
   not in tp_sshd: a tp_sshd fix is not possible without the decoder
   preserving the flag. Folded into the dartssh2-side fix list.


## Area E — timing surfaces

Timing rows (E01, E02, E05) are judged `match-in-kind` — both uniform or
both variable — never by numeric equality; wall-clock µs over loopback TCP
are not comparable across processes. What IS a finding is an oracle: a
failure class one server makes indistinguishable (by padding) that the
other answers at measurably different speeds. E01/E02/E04 run on dedicated
harness pairs (`startAuditServers(sshdConfigExtras: …)`) — see the method
section; latencies are read from the raw driver's µs observation
timestamps. In 10.2 the auth-failure padding lives in `auth2.c`
(`ensure_minimum_time_since` + `user_specific_delay`: a 5 ms floor plus
0–4.2 ms per-username pseudorandom jitter derived from a secret) — that
mechanism is the anti-oracle E01 measures.

| ID | 刺激 | OpenSSH 预期（源码出处） | OpenSSH 实测 | tp_sshd 实测 | 判定 |
|----|------|--------------------------|--------------|--------------|------|
| E01 | 认证失败时延分布：三种失败条件各 50 次全新连接（每条件新连接，避开两端的 6 次失败上限）——wrong-key（真实用户名 + 未授权密钥 + **有效** RFC 4252 §7 签名）、unknown-user（不存在的用户名，其余为有效登录）、malformed-blob（不可解码密钥 blob，A10 形状）——测量 USERAUTH_REQUEST 发出到 USERAUTH_FAILURE 回复的墙钟 µs，每格 median/p95/max（专用 harness，PerSourcePenalties 关闭：150 次失败登录测的是认证时延而非惩罚门控） | 每个失败的 non-"none" 尝试都被垫时：5 ms 下限 + 0–4.2 ms 由 timing_secret 派生的按用户名伪随机抖动，之后才回包——三种失败条件在时延上不可区分（垫时即反预言机；路径差异被下限吸收）。[auth2.c:input_userauth_request -> ensure_minimum_time_since + user_specific_delay] | wrong-key med 6986µs p95 7571µs；unknown-user med 7744µs p95 8115µs；malformed-blob med 6765µs p95 7066µs — 同用户名的两条件（wrong-key/malformed）仅差 220µs，unknown-user 的 ~1 ms 落差是按用户名抖动（秘密派生的常量，不泄露路径） | wrong-key med 2808µs p95 3805µs；unknown-user med 902µs p95 1213µs；malformed-blob med 630µs p95 838µs — 三类清晰可分：正确用户名要付完整 ed25519 验签 + 异步 authenticate 回调（~2.8 ms），错误用户名在用户名比较处提前退出（~0.9 ms），坏 blob 在解码/回调处最快（~0.6 ms） | **fix-divergence**（用户名枚举预言机：正确用户名的拒绝比错误用户名慢 3 倍，sshd 用垫时防住的正是这个；验收标准见 triage 注 1） |
| E02 | 认证前空闲超时：拨号完成 KEX、协商 ssh-userauth 后不发任何字节，测量拆连接的时刻与方式（两端都配 3 s：sshd `LoginGraceTime 3`、tp_sshd `authTimeout 3 s`，使行可运行；默认值差异记录于 triage 注 3） | setitimer 为 login_grace_time 加 0–4 s 随机抖动（arc4random_uniform(4×10⁶) µs）；到时 grace_alarm_handler 杀进程组并 `_exit(EXIT_LOGIN_GRACE)`——静默关闭、线上无 DISCONNECT，落在 ~3–7 s。[sshd-session.c:1238-1248；sshd-session.c:211 grace_alarm_handler] | 4.29 s 处静默 `closed`（3 s + ~1.3 s 抖动，落在预测区间） | 2.97 s 处静默 `closed`（定时器自连接建立起 3 s 整、无抖动；测量锚点在 KEX+协商之后，故读数略小于 3.00，见 triage 注 2） | **match**（等配置下机制一致：超时即静默拆连接、无 DISCONNECT；默认值 30 s vs 120 s 为 deliberate，见 triage 注 3） |
| E03 | 认证后空闲：已认证连接 5 s 内无任何流量（无通道）——服务端有无 keepalive 探测、有无空闲断连 | 两端都不探测也不断连：client_alive_interval 默认 0 = 禁用（client_alive_check 仅在 interval > 0 时发探测）；tp_sshd 认证成功即取消唯一的 _authTimer，此后无任何定时器。[servconf.c:452-455；serverloop.c:client_alive_check；server_connection.dart] | 5 s 空闲零流量（2 条环境噪声消息已过滤），连接存活 — prediction confirmed | 5 s 空闲零流量，连接存活 | **match** |
| E04 | 认证前连接洪泛：顺序开 7 条连接并保持未认证（专用 harness，sshd 配 `MaxStartups 3:100:6` 使丢弃模式确定：begin=3、rate=100%、full=6）；按每条连接的首字节分类（SSH banner = 接受） | children_active < 3 的连接被接受（banner）；达到 3 后每个新连接被 drop_connection 拒绝：在任何 SSH banner 之前收到明文 `Not allowed at this time\r\n`，随后 socket 被父进程关闭。[sshd.c:drop_connection + should_drop_connection；sshd.c:1147 close(newsock)] | accepted #1–#3（banner），dropped #4–#7（拒绝行 + 关闭），sshd log 证实 `drop connection` — prediction confirmed | 7/7 全部接受（banner），无任何拒绝 | **deliberate-divergence**（tp_sshd 无认证前连接上限——嵌入式配对场景的监听面不由服务端自限；见 triage 注 4） |
| E05 | 通道上限的执行时机（认证后）：先确认 10 个 session 通道，再计时 10 次第 11 个 open——每次 CHANNEL_OPEN 发出到 CHANNEL_OPEN_FAILURE 回复的 µs（C08 已记录拒绝码差异，本行是执行时机半边） | 两端都在 dispatch 当轮即时拒绝，无延迟、无限速：session_new 达到 max_sessions 返回 NULL，server_input_channel_open 立即回 CHANNEL_OPEN_FAILURE。[session.c:session_new；serverloop.c:server_input_channel_open] | 10/11 确认，第 11 个拒绝 reason=2 "open failed"，med 720µs p95 772µs max 838µs | 10/11 确认，第 11 个拒绝 reason=4 "Too many open channels (10/10)"，med 662µs p95 956µs max 1176µs | **match**（in-kind：两端均在分发当轮亚毫秒拒绝；拒绝码差异归 C08） |
| E06 | keepalive 全局请求节奏：认证后流水线连发 20 个 `keepalive@openssh.com` GLOBAL_REQUEST（want_reply=1，间隔为零），随后活性检查——每个都必须被应答 | `keepalive@openssh.com` 不在 server_input_global_request 的已知请求表里（它是 sshd 自己的**出站** keepalive 名，serverloop.c:132-138）→ 未知请求 → success 保持 0 → 每个 REQUEST_FAILURE；sshd 的容活语义是任意四种回复都重置计数器（server_input_keep_alive）。[serverloop.c:server_input_global_request；serverloop.c:402-410] | 20 × REQUEST_FAILURE，连接存活 — prediction confirmed | 20 × REQUEST_SUCCESS，连接存活 | **deliberate-divergence**（应答种类不同、存活等价：任何合规客户端把任意回复都当活性证明；见 triage 注 5） |

## Area E triage

Verdicts: 3 match (E02, E03, E05), 2 deliberate-divergence (E04, E06),
1 fix-divergence (E01), 6 rows. Timing rows are judged match-in-kind, never
by numeric equality (area method note).

### fix-divergence — acceptance criteria

1. **E01 — auth-failure timing must not be an oracle.** A remote peer
   timing the `USERAUTH_FAILURE` reply must not be able to distinguish
   failure classes — in particular whether the USERNAME matched. Today
   tp_sshd's three failure paths have disjoint costs (wrong-key med
   ~2.8 ms — the full ed25519 verify plus the async authenticate callback;
   unknown-user ~0.9 ms — the username mismatch early-exit before any
   crypto, server_connection.dart:634; malformed-blob ~0.6 ms), so a
   correct username is ~3× slower to reject than a wrong one. sshd
   prevents exactly this by padding every failed non-"none" attempt to a
   common floor before replying (auth2.c:ensure_minimum_time_since +
   user_specific_delay: 5 ms minimum + 0-4.2 ms pseudorandom per-username
   jitter derived from a secret — measured 6.8/7.0/7.7 ms medians with the
   same-username conditions within 0.22 ms, the cross-username gap being
   the secret-derived constant). Acceptance: fresh-connection-per-trial
   median reply latencies for wrong-key / unknown-user / malformed-blob
   are indistinguishable within the noise band. An implementation may
   adopt sshd's floor+jitter scheme or equivalent constant-work padding;
   note the fix is the total path time, not the individual compares (the
   early-exit username compare and the embedder's early-exit key compare
   are not themselves the observable).

   *Fix landed (2026-09-14):* `SSHServerConfig.authFailureMinDelay` (a
   10 ms floor by default, `Duration.zero` disables) pads every failure
   reply — the `USERAUTH_FAILURE`, or the throttle disconnect — out to the
   floor measured from the request's receipt; the throttle verdict is
   captured at receipt so pipelined attempts keep their reply assignment.
   Area E regeneration (50 fresh connections per condition): tp_sshd
   wrong-key med 11200 µs / unknown-user med 10871 µs / malformed-blob med
   10185 µs (was 2808 / 902 / 630 µs — a 4.5x spread). The three
   conditions now sit within one noise band, in-kind with the same run's
   sshd cells (8452 / 7487 / 8256 µs, itself a ~13% spread). Per-username
   jitter (sshd's `user_specific_delay`) is recorded as a hardening
   follow-up, not part of the floor.

### deliberate-divergence (documented, not scheduled for fixing)

- **E04 — no pre-auth connection cap.** sshd bounds concurrent
  unauthenticated connections (MaxStartups 10:30:100 by default;
  drop_connection answers with the plaintext "Not allowed at this time"
  line and closes before any banner); tp_sshd accepts every connection
  and gives each its full auth window. Embedded context: the server is
  paired with the app client on the device — the flood surface the cap
  defends against (an internet-facing sshd) is not this deployment, and
  an embedder that needs the bound can enforce it at the listener (the
  harness's own `ServerSocket`). A configurable cap policy is a Task 7
  backlog candidate, not a fix.
- **E06 — keepalive answered REQUEST_SUCCESS.** sshd replies
  REQUEST_FAILURE (keepalive@openssh.com is unknown to its global-request
  handler — it is the name sshd itself uses for outgoing keepalives);
  tp_sshd special-cases the name and replies REQUEST_SUCCESS
  (server_connection.dart:209-215). Liveness-equivalent: sshd's own
  contract accepts any of the four reply types as proof of life
  (server_input_keep_alive), so no compliant client observes a difference
  beyond the reply id. Related observation: tp_sshd never SENDS
  keepalives — it has no ClientAliveInterval equivalent (E03's
  none/none).

### notes (no action)

1. **E01's sshd cross-username gap** — sshd's unknown-user cell (7.7 ms
   median) sits ~1 ms above the same-username cells; that is
   user_specific_delay working as designed (each username draws a
   secret-derived constant of 0-4.2 ms; this run's draws happened to
   differ by ~1 ms). Same-username conditions (wrong-key, malformed-blob)
   are within 0.22 ms — the anti-oracle property holds where it matters.
   The wrong-key condition is also the clearest cross-server processing
   asymmetry in the area: sshd does NOT verify an unallowed key's
   signature (user_key_allowed short-circuits the && in
   auth2-pubkey.c:userauth_pubkey), while tp_sshd verifies before asking
   the embedder — both absorbed under sshd's floor, both visible in
   tp_sshd's unpadded cells.
2. **E02's measurement anchor** — both servers arm their timer at
   connection acceptance; the probe's clock starts after KEX + service
   negotiation, so both readings undercount by the same ~20-30 ms.
   tp_sshd's 2.97 s is "3 s minus the handshake lead-in"; sshd's 4.29 s
   is "3 s + ~1.3 s jitter minus the same lead-in". Only one sample per
   server per run is taken (the full jitter sweep would multiply the
   row's wall time); the single sample landing inside the predicted
   3-7 s band is the confirmation.
3. **E02's default values** — the row matches at equal config, but the
   DEFAULTS diverge: sshd LoginGraceTime 120 s (servconf.c:327-328) vs
   tp_sshd authTimeout 30 s (ssh_server.dart). Deliberate: the embedded
   pairing window (QR-pair → first login) is short-lived and a stale
   pre-auth socket should not pin state for two minutes; 30 s is the
   documented spec choice. sshd additionally jitters its grace expiry
   (0-4 s) to make the exact teardown time unpredictable — tp_sshd's
   fixed Timer is acceptable because the timeout is public configuration,
   not a secret; recorded as a hardening candidate only.
4. **E04's close detection** — the dropped connections' first bytes are
   the refusal line; the close that follows (close(newsock) right after
   drop_connection) was verified by keeping the socket subscription alive
   past the first chunk (a first pass used `Socket.first`, whose
   cancelled subscription hides the server's FIN and misreported the
   refused connections as still open).
5. **E01/E02/E04 dedicated harnesses** — these rows run on their own
   server pairs (`startAuditServers` with `sshdConfigExtras`), both
   because their sshd needs other config (LoginGraceTime 3 /
   MaxStartups 3:100:6) and because E01's 150 failing logins would
   otherwise run 127.0.0.1 into sshd's PerSourcePenalties (an authfail
   penalty of 5 s each, active once past the 15 s penalty_min) and gate
   the rows that follow on the shared sshd.

## Summary — triage consolidation

All five areas are complete: **53 rows**. This section is what Task 7's
fix implementation is driven from. Triage did not change any row's
verdict — every count below is the area tallies summed — it groups the
18 fix-divergence rows into 12 mechanism-level fix items (plus one
non-row harness finding), assigns priorities (security → client-visible
compatibility → hostile-input robustness → hygiene), and records the
downgrades/follow-ups.

### Final counts per verdict

| Area | match | deliberate-divergence | fix-divergence | rows |
|------|-------|----------------------|----------------|------|
| A — malformed input | 8 | 3 (A07, A12, A14) | 8 (A01, A08, A09, A10, A11, A15, A16, A19) | 19 |
| B — rekey timing | 3 | 0 | 5 (B02, B03, B06, B07, B08) | 8 |
| C — window handling | 3 | 5 (C02, C03, C04, C06, C08) | 2 (C05, C07) | 10 |
| D — channel close races | 4 | 4 (D02, D04, D07, D10) | 2 (D01, D05) | 10 |
| E — timing surfaces | 3 | 2 (E04, E06) | 1 (E01) | 6 |
| **Total** | **21** | **14** | **18** | **53** |

Plus one documented deliberate divergence that is **not a row verdict**:
E02's *default values* — tp_sshd `authTimeout` 30 s vs sshd
`LoginGraceTime` 120 s (Area E triage note 3). The E02 row itself is a
match at equal config (both run at 3 s); only the shipped defaults
diverge, deliberately. It is carried in the deliberate table below so
the tally does not lose it.

### Deliberate divergences (documented spec, not scheduled for fixing)

| ID | surface | sshd | tp_sshd | spec rationale |
|----|---------|------|---------|----------------|
| A07 | unknown service request | `DISCONNECT(2, "bad service request <name>")` | `DISCONNECT(7, "Service not available: <name>")` | Both fatal; reason 7 is the more apt RFC 4253 §11.1 semantic; clients only surface the text. |
| A12 | auth-attempt cap disconnect | reason 2, `Too many authentication failures` | reason 14, `Too many failed authentication attempts` | Cap parity (both cut at 6: five failures then the disconnect); no client branches on the reason code. The failure packets' empty methods list is A09's fix (F8). |
| A14 | unknown channel type | `CHANNEL_OPEN_FAILURE` reason 2 `"open failed"` | reason 1, `Channel type '<name>' is not supported` | RFC 4254 §5.1 actually suggests reason 3 for unknown types — both deviate; clients only display the string. |
| C02 | initial session-channel window | confirms with window 0 (LARVAL), grants 2 MiB via WINDOW_ADJUST at program start | confirms with the full 2 MiB immediately | Same effective grant, one round-trip cheaper; both stay at 2 MiB. |
| C03 | non-reading client (send side) | stops reading the child at window 0 (child freezes on its stdout pipe; channel held open) | no send-side backpressure — output queued in memory, channel finishes after the 2 s close-flush bound, tail dropped | The bounded-flush family with D02; the client-visible edge (a client pausing > 2 s after process exit loses the un-granted tail) is the recorded risk of that bound (D02). |
| C04 | single chunk over granted maxpacket | drops the packet silently ("rcvd big packet"), channel lives on | closes the channel (connection unaffected) | A sender violating the advertised maxpacket is misbehaving either way; channel-scope teardown is the documented `_handleIncoming` bound check. Revisit candidate (follow-ups). |
| C06 | overflowing WINDOW_ADJUST (uint32 wrap) | `fatal` kills the whole connection (log-only, no wire DISCONNECT) | closes just the offending channel (`_failChannel`) | Mirrors the fork's client-side policy of failing a channel without taking the connection down; the unknown-channel and zero-adjust halves are identical. |
| C08 | channel/session cap refusal | reason 2 `"open failed"` at the 11th open | reason 4 `"Too many open channels (10/10)"` | Cap parity (10 = `MaxSessions` default); RFC 4254 §5.1's reason 4 (resource shortage) is exactly this case — tp_sshd's reply is the more spec-apt of the two. |
| D02 | close flush bound | none — exit path drops the tail instantly; received CLOSE waits for a drain that may never come (or the child dies of SIGPIPE) | pending outgoing data gets a 2 s window-credit wait (`closeFlushTimeout`) before finishing | Documented spec choice: the bound guarantees teardown. Recorded risk: a healthy-but-slow client that does not grant the tail's credit within 2 s of process exit loses data it intended to read (C03's manifestation). |
| D04 | exit-status/EOF ordering | EOF races ahead of exit-status (pipe EOF vs SIGCHLD, observed every round) | exit-status strictly before EOF/CLOSE (`_pipeProcess`: "a client that sees EOF first may stop waiting for it") | Both orders are RFC-legal; clients must accept either; tp_sshd's order is deliberate. |
| D07 | early client CLOSE | holds the channel "almost dead" until the child exits, then delivers exit-status + CLOSE | finishes immediately (`handleClose` → `_finish`), kills the process, no exit-status | The client has declared the channel unneeded; tp_sshd trades the late exit report for immediate teardown and no orphaned process. |
| D10 | `signal` request with a bogus name | `CHANNEL_FAILURE` (generic want_reply handling) | no reply (decoder hardcodes `wantReply: false`, so the server never sees the flag) | RFC 4254 §6.9 pins `want reply FALSE` in the signal message format itself, so no compliant client waits for a reply. The decoder flag loss is a latent dartssh2 issue (follow-ups). |
| E02-defaults | pre-auth idle timeout *default* | `LoginGraceTime` 120 s (plus 0-4 s jitter) | `authTimeout` 30 s, fixed timer | Deliberate: the embedded pairing window (QR-pair → first login) is short-lived and a stale pre-auth socket should not pin state for two minutes. The fixed (unjittered) timer is acceptable because the timeout is public configuration, not a secret; jitter is a hardening candidate (follow-ups). |
| E04 | pre-auth connection cap | `MaxStartups 10:30:100`; past the threshold answers the plaintext `Not allowed at this time` line and closes before any banner | no pre-auth cap; every connection gets its full auth window | Embedded pairing context: the listener is paired with the app client on the device, not internet-facing; an embedder needing the bound can enforce it at the listener. Configurable cap is a backlog candidate (follow-ups). |
| E06 | `keepalive@openssh.com` reply | `REQUEST_FAILURE` (the name is unknown to sshd's global-request handler — it is sshd's own *outbound* keepalive name) | `REQUEST_SUCCESS` (special-cased) | Liveness-equivalent: sshd's own keepalive contract accepts any of the four reply types as proof of life (server_input_keep_alive), so no compliant client observes a difference beyond the reply id. |

### Fix list — prioritized, grouped by mechanism

Task 7 implements per mechanism, not per row: 18 fix-divergence rows
collapse into 12 fix items (F1–F12) plus one non-row harness finding
(F13). Priority order: security first (P0), client-visible compatibility
next (P1), hostile-input robustness in the shared dartssh2 transport
(P2), package hygiene (P3). Within a priority tier the items are
independent — the ordering inside a tier is a suggestion (security
impact vs churn), not a dependency.

**P0 — security**

- **F1 — E01: auth-failure timing must not be an oracle** (tp_sshd,
  `server_connection.dart`). A remote peer timing the
  `USERAUTH_FAILURE` reply must not be able to distinguish failure
  classes — in particular whether the USERNAME matched. Today the three
  failure paths have disjoint costs (wrong-key med ~2.8 ms — full
  ed25519 verify plus the async authenticate callback; unknown-user
  ~0.9 ms — the username-mismatch early-exit before any crypto; malformed
  ~0.6 ms), so a correct username is ~3× slower to reject than a wrong
  one. sshd prevents exactly this by padding every failed non-"none"
  attempt to a common floor before replying (auth2.c:
  `ensure_minimum_time_since` + `user_specific_delay`: 5 ms minimum +
  0-4.2 ms pseudorandom per-username jitter derived from a secret).
  *Acceptance:* fresh-connection-per-trial median reply latencies for
  wrong-key / unknown-user / malformed-blob are indistinguishable within
  the noise band. An implementation may adopt sshd's floor+jitter scheme
  or equivalent constant-work padding; the fix is the total path time,
  not the individual compares (the early-exit username compare and the
  embedder's early-exit key compare are not themselves the observable).
- **F2 — A19: strict-kex violations must carry a wire DISCONNECT**
  (dartssh2, `ssh_transport.dart`). A non-KEX packet arriving between
  `KEXINIT` and `NEWKEYS` under negotiated strict kex (RFC 9142 §3.2)
  must be answered with `DISCONNECT(2, "strict key exchange violation:
  …")` before the connection closes, the way sshd does
  (kex.c:kex_protocol_error → packet.c:ssh_packet_disconnect →
  `SSH2_DISCONNECT_PROTOCOL_ERROR`). The Terrapin countermeasure itself
  is already enforced (the connection is torn down) but via
  `SSHHandshakeError` → `SSHTransport.closeWithError` →
  `socket.destroy()`, so a client sees an unexplained TCP close where
  sshd delivers a protocol-error reason. *Acceptance:* a strict-kex
  violation produces a decodable `SSH_MSG_DISCONNECT` (reason 2,
  description naming the strict-key-exchange violation) on the wire
  before the close. The strict-kex throw paths (`_handleMessage`'s
  forbidden-message check, `_handleUnexpectedKexMessage`,
  `_negotiateStrictKex`) should send the DISCONNECT before closing.

  *Fix landed (2026-09-14, dartssh2 fork branch `differential-fixes`,
  43899e5):* all three throw paths now route through
  `_failStrictKex`, which sends
  `DISCONNECT(2, "strict KEX violation: …")` before throwing — in the
  clear (every caller sits inside the initial exchange, before NEWKEYS
  applied keys), bypassing the rekey buffer, and flushed before
  `closeWithError` destroys the socket. Both roles emit it, matching
  OpenSSH's client and server. Area A regeneration observes it on the
  wire: tp_sshd actual for A19 is now
  `disconnect:2("strict KEX violation: unexpected message 5 received
  during key exchange")` followed by close (before: closed with no
  DISCONNECT on the wire). The row still string-diffs against sshd on
  message wording and banner text; the acceptance criterion above is met,
  and the row-verdict refresh belongs to the final fix-wave dispatch.
- **F3 — B06+B07: the server must be able to initiate a rekey**
  (tp_sshd, `server_connection.dart`). Today there is no trigger of any
  kind (no byte counter, no timer; dartssh2's `rekey()` is a client-role
  API), so a pairing session's keys never rotate unless the client asks.
  *Acceptance (Task 7):* a server whose session exceeds
  `rekeyBytes`/`rekeyInterval` initiates KEXINIT unprompted; open
  channels survive; strict-kex ordering holds; an incompatible client
  gets a clean disconnect.
  *Defaults rationale (corrected during Area B — supersedes any
  "matching sshd's 4 GiB/1 h default" reasoning):* OpenSSH 10.2's
  default is **no configured RekeyLimit at all** — `RekeyLimit default
  none` (sshd_config.5:1788-1812; servconf.c:398-401 defaults
  rekey_limit = 0, interval = 0). The only bound that fires by default
  is cipher geometry: `max_blocks = 2^(block×2)` blocks
  (packet.c:1046-1063; observed in the harness log as `rekey in after
  4294967296 blocks` ≈ 64 GiB at AES's 16-byte blocks) with a 2^31-packet
  hard cap, and a time-based rekey fires only when an interval is
  configured (serverloop.c:171, packet.c:1095-1097). Proposed tp_sshd
  defaults: **`rekeyBytes` 1 GiB, `rekeyInterval` 1 h**, both
  configurable and 0-disableable. Justification (deliberate divergence
  from sshd's effective default): tp_sshd's deployment is the opposite
  of an internet-facing sshd's — pairing sessions are long-lived and
  frequently low-volume, so a geometry-scale byte-only bound would
  essentially never fire and the session would keep its keys forever,
  which is exactly the B06 finding. A 1 GiB byte bound plus a 1 h
  interval guarantees every live pairing session rotates keys at least
  hourly, covering idle-but-alive sessions a byte counter never reaches;
  0 restores sshd-default-equivalent behavior for embedders who want it.

**P1 — client-visible compatibility (a real client misbehaves)**

- **F4 — A16 + C05 (+ C03's receive half): the granted receive window
  must be enforceable** (tp_sshd, `server_channel.dart`). A peer that
  keeps sending past the granted window beyond the grace margin (sshd:
  10% of `local_window_max`) must be disconnected (`channel <id>: peer
  ignored channel window`, reason 2; the DISCONNECT may be
  queued-unflushed exactly like sshd's — the acceptance observable is
  the teardown + the bound). Today `_grantReceiveWindowIfNeeded` refills
  on pure receipt accounting (below half or > 3 packets outstanding —
  regardless of consumption), so against a non-reading program the
  window is never a bound and the server buffers unboundedly (C05: 2.4
  MiB into a `sleep`; A16: ~10 MiB buffered with 55 gratuitous
  WINDOW_ADJUSTs). *Acceptance:* (a) against a peer that exceeds the
  granted window past the grace margin, the server disconnects (the
  connection does not stay open granting credit); (b) window refill is
  consumption-driven — against a non-reading program, sent-but-unread
  bytes are never re-granted; (c) a well-behaved peer that stays inside
  its grant is never disconnected (C01's exactness and C10's SFTP
  round-trip still pass). One fix serves A16 + C05 + C03's receive
  half.
- **F5 — A15 + D05: channel-scoped messages for a nonexistent channel
  must be a protocol error** (tp_sshd, `server_connection.dart`). Every
  channel-scoped message (DATA, REQUEST, EOF, …) addressed to an unknown
  recipient channel must draw `DISCONNECT(2, "<what> packet referred to
  nonexistent channel <id>")` the way sshd does
  (channels.c:channel_from_packet_id;
  serverloop.c:server_input_channel_req), instead of being silently
  ignored. The racing-close rationale covers at most a small window
  around a channel's own CLOSE; swallowing every unknown id indefinitely
  hides real client bugs (a silent hang instead of an error).
  *Acceptance:* `CHANNEL_DATA` and a want-reply `CHANNEL_REQUEST` to a
  never-opened (or fully closed and reaped) recipient id each produce a
  decodable `SSH_MSG_DISCONNECT` reason 2 naming the nonexistent
  channel, and the connection closes.
- **F6 — B02 + C07: messages racing the rekey exchange window must not
  be dropped** (dartssh2, `ssh_transport.dart`). The shared transport
  answers every incoming non-KEX message processed while a key exchange
  is in progress with `UNIMPLEMENTED` and drops it
  (ssh_transport.dart:1625-1627). OpenSSH keeps dispatching ids ≥ 50
  through a rekey (`kex_reset_dispatch` only guards the transport range
  1-49). The casualties are packets sent before the peer's KEXINIT
  arrived that land inside the window — in B02 the exec teardown
  (exit-status/EOF/CLOSE) in 1-2 of 8 rounds, leaving the channel hung
  forever; in C07 the drop is a deterministic deadlock under window
  pressure (tp_sshd 0/3 rounds froze at exactly the client's initial
  window because the reopening WINDOW_ADJUST was dropped mid-exchange;
  the sshd side also lost 1/3 rounds through the same drop in its
  client half — this is one cross-cutting dartssh2-side fix, not a
  per-server behavior gap). *Acceptance:* a non-KEX message racing into
  the exchange window is processed, or buffered and re-dispatched after
  NEWKEYS — never silently dropped; in particular a channel teardown
  always survives a rekey (B02's 5-round run: 5/5 clean closes; C07's
  3-round run under window pressure: streams complete and channels
  close). B02 is a racy distribution row — the verdict rests on the
  trace evidence (UNIMPLEMENTED for packets 40/41/42) plus repeated
  runs, not on any single regeneration (see the regeneration note).
- **F7 — D01: data after EOF must not kill the connection** (tp_sshd,
  `server_channel.dart`). A `CHANNEL_DATA` arriving after the client's
  `CHANNEL_EOF` on a live channel must be tolerated the way sshd
  tolerates it (dropped with window accounting only,
  channels.c:channel_input_data's `ostate != CHAN_OUTPUT_OPEN` branch)
  — or delivered — but never allowed to throw. Today `handleEof` closes
  the channel's input `StreamController` and `_handleIncoming`'s
  `controller.add` on the closed controller throws synchronously; the
  error escapes the transport dispatch into `closeWithError` and the
  whole connection is torn down with nothing on the wire (one
  misbehaving channel kills every other channel on the connection).
  *Acceptance:* post-EOF data on a live channel leaves the connection
  serving (drop it like sshd, or close just that channel); the
  connection does not close. Guard `_handleIncoming` on `_receivedEof`.
- **F8 — A09/A10/A11 (+ A12's failure packets): `USERAUTH_FAILURE` must
  advertise the enabled methods** (tp_sshd, `server_connection.dart`).
  The failure packet's methods list must say `publickey` (RFC 4252 §8),
  not be empty. A client that consults the list to decide whether to
  offer a publickey sees "no methods available" and can give up on a
  login that would have succeeded. *Acceptance:* a password-method
  request, an undecodable-key-blob publickey request, and a
  bad-signature publickey request each answer
  `USERAUTH_FAILURE(methods=[publickey])`; A12's five failures carry the
  same list.
- **F9 — A08: no userauth before service negotiation** (tp_sshd,
  `server_connection.dart`). A `USERAUTH_REQUEST` arriving before
  `SERVICE_ACCEPT` must not be processed (sshd answers `UNIMPLEMENTED`
  through the default dispatch; auth2.c:do_authentication2 +
  input_service_request). *Acceptance:* tp_sshd ignores or refuses it;
  in particular it must not answer `USERAUTH_PK_OK` or authenticate on
  a connection that never negotiated `ssh-userauth`.

**P2 — hostile-input robustness in the shared transport (dartssh2-side)**

- **F10 — B03: a duplicate KEXINIT mid-exchange must be rejected, not
  merged into the negotiation** (dartssh2, `ssh_transport.dart`).
  *Acceptance:* while an exchange is in progress, a second KEXINIT draws
  `UNIMPLEMENTED` and the in-flight exchange completes, the way sshd
  does (kex.c:kex_input_kexinit:621 re-registers KEXINIT →
  kex_protocol_error for the duration of the exchange). Today
  `_handleMessageKexInit` has no in-progress guard: it overwrites
  `_remoteKexInit` and replaces the ephemeral kex, the exchange hashes
  desynchronize, the client's KEXDH_REPLY verification fails ("signature
  is invalid") and the connection dies. Reject or ignore a KEXINIT
  while `_kexInProgress` is true.
- **F11 — B08: an unsolicited NEWKEYS must not be adopted** (dartssh2,
  `ssh_transport.dart`). *Acceptance:* an unsolicited NEWKEYS
  (mid-exchange, or with no exchange in progress) is not applied — it
  draws `UNIMPLEMENTED` like sshd (kex.c:kex_input_newkeys:531 leaves
  NEWKEYS dispatched to kex_protocol_error outside a completed exchange)
  and the session survives. Today `_handleMessageNewKeys`
  (ssh_transport.dart:2016) applies remote keys unconditionally:
  mid-exchange it re-derives keys from the *stale* exchange hash, ends
  the exchange state and resets the strict-kex receive sequence number,
  after which the peer's real KEXDH_INIT hits the kex-null
  `SSHStateError` and the connection is torn down without a DISCONNECT
  (F2's missing-DISCONNECT family).
- **F12 — A01: server-side pre-banner garbage must be fatal** (dartssh2,
  server side). Any non-`SSH-` line from a client before its
  identification string must terminate the connection: send the
  plaintext `Invalid SSH identification string.` line and close
  (kex.c:kex_exchange_identification, server branch). Today tp_sshd
  discards up to 1024 such lines and completes the handshake against a
  prober. *Acceptance:* a garbage line before the version string closes
  the connection with the error line; a clean handshake right after a
  refused prober still succeeds on a fresh connection. (The client-side
  pre-banner tolerance is legitimate; only the server-side tolerance is
  the defect.)

**P3 — package hygiene**

- **F13 — A16 stray async error: the forward pump must consume
  `connection.done`'s error channel** (tp_sshd,
  `lib/src/server_forward.dart:pumpForwardConnection`). When a forwarded
  TCP connection is reset, the pump drops the future returned by
  `connection.done.whenComplete(...)`, so an *errored* connection
  completion propagates to an unlistened future — in the audit runner
  the zone caught `SocketException: Connection reset by peer` past every
  guard; in the app that is an unhandled exception. *Acceptance:* the
  pump must consume `connection.done`'s error channel
  (`.catchError`/`onError`) so a reset forwarded connection can never
  leak an unhandled error into the embedder's zone; a RST on a forwarded
  connection mid-stream (D06's shape) leaves the runner's stray-error
  list empty.

  *Fix landed (2026-09-14):* the pump consumes both channels of
  `connection.done` (`then`/`onError`): an errored completion closes the
  channel and finishes the pump like a normal end, and the error is
  diagnosed through a new optional `printDebug` seam. The area A
  regeneration ran with an empty stray-error list (the section does not
  even print).

### Documented follow-ups (recorded, not scheduled)

No fix-divergence row was downgraded in triage: every one of the 18 rows
carries concrete, testable acceptance criteria above (grouped into
F1–F12). The rubric's candidate downgrade — C07, if it is dominated by
the driver transport's own behavior — was checked against the row text:
C07's failures on *both* servers trace to the same shared-transport
drop (sshd lost 1/3 rounds through its dartssh2 client half), so C07 is
not a separate behavior gap; it is folded into F6 as evidence and a
second acceptance scenario, not downgraded. The entries below are
deliberate-divergence refinements and latent issues recorded for a
future pass, each with its one-line reason:

- **C04 revisit — tolerant drop for over-maxpacket chunks.** Matching
  sshd's silent drop would keep buggy-but-recoverable clients alive;
  deliberate today, revisit only if a real client shows up.
- **D10 decoder flag loss.** The shared dartssh2
  `SSH_Message_Channel_Request.signal` factory hardcodes
  `wantReply: false` (msg_channel.dart:781-791), so the server never
  sees the flag; no compliant client is affected (RFC 4254 §6.9 pins
  want reply FALSE in the format) — fix only alongside any signal
  feature work. A tp_sshd-side fix is not possible without the decoder
  preserving the flag.
- **E02 grace-timer jitter.** sshd jitters its grace expiry (0-4 s) so
  the exact teardown time is unpredictable; tp_sshd's fixed Timer is
  acceptable because the timeout is public configuration, not a secret
  — hardening candidate only.
- **E04 configurable pre-auth connection cap.** Embedded pairing does
  not need sshd's MaxStartups, and an embedder can enforce a bound at
  the listener (`ServerSocket`); a configurable cap policy is a backlog
  candidate.
- **C10 SFTP throughput (~2× slower per direction).** Correctness
  identical (byte-intact both ways); the harness `LocalSftpFileSystem`
  serializes position+read/write pairs per handle — a Task 7
  performance candidate, not a divergence.
- **A16 first-pass note — data ahead of the first CHANNEL_REQUEST on a
  request-less session channel.** sshd drops it (LARVAL channels discard
  data before window accounting); tp_sshd delivers it. tp_sshd is the
  more tolerant side and no client was observed to misbehave; recorded
  for the window work (F4) to keep in mind, not a separate item.

### Regeneration note — timing-variable rows

When the audit is regenerated, these rows compare **in-kind**, never by
numeric equality (wall-clock µs over loopback TCP are not comparable
across runs):

- **B02** — a distribution row: the exec teardown racing into the
  exchange window happens in 1-2 of 8 rounds (0/8 on the sshd side);
  the verdict rests on the trace evidence (the client answered
  UNIMPLEMENTED for packets 40/41/42) plus repeated runs, not on any
  single regeneration.
- **C07** — same family under window pressure (tp_sshd 0/3 clean, sshd
  1/3 clean in this run); the freeze point (exactly the initial grant)
  and the 0 × UNIMPLEMENTED trace are the stable observables.
- **D02 phase 2's ms figure** — the 1974 ms EOF+CLOSE delay is a single
  sample of the 2 s `closeFlushTimeout` bound; compare against the
  bound (≈ 2 s), not the exact milliseconds.
- **E01's distributions** — per-run medians/p95s vary; the finding is
  the cross-condition separability (wrong-key ~2.8 ms vs unknown-user
  ~0.9 ms vs malformed ~0.6 ms in this run — a ~3× oracle), not the
  absolute values. sshd's cross-username gap (~1 ms here) is
  `user_specific_delay` working as designed (each username draws a
  secret-derived 0-4.2 ms constant); same-username conditions are the
  cells that must be indistinguishable.
- **E02** — one sample per server per run; the sample must land inside
  the predicted band (tp_sshd: at the configured timeout minus the
  handshake lead-in; sshd: timeout + 0-4 s jitter minus the same
  lead-in).
