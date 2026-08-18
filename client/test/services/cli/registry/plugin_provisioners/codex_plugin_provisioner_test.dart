import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/plugin.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/codex/capabilities/plugin.dart';
import 'package:teampilot/services/cli/registry/capabilities/plugin_capability.dart';
import 'package:teampilot/services/host/host_one_shot_runner.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

import '../../../../support/in_memory_filesystem.dart';

final class _RecordingRunner implements HostOneShotRunner {
  _RecordingRunner({
    this.listJson = '{"installed":[]}',
    this.marketplaceListJson = '{"marketplaces":[]}',
  });

  final String listJson;
  final String marketplaceListJson;
  final calls = <HostRunRequest>[];

  @override
  Future<HostRunResult> run(HostRunRequest request) async {
    calls.add(request);
    if (request.arguments.contains('marketplace') &&
        request.arguments.contains('list')) {
      return HostRunResult(
        exitCode: 0,
        stdout: marketplaceListJson,
        stderr: '',
      );
    }
    if (request.arguments.contains('list')) {
      return HostRunResult(exitCode: 0, stdout: listJson, stderr: '');
    }
    return const HostRunResult(exitCode: 0, stdout: '{}', stderr: '');
  }
}

void main() {
  PluginProvisionContext context({
    required InMemoryFilesystem fs,
    required HostOneShotRunner runner,
    List<String> enabledPluginIds = const ['local/demo'],
  }) {
    return PluginProvisionContext(
      fs: fs,
      teampilotRoot: '/tp',
      configDir: '/cfg',
      bundlePoolDir: '/pool',
      enabledPluginIds: enabledPluginIds,
      installedCatalog: const [
        Plugin(
          id: 'local/demo',
          name: 'demo',
          description: '',
          version: '1.0.0',
          directory: 'demo',
          capabilities: PluginCapabilities(),
          installedAt: 0,
          updatedAt: 0,
        ),
      ],
      layout: RuntimeLayout(teampilotRoot: '/tp', fs: fs),
      tool: CliTool.codex,
      hostOneShotRunner: runner,
      executable: '/bin/codex-custom',
    );
  }

  Future<InMemoryFilesystem> seededFs() async {
    final fs = InMemoryFilesystem();
    await fs.writeString(
      '/pool/demo/.claude-plugin/plugin.json',
      jsonEncode({'name': 'demo', 'version': '1.0.0'}),
    );
    await fs.writeString('/pool/demo/skills/demo/SKILL.md', '# demo');
    return fs;
  }

  test(
    'uses Codex native install and keeps CODEX_HOME/plugins untouched',
    () async {
      final fs = await seededFs();
      final runner = _RecordingRunner();

      await const CodexPluginCapability().provision(
        context(fs: fs, runner: runner),
      );

      expect(
        (await fs.stat('/cfg/plugins')).exists,
        isFalse,
        reason: 'TeamPilot must not materialize Codex managed plugins',
      );
      final marketplace = await fs.readString(
        '/cfg/.teampilot/codex-marketplace/.agents/plugins/marketplace.json',
      );
      expect(jsonDecode(marketplace!)['name'], 'teampilot');
      expect(
        (await fs.stat(
          '/cfg/.teampilot/codex-marketplace/plugins/demo/skills/demo/SKILL.md',
        )).isFile,
        isTrue,
      );
      expect(runner.calls.map((call) => call.arguments), [
        [
          'plugin',
          'marketplace',
          'add',
          '/cfg/.teampilot/codex-marketplace',
          '--json',
        ],
        ['plugin', 'list', '--json'],
        ['plugin', 'add', 'demo@teampilot', '--json'],
      ]);
      expect(
        runner.calls.every((call) => call.environment?['CODEX_HOME'] == '/cfg'),
        isTrue,
      );
      expect(
        runner.calls.every((call) => call.executable == '/bin/codex-custom'),
        isTrue,
      );
    },
  );

  test(
    'skips native add when the matching version is already installed',
    () async {
      final fs = await seededFs();
      final runner = _RecordingRunner(
        listJson: jsonEncode({
          'installed': [
            {
              'name': 'demo',
              'marketplaceName': 'teampilot',
              'version': '1.0.0',
            },
          ],
        }),
      );

      await const CodexPluginCapability().provision(
        context(fs: fs, runner: runner),
      );

      expect(runner.calls.map((call) => call.arguments), [
        [
          'plugin',
          'marketplace',
          'add',
          '/cfg/.teampilot/codex-marketplace',
          '--json',
        ],
        ['plugin', 'list', '--json'],
      ]);
    },
  );

  test(
    'removes stale TeamPilot installs before adding changed plugins',
    () async {
      final fs = await seededFs();
      final runner = _RecordingRunner(
        listJson: jsonEncode({
          'installed': [
            {
              'name': 'demo',
              'marketplaceName': 'teampilot',
              'version': '0.9.0',
            },
            {'name': 'old', 'marketplaceName': 'teampilot', 'version': '1.0.0'},
          ],
        }),
      );

      await const CodexPluginCapability().provision(
        context(fs: fs, runner: runner),
      );

      expect(runner.calls.map((call) => call.arguments), [
        [
          'plugin',
          'marketplace',
          'add',
          '/cfg/.teampilot/codex-marketplace',
          '--json',
        ],
        ['plugin', 'list', '--json'],
        ['plugin', 'remove', 'demo@teampilot', '--json'],
        ['plugin', 'remove', 'old@teampilot', '--json'],
        ['plugin', 'add', 'demo@teampilot', '--json'],
      ]);
    },
  );

  test(
    'removes the native marketplace when no plugins remain enabled',
    () async {
      final fs = InMemoryFilesystem();
      final runner = _RecordingRunner(
        listJson: jsonEncode({
          'installed': [
            {
              'name': 'demo',
              'marketplaceName': 'teampilot',
              'version': '1.0.0',
            },
          ],
        }),
        marketplaceListJson: jsonEncode({
          'marketplaces': [
            {'name': 'teampilot'},
          ],
        }),
      );

      await const CodexPluginCapability().provision(
        context(fs: fs, runner: runner, enabledPluginIds: const []),
      );

      expect(runner.calls.map((call) => call.arguments), [
        ['plugin', 'list', '--json'],
        ['plugin', 'remove', 'demo@teampilot', '--json'],
        ['plugin', 'marketplace', 'list', '--json'],
        ['plugin', 'marketplace', 'remove', 'teampilot', '--json'],
      ]);
    },
  );
}
