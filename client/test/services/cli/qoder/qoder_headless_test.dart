import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/qoder/capabilities/headless.dart';
import 'package:teampilot/services/cli/registry/capabilities/headless_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/launch/cli_launch_arg_assembler.dart';
import 'package:teampilot/services/storage/home_storage.dart';

import '../../../support/in_memory_filesystem.dart';

const _configDir = '/tmp/headless-qoder';
const _model = 'glm-5.3';

HeadlessLaunchContext _run({
  String prompt = 'P',
  String model = '',
  String effort = '',
  bool stream = false,
  bool expectJson = false,
  bool promptViaStdin = false,
  LaunchSecurityPolicy securityPolicy = LaunchSecurityPolicy.fullAccess,
}) => HeadlessLaunchContext(
  prompt: prompt,
  model: model,
  effort: effort,
  configDir: _configDir,
  stream: stream,
  expectJson: expectJson,
  promptViaStdin: promptViaStdin,
  securityPolicy: securityPolicy,
);

List<String> _assemble(HeadlessLaunchContext ctx) =>
    const CliLaunchArgAssembler().assembleHeadless(
      CliToolRegistry.builtIn().tryGet(CliTool.qoder)!,
      ctx,
    );

void main() {
  group('capability shape', () {
    test('headless is supported and parses a result line', () {
      const cap = QoderHeadlessCapability();
      expect(cap.isSupported, isTrue);
      expect(cap.executable, 'qodercli');
      expect(cap.streamResultText('{"type":"result","result":"OK"}'), 'OK');
    });

    test('streams and accepts prompts on stdin', () {
      const cap = QoderHeadlessCapability();
      expect(cap.supportsStreaming, isTrue);
      expect(cap.supportsPromptStdin, isTrue);
      expect(cap.configFiles(_run()), isEmpty);
    });

    test('pins QODER_CONFIG_DIR and nothing else', () {
      const cap = QoderHeadlessCapability();
      expect(cap.buildEnvironment(_run()), {
        QoderHeadlessCapability.configDirEnvKey: _configDir,
      });
    });
  });

  group('result parsing', () {
    const cap = QoderHeadlessCapability();

    test('ignores non-result and malformed stream lines', () {
      expect(cap.streamResultText('{"type":"assistant"}'), isNull);
      expect(cap.streamResultText('{"type":"result","result":3}'), isNull);
      expect(cap.streamResultText('not json'), isNull);
      expect(cap.streamResultText('{"type":"result","result":"  OK  "}'), 'OK');
    });

    test('unwraps a non-stream JSON envelope', () {
      expect(
        cap.extractText(
          ProcessResult(0, 0, '{"type":"result","result":"Hi"}', ''),
        ),
        'Hi',
      );
    });

    test('falls back to plain stdout and empty output', () {
      expect(cap.extractText(ProcessResult(0, 0, ' plain ', '')), 'plain');
      expect(cap.extractText(ProcessResult(0, 0, '   ', '')), '');
    });
  });

  group('launch args', () {
    test('full access passes -p, the model and the bypass mode', () {
      expect(_assemble(_run(model: _model)), [
        '-p',
        '--model',
        _model,
        '--permission-mode',
        'bypass_permissions',
        'P',
      ]);
      // No model chosen → no flag, so settings.json / the account default wins.
      expect(_assemble(_run()), isNot(contains('--model')));
    });

    test('requesting json selects the non-stream output format', () {
      expect(_assemble(_run(model: _model, expectJson: true)), [
        '-p',
        '--model',
        _model,
        '--permission-mode',
        'bypass_permissions',
        'P',
        '--output-format',
        'json',
      ]);
    });

    test('streaming selects stream-json', () {
      expect(_assemble(_run(model: _model, stream: true)), [
        '-p',
        '--model',
        _model,
        '--permission-mode',
        'bypass_permissions',
        'P',
        '--output-format',
        'stream-json',
      ]);
    });

    test('stdin mode leaves the prompt out of argv', () {
      final args = _assemble(_run(model: _model, promptViaStdin: true));
      expect(args, isNot(contains('P')));
      expect(args.first, '-p');
      expect(args, containsAllInOrder(['--model', _model]));
    });

    test('ask policy falls back to the default permission mode', () {
      // The registry rejects ask for this ACP-only CLI at assembly time, so
      // exercise the contribution directly.
      final args = const QoderHeadlessCapability()
          .buildHeadlessLaunchArgs(
            _run(securityPolicy: LaunchSecurityPolicy.ask),
          )
          .expand((contribution) => contribution.args)
          .toList();
      expect(args, ['-p', '--permission-mode', 'default', 'P']);
    });
  });

  group('provisioning', () {
    late InMemoryFilesystem fs;
    late HomeStorage storage;
    late QoderHeadlessCapability cap;

    setUp(() {
      fs = InMemoryFilesystem();
      storage = fakeHomeStorage(filesystem: fs);
      cap = QoderHeadlessCapability(storage: storage);
    });

    Future<void> seedProviderStore(String providerId, String user) async {
      final dir = '/tp/providers/qoder/$providerId';
      await fs.ensureDir(dir);
      await fs.atomicWrite('$dir/user', user);
      await fs.atomicWrite('$dir/machine_id', 'MID');
    }

    HeadlessProvisionContext provisionCtx({
      String providerId = 'work',
      AppProviderConfig? provider,
      String model = '',
      String effort = '',
    }) => HeadlessProvisionContext(
      provider: provider,
      providerId: providerId,
      model: model,
      effort: effort,
      configDir: _configDir,
    );

    Future<Map<String, Object?>> readSettings() async =>
        jsonDecode((await fs.readString('$_configDir/settings.json'))!)
            as Map<String, Object?>;

    test(
      'writes settings.json and seeds .auth from the provider store',
      () async {
        await seedProviderStore('work', 'USER');
        const provider = AppProviderConfig(
          id: 'work',
          cli: CliTool.qoder,
          name: 'Work',
          isOfficial: true,
          defaultModel: 'glm-5.3',
        );
        // Unrelated keys already on disk must survive the merge.
        await fs.ensureDir(_configDir);
        await fs.atomicWrite(
          '$_configDir/settings.json',
          jsonEncode({'telemetry': false}),
        );

        final result = await cap.provision(
          provisionCtx(
            provider: provider,
            model: 'qwen3.8-flash',
            effort: 'high',
          ),
        );

        expect(result.credentialsReady, isTrue);
        expect(result.warnings, isEmpty);
        expect(result.extraEnvironment, isEmpty);
        final settings = await readSettings();
        expect(settings['model'], 'qwen3.8-flash');
        expect(settings['reasoningEffort'], 'high');
        expect(settings['telemetry'], isFalse);
        expect(await fs.readString('$_configDir/.auth/user'), 'USER');
        expect(await fs.readString('$_configDir/.auth/machine_id'), 'MID');
      },
    );

    test('falls back to the catalog provider model', () async {
      await seedProviderStore('work', 'USER');
      await fs.ensureDir('/tp/providers/qoder');
      await fs.atomicWrite(
        '/tp/providers/qoder/providers.json',
        jsonEncode({
          'providers': {
            'work': {
              'id': 'work',
              'cli': 'qoder',
              'name': 'Work',
              'defaultModel': 'glm-5.3',
            },
          },
        }),
      );

      final result = await cap.provision(provisionCtx());

      expect(result.credentialsReady, isTrue);
      expect((await readSettings())['model'], 'glm-5.3');
      expect(await fs.readString('$_configDir/.auth/user'), 'USER');
    });

    test('seeds from the machine login without writing to it', () async {
      await fs.ensureDir('/home/test/.qoder/.auth');
      await fs.atomicWrite('/home/test/.qoder/.auth/user', 'MACHINE');
      await fs.atomicWrite('/home/test/.qoder/.auth/machine_id', 'M2');
      final machineBefore = await fs.listDirRecursive('/home/test/.qoder');

      final result = await cap.provision(provisionCtx(providerId: 'missing'));

      expect(result.credentialsReady, isTrue);
      expect(await fs.readString('$_configDir/.auth/user'), 'MACHINE');
      expect(await fs.readString('$_configDir/.auth/machine_id'), 'M2');
      expect(
        await fs.listDirRecursive('/home/test/.qoder'),
        machineBefore,
        reason: 'the machine ~/.qoder tree is a read-only copy source',
      );
    });

    test('reports missing credentials when no login exists', () async {
      final result = await cap.provision(provisionCtx(providerId: 'missing'));

      expect(result.credentialsReady, isFalse);
      expect(result.warnings, [
        QoderHeadlessCapability.credentialsMissingWarning,
      ]);
      expect((await fs.stat('$_configDir/.auth')).exists, isFalse);
      // Settings are still written so the CLI can run after an interactive
      // sign-in fills the config dir.
      expect((await fs.stat('$_configDir/settings.json')).isFile, isTrue);
    });
  });
}
