import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/host/host_script_dialect.dart';
import 'package:teampilot/services/provider/codex/codex_http_hook_script.dart';

void main() {
  group('CodexHttpHookScript', () {
    test('powershell agent-status script posts JSON body', () {
      final script = CodexHttpHookScript.build(
        dialect: HostScriptDialect.powershell,
        url: 'http://127.0.0.1:1/agent-status?event=UserPromptSubmit',
        headers: const {
          'X-Member': 'worker-1',
          'Content-Type': 'application/json',
        },
        jsonBody: '{"hook_event_name":"UserPromptSubmit"}',
      );

      expect(script, contains('Invoke-WebRequest'));
      expect(script, contains('hook_event_name'));
      expect(script, contains('UserPromptSubmit'));
      expect(script, isNot(contains('curl -sS')));
    });

    test('powershell stop hook writes response body to stdout', () {
      final script = CodexHttpHookScript.build(
        dialect: HostScriptDialect.powershell,
        url: 'http://127.0.0.1:1/idle',
        headers: const {'X-Member': 'worker-1'},
        passResponseToStdout: true,
      );

      expect(script, contains('Write-Output'));
      expect(script, isNot(contains('-Body')));
    });
  });
}
