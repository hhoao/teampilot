# Embedded SSH Server — App Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire the `tp_sshd` package into the desktop app as the full replacement for the system sshd: an `EmbeddedSshServer` owned service, offer v2 pairing, the `RemoteCommandCodec` structured-command path, deletion of every system-sshd dependency, and the UI/l10n that goes with it.

**Architecture:** `EmbeddedSshServer` (app-lifetime service, `client/lib/services/connect/`) owns a `tp_sshd` `SSHServer` behind a real `ServerSocket` on a persisted high port, wiring every seam to app resources: auth → `PairedDeviceStore` (extended with device public keys), exec/pty → `Process.start` / `flutter_pty` with managed-toolchain PATH injection, SFTP → a native-filesystem adapter, forward → `ServerSocket.bind`. `ConnectAgent` mints offer v2 (`emb: true`) from the embedded server instead of probing port 22; all phone-side command emission converges on `RemoteCommandCodec`, which emits `tp1:` payloads for embedded targets and byte-identical POSIX shell strings for legacy targets.

**Tech Stack:** Flutter/Dart (`client/`), `client/packages/tp_sshd` (this PR #7 package), vendored `dartssh2` fork, `flutter_pty_new`, `pointycastle`/`pinenacl` (ed25519 key generation), `flutter_bloc` + `flutter_test`.

**Spec:** `docs/specs/2026-09-08-embedded-ssh-server-design.md` — sections "App integration and data flow", "Structured command protocol", "Security model", "Error handling", and the app-layer rows of "Testing". The protocol-server half is already shipped in PR #7 (`client/packages/tp_sshd`).

## Global Constraints

- Full replacement, not fallback: no `SshdPresence`, no `AuthorizedKeysFile`, no port-22 probe anywhere in the app after this plan.
- Publickey-only, fail-closed auth; the trust decision is always `PairedDeviceStore`.
- `exec` on embedded targets is `tp1:` structured payloads only; legacy branch output must stay byte-for-byte identical (regression-guarded by tests).
- Offer bumps to `v: 2` with `emb: true`; v1 phones scanning a v2 QR get a clean "unsupported version, upgrade" error.
- Persisted high port (random, `ConnectSettingsStore`), rebound on every launch; bind conflict → re-pick + persist + refresh live offer + non-blocking notice.
- Host key: load-or-generate ed25519 at `connect/host_key`, OpenSSH PEM via the fork's `SSHKeyPair.toPem()`; corrupt → regenerate.
- Loopback-only forwarding binds; no key material in logs; auth failures to `AppLogger` only.
- No migration for pre-upgrade profiles: fingerprint/port mismatch → "re-scan the pairing code" hint.
- Revocation fails the next auth AND tears down that device's established connections immediately.
- l10n: edit `client/lib/l10n/app_en.arb` and `app_zh.arb` only; user-facing errors via l10n, diagnostics via `AppLogger`.
- Before claiming any task done: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings` clean for the touched files, plus that task's tests.

## File Structure

```
client/lib/services/connect/
  embedded_host_key_store.dart      [new] load-or-generate host key + SHA256 fingerprint
  embedded_sftp_filesystem.dart     [new] tp_sshd SftpFileSystem over dart:io, path-context aware
  embedded_process_factories.dart   [new] SSHProcessFactory / SSHPtyFactory + shell/PATH policy
  embedded_ssh_server.dart          [new] app-lifetime owner of the tp_sshd SSHServer
  paired_device_store.dart          [mod] + device public-key registry (issueDevice / isValidDeviceKey)
  pairing_http.dart                 [mod] AuthorizedKeysFile → PairingDeviceSink
  connect_agent.dart                [mod] offer v2, embedded endpoints, relay target
  connect_settings_store.dart       [mod] + embeddedPort load-or-pick / repick
  sshd_presence.dart                [del]
  authorized_keys_file.dart         [del]
client/lib/services/host/
  remote_command_codec.dart         [new] RemoteCommandSpec + encode (legacy | tp1:)
client/lib/models/
  ssh_profile.dart                  [mod] + embeddedTarget
  ssh_pairing_offer.dart            [in connect/] [mod] + emb, v:2
client/lib/app/app_shell.dart       [mod] startup wiring; [del] sshd/authorized_keys block
client/lib/cubits/connect_cubit.dart[mod] canPair semantics, retry
client/lib/l10n/app_en.arb / app_zh.arb [mod] new keys, [del] install hint
client/packages/tp_sshd/
  lib/src/ssh_server.dart           [mod] + onAuthenticated hook (revocation support)
client/test/services/connect/       [new/modified tests mirroring the above]
client/test/integration/embedded_pairing_test.dart [new] full pairing loop
```

---

### Task 1: Embedded host key store — load-or-generate ed25519

**Files:**
- Create: `client/lib/services/connect/embedded_host_key_store.dart`
- Test: `client/test/services/connect/embedded_host_key_store_test.dart`

**Interfaces:**
- Consumes: `Filesystem` (`client/lib/services/io/filesystem.dart`), `SSHKeyPair.fromPem` / `OpenSSHEd25519KeyPair` / `toPem()` (dartssh2 fork), `pinenacl` `SigningKey.generate()`.
- Produces: `EmbeddedHostKey { SSHKeyPair keyPair; String fingerprint; }` and `EmbeddedHostKeyStore.loadOrCreate()` — used by Task 7 (`EmbeddedSshServer`) and Task 10 (offer fingerprints).

- [ ] **Step 1: Write the failing test**

```dart
// client/test/services/connect/embedded_host_key_store_test.dart
@TestOn('vm')
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/connect/embedded_host_key_store.dart';
import 'package:teampilot/services/io/local_filesystem.dart';

import '../support/post_frame_test_harness.dart';

void main() {
  testHarness(() {
    late LocalFilesystem fs;
    late String appDataRoot;

    setUp(() {
      final env = setUpTestAppStorage();
      fs = env.fs;
      appDataRoot = env.appDataRoot;
    });

    test('generates on first load and persists for the second', () async {
      final store = EmbeddedHostKeyStore(fs: fs, appDataRoot: appDataRoot);
      final first = await store.loadOrCreate();
      expect(first.fingerprint, startsWith('SHA256:'));
      expect(first.keyPair.type, 'ssh-ed25519');

      final second = await EmbeddedHostKeyStore(
        fs: fs,
        appDataRoot: appDataRoot,
      ).loadOrCreate();
      expect(second.fingerprint, first.fingerprint);
    });

    test('fingerprint is the SHA256 of the public key wire blob', () async {
      final key = await EmbeddedHostKeyStore(
        fs: fs,
        appDataRoot: appDataRoot,
      ).loadOrCreate();
      final blob = key.keyPair.toPublicKey().encode();
      final expected = 'SHA256:${base64.encode(sha256bytes(blob)).replaceAll('=', '')}';
      expect(key.fingerprint, expected);
    });

    test('corrupt key file is regenerated, not fatal', () async {
      final path = fs.pathContext.join(appDataRoot, 'connect', 'host_key');
      await fs.ensureDir(fs.pathContext.dirname(path));
      await fs.writeString(path, 'not a pem');
      final key = await EmbeddedHostKeyStore(
        fs: fs,
        appDataRoot: appDataRoot,
      ).loadOrCreate();
      expect(key.fingerprint, isNotEmpty);
    });
  });
}
```

(`sha256bytes` helper: `import 'package:crypto/crypto.dart'; List<int> sha256bytes(List<int> b) => sha256.convert(b).bytes;` — inline it in the test.)

Note: if `setUpTestAppStorage` exposes a different shape (check `client/test/support/post_frame_test_harness.dart` first and use its real API — do not invent fields), adapt the setup to what exists. The essential assertions stay.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/connect/embedded_host_key_store_test.dart`
Expected: FAIL — `embedded_host_key_store.dart` does not exist.

- [ ] **Step 3: Write minimal implementation**

```dart
// client/lib/services/connect/embedded_host_key_store.dart
import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dartssh2/dartssh2.dart'
    show SSHKeyPair, OpenSSHEd25519KeyPair, SSHHostKey;
import 'package:pinenacl/ed25519.dart' as ed25519;

import '../io/filesystem.dart';

/// The embedded server's host key and its OpenSSH-style SHA256 fingerprint.
class EmbeddedHostKey {
  const EmbeddedHostKey({required this.keyPair, required this.fingerprint});

  final SSHKeyPair keyPair;

  /// `SHA256:<base64-no-padding>` of the public-key wire blob — the format
  /// offer `hostKeyFingerprints` already filters for.
  final String fingerprint;
}

/// Load-or-generate the desktop's embedded-server host key, persisted as an
/// unencrypted OpenSSH PEM at `connect/host_key`.
class EmbeddedHostKeyStore {
  EmbeddedHostKeyStore({required this.fs, required this.appDataRoot});

  final Filesystem fs;
  final String appDataRoot;

  String get keyPath => fs.pathContext.join(appDataRoot, 'connect', 'host_key');

  Future<EmbeddedHostKey> loadOrCreate() async {
    final existing = await _loadExisting();
    if (existing != null) return existing;
    return _generateAndPersist();
  }

  Future<EmbeddedHostKey?> _loadExisting() async {
    final pem = await fs.readString(keyPath);
    if (pem == null || pem.trim().isEmpty) return null;
    try {
      final keyPair = SSHKeyPair.fromPem(pem).single;
      if (keyPair.type != 'ssh-ed25519') return null;
      return EmbeddedHostKey(
        keyPair: keyPair,
        fingerprint: _fingerprintOf(keyPair),
      );
    } on Object {
      // Corrupt file: regenerate (spec's error-handling table). The next
      // phone connect fails the pin check and surfaces the re-pair hint.
      return null;
    }
  }

  Future<EmbeddedHostKey> _generateAndPersist() async {
    final signingKey = ed25519.SigningKey.generate();
    final keyPair = OpenSSHEd25519KeyPair(
      Uint8List.fromList(signingKey.publicKey.asUint8List()),
      Uint8List.fromList(signingKey.encode()),
      'teampilot-embedded-host',
    );
    await fs.ensureDir(fs.pathContext.dirname(keyPath));
    await fs.atomicWrite(keyPath, keyPair.toPem());
    return EmbeddedHostKey(
      keyPair: keyPair,
      fingerprint: _fingerprintOf(keyPair),
    );
  }

  static String _fingerprintOf(SSHKeyPair keyPair) {
    final bytes = (keyPair.toPublicKey() as SSHHostKey).encode();
    return 'SHA256:${base64.encode(crypto.sha256.convert(bytes).bytes).replaceAll('=', '')}';
  }
}
```

Adjust imports to the exact exported names in the fork: `OpenSSHEd25519KeyPair` is exported from `package:dartssh2/dartssh2.dart` (it lives in `src/key_pair/openssh_key_pair.dart`; if not exported, import `package:dartssh2/src/key_pair/openssh_key_pair.dart` — the fork is ours). `Uint8List` needs `dart:typed_data`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/services/connect/embedded_host_key_store_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/services/connect/embedded_host_key_store.dart test/services/connect/embedded_host_key_store_test.dart
git commit -m "feat(connect): embedded host key store — load-or-generate ed25519"
```

---

### Task 2: Embedded port persistence in ConnectSettingsStore

**Files:**
- Modify: `client/lib/services/connect/connect_settings_store.dart`
- Test: `client/test/services/connect/connect_settings_store_test.dart` (extend the existing file)

**Interfaces:**
- Consumes: existing `ConnectSettingsStore` JSON I/O.
- Produces: `Future<int> loadOrCreateEmbeddedPort()`, `Future<int> repickEmbeddedPort()`, `static const embeddedPortMin = 49152; static const embeddedPortMax = 65535;` — used by Task 7.

- [ ] **Step 1: Write the failing tests** (append to the existing test file's `main`)

```dart
test('embeddedPort is picked once and persisted', () async {
  final store = ConnectSettingsStore(fs: fs, appDataRoot: appDataRoot);
  final first = await store.loadOrCreateEmbeddedPort();
  expect(first, inInclusiveRange(49152, 65535));

  final second = await ConnectSettingsStore(
    fs: fs,
    appDataRoot: appDataRoot,
  ).loadOrCreateEmbeddedPort();
  expect(second, first);
});

test('embeddedPort out of range is re-picked', () async {
  await fs.ensureDir(fs.pathContext.dirname(store.settingsPath));
  await fs.atomicWrite(store.settingsPath, '{"hostId":hostId,"embeddedPort":22}');
  final port = await store.loadOrCreateEmbeddedPort();
  expect(port, inInclusiveRange(49152, 65535));
  expect(port, isNot(22));
});

test('repickEmbeddedPort persists a different port', () async {
  final first = await store.loadOrCreateEmbeddedPort();
  var next = first;
  var guard = 0;
  while (next == first && guard++ < 64) {
    next = await store.repickEmbeddedPort();
  }
  expect(next, isNot(first));
});
```

Mirror the file's existing `fs` / `appDataRoot` / `hostId` fixtures — read the current test file first and reuse its setup.

- [ ] **Step 2: Run to verify failure**

Run: `cd client && flutter test test/services/connect/connect_settings_store_test.dart`
Expected: FAIL — no `loadOrCreateEmbeddedPort`.

- [ ] **Step 3: Implement**

Add to `ConnectSettings` and the store (keep the existing `_readJson`/`_write` helpers; they must round-trip unknown keys — extend `_write` callers to preserve `embeddedPort` when present by reading-then-merging, as `loadOrCreateHostId` already does):

```dart
static const embeddedPortMin = 49152;
static const embeddedPortMax = 65535;

Future<int> loadOrCreateEmbeddedPort() async {
  final json = await _readJson();
  final existing = json['embeddedPort'];
  if (existing is int &&
      existing >= embeddedPortMin &&
      existing <= embeddedPortMax) {
    return existing;
  }
  final port = _randomPort();
  await _write({...json, 'embeddedPort': port});
  return port;
}

Future<int> repickEmbeddedPort() async {
  final json = await _readJson();
  final port = _randomPort();
  await _write({...json, 'embeddedPort': port});
  return port;
}

static int _randomPort() {
  final random = Random.secure();
  return embeddedPortMin +
      random.nextInt(embeddedPortMax - embeddedPortMin + 1);
}
```

Also make `save()` and `loadOrCreateHostId()` merge instead of overwrite: `await _write({...await _readJson(), 'hostId': hostId, ...})` so saving endpoints never drops `embeddedPort` (and vice versa).

- [ ] **Step 4: Run to verify pass**

Run: `cd client && flutter test test/services/connect/connect_settings_store_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/connect/connect_settings_store.dart test/services/connect/connect_settings_store_test.dart
git commit -m "feat(connect): persist embedded server port in ConnectSettingsStore"
```

---

### Task 3: PairedDeviceStore — device public-key registry

**Files:**
- Modify: `client/lib/services/connect/paired_device_store.dart`
- Test: `client/test/services/connect/paired_device_store_test.dart` (extend)

**Interfaces:**
- Consumes: existing grants registry (`connect/grants.json`).
- Produces:
  - `Future<void> issueDevice({required String deviceId, required String publicKey, String? deviceName})` — `publicKey` is the OpenSSH one-line format (`ssh-ed25519 AAAA... comment`), as posted by the phone.
  - `Future<bool> isValidDeviceKey(String publicKeyLine)` — constant-time compare of the decoded wire blob against every registered device.
  - `Future<bool> revokeDevice(String deviceId)` — existing method now removes the key entry too.
  - `Stream<void> get deviceRegistryChanged` — fires after every mutation (revocation teardown, Task 7).
  - Registry file: `connect/devices.json`, shape `{"v":1,"devices":[{"deviceId","hostId","deviceName","publicKey"}]}`.

- [ ] **Step 1: Write failing tests** (append to existing test file)

```dart
test('issueDevice stores the key and isValidDeviceKey accepts it', () async {
  await store.issueDevice(
    deviceId: 'phone-1',
    publicKey: testDevicePubLine,
    deviceName: 'Pixel',
  );
  expect(await store.isValidDeviceKey(testDevicePubLine), isTrue);
  expect(await store.isValidDeviceKey(otherDevicePubLine), isFalse);
});

test('same device re-pair replaces the key entry', () async {
  await store.issueDevice(deviceId: 'phone-1', publicKey: testDevicePubLine);
  await store.issueDevice(deviceId: 'phone-1', publicKey: otherDevicePubLine);
  expect(await store.isValidDeviceKey(testDevicePubLine), isFalse);
  expect(await store.isValidDeviceKey(otherDevicePubLine), isTrue);
});

test('revokeDevice removes the key so auth fails', () async {
  await store.issueDevice(deviceId: 'phone-1', publicKey: testDevicePubLine);
  expect(await store.revokeDevice('phone-1'), isTrue);
  expect(await store.isValidDeviceKey(testDevicePubLine), isFalse);
});

test('deviceRegistryChanged fires on issue and revoke', () async {
  final events = <void>[];
  final sub = store.deviceRegistryChanged.listen(events.add);
  await store.issueDevice(deviceId: 'phone-1', publicKey: testDevicePubLine);
  await store.revokeDevice('phone-1');
  await sub.cancel();
  expect(events.length, 2);
});
```

Define the two key lines in the test from real ed25519 public keys (generate with `ssh-keygen -t ed25519 -N '' -f /tmp/k` once, paste the `.pub` contents as constants, comment included or not — both must work).

- [ ] **Step 2: Run to verify failure**

Run: `cd client && flutter test test/services/connect/paired_device_store_test.dart`

- [ ] **Step 3: Implement**

Add to `PairedDeviceStore` (keep grants untouched; new file, new load/write pair mirroring the grants pattern):

```dart
final _registryChanged = StreamController<void>.broadcast();
Stream<void> get deviceRegistryChanged => _registryChanged.stream;

String get devicesPath =>
    fs.pathContext.join(appDataRoot, 'connect', 'devices.json');

Future<void> issueDevice({
  required String deviceId,
  required String publicKey,
  String? deviceName,
}) async {
  final devices = (await _loadDeviceEntries()).toList()
    ..removeWhere((entry) => entry.deviceId == deviceId)
    ..add(_DeviceEntry(
      deviceId: deviceId,
      hostId: hostId, // read via loadOrCreateHostId? No: hostId stays caller-supplied on grants only; key entries are not host-scoped — drop hostId from _DeviceEntry.
      deviceName: deviceName,
      publicKey: publicKey.trim(),
    ));
  await _writeDeviceEntries(devices);
  _registryChanged.add(null);
}
```

`isValidDeviceKey`: decode the line's second whitespace field with `base64.decode` (invalid line → `false`), then constant-time compare against every stored entry's decoded blob (reuse the `_constantTimeEquals` pattern over bytes). `revokeDevice` filters both files' entries for the deviceId, returns whether anything changed, fires `_registryChanged`.

- [ ] **Step 4: Run tests, verify pass; close the controller**
  Add `void dispose() => _registryChanged.close();` — call it in app teardown (Task 10 wires this).

- [ ] **Step 5: Commit**

```bash
git add lib/services/connect/paired_device_store.dart test/services/connect/paired_device_store_test.dart
git commit -m "feat(connect): device public-key registry in PairedDeviceStore"
```

---

### Task 4: Pairing POST accepts devices instead of writing authorized_keys

**Files:**
- Modify: `client/lib/services/connect/pairing_http.dart`
- Test: `client/test/services/connect/pairing_http_test.dart` (extend/adjust)

**Interfaces:**
- Consumes: Task 3's `issueDevice`.
- Produces:

```dart
typedef PairingDeviceSink =
    Future<void> Function({
      required String deviceId,
      required String deviceName,
      required String publicKey,
    });

Future<PairingPostResult> handlePairingPost({
  required PairingPostBody body,
  required PairingTokenGate gate,
  required PairingDeviceSink acceptDevice, // was: AuthorizedKeysFile keys
  required DateTime now,
  required String profileHint,
  String? relayGrant,
});
```

- [ ] **Step 1: Update the tests** — replace every `keys:` argument with a recording sink:

```dart
final accepted = <Map<String, String>>[];
final sink = ({required String deviceId, required String deviceName, required String publicKey}) async {
  accepted.add({'deviceId': deviceId, 'deviceName': deviceName, 'publicKey': publicKey});
};
```

Assert: a valid POST calls the sink with the body's fields; `badKey`/`used`/`invalid` paths never call it; a sink that throws `ArgumentError` still surfaces `PairingHttpException('invalid')`.

- [ ] **Step 2: Run to verify failure** (compile error on removed `keys:` param)

- [ ] **Step 3: Implement** — in `handlePairingPost`, delete the `authorized_keys_file.dart` import and swap the body:

```dart
try {
  await acceptDevice(
    deviceId: body.deviceId,
    deviceName: body.deviceName,
    publicKey: body.publicKey,
  );
} on ArgumentError {
  throw const PairingHttpException('invalid');
}
```

`ConnectAgent._handleRequest` (Task 10 rewires it fully; here just make it compile) passes:

```dart
acceptDevice: (deviceId: body.deviceId, deviceName: body.deviceName, publicKey: body.publicKey) =>
    _deviceStore!.issueDevice(
      deviceId: deviceId,
      publicKey: publicKey,
      deviceName: deviceName,
    ),
```

(If `_deviceStore` is null the agent cannot pair — guard in `_startQrSession` instead, mirroring today's `sshd.listening` check.)

- [ ] **Step 4: Run tests, verify pass** — also `flutter analyze` (AuthorizedKeysFile import removal will ripple; fix every compile site now).

- [ ] **Step 5: Commit**

```bash
git add lib/services/connect/pairing_http.dart lib/services/connect/connect_agent.dart test/services/connect/pairing_http_test.dart
git commit -m "refactor(connect): pairing POST issues device keys, not authorized_keys"
```

---

### Task 5: EmbeddedSftpFilesystem — SFTP over the native filesystem

**Files:**
- Create: `client/lib/services/connect/embedded_sftp_filesystem.dart`
- Test: `client/test/services/connect/embedded_sftp_filesystem_test.dart`

**Interfaces:**
- Consumes: `SftpFileSystem` / `SftpHandle` / `SftpDirListing` / typed exceptions from `package:tp_sshd/tp_sshd.dart` + `SftpFileAttrs`/`SftpFileMode`/`SftpFileOpenMode`/`SftpName` from `package:dartssh2/protocol.dart`.
- Produces: `EmbeddedSftpFilesystem` implementing `SftpFileSystem` — used by Task 7.

**Porting source:** the working adapter already exists in `client/packages/tp_sshd/example/demo_sshd.dart` (`LocalSftpFileSystem`, `_IoSftpHandle`, `_IoDirListing`) — it passed a full round-trip battery against a real OpenSSH sftp client. Port those three classes into this file, then apply the production changes below.

Production differences from the demo:
1. **No sandbox jail.** SFTP paths are native absolute paths. On POSIX, `/home/u/x` maps to itself. On Windows, the path context is `p.context` from `p.windows`; a leading-`/` path resolves under `%USERPROFILE%`, and a drive path (`C:/x`, `C:\x`) resolves as-is — encode this in one `String _resolve(String sftpPath)` with tests for both contexts (construct the adapter with a `p.Context` parameter so tests can run the Windows context on Linux).
2. **Per-handle op lock** (already in the demo's `_IoSftpHandle._enqueue`) — keep it; the package dispatches SFTP requests concurrently.
3. **Typed errors** (already in the demo) — keep the errno mapping.

- [ ] **Step 1: Write the failing tests** (VM-only, temp dirs):

```dart
@TestOn('vm')
library;

import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tp_sshd/tp_sshd.dart';

import 'package:teampilot/services/connect/embedded_sftp_filesystem.dart';

void main() {
  late Directory root;
  late EmbeddedSftpFilesystem sftp;

  setUp(() {
    root = Directory.systemTemp.createTempSync('tp_sftp');
    sftp = EmbeddedSftpFilesystem(pathContext: p.posix, homePath: root.path);
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('realpath resolves . and .. lexically', () async {
    expect(await sftp.realpath('/a/../b/./c'), '/b/c');
  });

  test('stat/openFile round trip with sizes and modes', () async {
    File(p.join(root.path, 'f.txt')).writeAsStringSync('hello');
    final attrs = await sftp.stat('/f.txt');
    expect(attrs.size, 5);
    expect(attrs.isFile, isTrue);
  });

  test('openFile write/read at offsets', () async {
    final handle = await sftp.openFile(
      '/w.bin',
      SftpFileOpenMode.write | SftpFileOpenMode.create,
      null,
    );
    await handle.write(0, Uint8List.fromList([1, 2, 3]));
    await handle.write(6, Uint8List.fromList([7]));
    await handle.close();
    final reader = await sftp.openFile('/w.bin', SftpFileOpenMode.read, null);
    expect(await reader.read(0, 3), [1, 2, 3]);
    expect(await reader.read(4, 3), [0, 0, 7]);
    await reader.close();
  });

  test('openFile exclusive on existing path throws FileExists', () {
    File(p.join(root.path, 'e')).writeAsStringSync('');
    expect(
      sftp.openFile('/e', SftpFileOpenMode.create | SftpFileOpenMode.exclusive, null),
      throwsA(isA<SftpFileExistsException>()),
    );
  });

  test('openFile without create on missing path throws NoSuchFile', () {
    expect(
      sftp.openFile('/missing', SftpFileOpenMode.read, null),
      throwsA(isA<SftpNoSuchFileException>()),
    );
  });

  test('mkdir/rmdir/unlink/rename and the typed errno mapping', () async {
    await sftp.mkdir('/d', SftpFileAttrs());
    await expectLater(
      sftp.mkdir('/d', SftpFileAttrs()),
      throwsA(isA<SftpFileExistsException>()),
    );
    await expectLater(
      sftp.unlink('/d'),
      throwsA(isA<SftpFileSystemException>()), // is a directory
    );
    await sftp.rmdir('/d');
    await expectLater(
      sftp.stat('/d'),
      throwsA(isA<SftpNoSuchFileException>()),
    );
  });

  test('openDir lists entries with names and attrs', () async {
    File(p.join(root.path, 'a')).writeAsStringSync('x');
    Directory(p.join(root.path, 'b')).createSync();
    final listing = await sftp.openDir('/');
    final names = await listing.read();
    expect(names.map((n) => n.filename), containsAll(['a', 'b']));
    expect(names.firstWhere((n) => n.filename == 'b').attr.isDirectory, isTrue);
    expect(await listing.read(), isEmpty); // exhausted
    await listing.close();
  });

  test('windows context: leading-slash resolves under home, drive paths pass through', () async {
    final win = EmbeddedSftpFilesystem(pathContext: p.windows, homePath: r'C:\Users\u');
    expect(win.resolveForTest(r'/docs/x'), r'C:\Users\u\docs\x');
    expect(win.resolveForTest(r'C:/temp/x'), r'C:\temp\x');
  });
}
```

- [ ] **Step 2: Run to verify failure** (`flutter test test/services/connect/embedded_sftp_filesystem_test.dart`)

- [ ] **Step 3: Implement** — port `LocalSftpFilesystem`/`_IoSftpHandle`/`_IoDirListing` from the demo file, rename to `EmbeddedSftpFilesystem`, constructor `{required p.Context pathContext, required String homePath}`, replace `_joinRoot` with the context-aware `_resolve` above (expose `String resolveForTest(String)` for the last test). Keep `SftpFileSystemException`-typed errno mapping verbatim.

- [ ] **Step 4: Run to verify pass; then the package's own suite still green**

Run: `cd client && flutter test test/services/connect/embedded_sftp_filesystem_test.dart && cd packages/tp_sshd && dart test`
Expected: PASS + 57/57.

- [ ] **Step 5: Commit**

```bash
git add lib/services/connect/embedded_sftp_filesystem.dart test/services/connect/embedded_sftp_filesystem_test.dart
git commit -m "feat(connect): embedded SFTP filesystem adapter over native paths"
```

---

### Task 6: Process/pty factories — OS-native shells and PATH injection

**Files:**
- Create: `client/lib/services/connect/embedded_process_factories.dart`
- Test: `client/test/services/connect/embedded_process_factories_test.dart`

**Interfaces:**
- Consumes: `SSHServerProcess` / `SSHServerPty` / `SSHPtyDimensions` / `SSHProcessFactory` / `SSHPtyFactory` (tp_sshd), `Pty.start` (flutter_pty_new), `CliToolRegistry`'s toolchain locations.
- Produces:
  - `class EmbeddedShellSelection { static String executable(); static List<String> arguments(); }` — PowerShell on Windows, `$SHELL`/`/bin/bash` elsewhere.
  - `class EmbeddedSpawnEnvironment { static Map<String, String> mergeWithToolchainPath(Map<String, String> base); }` — injects the managed Node/npm bin dirs into `PATH`, replacing `RemoteFlashskyaiCommandBuilder`'s hardcoded export.
  - `SSHProcessFactory embeddedProcessFactory` and `SSHPtyFactory embeddedPtyFactory` getters (constructors take an injectable `PtySpawner` seam for tests).

- [ ] **Step 1: Write the failing tests** (pure logic — spawning stays behind seams):

```dart
test('shell selection is PowerShell on Windows, $SHELL elsewhere', () {
  // EmbeddedShellSelection takes the platform as a parameter.
  expect(EmbeddedShellSelection.executable(platform: 'windows'), 'powershell.exe');
  expect(
    EmbeddedShellSelection.arguments(platform: 'windows'),
    ['-NoLogo'],
  );
  expect(
    EmbeddedShellSelection.executable(platform: 'linux', shellEnv: '/bin/zsh'),
    '/bin/zsh',
  );
  expect(
    EmbeddedShellSelection.executable(platform: 'linux', shellEnv: null),
    '/bin/bash',
  );
});

test('toolchain PATH is prepended, existing PATH preserved', () {
  final env = EmbeddedSpawnEnvironment.mergeWithToolchainPath(
    {'PATH': '/usr/bin', 'HOME': '/home/u'},
    toolchainBin: '/home/u/.local/share/com.hhoa.teampilot/toolchain/node/current/bin',
  );
  expect(env['PATH'],
      '/home/u/.local/share/com.hhoa.teampilot/toolchain/node/current/bin:/usr/bin');
  expect(env['HOME'], '/home/u');
});

test('pty factory passes dimensions and env through the spawner', () async {
  final spawned = <String, Object?>[];
  final factory = embeddedPtyFactory(
    spawner: ({required executable, required arguments, required environment, required columns, required rows}) async {
      spawned.addAll([executable, arguments, environment, columns, rows]);
      return _FakePtyLike();
    },
  );
  final pty = await factory(const SSHPtyDimensions(
    columns: 80, rows: 24, environment: {'TERM': 'xterm-256color'},
  ));
  expect(spawned[3], 80);
  expect(spawned[4], 24);
  expect((spawned[2] as Map<String, String>)['TERM'], 'xterm-256color');
  pty!.resize(100, 30); // forwarded
  pty.kill();
});
```

`_FakePtyLike` records resize/kill/write calls and exposes static streams/exitCode — model `PtyLike` as a tiny abstract class in the production file so tests need no Flutter binding:

```dart
abstract class PtyLike {
  Stream<Uint8List> get output;
  Future<int> get exitCode;
  void write(Uint8List data);
  void resize(int columns, int rows);
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]);
}
```

- [ ] **Step 2: Run to verify failure**

- [ ] **Step 3: Implement**

```dart
typedef PtySpawner = Future<PtyLike> Function({
  required String executable,
  required List<String> arguments,
  required Map<String, String> environment,
  required int columns,
  required int rows,
});

SSHPtyFactory embeddedPtyFactory({PtySpawner? spawner}) {
  final spawn = spawner ?? _defaultPtySpawner;
  return (initial) async {
    final env = EmbeddedSpawnEnvironment.mergeWithToolchainPath({
      ...Platform.environment,
      ...initial.environment,
    });
    return _PtyLikeServerPty(await spawn(
      executable: EmbeddedShellSelection.executable(platform: Platform.operatingSystem),
      arguments: EmbeddedShellSelection.arguments(platform: Platform.operatingSystem),
      environment: env,
      columns: initial.columns,
      rows: initial.rows,
    ));
  };
}
```

`_PtyLikeServerPty extends _ProcessServerProcessBase implements SSHServerPty`: `resize` → `pty.resize(columns, rows)`; `signal(name)` maps `INT/TERM/HUP/KILL` to `ProcessSignal` and calls `pty.kill(signal)`; unknown names log via `AppLogger` and drop. `embeddedProcessFactory` spawns with `Process.start(argv.first, argv.skip(1), workingDirectory: cwd, environment: merged)`; a spawn failure logs and returns `null` (the server refuses the request). Both process classes share one `_ServerProcessAdapter` implementing `SSHServerProcess` (stdout/stderr cast, stdin → `IOSink`, exitCode, kill).

`_defaultPtySpawner` wraps `Pty.start(...)` into a `PtyLike` (it already matches the shape: `output`, `exitCode`, `write`, `resize(rows, cols)` — note the argument order swap — `kill`).

- [ ] **Step 4: Run tests, verify pass**

- [ ] **Step 5: Commit**

```bash
git add lib/services/connect/embedded_process_factories.dart test/services/connect/embedded_process_factories_test.dart
git commit -m "feat(connect): embedded exec/pty factories with native shells and toolchain PATH"
```

---

### Task 7: tp_sshd onAuthenticated hook + EmbeddedSshServer

**Files:**
- Modify: `client/packages/tp_sshd/lib/src/ssh_server.dart` (+ `server_connection.dart` invocation site)
- Test: `client/packages/tp_sshd/test/server_userauth_test.dart` (one new test)
- Create: `client/lib/services/connect/embedded_ssh_server.dart`
- Test: `client/test/services/connect/embedded_ssh_server_test.dart`

**Interfaces:**
- Consumes: Tasks 1–6 (`EmbeddedHostKey`, `PairedDeviceStore.isValidDeviceKey`, `EmbeddedSftpFilesystem`, factories), `ConnectSettingsStore.loadOrCreateEmbeddedPort` (Task 2), `SSHServer`/`SSHServerConfig` (tp_sshd), `ServerSocket`.
- Produces:

```dart
class EmbeddedSshServer {
  EmbeddedSshServer({
    required Filesystem fs,
    required String appDataRoot,
    required PairedDeviceStore deviceStore,
    p.Context? pathContext,        // default: platform context
    String? homePath,              // default: native home
  });
  Future<void> start();            // load key, bind wildcard on persisted port
  Future<int> get port;
  Future<List<String>> get hostKeyFingerprints;
  bool get isListening;
  Future<void> restart();          // re-pick port + rebind (bind-conflict path)
  Future<void> stop();
  Future<void> revokeDevice(String deviceId); // store remove + tear down live conns
}
```

- [ ] **Step 1: tp_sshd hook — failing test first**

In `server_userauth_test.dart`, extend one dual test to observe the new hook:

```dart
test('onAuthenticated reports the connection and auth request', () async {
  final seen = <(SSHServerConnection, String)>[];
  final (client, server) = await startDualPair(
    hostKeyPair: testHostKey,
    authenticate: (_) async => true,
    clientIdentities: [testDeviceKey],
    onAuthenticated: (connection, request) => seen.add((connection, request.username)),
  );
  await client.authenticated;
  await waitUntil(() => seen.isNotEmpty);
  expect(seen.single.$2, 'user');
  client.close();
  await server.close();
});
```

`startDualPair` gains an optional `onAuthenticated` parameter threaded into `SSHServerConfig`.

- [ ] **Step 2: Verify failure** (`cd client/packages/tp_sshd && dart test test/server_userauth_test.dart` — compile error), then implement:

In `SSHServerConfig`:

```dart
/// Invoked exactly once per connection, after the signed publickey request
/// verifies and `authenticate` accepts — the embedder's point to record
/// which connection belongs to which device (revocation teardown).
final void Function(SSHServerConnection connection, SSHServerAuthRequest request)?
    onAuthenticated;
```

In `server_connection.dart`, at the auth-success site (where `SSH_Message_Userauth_Success` is sent, in the `_Phase.auth` branch that handles signed `SSH_Message_Userauth_Request` — the same block `_failAuthAttempt` is the failure twin of), invoke `_config.onAuthenticated?.call(this, request)` **after** sending success.

Run: `dart test` → 58/58.

- [ ] **Step 3: EmbeddedSshServer failing tests** (in-memory `Filesystem`, real `ServerSocket` on `InternetAddress.loopbackIPv4`, port 0 — the test never touches the persisted port):

```dart
test('starts, answers a real dartssh2 login with an issued device key, and stops', () async {
  final server = EmbeddedSshServer(fs: fs, appDataRoot: root, deviceStore: store);
  await server.start();
  addTearDown(server.stop);

  await store.issueDevice(deviceId: 'phone-1', publicKey: devicePubLine);
  final client = SSHClient(
    await SSHSocket.connect('127.0.0.1', await server.port),
    username: username,
    identities: [SSHKeyPair.fromPem(devicePem).single],
  );
  await client.authenticated;
  client.close();
});

test('unregistered key is rejected', () async {
  // same shape; expect client.authenticated to throw SshAuthError
});

test('revoked device loses its live connection', () async {
  final server = EmbeddedSshServer(...);
  await server.start();
  await store.issueDevice(deviceId: 'phone-1', publicKey: devicePubLine);
  final client = ...; await client.authenticated;
  await server.revokeDevice('phone-1');
  await expectLater(client.done, completes);
});
```

- [ ] **Step 4: Implement `embedded_ssh_server.dart`**

```dart
Future<void> start() async {
  final hostKey = await EmbeddedHostKeyStore(fs: _fs, appDataRoot: _appDataRoot)
      .loadOrCreate();
  _settings = ConnectSettingsStore(fs: _fs, appDataRoot: _appDataRoot);
  var port = await _settings!.loadOrCreateEmbeddedPort();
  _listener = await _bindWithRetry(port); // ServerSocket.bind(InternetAddress.anyIPv4, port); on SocketException → port = await _settings!.repickEmbeddedPort(); retry once, then throw EmbeddedSshServerStartException
  _connections = StreamController<SSHSocket>();
  _listener!.listen((socket) => _connections!.add(_SocketSshAdapter(socket)));
  _server = await SSHServer.bind(
    StreamIterator(_connections!.stream),
    config: SSHServerConfig(
      hostKeyPair: hostKey.keyPair,
      expectedUsername: _username,        // resolved in app_shell (Task 10), injected here
      authenticate: (request) async => _deviceStore.isValidDeviceKey(
          _opensshLineFor(request.algorithm, request.publicKey)),
      processFactory: embeddedProcessFactory(),
      ptyFactory: embeddedPtyFactory(),
      hostInfo: _hostInfo,
      sftpFileSystem: EmbeddedSftpFilesystem(
        pathContext: _pathContext, homePath: _homePath),
      bindServerSocket: (address, port) async =>
          _IoServerSocketHandle(await ServerSocket.bind(address, port)),
      onAuthenticated: _recordDeviceConnection,
    ),
  );
  _deviceStore.deviceRegistryChanged.listen((_) => _evictRevokedDevices());
}
```

`_opensshLineFor(algorithm, blob)` = `'$algorithm ${base64.encode(blob)}'` — matches what `isValidDeviceKey` parses. `_recordDeviceConnection` maps `connection → deviceId` (the store gains `String? deviceIdForPublicKey(String line)` in this task — pure lookup, tested alongside Task 3's tests). `_evictRevokedDevices` closes every live connection whose deviceId is no longer registered (`_server!.activeConnections` ∩ `_connectionDevices`). Port `expectedUsername`: add a `required String username` constructor parameter — app_shell already resolves the native username today (the block at `app_shell.dart:1595-1612`); move that resolution into the Task 10 call site. `_SocketSshAdapter` / `_IoServerSocketHandle` port verbatim from the demo file (`example/demo_sshd.dart`), where they already passed real-client testing.

- [ ] **Step 5: Run both suites**

Run: `cd client && flutter test test/services/connect/embedded_ssh_server_test.dart && cd packages/tp_sshd && dart test`
Expected: PASS + 58/58.

- [ ] **Step 6: Commit**

```bash
git add ../packages/tp_sshd/lib/src/ssh_server.dart ../packages/tp_sshd/lib/src/server_connection.dart ../packages/tp_sshd/test/server_userauth_test.dart ../packages/tp_sshd/test/dual_test_utils.dart lib/services/connect/embedded_ssh_server.dart test/services/connect/embedded_ssh_server_test.dart
git commit -m "feat(connect): EmbeddedSshServer owning the tp_sshd instance"
```

---

### Task 8: Offer v2, SshProfile.embeddedTarget, profile writer passthrough

**Files:**
- Modify: `client/lib/services/connect/ssh_pairing_offer.dart`
- Modify: `client/lib/models/ssh_profile.dart`
- Modify: `client/lib/services/connect/paired_profile_writer.dart`
- Tests: extend `ssh_pairing_offer_test.dart`, `ssh_profile_test.dart` (or the existing model test home), `paired_profile_writer_test.dart`

**Interfaces:**
- Consumes: Task 7 (`port`, `hostKeyFingerprints`).
- Produces: `SshPairingOffer.v == 2` with `bool emb`; parsing a v2 offer without `emb` throws `SshPairingOfferFormatException`; parsing a v3 offer throws the version error. `SshProfile.embeddedTarget` (JSON key `"embeddedTarget"`, default false). `PairedProfileWriter.upsert` sets `embeddedTarget: offer.emb ?? false`.

- [ ] **Step 1: Failing tests**

Offer model (mirror the file's existing round-trip test style):

```dart
test('v2 offer round-trips emb and rejects v3', () {
  final offer = baseV2Offer(emb: true);
  final parsed = SshPairingOffer.fromJson(offer.toJson());
  expect(parsed.v, 2);
  expect(parsed.emb, isTrue);

  final tooNew = baseV2Offer(emb: true).toJson()..['v'] = 3;
  expect(() => SshPairingOffer.fromJson(tooNew),
      throwsA(isA<SshPairingOfferFormatException>()));
});
```

Profile: fromJson/toJson round-trips `embeddedTarget`, default `false` for absent key. Writer: `upsert` produces a profile with `embeddedTarget == true` when the offer says so.

- [ ] **Step 2: Verify failure → Step 3: Implement**

`SshPairingOffer`: add `final bool? emb;` (nullable: v1 offers have none), thread through the constructor, `toJson` (`if (emb != null) 'emb': emb`), and `fromJson` (`json['emb'] is bool ? json['emb'] as bool : null`); the accepted-version guard becomes `v != 1 && v != 2 → SshPairingOfferFormatException` (check the existing guard's shape and extend it — the v1-phone-scan-v2 error is the phone's *reader* rejecting v2? No: same release ships both ends; the phone accepts both 1 and 2. The "unsupported version" error is for a v1 *phone* reading a v2 QR — impossible to test from this repo's writer side; the guard here only future-proofs v3+).

`SshProfile`: `final bool embeddedTarget;` default false, JSON key `embeddedTarget`. `PairedProfileWriter.upsert`: `embeddedTarget: offer.emb ?? false` in the constructed/updated profile.

- [ ] **Step 4: Run the three test files, verify pass**

- [ ] **Step 5: Commit**

```bash
git add lib/services/connect/ssh_pairing_offer.dart lib/models/ssh_profile.dart lib/services/connect/paired_profile_writer.dart
git commit -m "feat(connect): offer v2 with emb flag and SshProfile.embeddedTarget"
```

---

### Task 9: RemoteCommandCodec — converge command emission

**Files:**
- Create: `client/lib/services/host/remote_command_codec.dart`
- Modify: `client/lib/services/cli/flashskyai/remote_flashskyai_command_builder.dart` and every call site that branches on target kind (grep `RemoteFlashskyaiCommandBuilder(` and `RemoteLoginShell.wrap`).
- Test: `client/test/services/host/remote_command_codec_test.dart`

**Interfaces:**
- Consumes: `RemoteLoginShell.wrap` (legacy), `TpExecCodec.encode` (tp_sshd — but the codec must not import tp_sshd into host code; inline the same `tp1:` + jsonEncode format: `'$prefix${jsonEncode({'argv': ..., if (cwd != null) 'cwd': ..., if (env.isNotEmpty) 'env': ...})}'`).
- Produces:

```dart
class RemoteCommandSpec {
  const RemoteCommandSpec({required this.argv, this.cwd, this.env});
  final List<String> argv;
  final String? cwd;
  final Map<String, String>? env;
}

class RemoteCommandCodec {
  /// Legacy target: POSIX shell string, byte-for-byte what
  /// RemoteFlashskyaiCommandBuilder.buildCommand produces today.
  String encodeLegacy(RemoteCommandSpec spec, {bool useLoginShell = false});

  /// Embedded target: `tp1:{...}` payload for the structured exec path.
  String encodeEmbedded(RemoteCommandSpec spec);
}
```

- [ ] **Step 1: Failing tests — the legacy branch is a regression guard**

```dart
test('legacy branch is byte-identical to the old builder output', () {
  final legacy = RemoteCommandCodec().encodeLegacy(
    const RemoteCommandSpec(
      argv: ['/usr/local/bin/flashskyai', '--version'],
      cwd: '/home/u/work',
      env: {'FOO': "it's"},
    ),
  );
  final old = RemoteFlashskyaiCommandBuilder().buildCommand(
    remoteExecutablePath: '/usr/local/bin/flashskyai',
    arguments: ['--version'],
    workingDirectory: '/home/u/work',
    environment: {'FOO': "it's"},
  );
  expect(legacy, old); // exact string equality, including the PATH export
});

test('embedded branch is a tp1: JSON payload', () {
  final payload = RemoteCommandCodec().encodeEmbedded(const RemoteCommandSpec(
    argv: ['claude', '--version'],
    cwd: r'C:\work',
    env: {'K': 'V'},
  ));
  expect(payload, r'tp1:{"argv":["claude","--version"],"cwd":"C:\\work","env":{"K":"V"}}');
  // and the package's decoder accepts it (cross-check):
  expect(TpExecCodec.tryDecode(payload)!.argv, ['claude', '--version']);
});
```

(The cross-check test may live in the same file with `import 'package:tp_sshd/tp_sshd.dart';` — the *test* may depend on the package even though the codec itself does not.)

- [ ] **Step 2: Verify failure → Step 3: Implement**

`encodeLegacy` delegates to the existing `RemoteFlashskyaiCommandBuilder().buildCommand(...)` (map spec → its parameters; `useLoginShell` passthrough). `encodeEmbedded` produces the `tp1:` payload with `cwd`/`env` omitted when null/empty — matching `TpExecCodec.encode`'s field-omission rules exactly.

- [ ] **Step 4: Wire the emission points** — every caller that today builds a shell string for a remote target now goes through the codec, branching on `profile.embeddedTarget`:

```dart
final command = profile.embeddedTarget
    ? codec.encodeEmbedded(spec)
    : codec.encodeLegacy(spec, useLoginShell: wasLoginShell);
```

Sweep these (grep-verified current users): `RemoteFlashskyaiCommandBuilder` call sites, `host_interactive_shell.dart`'s `_sshLaunchPlan` (embedded targets send the `shell` request with **no** command — the server picks the OS-native shell; only the legacy branch keeps sending `/bin/bash` strings), the PTY transport command assembly in `terminal_transport_factory.dart`, and the probes/run-handles that call `RemoteLoginShell.wrap` directly. For each: build the `RemoteCommandSpec`, branch, delete the inline string building. Update each call site's tests to assert both branches.

- [ ] **Step 5: Run the touched tests + analyze**

Run: `cd client && flutter test test/services/host/ && flutter analyze --no-fatal-infos --no-fatal-warnings`

- [ ] **Step 6: Commit**

```bash
git add lib/services/host/remote_command_codec.dart lib/services/cli/flashskyai/remote_flashskyai_command_builder.dart lib/services/host/ test/services/host/
git commit -m "feat(host): RemoteCommandCodec — tp1: payloads for embedded targets, byte-identical legacy branch"
```

---

### Task 10: ConnectAgent offer v2 + app_shell startup wiring

**Files:**
- Modify: `client/lib/services/connect/connect_agent.dart`
- Modify: `client/lib/app/app_shell.dart`
- Modify: `client/lib/cubits/connect_cubit.dart`
- Tests: extend `connect_agent_test.dart`; new `app_shell`-level assertions live in the integration test (Task 12).

**Interfaces:**
- Consumes: Tasks 3, 4, 7, 8.
- Produces: `ConnectAgent.production({required EmbeddedSshServer embeddedServer, required Filesystem fs, ...})` — `SshdPresenceProbe` and `AuthorizedKeysFile` parameters are gone. `canPair` ≡ `embeddedServer.isListening`.

- [ ] **Step 1: Failing tests** (extend `connect_agent_test.dart`)

```dart
test('offer is v2 with emb and the embedded port when the server is up', () async {
  final agent = buildAgent(embeddedServer: fakeEmbeddedServer(listening: true, port: 54321, fingerprints: ['SHA256:abc']));
  await agent.startQrSession(advertiseAddress: '192.168.1.5', username: 'u', displayName: 'desk', appDataRoot: root);
  final offer = agent.currentOffer!;
  expect(offer.v, 2);
  expect(offer.emb, isTrue);
  expect(offer.endpoints.first.kind, SshEndpointKind.lan);
  expect(offer.endpoints.first.port, 54321);
  expect(offer.hostKeyFingerprints, ['SHA256:abc']);
});

test('canPair is false when the embedded server failed to start', () async {
  final agent = buildAgent(embeddedServer: fakeEmbeddedServer(listening: false));
  await expectLater(agent.startQrSession(...), throwsA(isA<EmbeddedSshServerStartException>()));
});
```

`fakeEmbeddedServer` is a thin interface the tests implement — introduce `abstract class EmbeddedSshServerHandle { bool get isListening; int get port; List<String> get hostKeyFingerprints; }` in `embedded_ssh_server.dart` (the real class implements it) so `ConnectAgent` depends on the handle, not the concrete class.

- [ ] **Step 2: Verify failure → Step 3: Implement**

`connect_agent.dart`:
- Constructor: drop `probe`/`keys`; add `required EmbeddedSshServerHandle embeddedServer`.
- `_startQrSession`: delete the `_probe()` block; replace with `if (!embeddedServer.isListening) return;` (offer stays null; `canPair` surfaces the state). Fingerprints come from `embeddedServer.hostKeyFingerprints` (already SHA256-prefixed).
- `_mintOffer`: `v: 2`, `emb: true`, LAN endpoint port `embeddedServer.port`.
- `resolveRelayTarget('ssh')` → `(loopbackIPv4, embeddedServer.port)` when `isListening`; delete `_relaySshdReachable`/`_relaySshdPort`.
- `_handleRequest` uses the Task 4 sink.

`app_shell.dart` (replace the `1595-1622` block):

```dart
final nativeHome = /* unchanged resolution */;
final username = /* unchanged resolution */;
final embeddedServer = EmbeddedSshServer(
  fs: localFs,
  appDataRoot: nativeAppDataPath,
  deviceStore: pairedDeviceStore,
  username: username,
  homePath: nativeHome,
);
try {
  await embeddedServer.start();
} on EmbeddedSshServerStartException catch (error) {
  appLogger.e('embedded ssh server failed to start', error: error);
  // Non-blocking: the app continues; Connect UI shows the failed state + retry.
}
final connectAgent = ConnectAgent.production(
  embeddedServer: embeddedServer,
  fs: localFs,
  extraEndpoints: settings.extraEndpoints,
  deviceStore: pairedDeviceStore,
);
```

Delete: `AuthorizedKeysFile` construction, `SshdPresence()`, the `probe:` argument, and the `posix.chmod` import if now unused. App teardown: `await embeddedServer.stop()` alongside the existing agent teardown.

`connect_cubit.dart:167`: `bool get canPair => embeddedServer.isListening;` (inject the handle the cubit already receives its dependencies; follow the file's existing DI shape).

- [ ] **Step 4: Run `connect_agent_test.dart` + analyze; fix every remaining `SshdPresence`/`AuthorizedKeysFile` compile error** (they are deleted next, but this task must compile without them first).

- [ ] **Step 5: Commit**

```bash
git add lib/services/connect/connect_agent.dart lib/app/app_shell.dart lib/cubits/connect_cubit.dart test/services/connect/connect_agent_test.dart
git commit -m "feat(connect): ConnectAgent serves offer v2 from the embedded server"
```

---

### Task 11: Delete the system-sshd path + UI/l10n

**Files:**
- Delete: `client/lib/services/connect/sshd_presence.dart`, `client/lib/services/connect/authorized_keys_file.dart`
- Delete: their tests; grep `SshdHostKeyScanner` and delete if it still exists as a file
- Modify: `client/lib/l10n/app_en.arb`, `app_zh.arb`; the Connect UI file that renders `connectSshdDown` (grep its key)
- Test: l10n key presence test (the repo's existing arb test, if any — else the analyzer's unused-key check suffices)

- [ ] **Step 1: Delete the files and their tests; run analyze to find every dangling reference; fix all of them** (expected sites: `app_shell.dart` imports — already clean after Task 10 — plus any `platformSshdEnableHint` l10n consumers in the Connect UI; delete the hint's UI branch).

- [ ] **Step 2: Replace the l10n strings**

`app_en.arb`:
```json
"connectSshdDown": "The embedded connection server failed to start. Retry or restart the app.",
"connectSshdRetry": "Retry",
"connectRepairHint": "The desktop has been upgraded — re-scan its pairing code to reconnect."
```
`app_zh.arb` (mirror):
```json
"connectSshdDown": "内嵌连接服务启动失败。请重试或重启应用。",
"connectSshdRetry": "重试",
"connectRepairHint": "桌面端已升级——请重新扫码配对以恢复连接。"
```
Delete `platformSshdEnableHint` (and its zh twin) plus any `termuxSetupScriptHint`-adjacent install hints that referenced OpenSSH installation for the desktop. The retry affordance calls `embeddedServer.restart()` (already produced in Task 7) via the cubit.

- [ ] **Step 3: Stale-profile hint** — in the phone-side connect failure path that today surfaces a generic auth/connect error (find it via the l10n keys the SSH connect flow emits; start at `connect_cubit.dart`'s failure states), detect fingerprint/port mismatch against the profile's pinned `hostKeyFingerprints`/port and surface `connectRepairHint` instead. If the mismatch detection needs a new helper, it is `bool offerMatchesProfile(SshPairingOffer offer, SshProfile profile)` in `ssh_pairing_offer.dart`, unit-tested here (fingerprint-set intersect + port equality).

- [ ] **Step 4: Run the full check**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`
Expected: clean; no test references a deleted class.

- [ ] **Step 5: Commit**

```bash
git add -A lib/services/connect lib/l10n lib/cubits test/services/connect
git commit -m "feat(connect): remove system-sshd dependency; embedded-server connect UI"
```

---

### Task 12: Integration test + docs

**Files:**
- Create: `client/test/integration/embedded_pairing_test.dart` (`@Tags(['integration'])`)
- Modify: `docs/DEVELOPMENT.md` (one paragraph), `README.md`/`README.zh.md` (Connect section, if they mention system sshd)

**Interfaces:**
- Consumes: everything above.

- [ ] **Step 1: Write the integration test** — the spec's "full pairing loop":

```dart
@Tags(['integration'])
library;

// 1. EmbeddedSshServer on loopback (temporary appDataRoot, persisted port).
// 2. A pairing POST against the agent's QR session (startQrSession on
//    127.0.0.1, mint token from the gate, POST /pair with a freshly
//    generated device key — reuse EmbeddedHostKeyStore's generation code
//    or inline pinenacl).
// 3. dartssh2 SSHClient login with that device key → authenticated.
// 4. tp1: exec round trip (echo argv), host-info query.
// 5. SFTP open/write/read round trip through EmbeddedSftpFilesystem.
// 6. revokeDevice → client's live connection completes (done).
```

Use real `dart:io` sockets and temp dirs; no fakes past the pairing HTTP layer. Each numbered stage is one `test()` block chained through `setUpAll`-scoped fixtures (or one test with clearly commented stages if the harness prefers atomicity — follow `client/test/integration/`'s existing conventions; read one existing file first).

- [ ] **Step 2: Run it**

Run: `cd client && dart run tool/run_tests.dart` (integration tags included per DEVELOPMENT.md).
Expected: PASS.

- [ ] **Step 3: Docs**

`docs/DEVELOPMENT.md`: under the Connect/pairing area (add a short section if none exists) — the Windows firewall one-time prompt for the embedded port, and that no OS OpenSSH is required anymore. README/README.zh: update any "requires OpenSSH Server / Remote Login" wording to "no OS configuration required".

- [ ] **Step 4: Full gate**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart && cd packages/tp_sshd && dart test`
Expected: all green (tp_sshd 58/58).

- [ ] **Step 5: Commit**

```bash
git add test/integration/embedded_pairing_test.dart ../../docs/DEVELOPMENT.md ../../README.md ../../README.zh.md
git commit -m "test(connect): full embedded pairing integration loop; docs"
```

---

## Self-Review

**Spec coverage** (spec section → task):
- Startup sequence (host key, port, bind) → Tasks 1, 2, 7, 10
- Pairing flow (issueDevice, offer v2, profile writer) → Tasks 3, 4, 8, 10
- Relay target → Task 10 (`resolveRelayTarget`)
- Connect UI / error table → Task 11 (every row of the spec's error table: port occupied → Task 7 bind retry; firewall → docs Task 12; corrupt key → Task 1; per-connection errors → tp_sshd (shipped); v1 phone → Task 8 guard; stale profile → Task 11 hint)
- Deleted (`SshdPresence`, `SshdHostKeyScanner`, `AuthorizedKeysFile`, `platformSshdEnableHint`) → Task 11
- Security model (revocation teardown) → Tasks 3, 7; constant-time compares already in the store
- RemoteCommandCodec / PATH injection / host-info / interactive shells → Tasks 6, 9
- Testing (app layer, integration, manual matrix) → Tasks 1–11 unit tests, Task 12 integration; **manual matrix (Windows real-device QR, macOS no-residue) is a human step — flag it in the PR description, it cannot be automated here.**
- Known package deferrals (SETSTAT/READLINK/SYMLINK) — unchanged, documented in PR #7.

**Placeholder scan:** none; every code step carries the actual code or a verbatim porting source (`example/demo_sshd.dart`).

**Type consistency:** `EmbeddedHostKey`/`EmbeddedHostKeyStore` (T1→T7), `loadOrCreateEmbeddedPort`/`repickEmbeddedPort` (T2→T7), `issueDevice`/`isValidDeviceKey`/`deviceRegistryChanged` (+`deviceIdForPublicKey` added in T7, tested in T3's file) (T3→T4/T7), `PairingDeviceSink` (T4), `EmbeddedSftpFilesystem(pathContext:, homePath:)` (T5→T7), `embeddedPtyFactory(spawner:)`/`embeddedProcessFactory()` (T6→T7), `EmbeddedSshServerHandle` (T7→T10), `emb`/`embeddedTarget` (T8→T9/T10), `RemoteCommandCodec`/`RemoteCommandSpec` (T9).
