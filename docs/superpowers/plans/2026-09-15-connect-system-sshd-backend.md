# Connect System sshd Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On Linux and macOS, Connect can serve the full phone pairing loop through either the embedded `tp_sshd` or the host OpenSSH `sshd` on port 22, so a developer can A/B the two servers.

**Architecture:** A `ConnectSshBackend` sits in front of Connect. `ConnectBackendHost` starts exactly one backend (embedded `EmbeddedSshServer` or `SystemSshdBackend` that probes `:22` and writes `authorized_keys`). `ConnectAgent` mints offer `v:2` from the live backend (`emb`, port, fingerprints, relay splice) and authorizes pairing keys through that backend. Windows stays embedded-only. Default is embedded. A down system sshd does not fall back to `tp_sshd`.

**Tech Stack:** Flutter/Dart, `flutter_bloc`, existing Connect services (`ConnectAgent`, `PairedDeviceStore`, `ConnectSettingsStore`), injectable TCP probe + `ssh-keyscan` runner. Tests use `InMemoryFilesystem` and never launch a real sshd.

**Spec:** `docs/superpowers/specs/2026-09-15-connect-system-sshd-backend-design.md`

## Global Constraints

- Never invoke `flutter test` directly; use `cd client && dart run tool/run_tests.dart <paths>`.
- Inner loop: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings` plus the task's test file. Full suite only once before claiming done.
- l10n: edit `client/lib/l10n/app_en.arb` and `app_zh.arb` only; never hand-edit `app_localizations*.dart`.
- No Windows system-sshd UI or runtime. No configurable port. No auto-fallback to embedded. Do not start/stop OS sshd. Do not migrate keys on switch.
- Constructor-inject probe, `ssh-keyscan`, chmod, and filesystem. Unit tests must not call a real sshd.
- Preserve unrelated existing worktree changes.
- Paths: injected `Filesystem`; `authorized_keys` is `<nativeHome>/.ssh/authorized_keys`.

## File structure

| File | Responsibility |
| --- | --- |
| Create `client/lib/services/connect/connect_ssh_backend.dart` | `ConnectSshBackendKind`, `effectiveConnectSshBackend`, `ConnectSshBackend` interface. |
| Modify `client/lib/services/connect/connect_settings_store.dart` | Persist `sshBackend`; `saveSshBackend`; reachability `save` preserves the field. |
| Modify `client/lib/services/connect/embedded_ssh_server.dart` | Implement `ConnectSshBackend`; delete `EmbeddedSshServerHandle`; authorize/revoke no-op. |
| Modify `client/test/support/fake_embedded_server.dart` | Fake implements `ConnectSshBackend`. |
| Create `client/lib/services/connect/authorized_keys_file.dart` | Append / dedupe / remove OpenSSH lines; chmod 600 via injected seam. |
| Create `client/lib/services/connect/sshd_presence.dart` | Injected TCP `:22` probe + `ssh-keyscan` → OpenSSH `SHA256:` fingerprints. |
| Create `client/lib/services/connect/system_sshd_backend.dart` | System `ConnectSshBackend` (port 22). |
| Create `client/lib/services/connect/connect_backend_host.dart` | App-lifetime swap; persist; start only the effective backend. |
| Modify `client/lib/services/connect/connect_agent.dart` | Depend on `ConnectSshBackend`; `emb`/port/relay; authorize-on-pair with rollback; `replaceSshBackend`. |
| Modify `client/lib/services/connect/paired_device_store.dart` | `publicKeyForDevice`. |
| Modify `client/lib/cubits/connect_cubit.dart` | Kind in state, `selectSshBackend`, backend-specific down copy, revoke via backend then store. |
| Create `client/lib/pages/connect/connect_ssh_backend_selector.dart` | Linux/macOS selector widget. |
| Modify `client/lib/pages/connect/connect_section.dart` | Host selector; re-pair snackbar. |
| Modify `client/lib/pages/connect/connect_qr_panel.dart` | Backend-specific down copy. |
| Modify `client/lib/app/app_shell.dart` | Construct host; start selected backend only. |
| Modify `client/lib/l10n/app_en.arb`, `app_zh.arb` | New strings. |
| Modify `client/lib/utils/ui/app_keys.dart` | Selector key. |

---

### Task 1: Persist `sshBackend` and effective kind

**Files:**
- Create: `client/lib/services/connect/connect_ssh_backend.dart`
- Modify: `client/lib/services/connect/connect_settings_store.dart`
- Test: `client/test/services/connect/connect_settings_store_test.dart`
- Test: `client/test/services/connect/connect_ssh_backend_kind_test.dart`

**Interfaces:**
- Consumes: existing `ConnectSettingsStore.load` / `save` / `_write` merge.
- Produces:
  - `enum ConnectSshBackendKind { embedded, system }`
  - `ConnectSshBackendKind parseConnectSshBackendKind(Object? raw)` — `"system"` → `system`, anything else → `embedded`
  - `ConnectSshBackendKind effectiveConnectSshBackend({required ConnectSshBackendKind stored, required bool systemSshdSelectable})` — `system` only when both are true
  - `ConnectSettings.sshBackend` (`ConnectSshBackendKind`)
  - `Future<void> ConnectSettingsStore.saveSshBackend(ConnectSshBackendKind kind)`
  - `load()` returns `sshBackend`; reachability `save` must not drop it

- [ ] **Step 1: Write the failing tests**

Create `client/test/services/connect/connect_ssh_backend_kind_test.dart`:

```dart
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/connect/connect_ssh_backend.dart';

void main() {
  test('parseConnectSshBackendKind treats only the system token as system', () {
    expect(parseConnectSshBackendKind('system'), ConnectSshBackendKind.system);
    expect(parseConnectSshBackendKind('embedded'), ConnectSshBackendKind.embedded);
    expect(parseConnectSshBackendKind(null), ConnectSshBackendKind.embedded);
    expect(parseConnectSshBackendKind(''), ConnectSshBackendKind.embedded);
    expect(parseConnectSshBackendKind('SYSTEM'), ConnectSshBackendKind.embedded);
    expect(parseConnectSshBackendKind(1), ConnectSshBackendKind.embedded);
  });

  test('effectiveConnectSshBackend ignores system unless selectable', () {
    expect(
      effectiveConnectSshBackend(
        stored: ConnectSshBackendKind.system,
        systemSshdSelectable: true,
      ),
      ConnectSshBackendKind.system,
    );
    expect(
      effectiveConnectSshBackend(
        stored: ConnectSshBackendKind.system,
        systemSshdSelectable: false,
      ),
      ConnectSshBackendKind.embedded,
    );
    expect(
      effectiveConnectSshBackend(
        stored: ConnectSshBackendKind.embedded,
        systemSshdSelectable: true,
      ),
      ConnectSshBackendKind.embedded,
    );
  });
}
```

Add to `connect_settings_store_test.dart`:

```dart
test('load defaults sshBackend to embedded', () async {
  final settings = await newStore().load();
  expect(settings.sshBackend, ConnectSshBackendKind.embedded);
});

test('saveSshBackend round-trips system and preserves embeddedPort', () async {
  final store = newStore();
  final port = await store.loadOrCreateEmbeddedPort();
  await store.saveSshBackend(ConnectSshBackendKind.system);
  final json = await readSettings(store.settingsPath);
  expect(json['sshBackend'], 'system');
  expect(json['embeddedPort'], port);
  expect((await newStore().load()).sshBackend, ConnectSshBackendKind.system);
});

test('reachability save preserves sshBackend', () async {
  final store = newStore();
  await store.saveSshBackend(ConnectSshBackendKind.system);
  await store.save(extraEndpoints: const [], relayUrl: '');
  expect((await newStore().load()).sshBackend, ConnectSshBackendKind.system);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/services/connect/connect_ssh_backend_kind_test.dart test/services/connect/connect_settings_store_test.dart`

Expected: FAIL compiling (`connect_ssh_backend.dart` missing / `sshBackend` missing).

- [ ] **Step 3: Minimal implementation**

`connect_ssh_backend.dart` (kind helpers only in this task):

```dart
enum ConnectSshBackendKind { embedded, system }

ConnectSshBackendKind parseConnectSshBackendKind(Object? raw) {
  return raw == 'system'
      ? ConnectSshBackendKind.system
      : ConnectSshBackendKind.embedded;
}

ConnectSshBackendKind effectiveConnectSshBackend({
  required ConnectSshBackendKind stored,
  required bool systemSshdSelectable,
}) {
  return systemSshdSelectable && stored == ConnectSshBackendKind.system
      ? ConnectSshBackendKind.system
      : ConnectSshBackendKind.embedded;
}

extension ConnectSshBackendKindJson on ConnectSshBackendKind {
  String get jsonValue => this == ConnectSshBackendKind.system ? 'system' : 'embedded';
}
```

Add `sshBackend` to `ConnectSettings` (default `embedded`). In `load()`, `sshBackend: parseConnectSshBackendKind(json['sshBackend'])`. Add `saveSshBackend` that `_write({...await _readJson(), 'sshBackend': kind.jsonValue})`. Reachability `save` already spreads `_readJson()`, so it preserves the key once it exists — do not omit it.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/services/connect/connect_ssh_backend_kind_test.dart test/services/connect/connect_settings_store_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/connect/connect_ssh_backend.dart \
  client/lib/services/connect/connect_settings_store.dart \
  client/test/services/connect/connect_ssh_backend_kind_test.dart \
  client/test/services/connect/connect_settings_store_test.dart
git commit -m "$(cat <<'EOF'
feat(connect): persist sshBackend setting for embedded vs system sshd

EOF
)"
```

---

### Task 2: `ConnectSshBackend` interface; retire `EmbeddedSshServerHandle`

**Files:**
- Modify: `client/lib/services/connect/connect_ssh_backend.dart`
- Modify: `client/lib/services/connect/embedded_ssh_server.dart`
- Modify: `client/lib/services/connect/connect_agent.dart`
- Modify: `client/lib/cubits/connect_cubit.dart`
- Modify: `client/test/support/fake_embedded_server.dart`
- Modify: every import/type of `EmbeddedSshServerHandle` (agent tests, cubit tests, page tests, `app_shell.dart`)

**Interfaces:**
- Consumes: Task 1 kind helpers; existing `EmbeddedSshServer.start` / `stop` / `restart`.
- Produces:

```dart
abstract class ConnectSshBackend {
  bool get isListening;
  int get port;
  List<String> get hostKeyFingerprints;
  bool get isEmbedded;
  Future<void> start();
  Future<void> stop();
  Future<void> restart();
  Future<void> authorizePublicKey(String publicKey);
  Future<void> revokePublicKey(String publicKey);
}
```

- `EmbeddedSshServer implements ConnectSshBackend` with `isEmbedded => true` and authorize/revoke no-ops.
- `FakeEmbeddedServer implements ConnectSshBackend` (same defaults as today; `start`/`stop`/`authorize`/`revoke` no-op; `isEmbedded` default `true`).
- Delete `EmbeddedSshServerHandle`. Constructor param named `sshBackend` on `ConnectAgent`. `ConnectCubit` keeps the `embeddedServer` parameter name but types it as `ConnectSshBackend` until Task 7.

- [ ] **Step 1: Write the failing test**

Add to `client/test/services/connect/connect_agent_test.dart` (will fail until the type exists):

```dart
test('fake backend is embedded and authorize is a no-op', () async {
  final fake = FakeEmbeddedServer();
  expect(fake, isA<ConnectSshBackend>());
  expect(fake.isEmbedded, isTrue);
  await fake.authorizePublicKey('ssh-ed25519 AAAA');
  await fake.revokePublicKey('ssh-ed25519 AAAA');
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/connect/connect_agent_test.dart`

Expected: FAIL (`isEmbedded` / `authorizePublicKey` missing).

- [ ] **Step 3: Implement the interface and migrate call sites**

Append `ConnectSshBackend` to `connect_ssh_backend.dart`. Remove `abstract class EmbeddedSshServerHandle` from `embedded_ssh_server.dart`. Make `EmbeddedSshServer` implement `ConnectSshBackend`:

```dart
@override
bool get isEmbedded => true;

@override
Future<void> authorizePublicKey(String publicKey) async {}

@override
Future<void> revokePublicKey(String publicKey) async {}
```

`start` / `stop` / `restart` already exist.

Update `FakeEmbeddedServer` the same way (`isEmbedded` field default `true` so Task 6 can construct a system fake). Rename `ConnectAgent`'s constructor argument `embeddedServer:` → `sshBackend:`. Offer minting still hardcodes `emb: true` until Task 6 — do not change offer behavior in this task.

`ConnectCubit` and `app_shell` only change the handle type (`EmbeddedSshServerHandle` → `ConnectSshBackend`); do not rewire startup.

- [ ] **Step 4: Run the connect unit tests**

Run: `cd client && dart run tool/run_tests.dart test/services/connect/connect_agent_test.dart test/services/connect/embedded_ssh_server_test.dart test/cubits/connect_cubit_test.dart test/pages/connect/connect_qr_panel_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/connect/connect_ssh_backend.dart \
  client/lib/services/connect/embedded_ssh_server.dart \
  client/lib/services/connect/connect_agent.dart \
  client/lib/cubits/connect_cubit.dart \
  client/lib/app/app_shell.dart \
  client/test/support/fake_embedded_server.dart \
  client/test/services/connect client/test/cubits/connect_cubit_test.dart \
  client/test/pages/connect
git commit -m "$(cat <<'EOF'
refactor(connect): replace EmbeddedSshServerHandle with ConnectSshBackend

EOF
)"
```

Only stage files this task actually changed.

---

### Task 3: `AuthorizedKeysFile`

**Files:**
- Create: `client/lib/services/connect/authorized_keys_file.dart`
- Test: `client/test/services/connect/authorized_keys_file_test.dart`

**Interfaces:**
- Consumes: `Filesystem` (`readString`, `ensureDir`, `atomicWrite`).
- Produces:

```dart
typedef AuthorizedKeysChmod = Future<void> Function(String path);

class AuthorizedKeysFile {
  AuthorizedKeysFile({
    required Filesystem fs,
    required String homePath,
    AuthorizedKeysChmod? chmod600,
  });
  String get path; // `$homePath/.ssh/authorized_keys`
  Future<void> authorize(String publicKey);
  Future<void> revoke(String publicKey);
}
```

Matching is by decoded key blob (comment-insensitive), same idea as `PairedDeviceStore._decodePublicKeyBlob`. Duplicate authorize is a no-op. Revoke leaves unrelated lines. After write, call `chmod600(path)` when provided. Create `.ssh` via `ensureDir`. Do not rewrite the file when nothing changed.

- [ ] **Step 1: Write the failing tests**

```dart
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/connect/authorized_keys_file.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;
  late List<String> chmoded;
  late AuthorizedKeysFile keys;

  const home = '/home/alice';
  const keyA = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGZha2VrZXlh phone-a';
  const keyAComment = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGZha2VrZXlh other';
  const keyB = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGZha2VrZXli phone-b';

  setUp(() {
    fs = InMemoryFilesystem();
    chmoded = [];
    keys = AuthorizedKeysFile(
      fs: fs,
      homePath: home,
      chmod600: (path) async => chmoded.add(path),
    );
  });

  test('authorize creates the file, chmod 600, and appends the line', () async {
    await keys.authorize(keyA);
    expect(
      await fs.readString('$home/.ssh/authorized_keys'),
      '$keyA\n',
    );
    expect(chmoded, ['$home/.ssh/authorized_keys']);
  });

  test('authorize is a no-op when the key blob is already present', () async {
    await fs.ensureDir('$home/.ssh');
    await fs.atomicWrite('$home/.ssh/authorized_keys', '$keyAComment\n');
    await keys.authorize(keyA);
    expect(await fs.readString('$home/.ssh/authorized_keys'), '$keyAComment\n');
    expect(chmoded, isEmpty);
  });

  test('revoke removes matching blobs and leaves others', () async {
    await fs.ensureDir('$home/.ssh');
    await fs.atomicWrite(
      '$home/.ssh/authorized_keys',
      '$keyA\n$keyB\n',
    );
    await keys.revoke(keyAComment);
    expect(await fs.readString('$home/.ssh/authorized_keys'), '$keyB\n');
    expect(chmoded, ['$home/.ssh/authorized_keys']);
  });
}
```

Use those exact blobs; they must `base64.decode` after `base64.normalize`. If a test setup error says invalid base64, pad with `=` until decode succeeds, keeping the two blobs distinct.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/connect/authorized_keys_file_test.dart`

Expected: FAIL (library missing).

- [ ] **Step 3: Implement**

Parse OpenSSH lines: trim, skip blanks and `#` comments, split on whitespace, require `type` + blob. Compare `base64.decode(base64.normalize(blob))` byte-wise. `authorize` appends `publicKey.trim()` plus newline when the blob is new. `revoke` filters lines whose blob matches. After a mutating `atomicWrite`, `await chmod600(path)`. If `chmod600` is null, skip (tests may omit it; production always passes `Process.run('chmod', ['600', path])` later in Task 5/8). Throw if `atomicWrite` throws.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/connect/authorized_keys_file_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/connect/authorized_keys_file.dart \
  client/test/services/connect/authorized_keys_file_test.dart
git commit -m "$(cat <<'EOF'
feat(connect): add authorized_keys helper for system sshd pairing

EOF
)"
```

---

### Task 4: System sshd presence (probe + fingerprints)

**Files:**
- Create: `client/lib/services/connect/sshd_presence.dart`
- Test: `client/test/services/connect/sshd_presence_test.dart`

**Interfaces:**
- Consumes: none from prior tasks except fingerprint encoding must match `EmbeddedHostKeyStore._fingerprintOf`: `SHA256:` + unpadded standard base64 of SHA-256 over the public-key wire blob (the decoded authorized_keys blob).
- Produces:

```dart
typedef SshdPortProbe = Future<bool> Function();
typedef SshKeyScanRunner = Future<({int exitCode, String stdout, String stderr})> Function();

const int systemSshdPort = 22;

List<String> fingerprintsFromSshKeyScan(String stdout);

class SshdPresence {
  SshdPresence({required SshdPortProbe probe, required SshKeyScanRunner scan});
  Future<({bool listening, List<String> fingerprints})> sample();
}

SshdPortProbe loopbackSshdProbe({
  Duration timeout = const Duration(seconds: 1),
}); // production: Socket.connect('127.0.0.1', 22)

SshKeyScanRunner sshKeyScanRunner({
  required Future<({int exitCode, String stdout, String stderr})> Function(
    String executable,
    List<String> arguments,
  ) run,
}); // production args: ['-t','ed25519,ecdsa,rsa','-p','22','-T','3','127.0.0.1']
```

`sample()`: if probe is false → `(false, [])`. Else scan; parse fingerprints; if empty → `(false, [])`. Missing `ssh-keyscan` / non-zero with empty stdout → empty fingerprints. No background poll.

- [ ] **Step 1: Write the failing tests**

```dart
test('fingerprintsFromSshKeyScan skips comments and hashes the blob', () {
  const blob = 'AAAAC3NzaC1lZDI1NTE5AAAAIGZha2VrZXlh';
  final stdout = '# comment\n127.0.0.1 ssh-ed25519 $blob phone\n';
  final prints = fingerprintsFromSshKeyScan(stdout);
  expect(prints, hasLength(1));
  expect(prints.single, startsWith('SHA256:'));
});

test('sample is down when probe fails', () async {
  final presence = SshdPresence(
    probe: () async => false,
    scan: () async => (exitCode: 0, stdout: '127.0.0.1 ssh-ed25519 AAAA\n', stderr: ''),
  );
  final shot = await presence.sample();
  expect(shot.listening, isFalse);
  expect(shot.fingerprints, isEmpty);
});

test('sample is down when scan returns no keys', () async {
  final presence = SshdPresence(
    probe: () async => true,
    scan: () async => (exitCode: 1, stdout: '', stderr: 'Connection refused'),
  );
  final shot = await presence.sample();
  expect(shot.listening, isFalse);
  expect(shot.fingerprints, isEmpty);
});

test('sample listens when probe and fingerprints succeed', () async {
  const blob = 'AAAAC3NzaC1lZDI1NTE5AAAAIGZha2VrZXlh';
  final presence = SshdPresence(
    probe: () async => true,
    scan: () async => (
      exitCode: 0,
      stdout: '127.0.0.1 ssh-ed25519 $blob\n',
      stderr: '',
    ),
  );
  final shot = await presence.sample();
  expect(shot.listening, isTrue);
  expect(shot.fingerprints.single, startsWith('SHA256:'));
});
```

Use the same blob as Task 3 if it decodes.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/connect/sshd_presence_test.dart`

Expected: FAIL.

- [ ] **Step 3: Implement**

Parse non-comment lines with ≥3 fields. Host may be `127.0.0.1` or `[127.0.0.1]:22`. Type + blob are the last two-or-from-index-1 fields (`parts[1]` type, `parts[2]` blob) for unhashed `ssh-keyscan` output. Decode blob, `sha256`, `SHA256:${base64.encode(digest).replaceAll('=', '')}`. Deduplicate.

Also implement the production helpers in this file:

```dart
SshdPortProbe loopbackSshdProbe({
  Duration timeout = const Duration(seconds: 1),
}) {
  return () async {
    try {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        systemSshdPort,
        timeout: timeout,
      );
      await socket.close();
      return true;
    } on Object {
      return false;
    }
  };
}

SshKeyScanRunner sshKeyScanRunner({
  required Future<({int exitCode, String stdout, String stderr})> Function(
    String executable,
    List<String> arguments,
  ) run,
}) {
  return () async {
    try {
      return await run('ssh-keyscan', const [
        '-t', 'ed25519,ecdsa,rsa',
        '-p', '22',
        '-T', '3',
        '127.0.0.1',
      ]);
    } on Object {
      return (exitCode: 127, stdout: '', stderr: '');
    }
  };
}
```

`sshd_presence.dart` must import `dart:io` for `Socket` / `InternetAddress`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/connect/sshd_presence_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/connect/sshd_presence.dart \
  client/test/services/connect/sshd_presence_test.dart
git commit -m "$(cat <<'EOF'
feat(connect): probe loopback:22 and fingerprint system sshd host keys

EOF
)"
```

---

### Task 5: `SystemSshdBackend`

**Files:**
- Create: `client/lib/services/connect/system_sshd_backend.dart`
- Test: `client/test/services/connect/system_sshd_backend_test.dart`

**Interfaces:**
- Consumes: `ConnectSshBackend`, `AuthorizedKeysFile`, `SshdPresence`.
- Produces:

```dart
class SystemSshdBackend implements ConnectSshBackend {
  SystemSshdBackend({
    required SshdPresence presence,
    required AuthorizedKeysFile authorizedKeys,
  });
}
```

`isEmbedded => false`. `port => systemSshdPort` (22). `start`/`restart` call `presence.sample()` and store listening/fingerprints. `stop` clears them (`isListening` false, fingerprints empty, port still reports 22 per spec table — use `isListening ? 22 : 0` to match today's `SshdPresenceSnapshot` which uses port 0 when down; Connect cubit already does `listening ? port : 0`). Match cubit: when not listening, `port` getter may still be 22 but snapshot zeroes it. Keep `port => 22` always; cubit already zeroes when `!isListening`. `authorizePublicKey` / `revokePublicKey` delegate to `AuthorizedKeysFile`.

- [ ] **Step 1: Write the failing tests**

```dart
test('start samples presence; stop forgets it', () async {
  var listening = true;
  final backend = SystemSshdBackend(
    presence: SshdPresence(
      probe: () async => listening,
      scan: () async => (
        exitCode: 0,
        stdout: '127.0.0.1 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGZha2VrZXlh\n',
        stderr: '',
      ),
    ),
    authorizedKeys: AuthorizedKeysFile(fs: fs, homePath: '/home/alice'),
  );
  expect(backend.isEmbedded, isFalse);
  expect(backend.port, 22);
  await backend.start();
  expect(backend.isListening, isTrue);
  expect(backend.hostKeyFingerprints, isNotEmpty);
  listening = false;
  await backend.stop();
  expect(backend.isListening, isFalse);
  expect(backend.hostKeyFingerprints, isEmpty);
});

test('authorize and revoke write authorized_keys', () async {
  final fs = InMemoryFilesystem();
  final backend = SystemSshdBackend(
    presence: SshdPresence(
      probe: () async => false,
      scan: () async => (exitCode: 1, stdout: '', stderr: ''),
    ),
    authorizedKeys: AuthorizedKeysFile(fs: fs, homePath: '/home/alice'),
  );
  const key = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGZha2VrZXlh phone';
  await backend.authorizePublicKey(key);
  expect(await fs.readString('/home/alice/.ssh/authorized_keys'), contains('AAAAC3NzaC1lZDI1NTE5AAAAIGZha2VrZXlh'));
  await backend.revokePublicKey(key);
  expect(
    (await fs.readString('/home/alice/.ssh/authorized_keys'))?.trim(),
    isEmpty,
  );
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/connect/system_sshd_backend_test.dart`

Expected: FAIL.

- [ ] **Step 3: Implement `SystemSshdBackend`**

No real sockets. Do not start `tp_sshd`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/connect/system_sshd_backend_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/connect/system_sshd_backend.dart \
  client/test/services/connect/system_sshd_backend_test.dart
git commit -m "$(cat <<'EOF'
feat(connect): add SystemSshdBackend for port-22 OpenSSH pairing

EOF
)"
```

---

### Task 6: `ConnectAgent` uses the live backend

**Files:**
- Modify: `client/lib/services/connect/connect_agent.dart`
- Modify: `client/test/services/connect/connect_agent_test.dart`
- Modify: `client/lib/services/connect/paired_device_store.dart` only if rollback needs nothing new (`revokeDevice` already exists)

**Interfaces:**
- Consumes: `ConnectSshBackend.isEmbedded`, `port`, `hostKeyFingerprints`, `isListening`, `authorizePublicKey`.
- Produces:
  - `_mintOffer` uses `emb: _sshBackend.isEmbedded` and LAN port `_sshBackend.port`
  - `resolveRelayTarget('ssh')` uses `_sshBackend.port` when listening
  - pairing `acceptDevice`: `issueDevice` then `authorizePublicKey`; on authorize throw, `revokeDevice(deviceId)` then rethrow
  - `Future<void> replaceSshBackend(ConnectSshBackend backend)` under `_lifecycleLock` (does not remint; caller rebuilds QR)

- [ ] **Step 1: Write the failing tests**

In `connect_agent_test.dart`:

```dart
test('system backend offer is v2 emb false on port 22', () async {
  final connectAgent = agent(
    sshBackend: FakeEmbeddedServer(
      isListening: true,
      port: 22,
      isEmbedded: false,
      hostKeyFingerprints: const ['SHA256:system-key'],
    ),
  );
  await connectAgent.startQrSession(
    advertiseAddress: '192.168.1.5',
    username: 'u',
    displayName: 'desk',
    appDataRoot: '/app-data',
  );
  final offer = connectAgent.currentOffer!;
  expect(offer.v, 2);
  expect(offer.emb, isFalse);
  expect(offer.endpoints.first.port, 22);
  expect(offer.hostKeyFingerprints, ['SHA256:system-key']);
});

test('relay ssh target follows the backend port', () async {
  final connectAgent = agent(
    sshBackend: FakeEmbeddedServer(
      isListening: true,
      port: 22,
      isEmbedded: false,
      hostKeyFingerprints: const ['SHA256:abc'],
    ),
  );
  expect(await connectAgent.resolveRelayTarget('ssh'), (
    host: InternetAddress.loopbackIPv4,
    port: 22,
  ));
});

test('pairing authorize failure rolls back the device store', () async {
  final deviceStore = store();
  final backend = FakeEmbeddedServer(
    isListening: true,
    port: 22,
    isEmbedded: false,
    hostKeyFingerprints: const ['SHA256:abc'],
    authorizeError: StateError('authorized_keys denied'),
  );
  final connectAgent = agent(sshBackend: backend, deviceStore: deviceStore);
  await _start(connectAgent);
  final response = Completer<({int statusCode, Map<String, Object?> body})>();
  binding.requests.add(
    PairingHttpRequest(
      method: 'POST',
      uri: Uri(path: '/pair'),
      body: PairingPostBody(
        token: connectAgent.currentOffer!.pairing.token,
        deviceId: 'pixel-1',
        deviceName: 'Pixel',
        publicKey: publicKey,
      ),
      respond: ({required statusCode, required body}) async {
        response.complete((statusCode: statusCode, body: body));
      },
    ),
  );
  final result = await response.future;
  expect(result.statusCode, HttpStatus.internalServerError);
  expect(await deviceStore.hasDevice('pixel-1'), isFalse);
});
```

Keep the existing test that offer `emb` is true for the default fake.

Add `Object? authorizeError` to `FakeEmbeddedServer.authorizePublicKey`.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/connect/connect_agent_test.dart`

Expected: FAIL (`emb` still true / no rollback).

- [ ] **Step 3: Implement**

In `_startQrSession` keep the listening + SHA256 fingerprint guards, but read them from `_sshBackend`. Rename `_QrSession.embeddedPort` to `sshPort` and assign `_sshBackend.port`. `_mintOffer`: `emb: _sshBackend.isEmbedded`. Relay ssh: `if (!_sshBackend.isListening) return null; return (host: loopback, port: _sshBackend.port)`.

Pairing acceptDevice:

```dart
acceptDevice: ({
  required deviceId,
  required deviceName,
  required publicKey,
}) async {
  await _deviceStore.issueDevice(
    deviceId: deviceId,
    publicKey: publicKey,
    deviceName: deviceName,
  );
  try {
    await _sshBackend.authorizePublicKey(publicKey);
  } on Object {
    await _deviceStore.revokeDevice(deviceId);
    rethrow;
  }
},
```

Add `replaceSshBackend`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/connect/connect_agent_test.dart`

Expected: PASS. Existing embedded offer test still expects `emb: true`.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/connect/connect_agent.dart \
  client/test/services/connect/connect_agent_test.dart \
  client/test/support/fake_embedded_server.dart
git commit -m "$(cat <<'EOF'
feat(connect): mint offers and authorize pairing through ConnectSshBackend

EOF
)"
```

---

### Task 7: `ConnectBackendHost` + cubit switch and revoke

**Files:**
- Create: `client/lib/services/connect/connect_backend_host.dart`
- Test: `client/test/services/connect/connect_backend_host_test.dart`
- Modify: `client/lib/services/connect/paired_device_store.dart`
- Test: `client/test/services/connect/paired_device_store_test.dart` (or existing store test file)
- Modify: `client/lib/cubits/connect_cubit.dart`
- Modify: `client/test/cubits/connect_cubit_test.dart`

**Interfaces:**
- Consumes: Tasks 1–6.
- Produces:

```dart
class ConnectBackendHost {
  ConnectBackendHost({
    required ConnectSshBackend embedded,
    ConnectSshBackend? system,
    required ConnectSettingsStore settings,
    required bool systemSshdSelectable,
  });
  ConnectSshBackend get current;
  ConnectSshBackendKind get kind;
  Future<void> startSelected();
  Future<void> select(ConnectSshBackendKind requested);
}

Future<String?> PairedDeviceStore.publicKeyForDevice(String deviceId);
```

`startSelected` / `select`: compute `effectiveConnectSshBackend`; `select` also `saveSshBackend(requested)` (persist the user's choice even when Windows ignores it at runtime — host is only constructed as selectable on Linux/macOS, but tests cover `systemSshdSelectable: false` still persisting). Stop previous `current`, then `start` the new current. Never start both. If `system` is null, effective kind is always embedded.

`ConnectCubit`:
- Replace stored `ConnectSshBackend _sshBackend` with `ConnectBackendHost _backends`.
- Add `systemSshdSelectable` (from host), `ConnectSystemSshdHint systemSshdHint` (injected; widget must not read `Platform`).
- `ConnectState` gains `sshBackend`, `systemSshdSelectable`, `systemSshdHint`, `rePairNotice` (bool, default false).
- `selectSshBackend(kind)`: `await _backends.select(kind)`; `await _agent.replaceSshBackend(_backends.current)`; `await refresh()` (rebuilds QR via stop+start inside `refresh` / `_startFor`); set `rePairNotice: true`.
- `ackRePairNotice()` clears the flag.
- `retryEmbeddedServer` stays as the retry entry (call `_backends.current.restart()` then `refresh()`).
- `_presenceSnapshot` reads `_backends.current`.
- `revokeDevice`: `final key = await _deviceStore.publicKeyForDevice(id)`; if key != null `await _backends.current.revokePublicKey(key)`; then `await _deviceStore.revokeDevice(id)`.

```dart
enum ConnectSystemSshdHint { none, linux, macos }
```

Put the enum in `connect_cubit.dart` (UI-only).

- [ ] **Step 1: Write the failing tests**

Host:

```dart
test('select stops embedded and starts system', () async {
  final embedded = FakeEmbeddedServer(isListening: true, port: 54321);
  final system = FakeEmbeddedServer(
    isListening: false,
    port: 22,
    isEmbedded: false,
    hostKeyFingerprints: const ['SHA256:sys'],
  );
  var systemStarts = 0;
  system.onStart = () async {
    systemStarts += 1;
    system.isListening = true;
  };
  final host = ConnectBackendHost(
    embedded: embedded,
    system: system,
    settings: store,
    systemSshdSelectable: true,
  );
  await host.startSelected();
  expect(host.kind, ConnectSshBackendKind.embedded);
  await host.select(ConnectSshBackendKind.system);
  expect(host.kind, ConnectSshBackendKind.system);
  expect(host.current, same(system));
  expect(systemStarts, 1);
  expect(embedded.isListening, isFalse); // stop() should clear listening on the fake
});

test('system stored but not selectable still runs embedded', () async {
  await store.saveSshBackend(ConnectSshBackendKind.system);
  final host = ConnectBackendHost(
    embedded: FakeEmbeddedServer(),
    system: FakeEmbeddedServer(isEmbedded: false, port: 22),
    settings: store,
    systemSshdSelectable: false,
  );
  await host.startSelected();
  expect(host.kind, ConnectSshBackendKind.embedded);
  expect(host.current.isEmbedded, isTrue);
});
```

Extend `FakeEmbeddedServer.stop` to set `isListening = false` and `start` to run `onStart` (default: `isListening = true` if no hook). Track `stops`.

Cubit: `selectSshBackend` updates `state.sshBackend`, sets `rePairNotice`, and restarts QR (`starts` count increases after a stop). Revoke calls `revokePublicKey` on the fake before the device disappears from `pairedDevices`.

Store: `publicKeyForDevice` returns the issued line / null.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/services/connect/connect_backend_host_test.dart test/cubits/connect_cubit_test.dart`

Expected: FAIL.

- [ ] **Step 3: Implement host, `publicKeyForDevice`, cubit**

`publicKeyForDevice`: scan `_loadDeviceEntries()`, return `entry.publicKey` or null.

`ConnectCubit` takes `required ConnectBackendHost backends` and `ConnectSystemSshdHint systemSshdHint = ConnectSystemSshdHint.none`. Update every cubit test to wrap its fake in `ConnectBackendHost(embedded: fake, system: null, settings: the test store, systemSshdSelectable: false)`. No dual constructor.

`refresh()` already stops QR when `!canPair` and starts when it can; after `select`, calling `refresh()` rebuilds `_QrSession` because `startQrSession` begins with `_stopQrSession`. That satisfies “do not `_regenerateQr` on the old session”.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/services/connect/connect_backend_host_test.dart test/cubits/connect_cubit_test.dart test/services/connect/connect_agent_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/connect/connect_backend_host.dart \
  client/lib/services/connect/paired_device_store.dart \
  client/lib/cubits/connect_cubit.dart \
  client/test/support/fake_embedded_server.dart \
  client/test/services/connect/connect_backend_host_test.dart \
  client/test/cubits/connect_cubit_test.dart \
  client/test/services/connect/paired_device_store_test.dart
git commit -m "$(cat <<'EOF'
feat(connect): switch SSH backends at runtime and revoke system keys

EOF
)"
```

If `paired_device_store_test.dart` has no `publicKeyForDevice` coverage yet, add one test there (`issueDevice` then `publicKeyForDevice` returns the line; unknown id returns null).

---

### Task 8: l10n, Connect UI, `app_shell` wiring

**Files:**
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`
- Modify: `client/lib/utils/ui/app_keys.dart`
- Create: `client/lib/pages/connect/connect_ssh_backend_selector.dart`
- Modify: `client/lib/pages/connect/connect_section.dart`
- Modify: `client/lib/pages/connect/connect_qr_panel.dart`
- Modify: `client/lib/app/app_shell.dart`
- Test: `client/test/pages/connect/connect_qr_panel_test.dart`
- Test: `client/test/pages/connect/connect_ssh_backend_selector_test.dart`

**Interfaces:**
- Consumes: `ConnectState.systemSshdSelectable`, `sshBackend`, `systemSshdHint`, `rePairNotice`.
- Produces: visible selector only when `systemSshdSelectable`; down copy from backend+hint; snackbar on `rePairNotice`; production `ConnectBackendHost` in `app_shell`.

l10n keys (exact copy):

| Key | en | zh |
| --- | --- | --- |
| `connectSshBackendLabel` | SSH server | SSH 服务器 |
| `connectSshBackendEmbedded` | Embedded | 内置 |
| `connectSshBackendSystem` | System OpenSSH (22) | 系统 OpenSSH (22) |
| `connectSshBackendHelp` | Compare the built-in server with this computer's OpenSSH. Switching requires re-scanning the pairing code. | 用本机 OpenSSH 对比内置服务器。切换后需重新扫码配对。 |
| `connectSshBackendRePair` | Paired phones must re-scan this computer's pairing code. | 已配对的手机需重新扫描此电脑的配对码。 |
| `connectSystemSshdDownLinux` | No SSH server is listening on port 22. Start the OpenSSH sshd service, then retry. | 22 端口没有 SSH 服务在听。请启动 OpenSSH 的 sshd，然后重试。 |
| `connectSystemSshdDownMacos` | No SSH server is listening on port 22. Enable Remote Login in Sharing settings, then retry. | 22 端口没有 SSH 服务在听。请在「共享」中打开远程登录，然后重试。 |
| `connectRevokeSystemHint` | New logins are blocked. Already-open OpenSSH sessions may stay connected until they disconnect. | 新登录会被拒绝。已经建立的 OpenSSH 会话可能要等断开后才会失效。 |

Keep existing `connectSshdDown` for embedded.

`AppKeys.connectSshBackendSelect = Key('connect-ssh-backend-select')`.

QR panel `!canPair` copy:

- `sshBackend == embedded` → `connectSshdDown`
- system + `ConnectSystemSshdHint.macos` → macos string
- system + `ConnectSystemSshdHint.linux` → linux string
- system + `ConnectSystemSshdHint.none` → linux string (tests / non-selectable hosts)

Selector: `TpSelect<ConnectSshBackendKind>` below the interface picker in `_PairingCard`. `onChanged` → `cubit.selectSshBackend`. Only build when `state.systemSshdSelectable`.

Re-pair: in `ConnectSection`, `BlocListener` when `rePairNotice` becomes true → `ScaffoldMessenger.showSnackBar` + `ackRePairNotice()`.

Paired-devices card: if `state.sshBackend == system`, show `connectRevokeSystemHint` under the title.

`app_shell.dart` (desktop branch, `!Platform.isAndroid`):

```dart
final systemSshdSelectable = Platform.isLinux || Platform.isMacOS;
final systemBackend = systemSshdSelectable
    ? SystemSshdBackend(
        presence: SshdPresence(
          probe: loopbackSshdProbe(),
          scan: sshKeyScanRunner(run: (exe, args) async {
            final result = await Process.run(exe, args);
            return (
              exitCode: result.exitCode,
              stdout: result.stdout.toString(),
              stderr: result.stderr.toString(),
            );
          }),
        ),
        authorizedKeys: AuthorizedKeysFile(
          fs: localFs,
          homePath: nativeHome,
          chmod600: (path) async {
            await Process.run('chmod', ['600', path]);
          },
        ),
      )
    : null;
final backendHost = ConnectBackendHost(
  embedded: server,
  system: systemBackend,
  settings: settingsStore,
  systemSshdSelectable: systemSshdSelectable,
);
await backendHost.startSelected(); // instead of always server.start()
// catch start errors as today, non-fatal
final connectAgent = ConnectAgent.production(
  sshBackend: backendHost.current,
  ...
);
connectCubit = ConnectCubit(
  agent: ...,
  backends: backendHost,
  systemSshdHint: Platform.isMacOS
      ? ConnectSystemSshdHint.macos
      : (Platform.isLinux
            ? ConnectSystemSshdHint.linux
            : ConnectSystemSshdHint.none),
  ...
);
```

Do **not** call `server.start()` when effective kind is system. `startSelected` starts only `current`. Teardown: `await backendHost.current.stop()` (and stop embedded if it is not current — `startSelected` already left the other stopped). On process exit keep `await shell?.embeddedSshServer?.stop()` plus `system` stop, or stop via host.

If `startSelected` chooses system, still construct `EmbeddedSshServer` so a later `select(embedded)` can start it.

- [ ] **Step 1: Write the failing widget tests**

`connect_qr_panel_test.dart`: down state with `sshBackend: system`, `systemSshdHint: macos` finds the macOS string, not `connectSshdDown`.

Selector test: pump `_PairingCard` / section with `systemSshdSelectable: true` and find `AppKeys.connectSshBackendSelect`; with `false`, find nothing.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/pages/connect/connect_qr_panel_test.dart test/pages/connect/connect_ssh_backend_selector_test.dart`

Expected: FAIL.

- [ ] **Step 3: Add l10n, widgets, app_shell**

Edit arb files, run `cd client && flutter gen-l10n` so committed `app_localizations*.dart` update. Extract the selector into `connect_ssh_backend_selector.dart` so `connect_section.dart` stays under the ~500 line soft limit.

- [ ] **Step 4: Run tests + analyze**

Run:

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd client && dart run tool/run_tests.dart \
  test/pages/connect/connect_qr_panel_test.dart \
  test/pages/connect/connect_ssh_backend_selector_test.dart \
  test/cubits/connect_cubit_test.dart \
  test/services/connect/
```

Expected: analyze clean, tests PASS. Existing `test/integration/embedded_pairing_test.dart` stays default-embedded; do not change it.

- [ ] **Step 5: Commit**

```bash
git add client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb \
  client/lib/l10n/app_localizations.dart \
  client/lib/l10n/app_localizations_en.dart \
  client/lib/l10n/app_localizations_zh.dart \
  client/lib/utils/ui/app_keys.dart \
  client/lib/pages/connect/ \
  client/lib/app/app_shell.dart \
  client/lib/cubits/connect_cubit.dart \
  client/test/pages/connect/
git commit -m "$(cat <<'EOF'
feat(connect): add Linux/macOS toggle between embedded and system sshd

EOF
)"
```

Only stage generated l10n files if `flutter gen-l10n` changed them.

---

## Spec coverage

| Spec requirement | Task |
| --- | --- |
| Persist `sshBackend`, default embedded, reachability save preserves it | 1 |
| `effectiveConnectSshBackend` Windows/unselectable ignores system | 1, 7 |
| `ConnectSshBackend` replaces `EmbeddedSshServerHandle` | 2 |
| Embedded authorize/revoke no-op | 2 |
| `authorized_keys` append/dedupe/remove/chmod 600 | 3 |
| Probe `127.0.0.1:22`, `ssh-keyscan`, SHA256 fingerprints, no poll | 4 |
| `SystemSshdBackend` port 22, no tp_sshd | 5 |
| Offer v2 `emb` from backend, LAN port, relay splice | 6 |
| Pairing authorize + store rollback | 6 |
| Host start-one, select stop/start, rebuild QR via refresh | 7 |
| Revoke keys then store; system sessions may linger (copy in UI) | 7, 8 |
| Selector Linux/macOS only, injected flag | 8 |
| Down copy embedded vs Linux vs macOS | 8 |
| Re-pair notice | 8 |
| `app_shell` starts selected backend only | 8 |
| No fallback, no Windows UI, no key migration, no custom port | all (non-goals, untested as absences) |
| Embedded pairing integration unchanged | 8 (do not edit) |
