import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/host/host_script_dialect.dart';
import 'package:teampilot/services/provider/codex/codex_http_hook_script.dart';

void main() {
  group('CodexHttpHookScript', () {
    test('powershell agent-status script uses curl and TEAMPILOT env URL', () {
      final script = CodexHttpHookScript.buildAgentStatus(
        dialect: HostScriptDialect.powershell,
        headers: const {
          'X-Member': 'worker-1',
          'Content-Type': 'application/json',
        },
        event: 'UserPromptSubmit',
      );

      expect(script, contains('curl.exe'));
      expect(script, contains('TEAMPILOT_AGENT_STATUS_URL'));
      expect(script, contains('UserPromptSubmit'));
      expect(script, contains('exit 0'));
      expect(script, isNot(contains('Invoke-WebRequest')));
    });

    test('powershell stop hook writes curl response to stdout', () {
      final script = CodexHttpHookScript.build(
        dialect: HostScriptDialect.powershell,
        url: 'http://127.0.0.1:1/idle',
        headers: const {'X-Member': 'worker-1'},
        passResponseToStdout: true,
      );

      expect(script, contains('curl.exe'));
      expect(script, contains('Write-Output'));
    });
  });
}
