import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/services/termux/termux_config.dart';
import 'package:teampilot/services/termux/termux_transport_profile.dart';

void main() {
  test('termuxTransportProfile uses reserved id and loopback privateKey auth', () {
    const config = TermuxConfig(
      username: 'u0_a123',
      host: '127.0.0.1',
      port: 8022,
    );

    final profile = termuxTransportProfile(config);

    expect(profile.id, 'termux');
    expect(profile.name, 'Termux');
    expect(profile.host, '127.0.0.1');
    expect(profile.port, 8022);
    expect(profile.username, 'u0_a123');
    expect(profile.authType, SshAuthType.privateKey);
  });

  test('termuxTransportProfile reflects custom host and port from config', () {
    const config = TermuxConfig(
      username: 'u0_a456',
      host: '127.0.0.1',
      port: 9022,
    );

    final profile = termuxTransportProfile(config);

    expect(profile.host, '127.0.0.1');
    expect(profile.port, 9022);
    expect(profile.username, 'u0_a456');
  });
}
