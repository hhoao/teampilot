import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/launch_security_policy.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/launch/cli_launch_context.dart';

void main() {
  const nativeTeam = TeamProfile(
    id: 'team',
    name: ' Native Team ',
    teamMode: TeamMode.native,
  );
  const mixedTeam = TeamProfile(
    id: 'mixed',
    name: 'Mixed Team',
    teamMode: TeamMode.mixed,
  );
  const member = TeamMemberConfig(id: ' member-id ', name: 'Member');

  test('copyWith replaces selected launch fields and preserves the rest', () {
    const context = CliLaunchContext(
      team: nativeTeam,
      member: member,
      sessionTeam: 'session-team',
      workingDirectory: r'C:\work',
      additionalDirectories: [r'C:\extra'],
      fixedSessionId: 'fixed',
      resumeSessionId: 'resume',
      settingsPath: '/settings.json',
      appendSystemPromptFile: '/prompt.txt',
      useWslPaths: true,
      nativeAgentTeam: false,
    );

    final copied = context.copyWith(
      workingDirectory: '/workspace',
      additionalDirectories: const ['/shared'],
      resumeSessionId: null,
    );

    expect(copied.team, same(nativeTeam));
    expect(copied.member, same(member));
    expect(copied.sessionTeam, 'session-team');
    expect(copied.workingDirectory, '/workspace');
    expect(copied.additionalDirectories, ['/shared']);
    expect(copied.fixedSessionId, 'fixed');
    expect(copied.resumeSessionId, 'resume');
    expect(copied.settingsPath, '/settings.json');
    expect(copied.appendSystemPromptFile, '/prompt.txt');
    expect(copied.useWslPaths, isTrue);
    expect(copied.nativeAgentTeam, isFalse);
  });

  test('defaults and copies the resolved launch security policy', () {
    const context = CliLaunchContext(team: nativeTeam, member: member);
    expect(context.launchSecurityPolicy, const LaunchSecurityPolicy());

    const fullAccess = LaunchSecurityPolicy.fullAccess;
    expect(
      context.copyWith(launchSecurityPolicy: fullAccess).launchSecurityPolicy,
      fullAccess,
    );
  });

  test(
    'teamName prefers the session team and trims the fallback team name',
    () {
      expect(
        const CliLaunchContext(team: nativeTeam, member: member).teamName,
        'Native Team',
      );
      expect(
        const CliLaunchContext(
          team: nativeTeam,
          member: member,
          sessionTeam: ' runtime-team ',
        ).teamName,
        ' runtime-team ',
      );
    },
  );

  test('memberCliId returns the trimmed roster id', () {
    expect(
      const CliLaunchContext(team: nativeTeam, member: member).memberCliId,
      'member-id',
    );
  });

  test('memberDisplayName returns the trimmed display name', () {
    expect(
      const CliLaunchContext(
        team: nativeTeam,
        member: TeamMemberConfig(id: 'member-id', name: ' Display Name '),
      ).memberDisplayName,
      'Display Name',
    );
  });

  test('usesNativeAgentTeam derives from team mode and honors an override', () {
    expect(
      const CliLaunchContext(
        team: nativeTeam,
        member: member,
      ).usesNativeAgentTeam,
      isTrue,
    );
    expect(
      const CliLaunchContext(
        team: mixedTeam,
        member: member,
      ).usesNativeAgentTeam,
      isFalse,
    );
    expect(
      const CliLaunchContext(
        team: mixedTeam,
        member: member,
        nativeAgentTeam: true,
      ).usesNativeAgentTeam,
      isTrue,
    );
  });

  test('normalizes Windows drive paths for WSL CLIs', () {
    expect(
      normalizePathForCli(r'C:\Users\alice\repo', useWslPaths: true),
      '/mnt/c/Users/alice/repo',
    );
    expect(
      normalizePathForCli(r'\\wsl$\Ubuntu\home\alice', useWslPaths: true),
      '/home/alice',
    );
    expect(
      normalizePathForCli(r'C:\Users\alice\repo', useWslPaths: false),
      r'C:\Users\alice\repo',
    );
  });
}
