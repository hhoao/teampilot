import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/connect/paired_device_store.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  // Real ed25519 public keys (ssh-keygen -t ed25519), one with a trailing
  // comment and one without — both storage and lookup must handle either.
  const testDevicePubLine =
      'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM4rsGoZI5fUEbSFfD7zV7MYcX7MfTkDwcabYbH9+BmM hhoa@hhoa-ROG-Zephyrus-G16-GU605MV-GU605MV';
  const otherDevicePubLine =
      'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPQJcI+xLrqE2+hxc/el8qYmLSc3A3OEPqlfZqmuRW3e';

  late InMemoryFilesystem fs;
  late PairedDeviceStore store;

  setUp(() {
    fs = InMemoryFilesystem();
    store = PairedDeviceStore(
      fs: fs,
      appDataRoot: '/data',
      generateGrant: () => 'grant-token-abc',
    );
  });

  test('issued grants validate for their device and host only', () async {
    await store.issueGrant(hostId: 'host-1', deviceId: 'device-1');

    expect(
      await store.validateGrant(
        hostId: 'host-1',
        deviceId: 'device-1',
        grant: 'grant-token-abc',
      ),
      isTrue,
    );
    expect(
      await store.validateGrant(
        hostId: 'other-host',
        deviceId: 'device-1',
        grant: 'grant-token-abc',
      ),
      isFalse,
    );
    expect(
      await store.validateGrant(
        hostId: 'host-1',
        deviceId: 'device-2',
        grant: 'grant-token-abc',
      ),
      isFalse,
    );
    expect(
      await store.validateGrant(
        hostId: 'host-1',
        deviceId: 'device-1',
        grant: '',
      ),
      isFalse,
    );
  });

  test('only the hash of a grant is persisted, never the raw token', () async {
    await store.issueGrant(hostId: 'host-1', deviceId: 'device-1');

    final contents = await fs.readString(
      fs.pathContext.join('/data', 'connect', 'grants.json'),
    );
    expect(contents, isNotNull);
    expect(contents, isNot(contains('grant-token-abc')));
    final json = jsonDecode(contents!) as Map<String, Object?>;
    final devices = (json['devices'] as List).cast<Map<String, Object?>>();
    expect(devices.single['deviceId'], 'device-1');
    expect(devices.single['grantSha256'], hasLength(64));
  });

  test('re-issue replaces the grant for the same device', () async {
    var call = 0;
    final rotating = PairedDeviceStore(
      fs: fs,
      appDataRoot: '/data',
      generateGrant: () => 'token-${call++}',
    );
    await rotating.issueGrant(hostId: 'host-1', deviceId: 'device-1');
    await rotating.issueGrant(hostId: 'host-1', deviceId: 'device-1');

    expect(
      await rotating.validateGrant(
        hostId: 'host-1',
        deviceId: 'device-1',
        grant: 'token-0',
      ),
      isFalse,
    );
    expect(
      await rotating.validateGrant(
        hostId: 'host-1',
        deviceId: 'device-1',
        grant: 'token-1',
      ),
      isTrue,
    );
  });

  test('revoke removes the grant so later dials fail', () async {
    await store.issueGrant(hostId: 'host-1', deviceId: 'device-1');
    await store.revokeDevice('device-1');

    expect(await store.hasDevice('device-1'), isFalse);
    expect(
      await store.validateGrant(
        hostId: 'host-1',
        deviceId: 'device-1',
        grant: 'grant-token-abc',
      ),
      isFalse,
    );
  });

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
    await pumpEventQueue();
    await sub.cancel();
    expect(events.length, 2);
  });

  test('deviceIdForPublicKey maps a registered line to its device', () async {
    await store.issueDevice(deviceId: 'phone-1', publicKey: testDevicePubLine);
    expect(await store.deviceIdForPublicKey(testDevicePubLine), 'phone-1');
    expect(await store.deviceIdForPublicKey(otherDevicePubLine), isNull);
  });

  test(
    'deviceIdForPublicKey follows a re-paired device to its new id',
    () async {
      await store.issueDevice(
        deviceId: 'phone-1',
        publicKey: testDevicePubLine,
      );
      await store.issueDevice(
        deviceId: 'phone-2',
        publicKey: otherDevicePubLine,
      );
      expect(await store.deviceIdForPublicKey(otherDevicePubLine), 'phone-2');
      await store.revokeDevice('phone-2');
      expect(await store.deviceIdForPublicKey(otherDevicePubLine), isNull);
      expect(await store.deviceIdForPublicKey(testDevicePubLine), 'phone-1');
    },
  );

  test(
    'a stored key without comment matches a line with trailing comment',
    () async {
      await store.issueDevice(
        deviceId: 'phone-1',
        publicKey: otherDevicePubLine,
      );
      expect(
        await store.isValidDeviceKey('$otherDevicePubLine phone@pixel'),
        isTrue,
      );
      expect(
        await store.deviceIdForPublicKey('$otherDevicePubLine phone@pixel'),
        'phone-1',
      );
    },
  );

  test('malformed public key lines are rejected', () async {
    await store.issueDevice(deviceId: 'phone-1', publicKey: testDevicePubLine);
    expect(await store.isValidDeviceKey(''), isFalse);
    expect(await store.isValidDeviceKey('ssh-ed25519'), isFalse);
    expect(await store.isValidDeviceKey('ssh-ed25519 not-base64!!'), isFalse);
    expect(
      await store.deviceIdForPublicKey('ssh-ed25519 not-base64!!'),
      isNull,
    );
  });

  test(
    'revokeDevice removes the device from grants and key registry',
    () async {
      await store.issueGrant(hostId: 'host-1', deviceId: 'phone-1');
      await store.issueDevice(
        deviceId: 'phone-1',
        publicKey: testDevicePubLine,
      );

      expect(await store.revokeDevice('phone-1'), isTrue);
      expect(await store.hasDevice('phone-1'), isFalse);
      expect(await store.isValidDeviceKey(testDevicePubLine), isFalse);

      final devicesJson =
          jsonDecode(
                (await fs.readString(
                  fs.pathContext.join('/data', 'connect', 'devices.json'),
                ))!,
              )
              as Map<String, Object?>;
      expect((devicesJson['devices'] as List), isEmpty);

      expect(await store.revokeDevice('phone-1'), isFalse);
    },
  );

  test(
    'device key entries persist as connect/devices.json without hostId',
    () async {
      await store.issueDevice(
        deviceId: 'phone-1',
        publicKey: testDevicePubLine,
        deviceName: 'Pixel',
      );

      final contents = await fs.readString(
        fs.pathContext.join('/data', 'connect', 'devices.json'),
      );
      expect(contents, isNotNull);
      final json = jsonDecode(contents!) as Map<String, Object?>;
      expect(json['v'], 1);
      final devices = (json['devices'] as List).cast<Map<String, Object?>>();
      expect(devices.single['deviceId'], 'phone-1');
      expect(devices.single['deviceName'], 'Pixel');
      expect(devices.single['publicKey'], testDevicePubLine);
      expect(devices.single.containsKey('hostId'), isFalse);
    },
  );

  test('dispose closes the device registry change stream', () async {
    store.dispose();
    var done = false;
    final sub = store.deviceRegistryChanged.listen(
      (event) {},
      onDone: () => done = true,
    );
    await pumpEventQueue();
    await sub.cancel();
    expect(done, isTrue);
  });
}
