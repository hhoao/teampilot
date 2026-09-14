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

