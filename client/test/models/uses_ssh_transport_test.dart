import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/runtime_target.dart';

void main() {
  test('usesSshTransport is true for ssh and termux only', () {
    expect(usesSshTransport(RuntimeKind.ssh), isTrue);
    expect(usesSshTransport(RuntimeKind.termux), isTrue);
    expect(usesSshTransport(RuntimeKind.local), isFalse);
    expect(usesSshTransport(RuntimeKind.wsl), isFalse);
  });

  test('RuntimeTarget.termux carries synthetic sshProfileId', () {
    final target = RuntimeTarget.termux();
    expect(target.sshProfileId, 'termux');
    expect(target.kind, RuntimeKind.termux);
  });
}
