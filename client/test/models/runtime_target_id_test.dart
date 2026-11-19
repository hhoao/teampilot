import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/runtime_target.dart';

void main() {
  group('RuntimeTargetId', () {
    test('round-trips every kind', () {
      const ids = [
        LocalTargetId(),
        WslTargetId('Ubuntu-22.04'),
        SshTargetId('p1'),
        TermuxTargetId(),
      ];
      for (final id in ids) {
        expect(RuntimeTargetId.decode(id.encode()), id);
      }
    });

    test('derives kind, profile id and distro from the encoded form', () {
      final ssh = RuntimeTargetId.decode('ssh:p1');
      expect(ssh.kind, RuntimeKind.ssh);
      expect(ssh.sshProfileId, 'p1');
      expect(ssh.wslDistro, isNull);

      final wsl = RuntimeTargetId.decode('wsl:Ubuntu');
      expect(wsl.kind, RuntimeKind.wsl);
      expect(wsl.wslDistro, 'Ubuntu');

      final termux = RuntimeTargetId.decode('termux:default');
      expect(termux.kind, RuntimeKind.termux);
      expect(termux.sshProfileId, 'termux');

      expect(RuntimeTargetId.decode('local').kind, RuntimeKind.local);
    });

    test('an unknown id is local, never a guessed remote kind', () {
      expect(RuntimeTargetId.decode('something-else'), const LocalTargetId());
      expect(RuntimeTargetId.decode(''), const LocalTargetId());
    });

    test('targets expose the typed view of their id', () {
      expect(RuntimeTarget.ssh('p1', label: 'box').targetId, const SshTargetId('p1'));
      expect(RuntimeTarget.local().targetId, const LocalTargetId());
      expect(RuntimeTarget.wsl('Ubuntu').targetId, const WslTargetId('Ubuntu'));
      expect(RuntimeTarget.termux().targetId, const TermuxTargetId());
    });

    test('usesSshTransport covers ssh and termux only', () {
      expect(usesSshTransport(RuntimeKind.ssh), isTrue);
      expect(usesSshTransport(RuntimeKind.termux), isTrue);
      expect(usesSshTransport(RuntimeKind.wsl), isFalse);
      expect(usesSshTransport(RuntimeKind.local), isFalse);
    });
  });
}
