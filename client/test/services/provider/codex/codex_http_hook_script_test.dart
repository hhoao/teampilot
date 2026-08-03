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

    test('agent-status script forwards the real hook payload from stdin', () {
      final bash = CodexHttpHookScript.buildAgentStatus(
        dialect: HostScriptDialect.bash,
        headers: const {'X-Member': 'worker-1'},
        event: 'PreToolUse',
      );
      expect(bash, contains('payload="\$(cat)"'));
      expect(bash, contains('if [ -z "\$payload" ]'));
      expect(bash, contains('-d "\$payload"'));
      expect(bash, isNot(contains('"hook_event_name"')));

      final powershell = CodexHttpHookScript.buildAgentStatus(
        dialect: HostScriptDialect.powershell,
        headers: const {'X-Member': 'worker-1'},
        event: 'PreToolUse',
      );
      expect(powershell, contains('[Console]::In.ReadToEnd()'));
      expect(powershell, contains('-d \$payload'));
    });
  });
}
