import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/pages/team_config/team_config_helpers.dart';

void main() {
  bool supports(CliTool cli) =>
      cli == CliTool.claude || cli == CliTool.flashskyai;

  test('mixed mode hides agent preset until member CLI is chosen', () {
    const mixedTeam = TeamIdentity(
      id: 't',
      name: 'T',
      cli: CliTool.claude,
      teamMode: TeamMode.mixed,
    );
    const inherit = TeamMemberConfig(id: 'm', name: 'dev');
    const withClaude = TeamMemberConfig(
      id: 'm',
      name: 'dev',
      cli: CliTool.claude,
    );
    const withCodex = TeamMemberConfig(
      id: 'm',
      name: 'dev',
      cli: CliTool.codex,
    );

    expect(
      computeMemberShowsAgentPreset(
        team: mixedTeam,
        member: inherit,
        supportsPreset: supports,
      ),
      isFalse,
    );
    expect(
      computeMemberShowsAgentPreset(
        team: mixedTeam,
        member: withClaude,
        supportsPreset: supports,
      ),
      isTrue,
    );
    expect(
      computeMemberShowsAgentPreset(
        team: mixedTeam,
        member: withCodex,
        supportsPreset: supports,
      ),
      isFalse,
    );
  });

  test('native mode follows team CLI for agent preset visibility', () {
    const nativeClaude = TeamIdentity(id: 't', name: 'T', cli: CliTool.claude);
    const nativeCodex = TeamIdentity(id: 't', name: 'T', cli: CliTool.codex);
    const member = TeamMemberConfig(id: 'm', name: 'dev');

    expect(
      computeMemberShowsAgentPreset(
        team: nativeClaude,
        member: member,
        supportsPreset: supports,
      ),
      isTrue,
    );
    expect(
      computeMemberShowsAgentPreset(
        team: nativeCodex,
        member: member,
        supportsPreset: supports,
      ),
      isFalse,
    );
  });
}
