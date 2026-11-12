import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/remote_target.dart';
import 'package:teampilot/models/ssh_auth_type.dart';

void main() {
  test('round-trips all fields', () {
    const target = RemoteTarget(
      id: 't1',
      name: 'dev-box',
      host: '10.0.0.5',
      port: 2222,
      username: 'alice',
      authType: SshAuthType.privateKey,
      vaultEntryId: 'v1',
      lastHome: '/home/alice',
      lastAppDataRoot: '/home/alice/.teampilot',
      embeddedTarget: true,
      relayUrl: 'wss://relay',
      pairedDesktopId: 'd1',
      updatedAt: 42,
    );
    final restored = RemoteTarget.fromJson(target.toJson());
    expect(restored, target);
    expect(restored.hostIdentifier, 'alice@10.0.0.5:2222');
  });

  test('defaults port and auth type', () {
    final target = RemoteTarget.fromJson({'id': 't1', 'host': 'h'});
    expect(target.port, 22);
    expect(target.authType, SshAuthType.password);
  });
}
