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
}
