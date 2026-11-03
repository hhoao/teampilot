import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/services/chat/launch/config_profile_service.dart';
import 'package:teampilot/services/cli/opencode/capabilities/provider.dart';
import 'package:teampilot/services/cli/registry/capabilities/provider_capability.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

import '../../../support/in_memory_filesystem.dart';

/// The launch identity's provider field carries the picked upstream namespace.
/// The config writer must use it verbatim instead of re-deriving it from model
/// membership, otherwise a Go pick can be written to the Zen namespace (and
/// vice versa) and the switch silently does nothing.
void main() {
  late Directory base;
  late LocalFilesystem fs;
  late ConfigProfileService service;
  late OpencodeProviderCapability capability;

  setUp(() async {
    base = await Directory.systemTemp.createTemp('opencode_launch_namespace_');
    fs = LocalFilesystem();
    final home = fakeHomeStorage();
    service = ConfigProfileService(
      basePath: base.path,
      fs: fs,
      layout: RuntimeLayout(teampilotRoot: base.path, fs: fs),
      storage: home,
    );
    final repository = AppProviderRepository(
      basePath: base.path,
      fs: fs,
      storage: home,
    );
    // The merged row: one catalog entry, bound to the Go subscription.
    await repository.saveProviders(CliTool.opencode, const [
      AppProviderConfig(
        id: 'opencode',
        cli: CliTool.opencode,
        name: 'OpenCode',
        apiKey: 'sk-test',
        baseUrl: 'https://opencode.ai/zen/go/v1',
        defaultModel: 'deepseek-v4.1-flash',
        config: {
          'credentialKind': 'apiKey',
          'npm': '@ai-sdk/openai-compatible',
          'opencodeSubscription': 'opencode-go',
        },
      ),
    ]);
    capability = OpencodeProviderCapability(storage: home);
  });

  tearDown(() async {
    if (await base.exists()) await base.delete(recursive: true);
  });

  Future<Object?> launchModel({
    required String sessionId,
    required String provider,
    required String model,
  }) async {
    final member = TeamMemberConfig(
      id: 'solo',
      name: 'solo',
      cli: CliTool.opencode,
      provider: provider,
      model: model,
    );
    final scope = resolveLaunchProfileScope(
      workspaceId: 'workspace-1',
      teamId: '',
      appSessionId: sessionId,
      cliTeamName: sessionId,
      memberId: '',
    );
    await capability.materializeSessionHome(
      sessionHomeContextFromLaunch(
        ConfigProfileLaunchContext(
          workspaceId: 'workspace-1',
          teamId: '',
          sessionId: scope.sessionId,
          scope: scope,
          team: null,
          member: member,
          members: [member],
          paths: service,
          catalog: service,
        ),
        CliTool.opencode,
      ),
    );
    final dir = service.sessionToolDir(
      scope.workspaceId,
      scope.sessionId,
      'opencode',
    );
    final decoded =
        jsonDecode((await fs.readString(p.join(dir, 'opencode.json')))!)
            as Map<String, Object?>;
    return decoded['model'];
  }

  test('a Go pick keeps the Go namespace', () async {
    expect(
      await launchModel(
        sessionId: 'go-model',
        provider: 'opencode',
        model: 'deepseek-v4.1-flash',
      ),
      'opencode-go/deepseek-v4.1-flash',
    );
  });

  test('a Zen pick keeps the Zen namespace', () async {
    expect(
      await launchModel(
        sessionId: 'zen-model',
        provider: 'opencode',
        model: 'deepseek-v4.1-flash-free',
      ),
      'opencode/deepseek-v4.1-flash-free',
    );
  });

  test('a qualified custom id under Go keeps its namespace', () async {
    // Custom ids have no catalog entry, so the pick prefixes the namespace it
    // was typed under.
    expect(
      await launchModel(
        sessionId: 'go-custom',
        provider: 'opencode',
        model: 'opencode-go/company/internal-model',
      ),
      'opencode-go/company/internal-model',
    );
  });

  test('a qualified custom id under Zen keeps its namespace', () async {
    expect(
      await launchModel(
        sessionId: 'zen-custom',
        provider: 'opencode',
        model: 'opencode/company/internal-model',
      ),
      'opencode/company/internal-model',
    );
  });

  test('legacy bare ids still infer the namespace', () async {
    expect(
      await launchModel(
        sessionId: 'legacy-zen-free',
        provider: 'opencode',
        model: 'deepseek-v4.1-flash-free',
      ),
      'opencode/deepseek-v4.1-flash-free',
    );
    expect(
      await launchModel(
        sessionId: 'legacy-go-only',
        provider: 'opencode',
        model: 'hy4-preview',
      ),
      'opencode-go/hy4-preview',
    );
  });

  test('a catalog-id provider still infers from the subscription', () async {
    expect(
      await launchModel(
        sessionId: 'legacy-row',
        provider: 'opencode-go-2',
        model: 'deepseek-v4.1-flash',
      ),
      'opencode-go/deepseek-v4.1-flash',
    );
  });
}
