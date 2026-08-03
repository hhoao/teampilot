import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/agent_status/member_agent_status_endpoint.dart';
import 'package:teampilot/services/host/host_execution_environment.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/provider/codex/codex_agent_status_overlay.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_config.dart';

String _bashHookFileName(String baseName) =>
    HostExecutionEnvironment.resolve(isWindowsHost: false)
        .scriptRunner
        .hookFileName(baseName);

void main() {
  group('CodexAgentStatusOverlay', () {
    late Directory root;
    late LocalFilesystem fs;
    late HostExecutionEnvironment host;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('codex_agent_status_');
      fs = LocalFilesystem();
      host = HostExecutionEnvironment.resolve(isWindowsHost: Platform.isWindows);
    });

    tearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    const endpoint = MemberAgentStatusEndpoint(
      url: 'http://127.0.0.1:12345/agent-status',
      sessionId: 'sess-codex',
    );
    const remoteEndpoint = MemberAgentStatusEndpoint(
      url: 'http://127.0.0.1:54321/agent-status',
      token: 'sess-tok',
    );

    test(
      'provisions hook scripts that POST lifecycle events to /agent-status',
      () async {
        final toml = await CodexAgentStatusOverlay.provision(
          fs: fs,
          runner: host.scriptRunner,
          codexHome: root.path,
          memberId: 'worker-1',
          endpoint: endpoint,
        );

        expect(toml, contains('[[hooks.PermissionRequest]]'));
        expect(toml, contains('[[hooks.Stop]]'));
        expect(toml, contains('type = "command"'));
        expect(toml, contains('teampilot-agent-status-UserPromptSubmit'));

        final scriptPath = p.join(
          root.path,
          'hooks',
          _bashHookFileName('teampilot-agent-status-UserPromptSubmit'),
        );
        expect(await File(scriptPath).exists(), isTrue);
        final script = await File(scriptPath).readAsString();
        expect(script, contains('TEAMPILOT_AGENT_STATUS_URL'));
        expect(script, contains('curl -sS'));
        // Forwards the real hook payload from stdin (tool / permission info).
        expect(script, contains('payload="\$(cat)"'));
        expect(script, contains('UserPromptSubmit'));
        if (Platform.isWindows) {
          final winScript = p.join(
            root.path,
            'hooks',
            host.scriptRunner.hookFileName(
              'teampilot-agent-status-UserPromptSubmit-win',
            ),
          );
          expect(await File(winScript).exists(), isTrue);
          expect(await File(winScript).readAsString(), contains('curl.exe'));
        }
      },
    );

    test('provisions X-Bus-Token for remote endpoints', () async {
      final toml = await CodexAgentStatusOverlay.provision(
        fs: fs,
        runner: host.scriptRunner,
        codexHome: root.path,
        memberId: 'worker-1',
        endpoint: remoteEndpoint,
      );
      expect(toml, contains('teampilot-agent-status'));
      final script = await File(
        p.join(
          root.path,
          'hooks',
          _bashHookFileName('teampilot-agent-status-PermissionRequest'),
        ),
      ).readAsString();
      expect(script, contains("'X-Bus-Token: sess-tok'"));
      if (Platform.isWindows) {
        expect(toml, contains('command_windows'));
      }
    });
  });
}
