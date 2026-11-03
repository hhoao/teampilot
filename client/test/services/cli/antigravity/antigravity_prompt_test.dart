import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
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
      p.join(
        '/runtime/sessions/s1/antigravity',
        'home',
        '.gemini',
        'config',
        'rules',
        'teampilot.md',
      ),
    );
  });

  test('provides the member role contribution', () async {
    const member = TeamMemberConfig(
      id: 'm1',
      name: 'Member',
      model: 'test',
      responsibilities: 'You are the reviewer.',
    );
    final specs = await const AntigravityPromptCapability().provide(
      PromptProviderContext(cli: CliTool.antigravity, member: member),
    );

    expect(specs, isNotEmpty);
    expect(specs.first.id, 'antigravity-member-role');
    expect(specs.first.title, 'Member role');
    expect(specs.first.scope, PromptScope.member);
    expect(specs.first.content, contains('You are the reviewer.'));
  });

  test('provider is empty for a null or invalid member', () async {
    final withoutMember = await const AntigravityPromptCapability().provide(
      PromptProviderContext(cli: CliTool.antigravity),
    );
    expect(withoutMember, isEmpty);

    final invalid = await const AntigravityPromptCapability().provide(
      PromptProviderContext(
        cli: CliTool.antigravity,
        member: const TeamMemberConfig(id: 'x', name: ''),
      ),
    );
    expect(invalid, isEmpty);
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
      AntigravityPromptCapability.toolId,
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

  test('removes a stale rules file when the document is empty', () async {
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
      AntigravityPromptCapability.toolId,
      memberId: scope.memberId,
    );
    final path = AntigravityPromptPaths.rulesPath(toolDir);
    await fs.atomicWrite(path, 'stale instructions\n');

    final result = await const AntigravityPromptCapability().materialize(
      PromptMaterializeContext(paths: service, scope: scope),
      document: PromptDocument.empty(),
    );

    expect(result.written, isFalse);
    expect((await fs.stat(path)).exists, isFalse);
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
