import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/connect/authorized_keys_file.dart';

void main() {
  test('upserts, lists, and revokes only tagged device keys', () async {
    var contents = 'ssh-ed25519 KEEP existing-device\n';
    var chmodMode = -1;
    final file = AuthorizedKeysFile(
      path: '/home/alice/.ssh/authorized_keys',
      read: (_) async => contents,
      write: (_, value) async => contents = value,
      chmod: (_, {required mode}) async => chmodMode = mode,
    );

    await file.upsertDevice(
      publicKey: 'ssh-ed25519 AAAA',
      deviceId: 'd1',
      deviceName: 'Pixel Pro',
    );
    await file.upsertDevice(
      publicKey: 'ssh-ed25519 BBBB',
      deviceId: 'd1',
      deviceName: 'Pixel/Updated',
    );

    expect(contents, contains('ssh-ed25519 KEEP existing-device'));
    expect(
      RegExp(r'teampilot-pair device=d1').allMatches(contents),
      hasLength(1),
    );
    expect(
      contents,
      contains('ssh-ed25519 BBBB teampilot-pair device=d1 name=Pixel_Updated'),
    );
    expect(chmodMode, 384);
    expect(await file.listDevices(), [(deviceId: 'd1', name: 'Pixel_Updated')]);

    await file.revokeDevice('d1');
    expect(contents, 'ssh-ed25519 KEEP existing-device\n');
  });
}
