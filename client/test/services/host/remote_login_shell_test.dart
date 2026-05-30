import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/host/remote_login_shell.dart';

void main() {
  test('wrap produces bash -lc with TERM and inner command', () {
    final wrapped = RemoteLoginShell.wrap('echo hi');
    expect(wrapped, startsWith(r'TERM="${TERM:-xterm-256color}" bash -lc '));
    expect(wrapped, contains('echo hi'));
    expect(wrapped, contains('.bashrc'));
  });
}
