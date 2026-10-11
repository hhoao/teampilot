@Tags(['integration', 'cross-platform'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/services/acp/acp_process_transport.dart';
import 'package:teampilot/services/chat/launch/config_profile_service.dart';
import 'package:teampilot/services/cli/claude/capabilities/acp.dart';
import 'package:teampilot/services/cli/claude/claude_bootstrap_entry.dart';
import 'package:teampilot/services/cli/claude/provider/claude_provider_credentials_service.dart';
import 'package:teampilot/services/cli/registry/capabilities/acp_capability.dart';
import 'package:teampilot/services/cli/registry/cli_bootstrap.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/provider/credential_binding.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

import '../support/post_frame_test_harness.dart';

/// Official Claude ACP must launch like PTY: `contributeLaunch` / `ensureLinked`
/// puts OAuth into `CLAUDE_CONFIG_DIR`, and the adapter process must not see
/// an empty `ANTHROPIC_API_KEY` (Dart `Process.start` turns `''` into a set
/// variable; `claude-agent-acp` then reports `_auth/status_update` kind=none
/// "Not logged in" instead of reading the linked credentials).
void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test(
    'Official ACP process env is logged in: linked credentials, no empty ANTHROPIC_API_KEY',
    () async {
      final fs = testHomeStorage.fs;
      final root = testHomeStorage.paths.basePath;
      final home = testHomeStorage.home;
      final layout = RuntimeLayout(teampilotRoot: root, fs: fs);
      const workspaceId = 'ws-acp';
      const sessionId = 'sess-acp';
      const providerId = 'claude-official';

      final credentials = ClaudeProviderCredentialsService(
        storage: testHomeStorage,
        fs: fs,
        basePath: root,
        resolveHomeDirectory: () => home,
      );
      CliToolRegistry.builtIn().configure(
        CliBootstrap({
          CliTool.claude: ClaudeBootstrapEntry(
            credentialsService: credentials,
            acpAuthSource: () => claudeAcpAuthForProvider(
              AppProviderConfig(
                id: providerId,
                cli: CliTool.claude,
                name: 'Official',
                category: AppProviderCategory.official,
                config: withCredentialBinding({
                  'env': <String, String>{},
                }, CredentialBindingKind.linked),
              ),
              credentials,
            ),
          ),
        }, storage: testHomeStorage),
      );

      await AppProviderRepository(
        basePath: root,
        fs: fs,
        storage: testHomeStorage,
      ).saveProviders(CliTool.claude, [
        AppProviderConfig(
          id: providerId,
          cli: CliTool.claude,
          name: 'Official',
          category: AppProviderCategory.official,
          config: withCredentialBinding({
            'env': <String, String>{},
          }, CredentialBindingKind.linked),
        ),
      ]);

      final globalCred = p.join(home, '.claude', '.credentials.json');
      await fs.writeString(
        globalCred,
        jsonEncode({
          'claudeAiOauth': {
            'accessToken': 'oauth-access-token',
            'refreshToken': 'oauth-refresh-token',
            'expiresAt': DateTime.now()
                .add(const Duration(days: 30))
                .millisecondsSinceEpoch,
            'scopes': ['user:inference'],
            'subscriptionType': 'pro',
          },
        }),
      );

      final outcome =
          await ConfigProfileService(
            basePath: root,
            fs: fs,
            layout: layout,
            home: home,
            storage: testHomeStorage,
          ).prepareSimpleSessionLaunch(
            workspaceId: workspaceId,
            sessionId: sessionId,
            runtimeBundle: const ConfigBundle(),
            member: const TeamMemberConfig(
              id: sessionId,
              name: 'solo',
              provider: providerId,
              cli: CliTool.claude,
            ),
            workingDirectory: p.join(root, 'workspace'),
          );

      final sessionToolDir = layout.sessionRuntimeToolDir(
        workspaceId,
        sessionId,
        'claude',
      );
      expect(
        outcome.environment['CLAUDE_CONFIG_DIR'],
        sessionToolDir,
        reason: 'PTY contributeLaunch isolates Official login here',
      );
      expect(outcome.warnings, isNot(contains('claude_credentials_missing')));

      final sessionCred = File(p.join(sessionToolDir, '.credentials.json'));
      expect(
        sessionCred.existsSync(),
        isTrue,
        reason: 'ensureLinked must put OAuth next to CLAUDE_CONFIG_DIR',
      );
      expect(
        sessionCred.readAsStringSync(),
        contains('"accessToken":"oauth-access-token"'),
      );

      final cap = CliToolRegistry.builtIn().capability<AcpCapability>(
        CliTool.claude,
      )!;
      expect(cap, isA<ClaudeAcpCapability>());
      final capabilityEnv = cap.buildEnvironment(
        sessionToolDir: sessionToolDir,
        workingDirectory: p.join(root, 'workspace'),
        baseEnv: {'PATH': '/usr/bin', ...outcome.environment},
      );

      final processEnv = mergeAcpProcessEnvironment(
        capabilityEnv,
        parent: {
          'PATH': '/usr/bin',
          'HOME': home,
          'ANTHROPIC_API_KEY': 'parent-must-not-leak',
          'ANTHROPIC_AUTH_TOKEN': 'parent-must-not-leak',
          'ANTHROPIC_BASE_URL': 'https://parent.example',
        },
      );

      expect(
        processEnv['CLAUDE_CONFIG_DIR'],
        sessionToolDir,
        reason: 'adapter must use the same slot as PTY, not a nested /claude',
      );
      expect(processEnv['CCGUI_CLI_LOGIN_AUTHORIZED'], '1');
      expect(
        processEnv.containsKey('ANTHROPIC_API_KEY'),
        isFalse,
        reason:
            'empty ANTHROPIC_API_KEY is still set in the child and forces '
            'API-key mode; Official OAuth then reports Not logged in',
      );
      expect(processEnv.containsKey('ANTHROPIC_AUTH_TOKEN'), isFalse);
      expect(processEnv.containsKey('ANTHROPIC_BASE_URL'), isFalse);
    },
  );
}
