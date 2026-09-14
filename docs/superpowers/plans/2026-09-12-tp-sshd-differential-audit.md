# tp_sshd Differential Audit vs OpenSSH — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Systematically audit `tp_sshd` against production OpenSSH (10.2p1) — behavior differential driven by OpenSSH source reference — across five gap areas, producing a cited matrix and fixing security/compat-relevant divergences.

**Architecture:** A Dart differential harness under `client/packages/tp_sshd/tool/differential/` launches two live servers on loopback — a real `sshd` (temp config, ephemeral port) and an in-process `tp_sshd` `SSHServer` — then replays identical wire-level stimuli through a raw `SSHTransport` driver and records observables (disconnect reason codes, message sequences, window behavior, timings). Each matrix row is: read OpenSSH source first → predicted behavior + citation → run both → record → verdict (match / deliberate-divergence / fix-divergence).

**Tech Stack:** Dart (tp_sshd package, vendored dartssh2 raw `SSHTransport`), system `sshd` 10.2p1 (skip-gated), openssh-portable source at tag `V_10_2_P1` (reference only, uncommitted).

**Audit policy (user decisions, binding):** 发现分歧 → 审计全部记录 + 修安全相关/兼容关键项，纯风格差异记 deliberate divergence。覆盖范围 → 五个缺口领域（畸形输入处置、rekey 时机、窗口策略、channel close/半关闭竞态、时序敏感面），约 40–60 行。

## Global Constraints

- OpenSSH source is REFERENCE ONLY: checkout at `~/.cache/openssh-portable` (tag `V_10_2_P1`), never committed, never vendored into the repo. Matrix citations are `file:function` paths within that tree.
- The harness must SKIP cleanly (not fail) when `/usr/sbin/sshd` is absent — the default `dart test` suite must stay green on any machine.
- Differential rows live in `client/packages/tp_sshd/DIFFERENTIAL_AUDIT.md`; harness output is regenerable, the doc is the durable artifact.
- tp_sshd's deliberate narrow surface (publickey-only, single KEX family, loopback-only forward, no shell strings, 2MB initial window, 30s pre-auth timeout, 6 auth attempts) is NOT a defect: rows confirming those are recorded as `deliberate-divergence` with the spec's rationale, never "fixed" away.
- Every `fix-divergence` verdict must land as a tp_sshd code change with a package test in the same task or the task is not done.
- All work on branch `tp-sshd-differential-audit` (off `main`). Commit trailer: `Co-Authored-By: Claude <noreply@anthropic.com>`.
- Package gate after every task: `cd client/packages/tp_sshd && dart analyze` (0 errors) && `dart test` (all green, count only grows).

## File Structure

```
client/packages/tp_sshd/
  tool/differential/
    run_audit.dart          [new] entry: launches both servers, runs all areas, emits results
    audit_harness.dart      [new] sshd launcher (temp config) + in-process tp_sshd launcher
    raw_driver.dart         [new] raw SSHTransport-over-TCP driver + observable recorder
    area_a_malformed.dart   [new] Area A row definitions
    area_b_rekey.dart       [new] Area B row definitions
    area_c_windows.dart     [new] Area C row definitions
    area_d_close_races.dart [new] Area D row definitions
    area_e_timing.dart      [new] Area E row definitions
  DIFFERENTIAL_AUDIT.md     [new] the cited matrix + triage summary (durable artifact)
  lib/src/server_connection.dart  [mod, T7 only] server-initiated rekey
  lib/src/ssh_server.dart         [mod, T7 only] rekey config knobs
  test/server_rekey_test.dart     [new, T7] rekey-initiation tests
```

---

### Task 1: Differential harness infrastructure

**Files:**
- Create: `client/packages/tp_sshd/tool/differential/audit_harness.dart`
- Create: `client/packages/tp_sshd/tool/differential/raw_driver.dart`
- Create: `client/packages/tp_sshd/tool/differential/run_audit.dart`
- Test: exercised via `run_audit.dart --smoke` (this is a tool, not a package test — no `dart test` surface)

**Interfaces:**
- Consumes: `SSHServer`/`SSHServerConfig` (tp_sshd), `SSHSocket.connect` + `SSHTransport` (dartssh2), system `ssh-keygen` + `/usr/sbin/sshd`.
- Produces (exact signatures used by Tasks 2–6):
  - `class AuditServers { final int sshdPort; final int tpdPort; final String deviceKeyPem; final String devicePubLine; final String username; Future<void> close(); }`
  - `Future<AuditServers> startAuditServers({bool useSystemSshd = true})` — throws `SshdUnavailableException` when sshd is missing (caller converts to skip).
  - `class RawSession { Future<void> sendRawBytes(Uint8List bytes); Future<List<Observed>> collect({Duration window}); Future<DisconnectObservation?> disconnectObserved; }` — `Observed` is a sealed record: `MessageObservation(int id, String name)`, `DisconnectObservation(int reasonCode, String description)`, `ClosedObservation()`.
  - `Future<RawSession> dialRaw({required int port, String? versionString})` — raw TCP, optional custom version string, drives dartssh2 `SSHTransport` with `onMessage` recording; `sendRawBytes` writes pre-KEX bytes directly for transport-level corruption rows.
  - `class RowResult { final String id; final OpenSshExpectation expected; final String openSshActual; final String tpSshdActual; }` — `OpenSshExpectation(String citation, String predicted)`.
- The smoke row: full publickey login + `tp1:{"query":"host-info"}`-equivalent exec (`echo ok`) against BOTH servers succeeds — proves the harness talks to both.

- [ ] **Step 1: Write `audit_harness.dart`**

Key implementation content (the sshd temp-config pattern was proven against OpenSSH 10.2p1 in a prior manual session — reuse it exactly):

```dart
/// Launches a throwaway system sshd plus an in-process tp_sshd on loopback.
///
/// sshd config: ephemeral port (bind-and-release probe), 127.0.0.1 only,
/// our generated device key authorized, password auth off, StrictModes off
/// (temp dir), Subsystem sftp internal-sftp.
Future<AuditServers> startAuditServers({bool useSystemSshd = true}) async {
  final dir = await Directory.systemTemp.createTemp('tp_diff_');
  // host key: Process.run('ssh-keygen', ['-t','ed25519','-N','','-f','$dir/host_key'])
  // device key: same, at '$dir/device_key' — the SAME key authorizes sshd's
  // authorized_keys and tp_sshd's authenticate callback, so one driver works
  // against both.
  // free port: final probe = await ServerSocket.bind(loopbackIPv4, 0);
  //   final port = probe.port; await probe.close();
  // sshd invocation: Process.run('/usr/sbin/sshd', ['-f','$dir/sshd_config',
  //   '-E','$dir/sshd.log','-p','$port']) — if ProcessException: throw
  //   SshdUnavailableException() (caller skips, never fails the suite).
  // sshd_config body:
  //   ListenAddress 127.0.0.1
  //   HostKey <dir>/host_key
  //   AuthorizedKeysFile <dir>/authorized_keys
  //   PubkeyAuthentication yes
  //   PasswordAuthentication no
  //   KbdInteractiveAuthentication no
  //   UsePAM no
  //   StrictModes no
  //   Subsystem sftp internal-sftp
  //   PidFile <dir>/sshd.pid
  //   LogLevel DEBUG3   // DEBUG3 gives per-message traces the driver can cross-check
  // tp_sshd side: SSHServer.bind over ServerSocket(loopbackIPv4, 0) with the
  // demo wiring (host key from PEM, authenticate comparing the device pub
  // blob, processFactory spawning real processes, LocalSftpFilesystem-style
  // FS over the temp dir) — port from client/packages/tp_sshd/example/demo_sshd.dart.
}
```

- [ ] **Step 2: Write `raw_driver.dart`** — `SSHTransport` over `SSHSocket.connect` (the pattern `test/dual_test_utils.dart:startRawPair` proves for raw driving; here over real TCP). Records every incoming message id + every `SSH_Message_Disconnect` (reason code + description). `sendRawBytes` writes to the raw socket for pre-KEX corruption (bad version strings, garbage bytes) where the driver must bypass `SSHTransport`.

- [ ] **Step 3: Write `run_audit.dart`** — arg parsing (`--smoke`, `--area a|b|c|d|e|all`, `--openssh-src <path>` default `~/.cache/openssh-portable`), calls `startAuditServers`, runs selected areas, prints a markdown results table; converts `SshdUnavailableException` into `SKIPPED: system sshd not available` + exit 0.

- [ ] **Step 4: Checkout OpenSSH source + smoke run**

```bash
git clone --depth 1 --branch V_10_2_P1 https://github.com/openssh/openssh-portable ~/.cache/openssh-portable
cd client/packages/tp_sshd && dart run tool/differential/run_audit.dart --smoke
```

Expected: both servers up, login + exec `echo ok` returns `ok` on both, exit 0. If the tag clone fails, fall back `--branch V_10_2_P2`… down to the newest `V_10_*` tag and record which version the citations refer to in the matrix header.

- [ ] **Step 5: Commit**

```bash
git checkout -b tp-sshd-differential-audit
git add client/packages/tp_sshd/tool/differential/
git commit -m "feat(tp_sshd): differential audit harness — dual server launcher + raw driver"
```

---

### Task 2: Matrix doc skeleton + Area A rows (malformed input handling)

**Files:**
- Create: `client/packages/tp_sshd/DIFFERENTIAL_AUDIT.md`
- Create: `client/packages/tp_sshd/tool/differential/area_a_malformed.dart`
- Modify: `run_audit.dart` (register area)

**Interfaces:**
- Consumes: Task 1 (`startAuditServers`, `dialRaw`, `RowResult`).
- Produces: `List<AuditRow> areaARows()` where `AuditRow { final String id; final String stimulus; final Future<RowResult> Function(AuditServers s) run; final String sourceHint; }` — Tasks 3–5 mirror this shape (`areaBRows()` etc.).

- [ ] **Step 1: Write the matrix skeleton** — header (method, OpenSSH version + source path, verdict legend: `match` / `deliberate-divergence` / `fix-divergence`), then Area A section with an empty table: `| ID | 刺激 | OpenSSH 预期（源码出处） | OpenSSH 实测 | tp_sshd 实测 | 判定 |`.

- [ ] **Step 2: Define Area A rows.** Each row: BEFORE running, read the cited OpenSSH source and write the predicted behavior into the doc's expectation column — predictions come from source, not from running. Rows (stimulus is wire-level; all against a fresh `dialRaw` connection unless noted):

| ID | Stimulus | Read + cite (openssh-portable) |
|----|----------|-------------------------------|
| A01 | Garbage before version string (send `xxxx\r\n` then real handshake) | `sshd.c:sshd_exchange_identification` |
| A02 | Unsupported version `SSH-1.99-...` | `sshd.c:sshd_exchange_identification`, `packet.c` compat banner logic |
| A03 | Oversized packet length (>35000) post-KEX | `packet.c:ssh_packet_read_structured` length checks |
| A04 | Zero/short (<min) packet payload | same |
| A05 | Unknown message id (e.g. 200) pre-auth | `dispatch.c:dispatch_protocol_error` |
| A06 | Unknown message id post-auth | `dispatch.c` running-phase table |
| A07 | `SERVICE_REQUEST` unknown service name | `sshd.c`/`auth2.c:input_service_request` |
| A08 | `USERAUTH_REQUEST` before `SERVICE_ACCEPT` | `auth2.c` ordering checks |
| A09 | `USERAUTH_REQUEST` method `password` (we advertise publickey-only) | `auth2.c:input_userauth_request` method dispatch |
| A10 | Malformed publickey blob (truncated base64 fields) | `auth2-pubkey.c:userauth_pubkey` + `sshkey.c:sshkey_from_blob` |
| A11 | Invalid signature (valid key, wrong signed bytes) | `auth2-pubkey.c` verify path |
| A12 | Excess auth attempts (7 keys) — disconnect reason + count | `auth.c:max_auth_attempts` handling (compare against tp_sshd's 6 — likely deliberate-divergence row) |
| A13 | `KEXINIT` mid-auth (strict-kex violation) | `packet.c`/`kex.c` first_kex_follows/strict rules |
| A14 | `CHANNEL_OPEN` bogus type string post-auth | `serverloop.c:server_input_channel_open` |
| A15 | `CHANNEL_DATA` unknown recipient channel | `serverloop.c`/`channels.c` channel lookup |
| A16 | `CHANNEL_DATA` exceeding granted window | `channels.c:channel_check_window`/input data path |
| A17 | `GLOBAL_REQUEST` unknown name (want_reply true) | `serverloop.c:server_input_global_request` |
| A18 | Client `DISCONNECT` mid-handshake — server side teardown observability | `sshd.c` cleanup |

- [ ] **Step 3: Implement the row runners** in `area_a_malformed.dart`. Hand-crafted messages use `SSHMessageWriter` (same construction pattern as `dual_test_utils.dart:testProbeRequest`). Observables per row: did disconnect happen, reason code + description string, remaining message sequence, whether listener survives the next clean login (crash-isolation check).

- [ ] **Step 4: Run + fill the table.** `dart run tool/differential/run_audit.dart --area a`. For each row write OpenSSH-actual and tp_sshd-actual into the doc. Verdict per policy: e.g. A12 (6 vs MaxAuthTries 6 — check actual sshd default is 6, so likely match) vs pre-auth timeout 30s vs `LoginGraceTime 120` is a DIFFERENT area (E) — do not conflate.

- [ ] **Step 5: Triage pass.** Any row where tp_sshd differs in a way a real client or attacker would feel (different disconnect reason semantics that break clients, crash instead of disconnect, accepted-what-sshd-rejects) → mark `fix-divergence` and note the fix in the doc's triage section (fixes land in Task 7 unless trivially local to the row's implementation).

- [ ] **Step 6: Gate + commit**

```bash
cd client/packages/tp_sshd && dart analyze && dart test   # package untouched — must stay 58/58
git add tool/differential/area_a_malformed.dart tool/differential/run_audit.dart DIFFERENTIAL_AUDIT.md
git commit -m "test(tp_sshd): differential audit area A — malformed input (18 rows, cited)"
```

---

### Task 3: Area B rows (rekey timing) — audit only

**Files:**
- Create: `client/packages/tp_sshd/tool/differential/area_b_rekey.dart`
- Modify: `run_audit.dart`, `DIFFERENTIAL_AUDIT.md`

**Interfaces:**
- Consumes: Task 1 harness; Task 2 row/doc conventions.

- [ ] **Step 1: Define Area B rows.** Already-confirmed anchor finding: tp_sshd NEVER initiates rekey (`rekey()` exists only client-side; no timer, no byte counter in `server_connection.dart`). Rows:

| ID | Stimulus | Read + cite |
|----|----------|-------------|
| B01 | Peer-initiated rekey mid-session (client `rekey()`), verify continuity of open channel | `kex.c:kex_send_newkeys`, `packet.c` rekey states |
| B02 | Rekey with data in flight (channel streaming during KEXINIT..NEWKEYS) | `packet.c:ssh_packet_send2` rekey queueing (dartssh2 has `_rekeyPendingPackets` — compare ordering) |
| B03 | `KEXINIT` while a KEX is already in progress | `kex.c:kex_input_kexinit` duplicate handling |
| B04 | Rekey proposing ONLY unsupported algorithms (expect disconnect vs rekey-failure) | `kex.c:kex_choose_conf` failure path |
| B05 | Host key change on rekey (server presents different key) — client-side policy mirror; record as client-behavior reference | `ssh_transport.dart:1903-1913` (our side already rejects — confirm vs `kex.c` verify_host_key) |
| B06 | Long-lived session byte threshold: document sshd `RekeyLimit` default (`sshconnect.c`/`packet.c`: default 4GB/1h via `kex_set_server_sign_key`… locate exact constant in `ssh.h:REKEY_LIMIT` / `packet.c:kex_setup` — cite what you find) vs tp_sshd (none) | `packet.c` rekey thresholds |
| B07 | Time-based rekey (sshd hourly) — document, cannot practically wait 1h: source-only row, mark `source-only` in OpenSSH-actual column | same |
| B08 | strict-kex rekey variant: NEWKEYS ordering violations during rekey | `packet.c` strict-kex checks (RFC 9142) |

- [ ] **Step 2: Implement runners** (B06/B07 are documentation rows: B06 runs a session pumping >4GB? NO — that is hours of loopback at 36MB/s. B06/B07 are `source-only` rows: prediction from source + a code-level confirmation that tp_sshd has no trigger, no differential run. The RUNNABLE rows are B01–B05, B08.)

- [ ] **Step 3: Run B01–B05, B08; fill table.** Expected headline: B06 records `fix-divergence` — tp_sshd lacks server-initiated rekey entirely; long-lived pairing sessions never rotate keys unless the client chooses to. This row's fix is Task 7.

- [ ] **Step 4: Gate + commit**

```bash
cd client/packages/tp_sshd && dart analyze && dart test
git add tool/differential/area_b_rekey.dart tool/differential/run_audit.dart DIFFERENTIAL_AUDIT.md
git commit -m "test(tp_sshd): differential audit area B — rekey (anchor finding: no server-initiated rekey)"
```

---

### Task 4: Area C (window policy) + Area D (channel close races)

**Files:**
- Create: `client/packages/tp_sshd/tool/differential/area_c_windows.dart`
- Create: `client/packages/tp_sshd/tool/differential/area_d_close_races.dart`
- Modify: `run_audit.dart`, `DIFFERENTIAL_AUDIT.md`

**Interfaces:** same row conventions as Task 2.

- [ ] **Step 1: Define + source-read Area C rows:**

| ID | Stimulus | Read + cite |
|----|----------|-------------|
| C01 | Client grants tiny initial window (e.g. 2048) then streams; record WINDOW_ADJUST cadence from server | `channels.c:channel_pre_open`/dynamic window: `channels.c:channel_after` window growth |
| C02 | Server→client flow: observe OUR initial window grant (2MB flat) vs sshd's dynamic (starts small, grows) — record both sides' adjust sequence on a bulk download | `channels.c` `CHAN_WINDOW_*=*` constants + dynamic window algo |
| C03 | Client never reads (zero consumption, no adjusts): does server block/stall/disconnect, and when | `channels.c` buffer limits |
| C04 | Single `CHANNEL_DATA` chunk > peer's max packet size | `channels.c` packet split rules |
| C05 | Data exceeding granted window by 1 byte | `channels.c:channel_check_window`/input path — disconnect vs tolerate |
| C06 | `WINDOW_ADJUST` for unknown channel / adjust 0 / adjust overflowing window (2^32) | `channels.c:channel_input_window_adjust` |
| C07 | Window behavior across rekey (B01 variant with window pressure) | `packet.c` + `channels.c` interplay |
| C08 | max-channels flood: open 11 channels (tp_sshd cap 10 vs sshd default MaxSessions 10 per connection) | `sshd.c`/`session.c` MaxSessions enforcement |
| C09 | 11th channel refusal observable: failure reason code + message | `channels.c:channel_request_open` failure replies |
| C10 | SFTP bulk transfer window behavior (pipelined READs) — observational row documenting both | `sftp-server.c` packet cadence |

- [ ] **Step 2: Define + source-read Area D rows:**

| ID | Stimulus | Read + cite |
|----|----------|-------------|
| D01 | EOF from client followed by more DATA | `channels.c:chan_rcv_eof` post-EOF data handling |
| D02 | CLOSE while server output still pending window credit (tp_sshd's 2s bounded flush vs sshd's behavior) | `channels.c:channel_close_fds`/output drain |
| D03 | Both sides EOF — who sends CLOSE first / teardown order | `serverloop.c` + `channels.c:channel_still_open` |
| D04 | `exit-status` request ordering relative to EOF/CLOSE (sshd: exit-status → EOF → CLOSE) | `session.c:session_close_by_pid`/exit path |
| D05 | `CHANNEL_REQUEST` after CLOSE (race: request in flight when close lands) | `channels.c` post-close request handling |
| D06 | Abrupt TCP close (RST) mid-channel — both sides' log/teardown behavior (observational) | `sshd.c` SIGCHLD/cleanup |
| D07 | CLOSE from client before ever sending EOF | `channels.c:channel_input_close` |
| D08 | Server-initiated channel (forwarded-tcpip) then client CLOSE before confirm — race variant | `serverlisten.c`/`channels.c` open-confirm path |
| D09 | pty session exit-status + close ordering with pty teardown | `session.c:session_pty_cleanup` |
| D10 | `signal` request with bogus name | `session.c:session_input_channel_req` signal path |

- [ ] **Step 3: Implement runners, run, fill both tables, triage.** Expected deliberate-divergence candidates: C02 (window policy — spec chose 2MB flat), D02 (bounded flush 2s vs sshd drain). Those get recorded, not fixed. Anything where tp_sshd hangs where sshd disconnects (or vice versa in a client-visible way) → `fix-divergence`.

- [ ] **Step 4: Gate + commit**

```bash
cd client/packages/tp_sshd && dart analyze && dart test
git add tool/differential/area_c_windows.dart tool/differential/area_d_close_races.dart tool/differential/run_audit.dart DIFFERENTIAL_AUDIT.md
git commit -m "test(tp_sshd): differential audit areas C+D — window policy, close races (20 rows)"
```

---

### Task 5: Area E rows (timing-sensitive surfaces)

**Files:**
- Create: `client/packages/tp_sshd/tool/differential/area_e_timing.dart`
- Modify: `run_audit.dart`, `DIFFERENTIAL_AUDIT.md`

**Interfaces:** same row conventions.

- [ ] **Step 1: Define + source-read Area E rows:**

| ID | Stimulus | Read + cite |
|----|----------|-------------|
| E01 | Auth-failure timing distribution: wrong-key vs unknown-user vs malformed-blob over N=50 trials each, compare variance across the two servers | `auth2.c:finish_auth`/`auth.c` fail paths (does sshd pad/serialize failure timing? cite what source shows; our side already constant-time-compares keys) |
| E02 | Pre-auth idle timeout: 30s (tp_sshd) vs sshd `LoginGraceTime` default 120s — source-only + confirmed-by-config row, verdict deliberate-divergence (embedded pairing context wants shorter) | `sshd.c:grace_alarm_handler` |
| E03 | Post-auth idle: sshd has no default idle timeout (ClientAliveInterval default 0) vs tp_sshd — document none/none → match | `sshd_config` defaults in `servconf.c` |
| E04 | Connection flood pre-auth: sshd `MaxStartups 10:30:100` — tp_sshd has none (embedded context) → deliberate-divergence row | `sshd.c:drop_connection` |
| E05 | Channel-open flood rate (post-auth): timing of cap enforcement vs sshd MaxSessions | `session.c` |
| E06 | Keepalive global request cadence tolerance (`keepalive@openssh.com`) — both must answer | `serverloop.c:server_input_global_request` |

- [ ] **Step 2: Implement runners.** E01's timing harness: same driver, wall-clock µs around the USERAUTH failure reply, 50 iterations × 3 conditions × 2 servers, output median + p95 + max per cell into the doc. Timing rows are informational: verdict is `match-in-kind` (both uniform or both variable) rather than numeric equality — state this in the doc's method note so reviewers don't chase µs noise.

- [ ] **Step 3: Run, fill, triage.** Likely outcome: E04 deliberate-divergence, E02 deliberate-divergence, E01 informational. Any timing ORACLE (unknown-user notably faster/slower than wrong-key in a way sshd avoids and we don't) → `fix-divergence` for Task 7.

- [ ] **Step 4: Gate + commit**

```bash
cd client/packages/tp_sshd && dart analyze && dart test
git add tool/differential/area_e_timing.dart tool/differential/run_audit.dart DIFFERENTIAL_AUDIT.md
git commit -m "test(tp_sshd): differential audit area E — timing surfaces (6 rows)"
```

---

### Task 6: Triage consolidation — the fix list

**Files:**
- Modify: `client/packages/tp_sshd/DIFFERENTIAL_AUDIT.md` (triage + summary sections)

**Interfaces:** consumes all area tables; produces the definitive fix list Task 7 implements.

- [ ] **Step 1:** Re-read all five area tables; write the **Summary** section: counts per verdict, the deliberate-divergence table with spec rationale for each, and the fix list. The anchor `fix-divergence` (already confirmed in Task 3) is: *server-initiated rekey absent — long-lived sessions never rotate keys* (B06). Additional fix-classified rows from Tasks 2/4/5 join it; style-only differences are recorded, not fixed.

- [ ] **Step 2:** For EVERY fix-list item, write the acceptance criteria Task 7 will test against (e.g. for B06: "a server whose session exceeds `rekeyBytes`/`rekeyInterval` initiates KEXINIT unprompted; open channels survive; strict-kex ordering holds; client that ignores rekey incompatibly gets a clean disconnect"). If any fix-list item cannot be given concrete acceptance criteria, downgrade it to a documented follow-up in the doc rather than leaving it vague.

- [ ] **Step 3: Commit**

```bash
git add client/packages/tp_sshd/DIFFERENTIAL_AUDIT.md
git commit -m "docs(tp_sshd): differential audit triage — fix list and deliberate divergences"
```

---

### Task 7: Implement the fix list (server-initiated rekey + audit findings)

**Files:**
- Modify: `client/packages/tp_sshd/lib/src/server_connection.dart`
- Modify: `client/packages/tp_sshd/lib/src/ssh_server.dart` (config knobs)
- Create: `client/packages/tp_sshd/test/server_rekey_test.dart`
- Modify: any additional files the Task 6 fix list names (row fixes with their row-local tests)
- Modify: `client/packages/tp_sshd/README.md` (document the new knobs)

**Interfaces:**
- Consumes: Task 6's fix list with acceptance criteria.
- Produces: `SSHServerConfig.rekeyBytes` (default 4 GiB, matching sshd's default), `SSHServerConfig.rekeyInterval` (default 1 h), both nullable to disable; the transport's `rekey()` is invoked server-side when either threshold is crossed while sending.

- [ ] **Step 1: Write failing tests (TDD)** in `server_rekey_test.dart`, driving through the existing dual-test infra (`startDualPair`) — inject tiny thresholds:

```dart
test('server initiates rekey after rekeyBytes of outbound traffic', () async {
  final (client, server) = await startDualPair(
    hostKeyPair: testHostKey,
    authenticate: (_) async => true,
    clientIdentities: [testDeviceKey],
    configOverride: (base) => SSHServerConfig from base with rekeyBytes: 64 * 1024,
  );
  final session = await openClientSessionChannel(client);
  await session.sendExec('tp1:{"argv":["head","-c","131072","/dev/zero"]}');
  // await client-side EOF; assert a fresh KEX happened: expose
  // SSHServerConnection.rekeyCount for the test (read-only counter).
  expect(connection.rekeyCount, greaterThanOrEqualTo(1));
});
test('rekey interval timer fires on an idle session', ...); // inject Duration(milliseconds: 200)
test('open channel survives a mid-stream server-initiated rekey', ...); // stream + assert continuity
test('rekey disabled when both knobs null — no KEXINIT ever sent unprompted', ...);
```

(If `startDualPair`'s config surface needs a small extension — e.g. `rekeyBytes`/`rekeyInterval` params — extend it; keep default call sites untouched.)

- [ ] **Step 2: Run to verify failure** — `cd client/packages/tp_sshd && dart test test/server_rekey_test.dart` → FAIL (no such knobs / no KEXINIT).

- [ ] **Step 3: Implement.** In `server_connection.dart`: an outbound byte counter and a one-shot `Timer` checked on each packet send (cheap: compare-and-reset inside the send path; the dartssh2 transport already serializes sends). Crossing either threshold calls `_transport.rekey()` (exists, line 2054) and resets the counters; concurrent triggers collapse to one KEX. In `ssh_server.dart`: the two config fields with OpenSSH-matching defaults, doc comments citing `REKEY_LIMIT` in openssh-portable and the B06 audit row. If the fix list from Task 6 named additional row fixes, implement each with its row-local test here.

- [ ] **Step 4: Full gate + differential re-run**

```bash
cd client/packages/tp_sshd && dart analyze && dart test          # 58 + new rekey tests
dart run tool/differential/run_audit.dart --area b               # B06 flips to fix-landed; update doc
```

- [ ] **Step 5: Update `DIFFERENTIAL_AUDIT.md`** — mark fixed rows `fixed-in-<sha>`, refresh summary counts.

- [ ] **Step 6: Commit**

```bash
git add lib/src/server_connection.dart lib/src/ssh_server.dart test/server_rekey_test.dart test/dual_test_utils.dart README.md DIFFERENTIAL_AUDIT.md
git commit -m "feat(tp_sshd): server-initiated rekey (RekeyLimit-matching defaults) + audit fixes"
```

---

## Self-Review

**Spec/policy coverage:** five gap areas → Tasks 2–5 (A:18, B:8, C:10, D:10, E:6 = 52 rows, within the 40–60 agreed). Audit+fix-critical policy → verdict column + Task 6 triage + Task 7 fixes. Source-referenced requirement → every row carries a `file:function` citation from the V_10_2_P1 checkout; predictions are written from source before running. The pre-confirmed finding (no server-initiated rekey) is anchored as B06 with its fix fully specified in Task 7.

**Placeholder scan:** Area tables name exact stimuli, exact source functions to read, and exact observables; the only "as-found" scope is Task 7's secondary fixes, which Task 6 converts to concrete acceptance criteria before Task 7 starts (and downgrades anything it cannot make concrete).

**Type consistency:** `AuditServers`/`RawSession`/`RowResult`/`AuditRow` defined in Task 1, consumed unchanged in Tasks 2–5; `rekeyBytes`/`rekeyInterval`/`rekeyCount` defined in Task 7 Steps 1/3 consistently; `SshdUnavailableException` thrown in Task 1 and converted to skip in `run_audit.dart`.
