import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/chat/launch/config_profile_service.dart';
import 'package:teampilot/services/cli/antigravity/capabilities/native_commands.dart';
import 'package:teampilot/services/cli/antigravity/capabilities/prompt.dart';
import 'package:teampilot/services/cli/antigravity/capabilities/workspace_base_info.dart';
import 'package:teampilot/services/cli/registry/capabilities/native_command_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/prompt_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/workspace_base_info_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/resource/contribution/resource_origin.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  test('rules path lives under the fake HOME', () {
    expect(
      AntigravityPromptPaths.rulesPath('/runtime/sessions/s1/antigravity'),
      '/runtime/sessions/s1/antigravity/home/.gemini/config/rules/teampilot.md',
    );
  });

  test('materializes the prompt document into the rules file', () async {
    final fs = InMemoryFilesystem();
    final service = ConfigProfileService(
      basePath: '/tp',
      fs: fs,
      layout: RuntimeLayout(teampilotRoot: '/tp', fs: fs),
      storage: fakeHomeStorage(filesystem: fs),
    );
    final scope = resolveLaunchProfileScope(
      workspaceId: 'workspace-1',
      teamId: 'team-a',
      appSessionId: 'session-1',
      cliTeamName: 'session-1',
      memberId: 'm1',
    );
    final toolDir = service.sessionToolDir(
      scope.workspaceId,
      scope.sessionId,
      'antigravity',
      memberId: scope.memberId,
    );

    final result = await const AntigravityPromptCapability().materialize(
      PromptMaterializeContext(paths: service, scope: scope),
      document: _document('Always reply in English.'),
    );

    expect(result.written, isTrue);
    final path = AntigravityPromptPaths.rulesPath(toolDir);
    expect(await fs.stat(path), isNotNull);
    expect(await fs.readString(path), 'Always reply in English.\n');
  });

  test('skips materialization without a scope', () async {
    final fs = InMemoryFilesystem();
    final service = ConfigProfileService(
      basePath: '/tp',
      fs: fs,
      layout: RuntimeLayout(teampilotRoot: '/tp', fs: fs),
      storage: fakeHomeStorage(filesystem: fs),
    );

    final result = await const AntigravityPromptCapability().materialize(
      PromptMaterializeContext(paths: service),
      document: _document('Never written.'),
    );

    expect(result.written, isFalse);
  });

  test('antigravity registers prompt, workspace, and native capabilities', () {
    final registry = CliToolRegistry.builtIn();

    expect(
      registry.capability<PromptCapability>(CliTool.antigravity),
      isA<AntigravityPromptCapability>(),
    );
    expect(
      registry.capability<WorkspaceBaseInfoCapability>(CliTool.antigravity),
      isA<AntigravityWorkspaceBaseInfo>(),
    );
    expect(
      registry.capability<NativeCommandCapability>(CliTool.antigravity),
      isA<AntigravityNativeCommands>(),
    );
    expect(
      registry
          .capability<NativeCommandCapability>(CliTool.antigravity)!
          .commands,
      isEmpty,
    );
  });
}

PromptDocument _document(String content) => PromptDocument([
  PromptSection(
    id: 'test',
    title: 'Test',
    scope: PromptScope.member,
    contributions: [
      PromptContribution(
        id: 'test-contribution',
        title: 'Test',
        content: content,
        origin: const ContributionOrigin(
          providerId: 'test',
          kind: ResourceOriginKind.cliBuiltIn,
          sourceId: 'test',
        ),
      ),
    ],
  ),
]);
