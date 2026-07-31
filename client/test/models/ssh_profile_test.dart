import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';

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

  test('equality ignores path cache fields', () {
    final a = SshProfile(
      id: 'a',
      name: 'Box',
      host: 'h',
      username: 'u',
      lastHome: '/home/u',
    );
    final b = SshProfile(
      id: 'a',
      name: 'Box',
      host: 'h',
      username: 'u',
      lastHome: '/other',
    );
    expect(a, equals(b));
  });
}
