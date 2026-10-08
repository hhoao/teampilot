import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/connect/sshd_presence.dart';

void main() {
  test('fingerprintsFromSshKeyScan skips comments and hashes the blob', () {
    const blob = 'AAAAC3NzaC1lZDI1NTE5AAAAIGZha2VrZXlh';
    final stdout = '# comment\n127.0.0.1 ssh-ed25519 $blob phone\n';

    final prints = fingerprintsFromSshKeyScan(stdout);

    expect(prints, hasLength(1));
    expect(prints.single, 'SHA256:FvilWia5vBU67xx6gAb1dRPgDkgTyXLMZHAF351r4hE');
  });

  test('sample is down when probe fails', () async {
    final presence = SshdPresence(
      probe: () async => false,
      scan: () async =>
          (exitCode: 0, stdout: '127.0.0.1 ssh-ed25519 AAAA\n', stderr: ''),
    );

    final shot = await presence.sample();

    expect(shot.listening, isFalse);
    expect(shot.fingerprints, isEmpty);
  });

  test('sample is down when scan returns no keys', () async {
    final presence = SshdPresence(
      probe: () async => true,
      scan: () async => (exitCode: 1, stdout: '', stderr: 'Connection refused'),
    );

    final shot = await presence.sample();

    expect(shot.listening, isFalse);
    expect(shot.fingerprints, isEmpty);
  });

  test('sample listens when probe and fingerprints succeed', () async {
    const blob = 'AAAAC3NzaC1lZDI1NTE5AAAAIGZha2VrZXlh';
    final presence = SshdPresence(
      probe: () async => true,
      scan: () async =>
          (exitCode: 0, stdout: '127.0.0.1 ssh-ed25519 $blob\n', stderr: ''),
    );

    final shot = await presence.sample();

    expect(shot.listening, isTrue);
    expect(
      shot.fingerprints.single,
      'SHA256:FvilWia5vBU67xx6gAb1dRPgDkgTyXLMZHAF351r4hE',
    );
  });
}
