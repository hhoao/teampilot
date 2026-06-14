import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/cli_data_layout.dart';
import 'package:teampilot/services/cli/member_config/member_config_detail.dart';
import 'package:teampilot/services/cli/member_config/member_config_inspector.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;
  late CliDataLayout layout;
  late MemberConfigInspector inspector;

  const member = TeamMemberConfig(
    id: 'm1',
    name: 'Backend',
    provider: 'anthropic',
    model: 'claude-opus-4-8',
  );
  const team = TeamConfig(
    id: 'team-a',
    name: 'Team A',
    cli: CliTool.claude,
    teamMode: TeamMode.mixed,
    members: [member],
  );

  setUp(() {
    fs = InMemoryFilesystem();
    layout = CliDataLayout(teampilotRoot: '/tp', fs: fs);
    inspector = MemberConfigInspector(
      layout: layout,
      fs: fs,
      registry: CliToolRegistry.builtIn(),
    );
  });

  test('prefers the runtime member dir when it exists (mixed mode nests by id)',
      () async {
    final dir = layout.memberToolDir('team-a', 'team-a-1/m1', 'claude');
    await fs.ensureDir(dir);
    await fs.writeString('$dir/skills/a/SKILL.md', '---\nname: A\n---');

    final detail = await inspector.inspect(
      team: team,
      member: member,
      cliTeamName: 'team-a-1',
    );

    expect(detail.sourceLayer, MemberConfigSourceLayer.runtime);
    expect(detail.resolvedDir, dir);
    expect(detail.skills.single.name, 'A');
  });

  test('falls back to the team dir when runtime dir is absent', () async {
    final teamDir = layout.teamToolDir('team-a', 'claude');
    await fs.ensureDir(teamDir);

    final detail = await inspector.inspect(
      team: team,
      member: member,
      cliTeamName: 'team-a-1',
    );

    expect(detail.sourceLayer, MemberConfigSourceLayer.team);
    expect(detail.resolvedDir, teamDir);
  });

  test('returns none when neither layer exists', () async {
    final detail = await inspector.inspect(
      team: team,
      member: member,
      cliTeamName: '',
    );
    expect(detail.sourceLayer, MemberConfigSourceLayer.none);
    expect(detail.hasConfig, isFalse);
  });
}
