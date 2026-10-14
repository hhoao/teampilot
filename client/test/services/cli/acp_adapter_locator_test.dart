import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/acp_adapter_locator.dart';

void main() {
  test('Windows PATH hit uses semicolon and PATHEXT', () {
    expect(
      locateAcpAdapter(
        name: 'claude-agent-acp',
        environment: const {
          'PATH': r'C:\Windows;C:\npm',
          'PATHEXT': '.EXE;.CMD',
        },
        fileExists: (p) => p == r'C:\npm\claude-agent-acp.EXE',
        isWindows: true,
      ),
      r'C:\npm\claude-agent-acp.EXE',
    );
  });

  test('Windows missing adapter returns the bare name', () {
    expect(
      locateAcpAdapter(
        name: 'codex-acp',
        environment: const {'PATH': r'C:\Windows', 'PATHEXT': '.EXE'},
        fileExists: (_) => false,
        isWindows: true,
      ),
      'codex-acp',
    );
  });
}
