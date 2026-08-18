import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/codex/capabilities/prompt.dart';
import 'package:teampilot/services/cli/registry/capabilities/prompt_capability.dart';
import 'package:teampilot/services/resource/assemblers/prompt_assembler.dart';
import 'package:teampilot/services/resource/providers/prompt_contribution_provider.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

void main() {
  test('CodexPromptCapability provides the member role contribution', () async {
    const member = TeamMemberConfig(
      id: 'm1',
      name: 'Member',
      model: 'test',
      responsibilities: 'You are the reviewer.',
    );
    final specs = await const CodexPromptCapability().provide(
      PromptProviderContext(cli: CliTool.codex, member: member),
    );

    expect(specs, isNotEmpty);
    expect(specs.first.id, 'codex-member-role');
    expect(specs.first.title, 'Member role');
    expect(specs.first.scope, PromptScope.member);
    expect(specs.first.content, contains('You are the reviewer.'));
  });

  test('CodexPromptCapability writes AGENTS.md under CODEX_HOME', () async {
    final base = await Directory.systemTemp.createTemp('codex_prompt_');
    addTearDown(() async {
      if (await base.exists()) await base.delete(recursive: true);
    });
    final fs = LocalFilesystem();
    final service = ConfigProfileService(
      basePath: base.path,
      fs: fs,
      layout: RuntimeLayout(teampilotRoot: base.path, fs: fs),
    );
    const member = TeamMemberConfig(
      id: 'm1',
      name: 'Member',
      model: 'test',
      responsibilities: 'You are the reviewer.',
    );
    final scope = resolveLaunchProfileScope(
      workspaceId: 'workspace-1',
      teamId: 'team-a',
      appSessionId: 'session-1',
      cliTeamName: 'session-1',
      memberId: 'm1',
    );

    final contribution = await const CodexPromptCapability().materialize(
      PromptMaterializeContext(paths: service, scope: scope, member: member),
      document: await _document(member),
    );

    expect(contribution.written, isTrue);
    expect(contribution.environment, isEmpty);
    final codexHome = service.sessionToolDir(
      scope.workspaceId,
      scope.sessionId,
      'codex',
      memberId: scope.memberId,
    );
    final agents = await fs.readString(
      '$codexHome/${CodexPromptCapability.agentsFileName}',
    );
    expect(agents, isNotNull);
    expect(agents, contains('You are the reviewer.'));
  });

  test('CodexPromptCapability skips without scope', () async {
    const member = TeamMemberConfig(
      id: 'm1',
      name: 'Member',
      model: 'test',
      responsibilities: 'You are the reviewer.',
    );
    final contribution = await const CodexPromptCapability().materialize(
      const PromptMaterializeContext(member: member),
      document: PromptDocument.empty(),
    );
    expect(contribution.written, isFalse);
  });
}

Future<PromptDocument> _document(TeamMemberConfig member) async {
  return (await PromptAssembler().assemble(
    context: PromptProviderContext(cli: CliTool.codex, member: member),
    providers: [const CodexPromptCapability()],
  )).document;
}
