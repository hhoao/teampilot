import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/connect/paired_device_store.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
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
      await store.validateGrant(hostId: 'host-1', deviceId: 'device-1', grant: ''),
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
}
