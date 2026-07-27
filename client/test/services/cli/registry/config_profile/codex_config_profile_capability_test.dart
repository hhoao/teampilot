import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/host/host_execution_environment.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/provider/codex/codex_team_bus_overlay.dart';
import 'package:teampilot/services/team_bus/member_bus_idle_endpoint.dart';

String _bashHookFileName(String baseName) =>
    HostExecutionEnvironment.resolve(isWindowsHost: false)
        .scriptRunner
        .hookFileName(baseName);

void main() {
  group('CodexTeamBusOverlay', () {
    late Directory root;
    late LocalFilesystem fs;
    late HostExecutionEnvironment host;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('codex_team_bus_');
      fs = LocalFilesystem();
      host = HostExecutionEnvironment.resolve(isWindowsHost: Platform.isWindows);
    });

    tearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    const idle = MemberBusIdleEndpoint(
      url: 'http://127.0.0.1:54321/idle',
      sessionId: 'sess-codex',
    );

    test('registers teammate-bus MCP and provisions a Stop hook script', () async {
      final toml = await CodexTeamBusOverlay.buildLocal(
        fs: fs,
        runner: host.scriptRunner,
        codexHome: root.path,
        memberId: 'worker-1',
        idle: idle,
      );

      expect(toml, contains('[mcp_servers.teammate-bus]'));
      expect(toml, contains('url = "http://127.0.0.1:54321/mcp"'));
      expect(toml, contains('"X-Member" = "worker-1"'));
      expect(toml, contains('"X-Session" = "sess-codex"'));
      expect(
        toml,
        contains('tool_timeout_sec = ${CodexTeamBusOverlay.busToolTimeoutSec}'),
      );
      expect(
        toml,
        contains(
          'default_tools_approval_mode = '
          '"${CodexTeamBusOverlay.defaultToolsApprovalMode}"',
        ),
      );
      expect(toml, contains('[[hooks.Stop]]'));
      expect(toml, contains('type = "command"'));
      expect(toml, contains('teampilot-team-bus-stop'));

      final scriptPath = p.join(
        root.path,
        'hooks',
        _bashHookFileName('teampilot-team-bus-stop'),
      );
      expect(await File(scriptPath).exists(), isTrue);
      final script = await File(scriptPath).readAsString();
      expect(script, contains('http://127.0.0.1:54321/idle'));
      if (Platform.isWindows) {
        final winScript = p.join(
          root.path,
          'hooks',
          host.scriptRunner.hookFileName('teampilot-team-bus-stop-win'),
        );
        expect(await File(winScript).exists(), isTrue);
      }
    });
  });

  group('CodexTeamBusOverlay remote stop hook', () {
    late Directory root;
    late LocalFilesystem fs;
    late HostExecutionEnvironment host;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('codex_team_bus_remote_');
      fs = LocalFilesystem();
      host = HostExecutionEnvironment.resolve(isWindowsHost: Platform.isWindows);
    });

    tearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    test('provisionStopHook includes X-Bus-Token for remote idle endpoints', () async {
      const idle = MemberBusIdleEndpoint(
        url: 'http://127.0.0.1:54321/idle',
        token: 'sess-tok',
      );
      final toml = await CodexTeamBusOverlay.provisionStopHook(
        fs: fs,
        runner: host.scriptRunner,
        codexHome: root.path,
        memberId: 'worker-1',
        idle: idle,
      );
      final script = await File(
        p.join(root.path, 'hooks', _bashHookFileName('teampilot-team-bus-stop')),
      ).readAsString();
      expect(script, contains('sess-tok'));
      expect(toml, contains('teampilot-team-bus-stop'));
      expect(toml, isNot(contains('[mcp_servers.teammate-bus]')));
    });
  });
}
