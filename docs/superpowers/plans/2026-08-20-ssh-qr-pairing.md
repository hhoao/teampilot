# SSH QR pairing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Desktop TeamPilot shows a QR; Android scans it and becomes an SSH client of that computer’s OpenSSH, with optional self-hosted relay for off-LAN.

**Architecture:** Pure `SshPairingOffer` codec plus a desktop `ConnectAgent` (sshd probe, short-lived pinned-TLS pairing HTTP, tagged `authorized_keys`). The phone upserts an `SshProfile`, pins host keys from the offer, and uses existing `dartssh2` + `applyAndroidSshConnectHome`. Relay is a dumb WSS byte pipe; SSH always terminates on desktop OpenSSH via loopback forward.

**Tech Stack:** Dart / Flutter, `dart:io` HttpServer + SecurityContext, `qr_flutter`, `mobile_scanner`, `web_socket_channel`, existing `SshProfile` / `SshCredentialStore` / `SshKnownHostRepository` / `SshHostKeyTrustPolicy`, `pinenacl` for device Ed25519.

**Spec:** `docs/superpowers/specs/2026-08-20-ssh-qr-pairing-design.md`

## Global Constraints

- Passwords and private keys never appear in the QR or logs.
- Pairing HTTPS binds only while the QR surface is visible, and only to the selected advertise address (not `0.0.0.0`).
- Do not mint an offer if sshd is not listening.
- Phone tries endpoints lan → extra → relay; unknown `kind` values are ignored.
- `kind: relay` is WSS to `relay.url`, not sshd on that host. Loopback `127.0.0.1` is never written to `SshProfile.host`.
- `relayGrant` lives in `SshCredentialStore`, not profile JSON.
- `appDataRoot` from the offer becomes `SshProfile.lastAppDataRoot`.
- `hostId` is always present on the offer (16-char base64url desktop install id) and becomes `pairedDesktopId`.
- Android only for scan/connect; ConnectAgent is desktop-only.
- No official TeamPilot cloud relay; same `relay` object shape is reserved.
- Constructor-inject filesystem, process, sockets, and clocks. No real camera, sshd, or WAN in unit tests.
- l10n: edit `client/lib/l10n/app_en.arb` and `app_zh.arb` only, then `flutter gen-l10n`.
- Do not modify unrelated working-tree changes.
- Verify with focused `flutter test` from `client/` before any broader suite.

## File structure

| File | Responsibility |
|------|----------------|
| `client/lib/models/ssh_reachability.dart` | `SshEndpointKind`, `SshReachabilityEndpoint`, `ConnectPolicy` |
| `client/lib/services/connect/ssh_pairing_offer.dart` | Offer encode/decode + validation |
| `client/lib/services/connect/pairing_token_gate.dart` | Single-use token mint/consume/invalidate |
| `client/lib/services/connect/authorized_keys_file.dart` | Tagged authorized_keys write/replace/revoke |
| `client/lib/services/connect/pairing_http.dart` | POST `/pair` handler + TLS pin helper |
| `client/lib/services/connect/sshd_presence.dart` | Probe listening sshd + fingerprints + enable hints |
| `client/lib/services/connect/connect_agent.dart` | Desktop facade: mint offer, pairing server lifecycle |
| `client/lib/services/connect/connect_pair_client.dart` | Phone: POST pair (pinned TLS) |
| `client/lib/services/connect/paired_profile_writer.dart` | Upsert `SshProfile` + copy device key + pin host keys |
| `client/lib/services/connect/endpoint_dial_planner.dart` | lan → extra → relay try order |
| `client/lib/services/connect/connect_relay_protocol.dart` | Register/dial handshake JSON keys |
| `client/lib/services/connect/connect_relay_client.dart` | Desktop outbound WSS |
| `client/lib/services/connect/phone_relay_tunnel.dart` | Phone WSS → loopback TCP for dartssh2 |
| `client/lib/models/ssh_profile.dart` | Optional pairing fields |
| `client/lib/repositories/ssh_credential_store.dart` | Device key + `relayGrant` |
| `client/lib/services/ssh/ssh_client_factory.dart` | Paired-profile host-key pin (no prompt) |
| `client/lib/pages/connect/` | Desktop Connect settings + QR; Android pair sheet |
| `tools/teampilot_connect_relay/` | Self-hosted WSS splice server |

---

### Task 1: Offer codec

**Files:**
- Create: `client/lib/models/ssh_reachability.dart`
- Create: `client/lib/services/connect/ssh_pairing_offer.dart`
- Create: `client/test/services/connect/ssh_pairing_offer_test.dart`

**Interfaces:**
- Consumes: none
- Produces:
  - `enum SshEndpointKind { lan, extra, relay }`
  - `enum ConnectPolicy { automatic, lanOnly }`
  - `class SshReachabilityEndpoint { kind, host, port; Map<String, Object?> toJson(); static SshReachabilityEndpoint? tryParse(Map<String, Object?> json); }`
  - `class SshPairingSession { token, expiresAt, url, tlsCertSha256 }`
  - `class SshRelayOffer { v, url, hostId, inviteToken, inviteExpiresAt }`
  - `class SshPairingOffer { v, hostId, username, displayName, appDataRoot, endpoints, hostKeyFingerprints, pairing, relay?; String encode(); static SshPairingOffer decode(String input); Map<String, Object?> toJson(); factory fromJson }`
  - `class SshPairingOfferFormatException implements Exception`

- [ ] **Step 1: Write the failing codec tests**

Create `client/test/services/connect/ssh_pairing_offer_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_reachability.dart';
import 'package:teampilot/services/connect/ssh_pairing_offer.dart';

SshPairingOffer _offer({SshRelayOffer? relay}) {
  return SshPairingOffer(
    v: 1,
    hostId: 'AbCdEf0123_-xyZ9',
    username: 'alice',
    displayName: 'alice-laptop',
    appDataRoot: '/home/alice/.local/share/com.hhoa.teampilot',
    endpoints: const [
      SshReachabilityEndpoint(
        kind: SshEndpointKind.lan,
        host: '192.168.1.20',
        port: 22,
      ),
      SshReachabilityEndpoint(
        kind: SshEndpointKind.extra,
        host: '203.0.113.8',
        port: 2222,
      ),
    ],
    hostKeyFingerprints: const ['SHA256:abcdefgh'],
    pairing: const SshPairingSession(
      token: 'abcdefghijklmnopqrstuvwxyz0123456789ABCDE',
      expiresAt: 1770000000000,
      url: 'https://192.168.1.20:2768/pair',
      tlsCertSha256: 'deadbeef',
    ),
    relay: relay,
  );
}

void main() {
  test('round-trips deep link and bare code', () {
    final encoded = _offer().encode();
    expect(encoded.startsWith('teampilot://pair-ssh?code='), isTrue);
    final fromLink = SshPairingOffer.decode(encoded);
    expect(fromLink.username, 'alice');
    expect(fromLink.hostId, 'AbCdEf0123_-xyZ9');
    expect(fromLink.endpoints.first.host, '192.168.1.20');
    final code = Uri.parse(encoded).queryParameters['code']!;
    expect(SshPairingOffer.decode(code).displayName, 'alice-laptop');
  });

  test('ignores unknown endpoint kinds and keeps lan/extra/relay order', () {
    final json = _offer().toJson();
    final endpoints = List<Map<String, Object?>>.from(
      (json['endpoints'] as List).cast<Map<String, Object?>>(),
    );
    endpoints.insert(1, {'kind': 'future', 'host': 'x', 'port': 1});
    json['endpoints'] = endpoints;
    final offer = SshPairingOffer.fromJson(json);
    expect(offer.endpoints.map((e) => e.kind), [
      SshEndpointKind.lan,
      SshEndpointKind.extra,
    ]);
  });

  test('rejects unknown offer version', () {
    final json = _offer().toJson();
    json['v'] = 2;
    expect(
      () => SshPairingOffer.fromJson(json),
      throwsA(isA<SshPairingOfferFormatException>()),
    );
  });

  test('rejects missing hostId', () {
    final json = _offer().toJson();
    json.remove('hostId');
    expect(
      () => SshPairingOffer.fromJson(json),
      throwsA(isA<SshPairingOfferFormatException>()),
    );
  });

  test('passwords are not serialized', () {
    final json = _offer().toJson();
    expect(json.containsKey('password'), isFalse);
    expect(json['pairing'], isNot(contains('privateKey')));
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run from `client/`:

```bash
flutter test test/services/connect/ssh_pairing_offer_test.dart
```

Expected: FAIL compiling (`ssh_pairing_offer.dart` does not exist).

- [ ] **Step 3: Implement the codec**

Create `client/lib/models/ssh_reachability.dart`:

```dart
enum SshEndpointKind { lan, extra, relay }

enum ConnectPolicy { automatic, lanOnly }

class SshReachabilityEndpoint {
  const SshReachabilityEndpoint({
    required this.kind,
    required this.host,
    required this.port,
  });

  final SshEndpointKind kind;
  final String host;
  final int port;

  static SshReachabilityEndpoint? tryParse(Map<String, Object?> json) {
    final kindRaw = json['kind'] as String?;
    SshEndpointKind? kind;
    for (final value in SshEndpointKind.values) {
      if (value.name == kindRaw) kind = value;
    }
    if (kind == null) return null;
    final host = json['host'] as String? ?? '';
    final port = (json['port'] as num?)?.toInt() ?? 22;
    if (host.isEmpty || port <= 0) return null;
    return SshReachabilityEndpoint(kind: kind, host: host, port: port);
  }

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'host': host,
    'port': port,
  };
}
```

Create `client/lib/services/connect/ssh_pairing_offer.dart`:

- `encode()`: `jsonEncode(toJson())` → utf8 → `base64Url.encode` with `=` stripped → `teampilot://pair-ssh?code=$code`.
- `decode(input)`: trim; if starts with `teampilot://` parse URI (`protocol == teampilot:` and host `pair-ssh`), take `code` query param; else treat input as bare code. Restore padding, base64url-decode, `jsonDecode`, `fromJson`.
- `fromJson` requires `v == 1`, `hostId` matching `^[A-Za-z0-9_-]{16}$`, non-empty `username`, `pairing.token`, `pairing.url`, `pairing.tlsCertSha256`. Parse `endpoints` via `tryParse` (drop unknown kinds). Optional `relay` with `v == 1`. Throw `SshPairingOfferFormatException` otherwise.

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/services/connect/ssh_pairing_offer_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/ssh_reachability.dart \
  client/lib/services/connect/ssh_pairing_offer.dart \
  client/test/services/connect/ssh_pairing_offer_test.dart
git commit -m "$(cat <<'EOF'
Add SSH pairing offer codec for QR connect.

EOF
)"
```

---

### Task 2: Profile pairing fields and credential secrets

**Files:**
- Modify: `client/lib/models/ssh_profile.dart`
- Modify: `client/test/models/ssh_profile_test.dart`
- Modify: `client/lib/repositories/ssh_credential_store.dart`
- Modify: `client/lib/services/ssh/ssh_client_factory.dart` (`_CredentialOverrideStore` must implement new methods)
- Create: `client/test/repositories/ssh_credential_store_connect_test.dart`

**Interfaces:**
- Consumes: `SshReachabilityEndpoint`, `SshEndpointKind`
- Produces:
  - `SshProfile` optional: `endpoints`, `hostKeyFingerprints`, `pairedDesktopId`, `relayUrl`, `lastGoodKind`
  - `SshCredentialStore.loadDevicePrivateKey()` / `saveDevicePrivateKey(String pem)`
  - `SshCredentialStore.loadRelayGrant(String profileId)` / `saveRelayGrant(String profileId, String grant)`
  - `deleteAll` also removes `relayGrant` (not the device key)

- [ ] **Step 1: Write failing profile + store tests**

Add to `client/test/models/ssh_profile_test.dart` (import `ssh_reachability.dart`):

```dart
test('json round-trip preserves pairing fields; manual profiles omit them', () {
  final paired = SshProfile(
    id: 'a',
    name: 'Box',
    host: '192.168.1.20',
    username: 'u',
    endpoints: const [
      SshReachabilityEndpoint(
        kind: SshEndpointKind.lan,
        host: '192.168.1.20',
        port: 22,
      ),
    ],
    hostKeyFingerprints: const ['SHA256:abc'],
    pairedDesktopId: 'AbCdEf0123_-xyZ9',
    relayUrl: 'wss://relay.example.com',
    lastGoodKind: SshEndpointKind.lan,
  );
  final round = SshProfile.fromJson(paired.toJson());
  expect(round.pairedDesktopId, 'AbCdEf0123_-xyZ9');
  expect(round.relayUrl, 'wss://relay.example.com');
  expect(round.lastGoodKind, SshEndpointKind.lan);
  expect(round.endpoints.single.host, '192.168.1.20');

  const manual = SshProfile(id: 'b', name: 'm', host: 'h', username: 'u');
  expect(manual.toJson().containsKey('pairedDesktopId'), isFalse);
});
```

Create `client/test/repositories/ssh_credential_store_connect_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';

void main() {
  test('device key is global; relay grant is per profile and deleted with deleteAll', () async {
    final store = InMemorySshCredentialStore();
    await store.saveDevicePrivateKey('PEM');
    expect(await store.loadDevicePrivateKey(), 'PEM');
    await store.saveRelayGrant('p1', 'grant');
    expect(await store.loadRelayGrant('p1'), 'grant');
    await store.deleteAll('p1');
    expect(await store.loadRelayGrant('p1'), isNull);
    expect(await store.loadDevicePrivateKey(), 'PEM');
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
flutter test test/models/ssh_profile_test.dart test/repositories/ssh_credential_store_connect_test.dart
```

Expected: FAIL compiling (new fields/methods missing).

- [ ] **Step 3: Implement fields and store methods**

Update `SshProfile` constructor, `fromJson`, `copyWith`, `toJson`, `==`, `hashCode` with:

- `this.endpoints = const []`
- `this.hostKeyFingerprints = const []`
- `this.pairedDesktopId`
- `this.relayUrl`
- `this.lastGoodKind`

`toJson` only emits pairing keys when `pairedDesktopId != null` or `endpoints.isNotEmpty`.

Add to `SshCredentialStore` and **all** implementations (`SecureSshCredentialStore`, `SharedPrefsSshCredentialStore`, `InMemorySshCredentialStore`, `_CredentialOverrideStore` in `ssh_client_factory.dart` — forward to `_base`):

```dart
Future<String?> loadDevicePrivateKey();
Future<void> saveDevicePrivateKey(String pem);
Future<String?> loadRelayGrant(String profileId);
Future<void> saveRelayGrant(String profileId, String grant);
```

Secure/SharedPrefs keys: `$_prefix.device.privateKey` and `$_prefix.$profileId.relayGrant`. Search `implements SshCredentialStore` under `client/` and update every fake.

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/models/ssh_profile_test.dart test/repositories/ssh_credential_store_connect_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/ssh_profile.dart \
  client/lib/repositories/ssh_credential_store.dart \
  client/lib/services/ssh/ssh_client_factory.dart \
  client/test/models/ssh_profile_test.dart \
  client/test/repositories/ssh_credential_store_connect_test.dart
git commit -m "$(cat <<'EOF'
Add pairing fields to SSH profiles and credential store.

EOF
)"
```

---

### Task 3: Token gate and tagged authorized_keys

**Files:**
- Create: `client/lib/services/connect/pairing_token_gate.dart`
- Create: `client/lib/services/connect/authorized_keys_file.dart`
- Create: `client/test/services/connect/pairing_token_gate_test.dart`
- Create: `client/test/services/connect/authorized_keys_file_test.dart`

**Interfaces:**
- Consumes: none
- Produces:
  - `class PairingTokenGate { String mint({required DateTime now, Duration ttl = const Duration(minutes: 10)}); bool consume(String token, DateTime now); void invalidate(); }`
  - `class AuthorizedKeysFile { AuthorizedKeysFile({required String path, required Future<String?> Function(String) read, required Future<void> Function(String, String) write, required Future<void> Function(String, {required int mode}) chmod}); Future<void> upsertDevice({required String publicKey, required String deviceId, required String deviceName}); Future<void> revokeDevice(String deviceId); Future<List<({String deviceId, String name})>> listDevices(); }`

- [ ] **Step 1: Write failing tests**

`pairing_token_gate_test.dart`:

- `mint` returns 43-char base64url (no `=`).
- `consume` once succeeds; second consume fails.
- expired (`now` after TTL) fails.
- `invalidate` then consume fails.
- new `mint` invalidates previous token.

`authorized_keys_file_test.dart` (in-memory map as fake fs):

- `upsertDevice` writes `ssh-ed25519 AAAA teampilot-pair device=d1 name=Pixel`.
- second upsert with same `deviceId` replaces the line (still one matching line).
- `revokeDevice` removes it; unrelated existing keys stay.
- `chmod` called with mode `384` (`int.parse('600', radix: 8)`).

Sanitize `deviceName` to `[A-Za-z0-9._-]+` (replace others with `_`) so the comment stays one token.

- [ ] **Step 2: Run tests to verify they fail**

```bash
flutter test test/services/connect/pairing_token_gate_test.dart test/services/connect/authorized_keys_file_test.dart
```

Expected: FAIL compiling.

- [ ] **Step 3: Implement**

`PairingTokenGate` keeps `_token`, `_expiresAt`, `_used`. `mint` uses `Random.secure()` 32 bytes, `base64Url.encode` strip `=`. `consume` checks equality, `!_used`, and `now.isBefore(_expiresAt)`.

`AuthorizedKeysFile.upsertDevice` reads text, filters out lines containing `teampilot-pair device=$deviceId`, appends the tagged line, writes, `chmod` 600.

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/services/connect/pairing_token_gate_test.dart test/services/connect/authorized_keys_file_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/connect/pairing_token_gate.dart \
  client/lib/services/connect/authorized_keys_file.dart \
  client/test/services/connect/pairing_token_gate_test.dart \
  client/test/services/connect/authorized_keys_file_test.dart
git commit -m "$(cat <<'EOF'
Add pairing token gate and tagged authorized_keys writer.

EOF
)"
```

---

### Task 4: Pairing POST handler and TLS pin helper

**Files:**
- Create: `client/lib/services/connect/pairing_http.dart`
- Create: `client/test/services/connect/pairing_http_test.dart`

**Interfaces:**
- Consumes: `PairingTokenGate`, `AuthorizedKeysFile`
- Produces:
  - `class PairingPostBody { token, deviceId, deviceName, publicKey }`
  - `class PairingPostResult { ok, profileHint, relayGrant }`
  - `class PairingHttpException implements Exception { String code; }` codes: `expired` | `used` | `invalid` | `badKey`
  - `Future<PairingPostResult> handlePairingPost({required PairingPostBody body, required PairingTokenGate gate, required AuthorizedKeysFile keys, required DateTime now, required String profileHint, String? relayGrant})`
  - `class PairingTlsPin { static bool matches({required List<int> derBytes, required String expectedSha256Hex}); }`

Do not spin a real `HttpServer` in this task.

- [ ] **Step 1: Write failing handler tests**

- Valid body → upsert keys, consume token, return `{ok: true, profileHint: 'alice-laptop'}`.
- Bad token / expired / already used → `PairingHttpException`.
- `publicKey` not starting with `ssh-ed25519 ` → `badKey`.
- `PairingTlsPin.matches` true for `sha256.convert(derBytes).toString()` hex (case-insensitive), false otherwise.

- [ ] **Step 2: Run the test to verify it fails**

```bash
flutter test test/services/connect/pairing_http_test.dart
```

Expected: FAIL compiling.

- [ ] **Step 3: Implement `handlePairingPost` and `PairingTlsPin`**

Use `package:crypto` `sha256.convert(derBytes).toString()`. If `!gate.consume(...)` throw `expired` when a token was minted else `invalid`. Then `keys.upsertDevice(...)`. Return result including optional `relayGrant`.

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/services/connect/pairing_http_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/connect/pairing_http.dart \
  client/test/services/connect/pairing_http_test.dart
git commit -m "$(cat <<'EOF'
Add pairing POST handler and TLS certificate pin helper.

EOF
)"
```

---

### Task 5: sshd presence and ConnectAgent LAN mint

**Files:**
- Create: `client/lib/services/connect/sshd_presence.dart`
- Create: `client/lib/services/connect/connect_agent.dart`
- Create: `client/lib/services/connect/connect_settings_store.dart`
- Create: `client/test/services/connect/connect_agent_test.dart`

**Interfaces:**
- Consumes: `SshPairingOffer`, `PairingTokenGate`, `handlePairingPost`, `AuthorizedKeysFile`
- Produces:
  - `class SshdPresenceSnapshot { listening, port, fingerprints, enableHint }`
  - `typedef SshdPresenceProbe = Future<SshdPresenceSnapshot> Function()`
  - `class PairingBinding { address, port, close, Stream<PairingHttpRequest> requests }`
  - `typedef PairingBind = Future<PairingBinding> Function(InternetAddress address, Object tlsContext)`
  - `class ConnectAgent { Future<void> startQrSession({required String advertiseAddress, required String username, required String displayName, required String appDataRoot}); Future<void> stopQrSession(); SshPairingOffer? get currentOffer; Future<void> regenerateQr(); }`

`startQrSession` must not mint when `!sshd.listening`. Bind only to `InternetAddress(advertiseAddress)` (never `0.0.0.0`). Fill `pairing.url` as `https://$advertiseAddress:$port/pair`.

Inject probe, keys, gate, bind, `certSha256Hex`, `now`, stable `hostId`, extra endpoints, `relayRegistered`.

Do **not** use real `HttpServer` in unit tests — use `PairingBind`.

Production TLS: `ConnectTls.generate()` via injected `ProcessRunner` running `openssl req -x509 -newkey rsa:2048 -days 1 -nodes -subj /CN=teampilot-pair`. Unit tests never call openssl.

Default sshd probe (app only, not unit tests): TCP `127.0.0.1:22` with 300ms timeout; fingerprints from injected `readHostFingerprints()` using `SHA256:` format matching `SshClientFactory.fingerprintIdentity`. Enable hints:

- Linux: enable/start `ssh` or `sshd`
- macOS: Remote Login
- Windows: Optional Features → OpenSSH Server

- [ ] **Step 1: Write failing agent tests**

- Probe `listening: false` → `currentOffer == null`, `bind` not called.
- Probe `listening: true` → offer minted, `pairing.url` uses advertise address, `bind` called with that address.
- `stopQrSession` closes binding and clears offer; old token consume fails.
- `regenerateQr` changes `pairing.token`; old token consume fails.
- Incoming POST with valid token writes authorized_keys (in-memory `AuthorizedKeysFile`).

- [ ] **Step 2: Run the test to verify it fails**

```bash
flutter test test/services/connect/connect_agent_test.dart
```

Expected: FAIL compiling.

- [ ] **Step 3: Implement `ConnectAgent` mint + session lifecycle**

Endpoints = one `lan` for `advertiseAddress` + extras from settings + optional `kind: relay` when `relayRegistered`. Omit `relay` object unless registered. Persist `hostId` in `ConnectSettingsStore` (JSON under app data `connect/settings.json` via injected `Filesystem`).

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/services/connect/connect_agent_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/connect/sshd_presence.dart \
  client/lib/services/connect/connect_agent.dart \
  client/lib/services/connect/connect_settings_store.dart \
  client/test/services/connect/connect_agent_test.dart
git commit -m "$(cat <<'EOF'
Add ConnectAgent LAN offer mint gated on sshd presence.

EOF
)"
```

---

### Task 6: Phone pair client, profile upsert, host-key pin

**Files:**
- Create: `client/lib/services/connect/connect_pair_client.dart`
- Create: `client/lib/services/connect/paired_profile_writer.dart`
- Create: `client/lib/services/connect/ssh_device_key.dart`
- Create: `client/test/services/connect/paired_profile_writer_test.dart`
- Modify: `client/lib/services/ssh/ssh_client_factory.dart` (`SshHostKeyTrustPolicy.verify`)
- Modify: `client/test/services/ssh/ssh_host_key_trust_policy_test.dart`

**Interfaces:**
- Consumes: `SshPairingOffer`, `PairingPostResult`, `SshProfileRepository.save`, `SshProfileRepository.loadAll`
- Produces:
  - `class SshDeviceKey { static ({String pem, String openSshPublic}) generate(); }` — tests inject canned pem/public, do not call `generate()` unless needed
  - `class PairedProfileWriter { Future<SshProfile> upsert({required SshPairingOffer offer, required PairingPostResult result, required String devicePem}); }`
  - Match existing profile when `pairedDesktopId == offer.hostId`. Manual profiles (no `pairedDesktopId`) untouched.

- [ ] **Step 1: Write failing writer + host-key tests**

Writer tests:

- Creates profile with `authType: privateKey`, `lastAppDataRoot: offer.appDataRoot`, `host`/`port` of first lan endpoint, `savePrivateKey(profile.id, devicePem)`.
- Second upsert with same `hostId` updates endpoints, does not create a second profile (`loadAll` length 1).
- Manual profile is left untouched.
- Calls `SshKnownHostRepository.saveFingerprint` for each lan/extra `hostIdentifier`.

Host-key policy: when `profile.hostKeyFingerprints` is non-empty, `verify` returns true only if `SHA256:` + base64 or hex identity is in that list; **does not** call `onHostKeyPrompt`; mismatch returns false without writing known_hosts. Existing tests for empty `hostKeyFingerprints` must still pass.

- [ ] **Step 2: Run tests to verify they fail**

```bash
flutter test test/services/connect/paired_profile_writer_test.dart test/services/ssh/ssh_host_key_trust_policy_test.dart
```

Expected: FAIL on new assertions / missing types.

- [ ] **Step 3: Implement writer + pin policy**

`SshDeviceKey.generate`: OpenSSH-compatible Ed25519 private key (`-----BEGIN OPENSSH PRIVATE KEY-----`) plus `ssh-ed25519 AAAA…` public line. Tests pass canned keys.

`SshHostKeyTrustPolicy.verify`: if `profile.hostKeyFingerprints.isNotEmpty`, accept iff identity is in the list; never prompt; on miss return false.

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/services/connect/paired_profile_writer_test.dart test/services/ssh/ssh_host_key_trust_policy_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/connect/connect_pair_client.dart \
  client/lib/services/connect/paired_profile_writer.dart \
  client/lib/services/connect/ssh_device_key.dart \
  client/lib/services/ssh/ssh_client_factory.dart \
  client/test/services/connect/paired_profile_writer_test.dart \
  client/test/services/ssh/ssh_host_key_trust_policy_test.dart
git commit -m "$(cat <<'EOF'
Upsert paired SSH profiles and pin host keys from the QR offer.

EOF
)"
```

---

### Task 7: Desktop Connect UI

**Files:**
- Create: `client/lib/cubits/connect_cubit.dart`
- Create: `client/lib/pages/connect/connect_section.dart`
- Create: `client/lib/pages/connect/connect_qr_panel.dart`
- Create: `client/lib/pages/config/connect_config_section.dart`
- Modify: `client/lib/cubits/config_cubit.dart` (add `ConfigSection.connect` after `sshProfiles`)
- Modify: `client/lib/pages/config/config_workspace.dart` (nav entry + body; bump `_configSectionDialogIndex` for github and later by +1)
- Modify: `client/lib/router/app_router.dart` (`/config/connect`)
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`
- Modify: `client/pubspec.yaml` (`qr_flutter: ^4.1.0`)
- Modify: `client/lib/utils/ui/app_keys.dart`
- Modify: `client/lib/app/app_shell.dart` (provide `ConnectCubit` when `!Platform.isAndroid`)
- Create: `client/test/pages/connect/connect_qr_panel_test.dart`

**Interfaces:**
- Consumes: `ConnectAgent`
- Produces: keys `AppKeys.connectQrCode`, `AppKeys.connectSshdEnableCta`, `AppKeys.connectRegenerateQr`

l10n:

- `connectSettingsTitle`: Phone / 手机
- `connectSettingsSubtitle`: Pair a phone over SSH / 扫码用 SSH 连接这台电脑
- `connectLanOnlyStatus`: LAN only / 仅局域网
- `connectRemoteReadyStatus`: LAN and remote / 局域网和远程
- `connectSshdDown`: OpenSSH is not listening… / 未检测到 OpenSSH，请先开启远程登录或 sshd。
- `connectScanHint`: Scan this code in TeamPilot on your phone. / 在手机上的 TeamPilot 中扫描此码。

Then from `client/`: `flutter gen-l10n` and `flutter pub get`.

- [ ] **Step 1: Write the failing widget test**

Pump `ConnectQrPanel` with fake state:

- `sshd.listening == false` → no `AppKeys.connectQrCode`; `AppKeys.connectSshdEnableCta` finds one.
- `sshd.listening == true` and offer non-null → QR key finds one; CTA absent.

Wrap in `MaterialApp` + `TpTheme` like other page tests. QR widget: `QrImageView(data: offer.encode())` inside the keyed widget.

- [ ] **Step 2: Run the test to verify it fails**

```bash
flutter test test/pages/connect/connect_qr_panel_test.dart
```

Expected: FAIL compiling.

- [ ] **Step 3: Implement UI + settings entry**

Android settings may show the section with copy “Scan a QR from desktop TeamPilot” and must **not** start the agent.

NIC picker: injected interfaces; default first non-loopback IPv4. Extra host:port rows via `ConnectSettingsStore`. Relay URL field may exist; registration is Task 11.

Copy link copies `offer.encode()`. Regenerate calls `agent.regenerateQr()`. Paired devices from `AuthorizedKeysFile.listDevices()` with revoke.

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/pages/connect/connect_qr_panel_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/pubspec.yaml client/pubspec.lock \
  client/lib/cubits/connect_cubit.dart \
  client/lib/cubits/config_cubit.dart \
  client/lib/pages/connect \
  client/lib/pages/config/connect_config_section.dart \
  client/lib/pages/config/config_workspace.dart \
  client/lib/router/app_router.dart \
  client/lib/app/app_shell.dart \
  client/lib/utils/ui/app_keys.dart \
  client/lib/l10n \
  client/test/pages/connect
git commit -m "$(cat <<'EOF'
Add desktop Connect settings with sshd-gated pairing QR.

EOF
)"
```

---

### Task 8: Android scan / paste and onboarding entry

**Files:**
- Create: `client/lib/pages/connect/android_pair_sheet.dart`
- Modify: `client/lib/pages/ssh_profiles/ssh_profiles_section.dart`
- Modify: `client/lib/pages/onboarding/steps/work_home_step.dart` (SSH subpage already uses `SshProfilesPage`; Scan lives in the section)
- Modify: `client/android/app/src/main/AndroidManifest.xml`
- Modify: `client/pubspec.yaml` (`mobile_scanner`)
- Modify: `client/lib/l10n/app_en.arb`, `app_zh.arb`
- Modify: `client/lib/utils/ui/app_keys.dart` (`connectScanQr`, `connectPasteCode`)
- Create: `client/test/pages/connect/android_pair_sheet_test.dart`
- Modify: `client/test/pages/ssh_profiles/ssh_profiles_section_test.dart`

**Interfaces:**
- Consumes: `SshPairingOffer.decode`, pairing POST, `PairedProfileWriter.upsert`, `SshConnectionCubit.connect` (Android already rebinds home via `selectProfileOnConnect`)
- Produces: `AndroidPairSheet` with `Future<String?> Function()? scanCode` (tests inject; production uses `mobile_scanner`)

- [ ] **Step 1: Write failing tests**

`android_pair_sheet_test.dart`:

- Primary `AppKeys.connectScanQr` and paste `AppKeys.connectPasteCode` exist.
- Inject `scanCode: () async => offer.encode()` and fakes; tap scan → writer once + `connect(profileId)`.
- `PairingHttpException(code: expired)` shows `connectPairExpired` (“Code expired. Scan again.” / “配对码已过期，请重新扫描。”).
- Unknown `v` shows `connectPairUpdateApp`.

`ssh_profiles_section_test.dart`: `debugDefaultTargetPlatformOverride = TargetPlatform.android` → find `AppKeys.connectScanQr`. Reset in `tearDown`.

Manifest: `CAMERA` permission plus VIEW/BROWSABLE intent-filter:

```xml
<data android:scheme="teampilot" android:host="pair-ssh"/>
```

First-pair path is in-app scanner/paste. Intent filter is required even if URI routing is not wired in this task.

- [ ] **Step 2: Run tests to verify they fail**

```bash
flutter test test/pages/connect/android_pair_sheet_test.dart test/pages/ssh_profiles/ssh_profiles_section_test.dart
```

Expected: FAIL (missing keys / widgets).

- [ ] **Step 3: Implement sheet + Scan as primary on Android**

On Android, `SshProfilesSection` header: `FilledButton` Scan (primary), existing Add target secondary. Desktop section unchanged.

If `loadDevicePrivateKey()` is null, `SshDeviceKey.generate()` and `saveDevicePrivateKey`.

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/pages/connect/android_pair_sheet_test.dart test/pages/ssh_profiles/ssh_profiles_section_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/connect/android_pair_sheet.dart \
  client/lib/pages/ssh_profiles/ssh_profiles_section.dart \
  client/android/app/src/main/AndroidManifest.xml \
  client/pubspec.yaml client/pubspec.lock \
  client/lib/l10n client/lib/utils/ui/app_keys.dart \
  client/test/pages/connect/android_pair_sheet_test.dart \
  client/test/pages/ssh_profiles/ssh_profiles_section_test.dart
git commit -m "$(cat <<'EOF'
Add Android QR scan and paste pairing for SSH home.

EOF
)"
```

---

### Task 9: Multi-endpoint dial planner

**Files:**
- Create: `client/lib/services/connect/endpoint_dial_planner.dart`
- Create: `client/test/services/connect/endpoint_dial_planner_test.dart`
- Create: `client/test/services/connect/paired_connect_attempt_test.dart`
- Modify connect path used by Android pair sheet / `SshConnectionCubit.connect` so paired profiles (`pairedDesktopId != null`) use the planner. Manual profiles unchanged.

**Interfaces:**
- Consumes: `SshProfile.endpoints`, `ConnectPolicy`
- Produces:
  - `List<SshReachabilityEndpoint> planEndpointDials(SshProfile profile, {ConnectPolicy policy = ConnectPolicy.automatic})`
  - Order: all `lan`, then `extra`, then `relay`. `lanOnly` → `lan` only.
  - `class SshHostKeyMismatch implements Exception {}`
  - `class PairedConnectAttempt { Future<SshReachabilityEndpoint> connectFirst({required SshProfile profile, required Future<void> Function(SshReachabilityEndpoint) dial, Duration perEndpointTimeout}); }`
  - Success `lan`/`extra`: persist `host`/`port`/`lastGoodKind`. Success `relay`: persist `lastGoodKind: relay` only (never `127.0.0.1` as host).
  - Host-key mismatch aborts the whole attempt (no fallthrough). Network failures fall through.
  - Optional `Future<({InternetAddress address, int port})> Function()? openRelayTunnel`. If null, skip `kind: relay` candidates (Task 11 supplies it).

- [ ] **Step 1: Write failing planner tests**

- Mixed list plans lan → extra → relay.
- `lanOnly` drops extra/relay.
- `connectFirst`: first dial throws `SocketException`, second succeeds → returns second; saver updates host.
- First dial throws `SshHostKeyMismatch` → second dial not called; saver not called.

- [ ] **Step 2: Run tests to verify they fail**

```bash
flutter test test/services/connect/endpoint_dial_planner_test.dart test/services/connect/paired_connect_attempt_test.dart
```

Expected: FAIL compiling.

- [ ] **Step 3: Implement planner and wire paired connects**

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/services/connect/endpoint_dial_planner_test.dart test/services/connect/paired_connect_attempt_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/connect/endpoint_dial_planner.dart \
  client/test/services/connect/endpoint_dial_planner_test.dart \
  client/test/services/connect/paired_connect_attempt_test.dart
git commit -m "$(cat <<'EOF'
Try LAN then extra SSH endpoints for paired profiles.

EOF
)"
```

---

### Task 10: Self-hosted relay server

**Files:**
- Create: `tools/teampilot_connect_relay/pubspec.yaml` (SDK `^3.7.0`, `dev_dependencies: test, lints`)
- Create: `tools/teampilot_connect_relay/lib/relay_server.dart`
- Create: `tools/teampilot_connect_relay/bin/teampilot_connect_relay.dart`
- Create: `tools/teampilot_connect_relay/test/relay_server_test.dart`
- Create: `client/lib/services/connect/connect_relay_protocol.dart`

**Interfaces:**
- Protocol JSON keys live in the client file. The tool **reimplements the same string constants** (`register`, `dial`, `splice`, `hostId`, `channel`, `inviteToken`, `relayGrant`) with a comment pointing at the client file. Do not add a path dependency from tools → client.

Routes:

- `GET /health` → `200 ok`
- WebSocket `/register?hostId=`
- WebSocket `/dial?hostId=&channel=&inviteToken=` or `relayGrant=`
- WebSocket `/splice?id=`

Flow: phone `/dial` → relay creates `spliceId`, sends text JSON `{type:dial, channel, spliceId}` on desktop `/register` → desktop opens `/splice?id=` → relay forwards binary frames until either closes.

CLI: `--bind 0.0.0.0 --port 2769` (default unprivileged). User may put TLS in front (Caddy). Client uses `ws://` or `wss://` from the typed URL.

- [ ] **Step 1: Write failing relay tests**

Use `package:test` (not flutter_test). Bind `HttpServer` on loopback port 0. Two `WebSocket` clients: register + dial; fake desktop receives dial and connects splice; phone sends `hello`; splice receives `hello`.

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd tools/teampilot_connect_relay && dart pub get && dart test
```

Expected: FAIL compiling.

- [ ] **Step 3: Implement the splice server**

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd tools/teampilot_connect_relay && dart test
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tools/teampilot_connect_relay client/lib/services/connect/connect_relay_protocol.dart
git commit -m "$(cat <<'EOF'
Add self-hosted TeamPilot Connect relay splice server.

EOF
)"
```

---

### Task 11: Relay client, grants, cellular pairing, loopback SSH

**Files:**
- Create: `client/lib/services/connect/connect_relay_client.dart`
- Create: `client/lib/services/connect/phone_relay_tunnel.dart`
- Create: `client/lib/services/connect/paired_device_store.dart` (keys + grant **hashes** in `connect/grants.json`)
- Modify: `client/lib/services/connect/connect_agent.dart` (register when URL set; include `relay` on offer; issue `relayGrant` on pairing POST when registered)
- Modify: `PairedConnectAttempt` to accept `openRelayTunnel`
- Modify: `AndroidPairSheet` — if LAN POST fails with connection error and `offer.relay != null`, retry POST through pair channel with `inviteToken`
- Create: `client/test/services/connect/connect_relay_client_test.dart`
- Create: `client/test/services/connect/phone_relay_tunnel_test.dart`

**Interfaces:**
- `ConnectRelayClient.connect({required Uri url, required String hostId})` — outbound `/register`
- On `{type:dial, channel, spliceId}`: open `/splice` and pipe to `127.0.0.1:sshdPort` (`ssh`) or pairing HTTPS port (`pair` only if QR session active; else close)
- `PhoneRelayTunnel.open({required Uri relayUrl, required String hostId, required String channel, String? inviteToken, String? relayGrant})` → loopback `ServerSocket` port 0, pipe to `/dial`. Never persist that loopback as `SshProfile.host`.
- Pair channel: phone HTTP client uses HTTPS to `127.0.0.1:$port` with `badCertificateCallback` matching `pairing.tlsCertSha256` (hostname mismatch is expected).
- Grant: 32 random bytes base64url; desktop stores **sha256 hex** keyed by `deviceId`; phone stores raw grant via `saveRelayGrant`. Dial with `relayGrant` succeeds if hash matches. Invite only valid while QR session token is live.
- Revoke: delete hash + `AuthorizedKeysFile.revokeDevice`.
- Do not log grant or invite.

- [ ] **Step 1: Write failing tests**

Use an in-process fake splice (`StreamController<List<int>>`), not the real tool:

- Desktop client receives dial ssh → bytes to fake sshd loopback appear from phone tunnel.
- Pair channel refused when QR session is stopped.
- Grant stored hashed; raw grant not written to `grants.json`.
- LAN pairing still succeeds when relay client is disconnected (offer has no `relay` object).

- [ ] **Step 2: Run tests to verify they fail**

```bash
flutter test test/services/connect/connect_relay_client_test.dart test/services/connect/phone_relay_tunnel_test.dart
```

Expected: FAIL compiling.

- [ ] **Step 3: Implement client, tunnel, grants**

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/services/connect/connect_relay_client_test.dart test/services/connect/phone_relay_tunnel_test.dart test/services/connect/connect_agent_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/connect/connect_relay_client.dart \
  client/lib/services/connect/phone_relay_tunnel.dart \
  client/lib/services/connect/paired_device_store.dart \
  client/lib/services/connect/connect_agent.dart \
  client/lib/services/connect/endpoint_dial_planner.dart \
  client/lib/pages/connect/android_pair_sheet.dart \
  client/test/services/connect
git commit -m "$(cat <<'EOF'
Pipe paired SSH and pairing HTTP through a self-hosted relay.

EOF
)"
```

---

### Task 12: Policy labels, revoke, and error copy

**Files:**
- Modify: `client/lib/pages/connect/connect_section.dart`
- Modify: `client/lib/pages/connect/android_pair_sheet.dart`
- Modify: `client/lib/l10n/app_en.arb`, `app_zh.arb`
- Create: `client/test/pages/connect/connect_policy_label_test.dart`
- Create: `client/test/pages/connect/connect_revoke_device_test.dart`

**Interfaces:**
- Heading says LAN only when there is no extra endpoint and no live relay registration; otherwise `connectRemoteReadyStatus`.
- l10n `connectNeedLanOrRelay`: “Join the same Wi-Fi, or set a relay on the desktop.” / “请连同一 Wi-Fi，或在桌面填写中继地址。”
- Revoke removes the device row (fake store).

- [ ] **Step 1: Write failing widget tests**

- No extra, not registered → `connectLanOnlyStatus`.
- Extra host present → `connectRemoteReadyStatus`.
- Revoke removes the device row.

- [ ] **Step 2: Run tests to verify they fail**

```bash
flutter test test/pages/connect/connect_policy_label_test.dart test/pages/connect/connect_revoke_device_test.dart
```

Expected: FAIL.

- [ ] **Step 3: Implement labels + revoke + Android error copy**

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/pages/connect/connect_policy_label_test.dart test/pages/connect/connect_revoke_device_test.dart test/pages/connect/connect_qr_panel_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/connect client/lib/l10n client/test/pages/connect
git commit -m "$(cat <<'EOF'
Label Connect reachability honestly and allow revoking paired phones.

EOF
)"
```

---

## Spec coverage

| Spec requirement | Task |
|------------------|------|
| QR / deep link codec, ignore unknown kinds, v=1, required `hostId` | 1 |
| No secrets in QR | 1 |
| `SshProfile` pairing fields + `relayGrant` in credential store | 2 |
| Single-use ≤10min token, regenerate invalidates | 3, 5 |
| Tagged authorized_keys upsert/revoke | 3, 11, 12 |
| Pairing POST + TLS pin | 4, 5, 8 |
| No QR if sshd down; enable CTA | 5, 7 |
| Android scan/paste; connect + `lastAppDataRoot` | 6, 8 |
| Host-key pin, no last-good on mismatch | 6, 9 |
| lan → extra → relay; loopback never in `host` | 9, 11 |
| Self-hosted relay splice + grants | 10, 11 |
| Cellular pairing via pair channel | 11 |
| LAN still works without relay | 5, 11 |
| Settings UI, policy labels, devices | 7, 12 |
| Intent `teampilot://pair-ssh` | 8 |
| Official cloud relay | not implemented (schema reserved via `SshRelayOffer`) |
| iOS / Orca RPC / Tailscale dependency | non-goals |
