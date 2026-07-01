import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/runtime_context.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';
import 'package:teampilot/services/cli/member_config/member_config_detail.dart';
import 'package:teampilot/services/cli/member_config/member_config_inspector.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;
  late RuntimeLayout layout;
  late MemberConfigInspector inspector;

  const member = TeamMemberConfig(
    id: 'm1',
    name: 'Backend',
    provider: 'anthropic',
    model: 'claude-opus-4-8',
  );
  const team = TeamProfile(
    id: 'team-a',
    name: 'Team A',
    cli: CliTool.claude,
    teamMode: TeamMode.mixed,
    members: [member],
  );

  setUp(() {
    fs = InMemoryFilesystem();
    layout = RuntimeLayout(teampilotRoot: '/tp', fs: fs);
    inspector = MemberConfigInspector(
      layout: layout,
      fs: fs,
      registry: CliToolRegistry.builtIn(),
    );
  });

  test('prefers the runtime member dir when it exists (mixed mode nests by id)',
      () async {
    final dir = layout.sessionRuntimeToolDir(
      'workspace-1',
      'team-a-1',
      'claude',
      memberId: 'm1',
    );
    await fs.ensureDir(dir);
    await fs.writeString('$dir/skills/a/SKILL.md', '---\nname: A\n---');

    final detail = await inspector.inspect(
      workspaceId: 'workspace-1',
      sessionId: 'team-a-1',
      team: team,
      member: member,
    );

    expect(detail.sourceLayer, MemberConfigSourceLayer.runtime);
    expect(detail.resolvedDir, dir);
    expect(detail.skills.single.name, 'A');
  });

  test('falls back to the team dir when runtime dir is absent', () async {
    final teamDir = layout.identityToolDir('team-a', 'claude');
    await fs.ensureDir(teamDir);

    final detail = await inspector.inspect(
      workspaceId: 'workspace-1',
      sessionId: 'team-a-1',
      team: team,
      member: member,
    );

    expect(detail.sourceLayer, MemberConfigSourceLayer.team);
    expect(detail.resolvedDir, teamDir);
  });

  test('returns none when neither layer exists', () async {
    final detail = await inspector.inspect(
      workspaceId: 'workspace-1',
      sessionId: '',
      team: team,
      member: member,
    );
    expect(detail.sourceLayer, MemberConfigSourceLayer.none);
    expect(detail.hasConfig, isFalse);
  });

  test('mixed cursor member resolves cursor runtime home/.cursor via preset',
      () async {
    const cursorMember = TeamMemberConfig(
      id: 'reviewer',
      name: 'Reviewer',
      activePresetId: 'cursor-preset',
    );
    const presets = [
      CliPreset(
        id: 'cursor-preset',
        name: 'Cursor',
        cli: CliTool.cursor,
        provider: 'work',
        model: 'gpt-4',
        createdAt: 1,
        updatedAt: 1,
      ),
    ];

    final detail = await inspector.inspect(
      workspaceId: 'workspace-1',
      sessionId: 'team-a-1',
      team: team,
      member: cursorMember,
      globalPresets: presets,
      preferExpectedRuntimeDir: true,
    );

    final expected = p.join(
      layout.sessionRuntimeToolDir(
        'workspace-1',
        'team-a-1',
        'cursor',
        memberId: 'reviewer',
      ),
      'home',
      '.cursor',
    );
    expect(detail.cli, CliTool.cursor);
    expect(detail.resolvedDir, expected);
    expect(detail.sourceLayer, MemberConfigSourceLayer.runtime);
  });

  test('reads from the member work context when it differs from home', () async {
    final remoteFs = InMemoryFilesystem();
    final remoteLayout = RuntimeLayout(teampilotRoot: '/remote/app', fs: remoteFs);
    final remoteDir = remoteLayout.sessionRuntimeToolDir(
      'workspace-1',
      'team-a-1',
      'claude',
      memberId: 'm1',
    );
    await remoteFs.ensureDir(remoteDir);
    await remoteFs.writeString('$remoteDir/skills/remote/SKILL.md', '---\nname: Remote\n---');

    final detail = await inspector.inspect(
      workspaceId: 'workspace-1',
      sessionId: 'team-a-1',
      team: team,
      member: member,
      workContext: RuntimeContext(
        target: RuntimeTarget.ssh('p1', label: 'box'),
        filesystem: remoteFs,
        home: '/remote',
        cwd: '/remote',
        appDataRoot: '/remote/app',
        paths: AppPaths('/remote/app'),
      ),
    );

    expect(detail.sourceLayer, MemberConfigSourceLayer.runtime);
    expect(detail.resolvedDir, remoteDir);
    expect(detail.skills.single.name, 'Remote');
  });
}
