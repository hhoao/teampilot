import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_auth_type.dart';
import 'package:teampilot/models/ssh_server_profile.dart';

void main() {
  test('round-trips without credentials', () {
    const profile = SshServerProfile(
      id: 't1',
      name: 'dev',
      host: '10.0.0.5',
      port: 22,
      username: 'alice',
      authType: SshAuthType.privateKey,
      embeddedTarget: true,
      updatedAt: 7,
    );
    final json = profile.toJson();
    expect(json.containsKey('password'), isFalse);
    expect(json.containsKey('privateKey'), isFalse);
    expect(SshServerProfile.fromJson(json), profile);
  });
}
