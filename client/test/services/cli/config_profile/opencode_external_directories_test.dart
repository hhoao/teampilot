import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/opencode/capabilities/provider.dart';
import 'package:teampilot/services/cli/registry/capabilities/provider_capability.dart';
import 'package:teampilot/services/session/launch_command_builder.dart';
import 'package:teampilot/services/cli/opencode/capabilities/prompt.dart';
import 'package:teampilot/services/cli/registry/capabilities/prompt_capability.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

void main() {
  Future<SessionHomeContribution> contribute(
    OpencodeProviderCapability capability,
    ConfigProfileLaunchContext ctx,
  ) => capability.materializeSessionHome(
    sessionHomeContextFromLaunch(ctx, CliTool.opencode),
  );

  test(
    'mergeOpencodeExternalDirectories adds allow patterns per directory',
    () {
      final merged = mergeOpencodeExternalDirectories(
        <String, Object?>{},
        <String>['/repo/a', '/repo/b'],
      );
      final permission = merged['permission'] as Map;
      final external = (permission['external_directory'] as Map)
          .cast<String, Object?>();
      expect(external, <String, Object?>{
        '/repo/a/**': 'allow',
        '/repo/b/**': 'allow',
      });
    },
  );

  test('external directories remain config-only and are not argv flags', () {
    const team = TeamProfile(id: 'team', name: 'Team', cli: CliTool.opencode);
    const member = TeamMemberConfig(
      id: 'member',
      name: 'Member',
      provider: 'anthropic',
      model: 'claude-sonnet-4',
    );

    expect(
      LaunchCommandBuilder.buildArguments(
        team,
        member,
        workingDirectory: '/work',
        additionalDirectories: ['/repo/a', '/repo/b'],
      ),
      ['--model', 'anthropic/claude-sonnet-4'],
    );
  });

  test(
    'mergeOpencodeExternalDirectories preserves existing permission entries',
    () {
      final merged = mergeOpencodeExternalDirectories(
        <String, Object?>{
          'permission': <String, Object?>{
            'edit': 'deny',
            'external_directory': <String, Object?>{'/existing/**': 'allow'},
          },
        },
        <String>['/repo/a'],
      );
      final permission = merged['permission'] as Map;
      expect(permission['edit'], 'deny');
      final external = (permission['external_directory'] as Map)
          .cast<String, Object?>();
      expect(
        external.keys,
        containsAll(<String>['/existing/**', '/repo/a/**']),
      );
      expect(external['/existing/**'], 'allow');
      expect(external['/repo/a/**'], 'allow');
    },
  );

  test('mergeOpencodeExternalDirectories is idempotent and skips empties', () {
    final once = mergeOpencodeExternalDirectories(<String, Object?>{}, <String>[
      '/repo/a',
      '  ',
    ]);
    final twice = mergeOpencodeExternalDirectories(once, <String>[
      '/repo/a',
      '  ',
    ]);
    expect(twice, once);
  });

  test('OpencodePromptCapability virtualizes the member role spec', () {
    const member = TeamMemberConfig(
      id: 'm1',
      name: 'Member',
      model: 'test',
      responsibilities: 'You are the reviewer.',
    );
    final specs = const OpencodePromptCapability().virtualize(
      const PromptVirtualizeContext(member: member),
    );

    expect(specs, isNotEmpty);
    expect(specs.first.id, 'opencode-member-role');
    expect(specs.first.title, 'Member role');
    expect(specs.first.scope, PromptScope.member);
    expect(specs.first.content, contains('You are the reviewer.'));
  });

  test('OpencodePromptCapability virtualize includes workspace directories '
      'section and mixed addenda matching materialize', () async {
    const member = TeamMemberConfig(
      id: 'm1',
      name: 'Member',
      model: 'test',
      responsibilities: 'You are the reviewer.',
    );
    final specs = const OpencodePromptCapability().virtualize(
      const PromptVirtualizeContext(
        member: member,
        mixed: true,
        additionalDirectories: ['/abs/missing/repo'],
      ),
    );
    expect(specs.single.content, contains('## Workspace directories'));
    expect(specs.single.content, contains('- /abs/missing/repo'));
    expect(specs.single.content, contains('Multi-agent teammate'));
  });

  test('OpencodePromptCapability writes role + dirs into AGENTS.md', () async {
    final base = await Directory.systemTemp.createTemp('opencode_prompt_');
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

    final contribution = await const OpencodePromptCapability().materialize(
      PromptMaterializeContext(
        paths: service,
        scope: scope,
        member: member,
        additionalDirectories: const ['/abs/missing/repo'],
      ),
    );

    expect(contribution.written, isTrue);
    expect(contribution.environment, isEmpty);
    final opencodeDir = service.sessionToolDir(
      scope.workspaceId,
      scope.sessionId,
      'opencode',
      memberId: scope.memberId,
    );
    final agents = await fs.readString(
      '$opencodeDir/${OpencodePromptCapability.agentsFileName}',
    );
    expect(agents, isNotNull);
    expect(agents, contains('You are the reviewer.'));
    expect(agents, contains('## Workspace directories'));
    expect(agents, contains('- /abs/missing/repo'));
  });

  test('OpencodePromptCapability skips without scope', () async {
    final contribution = await const OpencodePromptCapability().materialize(
      const PromptMaterializeContext(),
    );
    expect(contribution.written, isFalse);
  });

  test('OpencodePromptCapability writes dirs-only AGENTS.md for '
      'invalid member', () async {
    final base = await Directory.systemTemp.createTemp('opencode_prompt_');
    addTearDown(() async {
      if (await base.exists()) await base.delete(recursive: true);
    });
    final fs = LocalFilesystem();
    final service = ConfigProfileService(
      basePath: base.path,
      fs: fs,
      layout: RuntimeLayout(teampilotRoot: base.path, fs: fs),
    );
    const member = TeamMemberConfig(id: 'x', name: '');
    final scope = resolveLaunchProfileScope(
      workspaceId: 'workspace-1',
      teamId: 'team-a',
      appSessionId: 'session-1',
      cliTeamName: 'session-1',
      memberId: 'x',
    );

    final contribution = await const OpencodePromptCapability().materialize(
      PromptMaterializeContext(
        paths: service,
        scope: scope,
        member: member,
        additionalDirectories: const ['/abs/missing/repo'],
      ),
    );

    expect(contribution.written, isTrue);
    final opencodeDir = service.sessionToolDir(
      scope.workspaceId,
      scope.sessionId,
      'opencode',
      memberId: scope.memberId,
    );
    final agents = await fs.readString(
      '$opencodeDir/${OpencodePromptCapability.agentsFileName}',
    );
    expect(agents, isNotNull);
    expect(agents, contains('## Workspace directories'));
    expect(agents, contains('- /abs/missing/repo'));
  });

  test('contributeLaunch writes external_directory permission and AGENTS.md '
      'section for additional directories', () async {
    final base = await Directory.systemTemp.createTemp('opencode_dirs_');
    addTearDown(() async {
      if (await base.exists()) await base.delete(recursive: true);
    });
    final sibling = Directory('${base.path}/sibling-repo')..createSync();

    final fs = LocalFilesystem();
    final service = ConfigProfileService(
      basePath: base.path,
      fs: fs,
      layout: RuntimeLayout(teampilotRoot: base.path, fs: fs),
    );

    const member = TeamMemberConfig(id: 'm1', name: 'Member', model: 'test');
    const team = TeamProfile(
      id: 'team-a',
      name: 'agent',
      cli: CliTool.opencode,
      teamMode: TeamMode.native,
      members: [member],
    );
    final scope = resolveLaunchProfileScope(
      workspaceId: 'workspace-1',
      teamId: 'team-a',
      appSessionId: 'session-1',
      cliTeamName: 'session-1',
      memberId: 'm1',
    );

    await contribute(
      const OpencodeProviderCapability(),
      ConfigProfileLaunchContext(
        workspaceId: 'workspace-1',
        teamId: 'team-a',
        sessionId: scope.sessionId,
        scope: scope,
        team: team,
        member: member,
        members: const [member],
        additionalDirectories: const ['/abs/missing/repo', ''],
        paths: service,
        catalog: service,
      ),
    );

    final opencodeDir = service.sessionToolDir(
      scope.workspaceId,
      scope.sessionId,
      'opencode',
      memberId: scope.memberId,
    );

    final agents = await fs.readString(
      '$opencodeDir/${OpencodeProviderCapability.agentsFileName}',
    );
    expect(agents, isNotNull);
    expect(agents, contains('## Workspace directories'));
    expect(agents, contains('- /abs/missing/repo'));
    expect(agents, isNot(contains('-  ')));

    final raw = await fs.readString(
      '$opencodeDir/${OpencodeProviderCapability.opencodeConfigFileName}',
    );
    final config = jsonDecode(raw!) as Map<String, dynamic>;
    final permission = config['permission'] as Map;
    final external = (permission['external_directory'] as Map)
        .cast<String, Object?>();
    expect(external, <String, Object?>{'/abs/missing/repo/**': 'allow'});
    expect(sibling.existsSync(), isTrue);
  });
}
