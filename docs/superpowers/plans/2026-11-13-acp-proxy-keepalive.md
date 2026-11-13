# ACP Keep-Alive Proxy — Plan 1 (Proxy Process) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land a Dart package that is the cloud ACP keep-alive process: it speaks ACP to one phone connection, holds the real CLI's stdin, replays a spool after reconnect, and reaps idle sessions.

**Architecture:** Plan 1 of 3 from `docs/superpowers/specs/2026-11-13-acp-proxy-keepalive-design.md`. The package `client/packages/acp_proxy` owns the advertisement file, launch `_meta`, the session book, the spool, permission/idle decisions, and an ACP agent wired to an injectable upstream. A loopback listener and `bin/teampilot_acp_proxy.dart` make the process startable. Plan 2 adds the CLI-page installer (GitHub Release download). Plan 3 teaches the phone to `forwardLocal` when the advertisement version matches, and otherwise keep today's SSH `exec`. Nothing in this plan changes session creation.

**Tech Stack:** Dart 3, package `acpd`, package `acpd_test` (`MemoryTransportPair`), `dart test`. No Flutter.

## Global Constraints

- Listen on `127.0.0.1` only. One TCP port per CLI id.
- Advertisement path is `<teampilotRoot>/acp-proxy.json`. Binary path is `<teampilotRoot>/acp-proxy/teampilot-acp-proxy`. Pid path is `<teampilotRoot>/acp-proxy/acp-proxy.pid`. Spool path is `<teampilotRoot>/acp-proxy/sessions/<agentSessionId>/`.
- Advertisement `version` is the constant `0.1.0` from this package.
- Default idle timeout is 30 minutes, overridable by `--idle-timeout`.
- Disconnected `session/request_permission` for `ask` waits 24 hours, then cancels.
- `session/load` or `session/resume` failure must not call `session/new`.
- Spool directories are owner-read/write only (`0600` on the files, `0700` on the directory). Never log `env`.
- One ACP connection per session. A new `session/load` for that session closes the previous connection.
- Do not write `sessions/<id>/runtime/acp-transcript.jsonl` or `acp-session.json`.
- Personal ACP only. No team seats, no PTY, no WebSocket, no session-protocol intents.
- Commit only the files listed in each task. The working tree contains unrelated changes — do NOT stage anything else.
- `docs/superpowers/specs/2026-11-13-acp-proxy-keepalive-design.md` is the source of truth.
- Run this package's tests with `cd client/packages/acp_proxy && dart test <path>`. Do not use `flutter test`.

## Explicitly deferred (later plans; do NOT add here)

1. **Plan 2 — install.** CLI-page machine card, `uname -m` asset selection, SHA-256, `curl` on the remote, `--detach` from the app, update that signals only `acp-proxy.pid`.
2. **Plan 3 — phone routing.** Reading `acp-proxy.json` inside TeamPilot, `forwardLocal` versus SSH `exec`, the "go install it" hint, passing `_meta` from the existing remote staging result.
3. GitHub Release publishing and the AOT binary filename on disk. This plan's entrypoint is the Dart script `bin/teampilot_acp_proxy.dart`.

---

## File Structure

| File | Responsibility |
|---|---|
| `client/packages/acp_proxy/pubspec.yaml` | Package manifest. Depends on `acpd` and, for tests, `acpd_test`. |
| `client/packages/acp_proxy/lib/acp_proxy.dart` | Barrel export. |
| `client/packages/acp_proxy/lib/src/version.dart` | `acpProxyVersion`. |
| `client/packages/acp_proxy/lib/src/advertisement.dart` | Parse and atomically write `acp-proxy.json`. |
| `client/packages/acp_proxy/lib/src/launch_meta.dart` | Read and check `session/new` `_meta`. |
| `client/packages/acp_proxy/lib/src/idle_policy.dart` | When the idle clock runs. |
| `client/packages/acp_proxy/lib/src/permission_policy.dart` | Disconnected permission decision and allow-option picker. |
| `client/packages/acp_proxy/lib/src/session_book.dart` | One leg per session, in-flight prompt identity, turn phase. |
| `client/packages/acp_proxy/lib/src/spool.dart` | Disk spool and bounded memory tail. |
| `client/packages/acp_proxy/lib/src/upstream.dart` | `AcpUpstream` seam. The real CLI process is behind this. |
| `client/packages/acp_proxy/lib/src/proxy_agent.dart` | ACP agent handlers over one phone transport. |
| `client/packages/acp_proxy/lib/src/listener.dart` | `127.0.0.1` ports, advertisement, pid file. |
| `client/packages/acp_proxy/bin/teampilot_acp_proxy.dart` | Arg parse and process entry. |
| Tests under `client/packages/acp_proxy/test/` | One test file per library above. |

---

### Task 1: Package, version, advertisement

**Files:**
- Create: `client/packages/acp_proxy/pubspec.yaml`
- Create: `client/packages/acp_proxy/lib/src/version.dart`
- Create: `client/packages/acp_proxy/lib/src/advertisement.dart`
- Create: `client/packages/acp_proxy/lib/acp_proxy.dart`
- Test: `client/packages/acp_proxy/test/advertisement_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `const acpProxyVersion = '0.1.0'`. `AcpProxyAdvertisement({required String version, required int pid, required Map<String, int> ports})`. `AcpProxyAdvertisement.parse(String raw)`. `Future<void> writeAcpProxyAdvertisement(Directory root, AcpProxyAdvertisement ad)`. `File acpProxyAdvertisementFile(Directory root)` → `<root>/acp-proxy.json`.

- [ ] **Step 1: Write the failing test**

Create `client/packages/acp_proxy/test/advertisement_test.dart`:

```dart
import 'dart:io';

import 'package:acp_proxy/acp_proxy.dart';
import 'package:test/test.dart';

void main() {
  test('parse reads version, pid, and ports', () {
    final ad = AcpProxyAdvertisement.parse('''
{
  "v": 1,
  "version": "0.1.0",
  "bind": "127.0.0.1",
  "pid": 42,
  "clis": { "claude": { "port": 43111 }, "codex": { "port": 43112 } }
}
''');
    expect(ad.version, '0.1.0');
    expect(ad.pid, 42);
    expect(ad.ports, {'claude': 43111, 'codex': 43112});
  });

  test('parse rejects a non-loopback bind', () {
    expect(
      () => AcpProxyAdvertisement.parse(
        '{"v":1,"version":"0.1.0","bind":"0.0.0.0","pid":1,"clis":{}}',
      ),
      throwsFormatException,
    );
  });

  test('write is atomic and round-trips', () async {
    final root = await Directory.systemTemp.createTemp('acp-proxy-ad');
    addTearDown(() => root.delete(recursive: true));
    const ad = AcpProxyAdvertisement(
      version: acpProxyVersion,
      pid: 7,
      ports: {'claude': 43111},
    );
    await writeAcpProxyAdvertisement(root, ad);
    final read = AcpProxyAdvertisement.parse(
      acpProxyAdvertisementFile(root).readAsStringSync(),
    );
    expect(read.version, acpProxyVersion);
    expect(read.pid, 7);
    expect(read.ports['claude'], 43111);
    expect(acpProxyAdvertisementFile(root).path, endsWith('acp-proxy.json'));
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd client/packages/acp_proxy && dart test test/advertisement_test.dart
```

Expected: FAIL — package or library cannot be found. Create the package first if `dart test` cannot resolve it; the test must still fail on the missing API before Step 3 fills it in. If the package files do not exist yet, Step 3 creates them and this step's failure is "path not found".

- [ ] **Step 3: Write the implementation**

`pubspec.yaml`:

```yaml
name: acp_proxy
publish_to: none
version: 0.1.0
environment:
  sdk: ^3.8.1
dependencies:
  acpd:
    path: ../acpd/packages/acpd
dev_dependencies:
  acpd_test:
    path: ../acpd/packages/acpd_test
  test: ^1.25.0
```

`lib/src/version.dart`:

```dart
const acpProxyVersion = '0.1.0';
```

`lib/src/advertisement.dart` parses only `v == 1`, `bind == '127.0.0.1'`, a positive `pid`, and `clis` entries whose `port` is an `int` greater than 0. `writeAcpProxyAdvertisement` writes `<root>/acp-proxy.json.tmp` then `rename`s it over `acp-proxy.json`. Encode `version`, `pid`, `bind`, and `clis`.

`lib/acp_proxy.dart` exports `version.dart` and `advertisement.dart`.

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd client/packages/acp_proxy && dart test test/advertisement_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/packages/acp_proxy/pubspec.yaml \
  client/packages/acp_proxy/lib/acp_proxy.dart \
  client/packages/acp_proxy/lib/src/version.dart \
  client/packages/acp_proxy/lib/src/advertisement.dart \
  client/packages/acp_proxy/test/advertisement_test.dart
git commit -m "feat(acp-proxy): add the loopback advertisement file"
```

---

### Task 2: session/new launch meta

**Files:**
- Create: `client/packages/acp_proxy/lib/src/launch_meta.dart`
- Modify: `client/packages/acp_proxy/lib/acp_proxy.dart`
- Test: `client/packages/acp_proxy/test/launch_meta_test.dart`

**Interfaces:**
- Consumes: nothing from Task 1 except the barrel file.
- Produces: `enum AcpProxyPermissionPolicy { fullAccess, ask }`. `class AcpProxyLaunchMeta { final String cli; final String executable; final List<String> args; final Map<String, String> env; final AcpProxyPermissionPolicy permissionPolicy; }`. `AcpProxyLaunchMeta parse({required String endpointCli, required Map<String, Object?> meta})`. Throws `FormatException` when `meta['teampilot']` is missing, `cli` differs from `endpointCli`, `executable` is empty, or `permissionPolicy` is not `fullAccess` or `ask`.

The `_meta` object on `session/new` is:

```json
{
  "teampilot": {
    "cli": "claude",
    "executable": "/usr/local/bin/claude",
    "args": ["--acp"],
    "env": {"HOME": "/home/runner"},
    "permissionPolicy": "fullAccess"
  }
}
```

- [ ] **Step 1: Write the failing test**

```dart
import 'package:acp_proxy/acp_proxy.dart';
import 'package:test/test.dart';

void main() {
  final meta = {
    'teampilot': {
      'cli': 'claude',
      'executable': '/usr/local/bin/claude',
      'args': ['--acp'],
      'env': {'HOME': '/home/runner'},
      'permissionPolicy': 'fullAccess',
    },
  };

  test('parses a matching endpoint', () {
    final launch = AcpProxyLaunchMeta.parse(
      endpointCli: 'claude',
      meta: meta,
    );
    expect(launch.executable, '/usr/local/bin/claude');
    expect(launch.args, ['--acp']);
    expect(launch.env['HOME'], '/home/runner');
    expect(launch.permissionPolicy, AcpProxyPermissionPolicy.fullAccess);
  });

  test('rejects a different cli than the port', () {
    expect(
      () => AcpProxyLaunchMeta.parse(endpointCli: 'codex', meta: meta),
      throwsFormatException,
    );
  });

  test('rejects an unknown permission policy', () {
    final bad = {
      'teampilot': {...(meta['teampilot']! as Map), 'permissionPolicy': 'yolo'},
    };
    expect(
      () => AcpProxyLaunchMeta.parse(endpointCli: 'claude', meta: bad),
      throwsFormatException,
    );
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd client/packages/acp_proxy && dart test test/launch_meta_test.dart
```

Expected: FAIL — `AcpProxyLaunchMeta` is not defined.

- [ ] **Step 3: Write the implementation**

`launch_meta.dart` reads only the `teampilot` map. `args` defaults to empty. `env` values must be strings. Export the types from `acp_proxy.dart`.

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd client/packages/acp_proxy && dart test test/launch_meta_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/packages/acp_proxy/lib/src/launch_meta.dart \
  client/packages/acp_proxy/lib/acp_proxy.dart \
  client/packages/acp_proxy/test/launch_meta_test.dart
git commit -m "feat(acp-proxy): parse session/new launch meta"
```

---

### Task 3: Idle clock and disconnected permission

**Files:**
- Create: `client/packages/acp_proxy/lib/src/idle_policy.dart`
- Create: `client/packages/acp_proxy/lib/src/permission_policy.dart`
- Modify: `client/packages/acp_proxy/lib/acp_proxy.dart`
- Test: `client/packages/acp_proxy/test/idle_policy_test.dart`
- Test: `client/packages/acp_proxy/test/permission_policy_test.dart`

**Interfaces:**
- Consumes: `AcpProxyPermissionPolicy` from Task 2.
- Produces: `bool shouldRunIdleTimer({required bool phoneConnected, required bool turnInProgress, required bool permissionPending})`. `const acpProxyIdleTimeout = Duration(minutes: 30)`. `const acpProxyPermissionTimeout = Duration(hours: 24)`. `enum DisconnectedPermissionAction { autoAllow, hold }`. `DisconnectedPermissionAction permissionActionWhenDisconnected(AcpProxyPermissionPolicy policy)`. `String? preferredAllowOptionId(Object? options)`.

- [ ] **Step 1: Write the failing tests**

`idle_policy_test.dart` asserts `shouldRunIdleTimer` is true only when the phone is gone, no turn is in progress, and no permission is pending. The other seven boolean combinations are false. Also `expect(acpProxyIdleTimeout, const Duration(minutes: 30))` and `expect(acpProxyPermissionTimeout, const Duration(hours: 24))`.

`permission_policy_test.dart`:

```dart
import 'package:acp_proxy/acp_proxy.dart';
import 'package:test/test.dart';

void main() {
  test('fullAccess auto-allows and ask holds', () {
    expect(
      permissionActionWhenDisconnected(AcpProxyPermissionPolicy.fullAccess),
      DisconnectedPermissionAction.autoAllow,
    );
    expect(
      permissionActionWhenDisconnected(AcpProxyPermissionPolicy.ask),
      DisconnectedPermissionAction.hold,
    );
  });

  test('prefers allow-always over allow-once', () {
    final id = preferredAllowOptionId([
      {'optionId': 'once', 'kind': 'allow-once'},
      {'optionId': 'always', 'kind': 'allow-always'},
      {'optionId': 'no', 'kind': 'reject-once'},
    ]);
    expect(id, 'always');
  });

  test('returns null when every option rejects', () {
    expect(
      preferredAllowOptionId([
        {'optionId': 'no', 'kind': 'reject_once'},
      ]),
      isNull,
    );
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd client/packages/acp_proxy && dart test test/idle_policy_test.dart test/permission_policy_test.dart
```

Expected: FAIL — the functions are not defined.

- [ ] **Step 3: Write the implementation**

`shouldRunIdleTimer` is `!phoneConnected && !turnInProgress && !permissionPending`.

`preferredAllowOptionId` copies the kind normalization in `client/lib/services/acp/acp_host_mcp_permission.dart` `_preferredAllowOptionId`: lowercase, hyphens to underscores, skip ids that start with `reject`, return the allow-always id, else allow-once, else any id whose kind or id starts with `allow`. It does not log and it does not import `package:teampilot`. Do not port the teammate-bus last-resort branch.

Export both libraries from the barrel.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd client/packages/acp_proxy && dart test test/idle_policy_test.dart test/permission_policy_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/packages/acp_proxy/lib/src/idle_policy.dart \
  client/packages/acp_proxy/lib/src/permission_policy.dart \
  client/packages/acp_proxy/lib/acp_proxy.dart \
  client/packages/acp_proxy/test/idle_policy_test.dart \
  client/packages/acp_proxy/test/permission_policy_test.dart
git commit -m "feat(acp-proxy): decide idle reaping and disconnected permissions"
```

---

### Task 4: Session book

**Files:**
- Create: `client/packages/acp_proxy/lib/src/session_book.dart`
- Modify: `client/packages/acp_proxy/lib/acp_proxy.dart`
- Test: `client/packages/acp_proxy/test/session_book_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces:

```dart
enum AcpProxyPromptDisposition { start, joinInFlight }

class AcpProxySessionBook {
  AcpProxySessionBook();

  /// Closes the previous connection id for [sessionId], if any.
  /// Returns that previous id, or null.
  String? attach({required String sessionId, required String connectionId});

  void detach(String connectionId);

  String? connectionFor(String sessionId);

  AcpProxyPromptDisposition onPrompt({
    required String sessionId,
    required String text,
  });

  void finishTurn(String sessionId);

  bool turnInProgress(String sessionId);
}
```

`joinInFlight` only when `text` equals the prompt already forwarded for the open turn. After `finishTurn`, the same text returns `start`.

- [ ] **Step 1: Write the failing test**

Cover: attaching a second connection id returns the first id; `connectionFor` is the new id; `detach` clears it. `onPrompt` returns `start`, a second call with the same text returns `joinInFlight`, a different text while the turn is open still returns `joinInFlight` is wrong — a different text while a turn is open throws `StateError` (the phone must not start a second turn). After `finishTurn`, the same text returns `start`. A different `sessionId` is independent.

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd client/packages/acp_proxy && dart test test/session_book_test.dart
```

Expected: FAIL — `AcpProxySessionBook` is not defined.

- [ ] **Step 3: Write the implementation**

One map from session id to `{connectionId, String? prompt, bool running}`. `attach` replaces `connectionId` and returns the old one. Do not clear the in-flight prompt on attach. `detach` clears the connection id only when it is still current.

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd client/packages/acp_proxy && dart test test/session_book_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/packages/acp_proxy/lib/src/session_book.dart \
  client/packages/acp_proxy/lib/acp_proxy.dart \
  client/packages/acp_proxy/test/session_book_test.dart
git commit -m "feat(acp-proxy): keep one connection per ACP session"
```

---

### Task 5: Spool

**Files:**
- Create: `client/packages/acp_proxy/lib/src/spool.dart`
- Modify: `client/packages/acp_proxy/lib/acp_proxy.dart`
- Test: `client/packages/acp_proxy/test/spool_test.dart`

**Interfaces:**
- Consumes: `AcpProxyLaunchMeta` from Task 2.
- Produces:

```dart
class AcpProxySpool {
  AcpProxySpool({required this.root, this.memoryTailBytes = 65536});

  final Directory root;
  final int memoryTailBytes;

  Future<void> create({
    required String sessionId,
    required String cwd,
    required AcpProxyLaunchMeta meta,
  });

  void appendUpdate(String sessionId, Map<String, Object?> update);

  List<Map<String, Object?> memoryTail(String sessionId);

  Future<List<Map<String, Object?>>> readAll(String sessionId);

  Future<void> delete(String sessionId);
}
```

Directory: `<root>/acp-proxy/sessions/<sessionId>/`. `meta.json` holds cwd, cli, executable, args, env, permissionPolicy. `updates.jsonl` is one JSON object per line. `memoryTail` returns only the suffix whose UTF-8 size is at most `memoryTailBytes`. `readAll` reads the file. `delete` removes the session directory. Create the directory with mode `0700` and the files with mode `0600` on POSIX. `appendUpdate` must not put `env` into the jsonl line.

- [ ] **Step 1: Write the failing test**

Use a temp directory. `create` then `appendUpdate` three small maps. `readAll` returns three. Set `memoryTailBytes` to a size that keeps only the last object, and expect `memoryTail` to have length 1. `delete` removes the directory. Assert `meta.json` contains `executable` and that a thrown log sink is unnecessary: the test reads `updates.jsonl` and expects it not to contain the env value `super-secret`.

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd client/packages/acp_proxy && dart test test/spool_test.dart
```

Expected: FAIL — `AcpProxySpool` is not defined.

- [ ] **Step 3: Write the implementation**

`meta.json` is the only file that stores `env`. Append to `updates.jsonl` with a trailing newline. After each append, drop the front of the in-memory list until its encoded size fits `memoryTailBytes`.

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd client/packages/acp_proxy && dart test test/spool_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/packages/acp_proxy/lib/src/spool.dart \
  client/packages/acp_proxy/lib/acp_proxy.dart \
  client/packages/acp_proxy/test/spool_test.dart
git commit -m "feat(acp-proxy): spool session updates on disk"
```

---

### Task 6: ACP agent over an injectable upstream

**Files:**
- Create: `client/packages/acp_proxy/lib/src/upstream.dart`
- Create: `client/packages/acp_proxy/lib/src/proxy_agent.dart`
- Modify: `client/packages/acp_proxy/lib/acp_proxy.dart`
- Test: `client/packages/acp_proxy/test/proxy_agent_test.dart`

**Interfaces:**
- Consumes: `AcpProxyLaunchMeta`, `AcpProxySessionBook`, `AcpProxySpool`, `shouldRunIdleTimer`, `permissionActionWhenDisconnected`, `preferredAllowOptionId`, `acpProxyPermissionTimeout`.
- Produces:

```dart
abstract class AcpUpstream {
  bool get alive;
  Future<String> openNew({
    required AcpProxyLaunchMeta meta,
    required String cwd,
    required List<Map<String, Object?>> mcpServers,
  });
  Future<void> openLoad({required String sessionId, required String cwd});
  Future<void> prompt(String text);
  Future<void> cancel();
  Future<void> close();
  Stream<Map<String, Object?>> get updates;

  /// CLI → client requests (`session/request_permission`, `cursor/ask_question`,
  /// `cursor/create_plan`). The proxy completes each one.
  Stream<AcpClientRequest> get clientRequests;
  void completeClientRequest(Object id, Map<String, Object?> result);
}

class AcpClientRequest {
  const AcpClientRequest({
    required this.id,
    required this.method,
    required this.params,
  });

  final Object id;
  final String method;
  final Map<String, Object?> params;
}

class AcpProxyAgent {
  AcpProxyAgent({
    required this.endpointCli,
    required this.book,
    required this.spool,
    required this.upstreams,
  });

  final String endpointCli;
  final AcpProxySessionBook book;
  final AcpProxySpool spool;

  /// Keyed by ACP session id. Tests insert fakes. Production creates them
  /// from [openNew] / [openLoad].
  final Map<String, AcpUpstream> upstreams;

  /// Factory used the first time a session id is unknown.
  /// Tests set this. Default throws StateError('no upstream').
  Future<AcpUpstream> Function({
    required AcpProxyLaunchMeta meta,
    required String cwd,
    required List<Map<String, Object?>> mcpServers,
  })? connectNew;

  AgentConnection serve(Transport phone);
}
```

`serve` builds an `AgentRole` (`package:acpd/acpd.dart`) and `connect`s it to `phone`. Register `onInitialize`, `onNewSession`, `onLoadSession`, `onResumeSession`, `onPrompt`, `onSessionCancel`, and `onCloseSession`. Those methods exist on `AgentRole` in `client/packages/acpd/packages/acpd/lib/src/role/role.dart`.

`AcpProxyAgent` takes `Duration permissionTimeout` defaulting to `acpProxyPermissionTimeout`. Tests pass a short duration.

Handler rules:

- `initialize` returns a response with `protocolVersion: 1` and empty capabilities. Do not spawn a CLI.
- `session/new` parses launch meta for `endpointCli`. On `FormatException`, complete the request with a JSON-RPC invalid-params error and do not insert a book entry. On success, call `connectNew`, then `openNew`. If `openNew` throws, call `upstream.close()`, do not keep the book entry, and surface the error. Store the returned session id in the book and spool.
- `session/load` with a live upstream: `book.attach`, then send the spool `readAll` updates as `session/update` notifications on the new phone context. Do not call `openLoad`.
- `session/load` with a dead or missing upstream: call `openLoad` on a newly connected upstream. If it throws, do not call `openNew`. Delete nothing from an existing phone transcript (this package never writes one). Surface the error.
- `session/prompt`: `book.onPrompt`. `start` calls `upstream.prompt`. `joinInFlight` does not call `upstream.prompt`; it completes when the in-flight prompt's stop update has been forwarded, which the test observes by the single `prompt` call count.
- `session/cancel` calls `upstream.cancel` and does not `finishTurn` until the upstream emits the stop update. The test's fake emits that stop itself.
- Phone transport `done`: `book.detach` only. `upstream.close` is not called. Record `disconnectedSince` for the idle reap in Task 8.
- `session/close`: `upstream.close()`, `book.finishTurn`, `spool.delete`.
- Each `clientRequests` event: if the phone leg is up, forward `session/request_permission`, `cursor/ask_question`, and `cursor/create_plan` to the phone and complete the upstream with the phone's result. If the phone is gone and the policy is `fullAccess` and the method is `session/request_permission`, complete with `preferredAllowOptionId`. If that returns null, or the policy is `ask`, or the method is a cursor question, do not invent an answer: wait until the phone leg returns or `permissionTimeout` elapses, then complete with a cancelled outcome. While that wait is outstanding, `permissionPending` is true so the idle timer does not run. Other client requests that are notifications are appended to the spool and, when they were JSON-RPC requests, completed with an empty map so the CLI is not left waiting.

The fake upstream in the test records `openNewCount`, `openLoadCount`, `promptCount`, `closeCount`, and a `StreamController` of updates.

- [ ] **Step 1: Write the failing test**

Use `MemoryTransportPair` from `package:acpd_test/acpd_test.dart`. Client role sits on `pair.left`. `agent.serve(pair.right)`.

Cases:

1. Disconnect (`pair.left.close()`) leaves `fake.closeCount == 0` and `fake.alive == true`.
2. After a `session/update` was emitted on the upstream while the phone was closed, a new pair's `session/load` receives that update and `openLoadCount` stays 0.
3. `openLoad` throwing makes `openNewCount` stay 0.
4. Two `session/prompt` calls with the same text while the fake has not emitted stop increment `promptCount` by 1.
5. After the fake emits `{'sessionUpdate': 'stop', 'stopReason': 'end_turn'}`, `finishTurn` has run: a later identical `session/prompt` increments `promptCount`.
6. A second `MemoryTransportPair` that `session/load`s the same id causes the first client connection's outbound stream to close.
7. With `permissionPolicy: fullAccess` and the phone transport closed, a `session/request_permission` whose options include `allow-always` is completed with that option id and `prompt` is not involved.
8. With `permissionPolicy: ask` and `permissionTimeout: Duration.zero`, the same request is completed with a cancelled outcome and `upstream.close` is not called.
9. A `cursor/ask_question` while the phone is gone is not completed with a made-up answer; after `permissionTimeout` it is cancelled.

Drive `session/new` with cwd `/work` and the Task 2 meta for cli `claude`.

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd client/packages/acp_proxy && dart test test/proxy_agent_test.dart
```

Expected: FAIL — `AcpProxyAgent` is not defined.

- [ ] **Step 3: Write the implementation**

Implement `upstream.dart` as the abstract class only. Implement `proxy_agent.dart` with the handlers above. Subscribe to `upstream.updates` and both append to the spool and, when `book.connectionFor(sessionId)` is non-null, `AgentContext.sessionUpdate`. A stop update calls `book.finishTurn`.

Use `NewSessionRequest`, `LoadSessionRequest`, `PromptRequest`, `CloseSessionRequest`, and `CancelNotification` from `package:acpd/acpd.dart` through the typed `on…` handlers named above. A different prompt text while a turn is open becomes a JSON-RPC error response and does not call `upstream.prompt`. `StateError` from the book stays inside the proxy; the phone sees the error response.

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd client/packages/acp_proxy && dart test test/proxy_agent_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/packages/acp_proxy/lib/src/upstream.dart \
  client/packages/acp_proxy/lib/src/proxy_agent.dart \
  client/packages/acp_proxy/lib/acp_proxy.dart \
  client/packages/acp_proxy/test/proxy_agent_test.dart
git commit -m "feat(acp-proxy): keep the CLI alive across phone reconnects"
```

---

### Task 7: Loopback listener

**Files:**
- Create: `client/packages/acp_proxy/lib/src/listener.dart`
- Modify: `client/packages/acp_proxy/lib/acp_proxy.dart`
- Modify: `client/packages/acp_proxy/pubspec.yaml` (add `acpd_io` path `../acpd/packages/acpd_io`)
- Test: `client/packages/acp_proxy/test/listener_test.dart`

**Interfaces:**
- Consumes: `AcpProxyAgent.serve`, `writeAcpProxyAdvertisement`, `acpProxyVersion`.
- Produces:

```dart
class AcpProxyListener {
  AcpProxyListener({
    required this.root,
    required this.cliIds,
    required this.agentForCli,
    this.pid,
  });

  final Directory root;
  final List<String> cliIds;
  final AcpProxyAgent Function(String cliId) agentForCli;
  final int? pid;

  Future<AcpProxyAdvertisement> start();
  Future<void> close();
}
```

`start` throws `ArgumentError` when `pid` is null. It binds one `ServerSocket` per cli id on `InternetAddress.loopbackIPv4` port 0. It writes `<root>/acp-proxy/acp-proxy.pid` first, then the advertisement with that pid. The test passes `pid: 4242`. Each accepted socket is adapted to a `Transport` by the same newline framing as `StdioTransport` in `package:acpd_io/acpd_io.dart`: split on `\n`, decode one JSON-RPC message per line, and write one JSON line per outbound frame. One socket serves `agentForCli(cliId).serve(transport)`. `close` closes every server socket and does not close upstreams.

- [ ] **Step 1: Write the failing test**

Start a listener with cli ids `['claude']` and an agent whose `connectNew` returns a fake upstream. Read `acp-proxy.json` and expect `bind == '127.0.0.1'`, `version == '0.1.0'`, and a positive port. Open a second `ServerSocket.bind(InternetAddress.loopbackIPv4, thatPort)` and expect it to throw (the port is taken by our listener). `close` then allows a bind on a new port; the test only needs `close` to complete and the pid file to contain the pid passed in (`pid: 4242`).

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd client/packages/acp_proxy && dart test test/listener_test.dart
```

Expected: FAIL — `AcpProxyListener` is not defined.

- [ ] **Step 3: Write the implementation**

Reject any attempt to bind a non-loopback address by not accepting an address parameter. Write the pid file before the advertisement so a reader never sees a port without a pid.

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd client/packages/acp_proxy && dart test test/listener_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/packages/acp_proxy/lib/src/listener.dart \
  client/packages/acp_proxy/lib/acp_proxy.dart \
  client/packages/acp_proxy/pubspec.yaml \
  client/packages/acp_proxy/test/listener_test.dart
git commit -m "feat(acp-proxy): listen on one loopback port per CLI"
```

---

### Task 8: Process entry and idle reap

**Files:**
- Create: `client/packages/acp_proxy/bin/teampilot_acp_proxy.dart`
- Create: `client/packages/acp_proxy/lib/src/args.dart`
- Modify: `client/packages/acp_proxy/lib/acp_proxy.dart`
- Test: `client/packages/acp_proxy/test/args_test.dart`
- Test: `client/packages/acp_proxy/test/idle_reap_test.dart`

**Interfaces:**
- Consumes: `shouldRunIdleTimer`, `acpProxyIdleTimeout`, `AcpProxyListener`, `AcpProxySpool.delete`.
- Produces: `AcpProxyArgs parseAcpProxyArgs(List<String> args)` with fields `Directory root`, `Duration idleTimeout`, `bool detach`, `List<String> cliIds`. Missing `--root` throws `FormatException`. `--idle-timeout 30m` parses minutes. `--detach` sets the flag and does not itself spawn a process; the bin script does.

`bin/teampilot_acp_proxy.dart` when `detach` is true runs `Process.start(Platform.resolvedExecutable, [...Platform.executableArguments, Platform.script.toFilePath(), ...args without --detach], mode: ProcessStartMode.detached)` and exits 0. When false, it constructs the listener and a periodic timer of one minute. Each tick, for every session where `shouldRunIdleTimer` is true and the disconnected-since time is older than `idleTimeout`, it calls `upstream.close()` and `spool.delete`. The test does not run the bin script. It calls the tick function with a fake clock.

```dart
Future<void> reapIdleSessions({
  required AcpProxySessionBook book,
  required AcpProxySpool spool,
  required Map<String, AcpUpstream> upstreams,
  required Map<String, DateTime> disconnectedSince,
  required DateTime now,
  required Duration idleTimeout,
  required bool Function(String sessionId) permissionPending,
});
```

`disconnectedSince` is set when the phone leg becomes null and cleared when a connection attaches. The book needs `List<String> get sessionIds` and `bool phoneConnected(String sessionId)` added in this task.

- [ ] **Step 1: Write the failing tests**

`args_test.dart`: `parseAcpProxyArgs(['--root', '/tmp/tp', '--idle-timeout', '30m', '--cli', 'claude', '--cli', 'codex'])` yields that root, 30 minutes, detach false, and both cli ids. Missing `--root` throws `FormatException`. `--detach` is true only when present.

`idle_reap_test.dart`: a session disconnected 31 minutes ago with no turn and no pending permission is closed and deleted. A session disconnected 31 minutes ago with `turnInProgress` true is kept. A session disconnected 1 minute ago is kept. Use `idleTimeout: const Duration(minutes: 30)`.

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd client/packages/acp_proxy && dart test test/args_test.dart test/idle_reap_test.dart
```

Expected: FAIL — `parseAcpProxyArgs` / `reapIdleSessions` are not defined.

- [ ] **Step 3: Write the implementation**

Add the two book getters in `session_book.dart`. Implement `reapIdleSessions` in `idle_policy.dart` so the decision and the effect stay next to `shouldRunIdleTimer`. Implement `args.dart` with no I/O. The bin script is the only file that calls `Process.start`.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd client/packages/acp_proxy && dart test
```

Expected: PASS for the whole package.

- [ ] **Step 5: Commit**

```bash
git add client/packages/acp_proxy/bin/teampilot_acp_proxy.dart \
  client/packages/acp_proxy/lib/src/args.dart \
  client/packages/acp_proxy/lib/src/idle_policy.dart \
  client/packages/acp_proxy/lib/src/session_book.dart \
  client/packages/acp_proxy/lib/acp_proxy.dart \
  client/packages/acp_proxy/test/args_test.dart \
  client/packages/acp_proxy/test/idle_reap_test.dart
git commit -m "feat(acp-proxy): reap idle sessions and add the process entry"
```

---

## Plan 1 self-check

Spec sections covered here: process and ports, ACP on both legs, `_meta`, one connection, reconnect replay without a second `session/load` on a live CLI, load failure does not `session/new`, spool versus phone transcript, close versus disconnect, idle 30 minutes, disconnected permission, duplicate in-flight prompt, loopback advertisement.

Spec sections deferred: CLI-page install, GitHub download, SHA-256, phone `forwardLocal` versus SSH `exec`, UI hint. Those are Plans 2 and 3.
