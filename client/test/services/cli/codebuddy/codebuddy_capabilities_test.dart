import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/credential_action_result.dart';
import 'package:teampilot/models/hook_event.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/codebuddy/capabilities/defaults.dart';
import 'package:teampilot/services/cli/codebuddy/capabilities/headless.dart';
import 'package:teampilot/services/cli/codebuddy/capabilities/hook_writer.dart';
import 'package:teampilot/services/cli/codebuddy/capabilities/mcp.dart';
import 'package:teampilot/services/cli/codebuddy/capabilities/provider.dart';
import 'package:teampilot/services/cli/codebuddy/provider/codebuddy_auth_store.dart';
import 'package:teampilot/services/cli/codebuddy/provider_presets.dart';
import 'package:teampilot/services/cli/registry/capabilities/headless_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/interactive_login_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/provider_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/skill_capability.dart';
import 'package:teampilot/services/cli/registry/launch/cli_launch_arg_contribution.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/resources/default_resource_capability.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  group('provider', () {
    const cap = CodebuddyProviderCapability();

    test('official provider id and presets', () {
      expect(cap.catalogCli, CliTool.codebuddy);
      expect(cap.defaultOfficialProviderId, 'codebuddy');
      expect(
        CodebuddyProviderPresets.all.map((p) => p.id),
        containsAll(['codebuddy', 'openai-compatible']),
      );
    });

    test('model candidates include the CLI account catalog', () {
      final models = cap.modelCandidates(
        provider: null,
        providerId: 'codebuddy',
        currentModel: 'custom-model',
      );
      expect(models, contains('hy3'));
      expect(models, contains('custom-model'));
    });

    test('effort is offered only for reasoning models', () {
      expect(cap.isApplicable(model: 'hy3'), isTrue);
      expect(cap.isApplicable(model: 'deepseek-v4.1-flash'), isFalse);
      expect(cap.effortCandidates(model: 'hy3'), [
        'low',
        'medium',
        'high',
        'xhigh',
      ]);
      expect(cap.effortCandidates(model: 'hy4-preview'), ['high']);
      expect(cap.effortCandidates(model: 'deepseek-v4.1-flash'), isEmpty);
    });
  });

  test('skills use the Claude-family skills/ layout and / invocation', () {
    final registry = CliToolRegistry.builtIn();
    final skill = registry.capability<SkillCapability>(CliTool.codebuddy);
    expect(skill, isA<DefaultSkillCapability>());
    expect(skill!.skillsSubdir, 'skills');
    expect(skill.skillInvocationPrefix, '/');
  });

  test('MCP writes the global mcp.json file name', () {
    expect(CodebuddyMcpCapability.metadataFileName, 'mcp.json');
  });

  group('hooks', () {
    const writer = CodebuddyHookWriter();

    test('claims the Claude-family event set', () {
      expect(writer.nativeEvent(HookEvent.preToolUse), 'PreToolUse');
      expect(writer.nativeEvent(HookEvent.stop), 'Stop');
      expect(writer.nativeEvent(HookEvent.subagentStop), 'SubagentStop');
      expect(writer.supportsEvent(HookEvent.preToolUse), isTrue);
    });

    test('shared matrix exposes codebuddy support', () {
      expect(
        HookEventCapability.nativeEvent(
          HookEvent.preToolUse,
          CliTool.codebuddy,
        ),
        'PreToolUse',
      );
      expect(
        HookEventCapability.nativeEvent(
          HookEvent.sessionStart,
          CliTool.codebuddy,
        ),
        'SessionStart',
      );
    });
  });

  group('team / terminal defaults', () {
    test('no native team, mixed seats use the ACP gate', () {
      const team = CodebuddyTeamBehavior();
      expect(team.supportsNativeTeam, isFalse);
      expect(team.requiresPtyFallback, isFalse);
      expect(team.agentPresetStyle, isNull);
      expect(team.doneEventNames, {'Stop', 'StopFailure'});
    });

    test('native commands exist in the CLI command list', () {
      const commands = CodebuddyNativeCommands();
      expect(commands.commands.map((c) => c.name), ['goal', 'compact', 'plan']);
    });
  });

  group('headless', () {
    const cap = CodebuddyHeadlessCapability();

    test('metadata', () {
      expect(cap.executable, 'codebuddy');
      expect(cap.isSupported, isTrue);
      expect(cap.supportsStreaming, isTrue);
      expect(
        cap.buildEnvironment(
          const HeadlessLaunchContext(
            prompt: 'x',
            model: '',
            effort: '',
            configDir: '/cfg',
          ),
        ),
        {'CODEBUDDY_CONFIG_DIR': '/cfg'},
      );
    });

    test('passes -p, model, permission, prompt and stream-json', () {
      final args = _flatten(
        cap.buildHeadlessLaunchArgs(
          const HeadlessLaunchContext(
            prompt: 'hello',
            model: 'hy3',
            effort: 'high',
            configDir: '/cfg',
            stream: true,
          ),
        ),
      );
      expect(args, containsAllInOrder(['-p', '--model', 'hy3', '-y', 'hello']));
      expect(args, containsAllInOrder(['--output-format', 'stream-json']));
    });
  });

  group('auth', () {
    final provider = AppProviderConfig(
      id: 'codebuddy',
      cli: CliTool.codebuddy,
      name: 'CodeBuddy',
      isOfficial: true,
    );

    test('official rows expose the interactive sign-in action', () {
      const cap = CodebuddyProviderCapability();
      expect(cap, isA<InteractiveCliLoginCapability>());
      expect(cap.appliesTo(provider), isTrue);
      final action = cap.actionsFor(provider).single;
      expect(action.kind, ProviderCredentialActionKind.login);
      expect(action.primary, isTrue);
      expect(action.showWhenReady, isTrue);
      expect(cap.hidesApiKeyFields(provider), isTrue);
    });

    test('custom rows keep API-key form fields and no login action', () {
      const cap = CodebuddyProviderCapability();
      final custom = provider.copyWith(isOfficial: false);
      expect(cap.appliesTo(custom), isFalse);
      expect(cap.actionsFor(custom), isEmpty);
      expect(cap.hidesApiKeyFields(custom), isFalse);
    });

    test('records the sign-in token and probes ready afterwards', () async {
      final fs = InMemoryFilesystem();
      final storage = fakeHomeStorage(filesystem: fs, appDataRoot: '/tp');
      final cap = CodebuddyProviderCapability(storage: storage);
      final authDir =
          '/tp/cli-login/codebuddy/codebuddy/home/.local/share/'
          'CodeBuddyExtension/Data/Public/auth';
      await fs.ensureDir(authDir);
      await fs.atomicWrite(
        '$authDir/Tencent-Cloud.coding-copilot.info',
        jsonEncode({
          'auth': {
            'accessToken': 'tok-1',
            'expiresAt': DateTime.now()
                .add(const Duration(days: 10))
                .millisecondsSinceEpoch,
          },
          'account': {'nickname': 'tester'},
        }),
      );

      expect((await cap.probe(provider)).isReady, isFalse);
      final result = await cap.execute(
        providerId: provider.id,
        kind: ProviderCredentialActionKind.login,
      );
      expect(result.ok, isTrue);
      expect(
        (await fs.stat('/tp/providers/codebuddy/codebuddy.auth.json')).isFile,
        isTrue,
      );
      expect((await cap.probe(provider)).isReady, isTrue);
    });

    test('an expired token does not probe ready', () async {
      final fs = InMemoryFilesystem();
      final storage = fakeHomeStorage(filesystem: fs, appDataRoot: '/tp');
      final cap = CodebuddyProviderCapability(storage: storage);
      await fs.ensureDir('/tp/providers/codebuddy');
      await fs.atomicWrite(
        '/tp/providers/codebuddy/codebuddy.auth.json',
        jsonEncode({
          'accessToken': 'tok-expired',
          'expiresAt': DateTime.now()
              .subtract(const Duration(days: 1))
              .millisecondsSinceEpoch,
        }),
      );
      expect((await cap.probe(provider)).isReady, isFalse);
    });

    test('login without any captured auth fails verification', () async {
      final storage = fakeHomeStorage();
      final cap = CodebuddyProviderCapability(storage: storage);
      final result = await cap.execute(
        providerId: provider.id,
        kind: ProviderCredentialActionKind.login,
      );
      expect(result.ok, isFalse);
      expect(result.failure?.code, CredentialActionFailureCode.verifyFailed);
    });

    test('non-login actions are unsupported', () async {
      final storage = fakeHomeStorage();
      final cap = CodebuddyProviderCapability(storage: storage);
      final result = await cap.execute(
        providerId: provider.id,
        kind: ProviderCredentialActionKind.revoke,
      );
      expect(result.ok, isFalse);
      expect(result.failure?.code, CredentialActionFailureCode.unsupported);
    });

    test(
      'seeds the isolated login trust (regression: unmodifiable map)',
      () async {
        final fs = InMemoryFilesystem();
        final store = CodebuddyAuthStore(
          fs: fs,
          basePath: '/tp',
          pathContext: fs.pathContext,
        );
        await store.ensureLoginWorkspace('codebuddy');

        final settingsPath =
            '${store.loginConfigDir('codebuddy')}/settings.json';
        final first =
            jsonDecode((await fs.readString(settingsPath))!)
                as Map<String, Object?>;
        expect(
          first['trustedDirectories'],
          contains(store.loginWorkspace('codebuddy')),
        );

        await fs.atomicWrite(
          settingsPath,
          jsonEncode({
            'model': 'hy3',
            'trustedDirectories': ['/other'],
          }),
        );
        await store.ensureLoginWorkspace('codebuddy');
        final second =
            jsonDecode((await fs.readString(settingsPath))!)
                as Map<String, Object?>;
        expect(second['model'], 'hy3');
        expect(
          second['trustedDirectories'],
          containsAll(['/other', store.loginWorkspace('codebuddy')]),
        );
      },
    );
  });
}

List<String> _flatten(Iterable<CliLaunchArgContribution> contributions) => [
  for (final contribution in contributions) ...contribution.args,
];
