@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/connect/authorized_keys_file.dart';
import 'package:teampilot/services/connect/sshd_presence.dart';
import 'package:teampilot/services/connect/system_sshd_backend.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  test('start samples presence; stop forgets it', () async {
    var listening = true;
    final fs = InMemoryFilesystem();
    final backend = SystemSshdBackend(
      presence: SshdPresence(
        probe: () async => listening,
        scan: () async => (
          exitCode: 0,
          stdout:
              '127.0.0.1 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGZha2VrZXlh\n',
          stderr: '',
        ),
      ),
      authorizedKeys: AuthorizedKeysFile(fs: fs, homePath: '/home/alice'),
    );
    expect(backend.isEmbedded, isFalse);
    expect(backend.port, 22);
    await backend.start();
    expect(backend.isListening, isTrue);
    expect(backend.hostKeyFingerprints, isNotEmpty);
    listening = false;
    await backend.stop();
    expect(backend.isListening, isFalse);
    expect(backend.hostKeyFingerprints, isEmpty);
  });

  test('authorize and revoke write authorized_keys', () async {
    final fs = InMemoryFilesystem();
    final backend = SystemSshdBackend(
      presence: SshdPresence(
        probe: () async => false,
        scan: () async => (exitCode: 1, stdout: '', stderr: ''),
      ),
      authorizedKeys: AuthorizedKeysFile(fs: fs, homePath: '/home/alice'),
    );
    const key = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGZha2VrZXlh phone';
    await backend.authorizePublicKey(key);
    expect(
      await fs.readString('/home/alice/.ssh/authorized_keys'),
      contains('AAAAC3NzaC1lZDI1NTE5AAAAIGZha2VrZXlh'),
    );
    await backend.revokePublicKey(key);
    expect(
      (await fs.readString('/home/alice/.ssh/authorized_keys'))?.trim(),
      isEmpty,
    );
  });

  test('restart resamples presence', () async {
    var listening = true;
    final backend = SystemSshdBackend(
      presence: SshdPresence(
        probe: () async => listening,
        scan: () async => (
          exitCode: 0,
          stdout:
              '127.0.0.1 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGZha2VrZXlh\n',
          stderr: '',
        ),
      ),
      authorizedKeys: AuthorizedKeysFile(
        fs: InMemoryFilesystem(),
        homePath: '/home/alice',
      ),
    );
    await backend.start();
    expect(backend.isListening, isTrue);

    listening = false;
    await backend.restart();
    expect(backend.isListening, isFalse);
    expect(backend.hostKeyFingerprints, isEmpty);

    listening = true;
    await backend.restart();
    expect(backend.isListening, isTrue);
    expect(backend.hostKeyFingerprints, isNotEmpty);
  });

  test('port getter stays 22 after stop when not listening', () async {
    final backend = SystemSshdBackend(
      presence: SshdPresence(
        probe: () async => true,
        scan: () async => (
          exitCode: 0,
          stdout:
              '127.0.0.1 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGZha2VrZXlh\n',
          stderr: '',
        ),
      ),
      authorizedKeys: AuthorizedKeysFile(
        fs: InMemoryFilesystem(),
        homePath: '/home/alice',
      ),
    );
    expect(backend.port, 22);
    await backend.start();
    expect(backend.port, 22);
    await backend.stop();
    expect(backend.isListening, isFalse);
    expect(backend.port, 22);
  });
}
