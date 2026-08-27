import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/models/ssh_reachability.dart';

void main() {
  test('SSH profile ignores legacy launch options', () {
    const profile = SshProfile(
      id: 'p1',
      name: 'dev',
      host: 'example.com',
      username: 'alice',
    );

    final encoded = profile.toJson();
    final decoded = SshProfile.fromJson({
      ...encoded,
      'remoteFlashskyaiPath': '/legacy/flashskyai',
      'defaultWorkingDirectory': '~/legacy',
      'useLoginShell': true,
    });

    expect(encoded, isNot(contains('remoteFlashskyaiPath')));
    expect(encoded, isNot(contains('defaultWorkingDirectory')));
    expect(encoded, isNot(contains('useLoginShell')));
    expect(decoded, profile);
  });

  test('json round-trip preserves lastHome and lastAppDataRoot', () {
    final p = SshProfile(
      id: 'a',
      name: 'Box',
      host: 'h',
      username: 'u',
      lastHome: '/home/u',
      lastAppDataRoot: '/home/u/.local/share/com.hhoa.teampilot',
    );
    final r = SshProfile.fromJson(p.toJson());
    expect(r.lastHome, '/home/u');
    expect(r.lastAppDataRoot, '/home/u/.local/share/com.hhoa.teampilot');
  });

  test('equality includes path cache fields', () {
    final a = SshProfile(
      id: 'a',
      name: 'Box',
      host: 'h',
      username: 'u',
      lastHome: '/home/u',
      lastAppDataRoot: '/home/u/.local/share/com.hhoa.teampilot',
    );
    final b = SshProfile(
      id: 'a',
      name: 'Box',
      host: 'h',
      username: 'u',
      lastHome: '/other',
      lastAppDataRoot: '/other/.local/share/com.hhoa.teampilot',
    );
    expect(a, isNot(equals(b)));
  });

  test(
    'json round-trip preserves pairing fields; manual profiles omit them',
    () {
      const paired = SshProfile(
        id: 'a',
        name: 'Box',
        host: '192.168.1.20',
        username: 'u',
        endpoints: [
          SshReachabilityEndpoint(
            kind: SshEndpointKind.lan,
            host: '192.168.1.20',
            port: 22,
          ),
        ],
        hostKeyFingerprints: ['SHA256:abc'],
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
    },
  );
}
