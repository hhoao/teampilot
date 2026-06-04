import 'package:teampilot/cubits/session_preferences_cubit.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/session_preferences_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<SessionPreferencesCubit> makeCubit({
    String? located,
    Map<TeamCli, String> locatedExecutables = const {},
  }) async {
    final prefs = await SharedPreferences.getInstance();
    return SessionPreferencesCubit(
      repository: SessionPreferencesRepository(prefs),
      locatedExecutable: located,
      locatedExecutables: locatedExecutables,
    );
  }

  test('resolveExecutable prefers user path over located path', () async {
    final cubit = await makeCubit(located: '/usr/local/bin/flashskyai');
    await cubit.load();
    await cubit.setCliExecutablePathFor(
      TeamCli.flashskyai,
      '/opt/custom/flashskyai',
    );

    expect(cubit.resolveExecutable(), '/opt/custom/flashskyai');
  });

  test(
    'resolveExecutable falls back to located path when user path empty',
    () async {
      final cubit = await makeCubit(located: '/usr/local/bin/flashskyai');
      await cubit.load();

      expect(cubit.resolveExecutable(), '/usr/local/bin/flashskyai');
    },
  );

  test(
    'resolveExecutable falls back to bare flashskyai when nothing known',
    () async {
      final cubit = await makeCubit(located: null);
      await cubit.load();

      expect(cubit.resolveExecutable(), 'flashskyai');
    },
  );

  test('setCliExecutablePathFor flashskyai persists and emits new state', () async {
    final cubit = await makeCubit(located: null);
    await cubit.load();
    await cubit.setCliExecutablePathFor(TeamCli.flashskyai, '/a/b/flashskyai');

    expect(
      cubit.state.preferences.cliExecutablePathFor('flashskyai'),
      '/a/b/flashskyai',
    );

    final cubit2 = await makeCubit(located: null);
    await cubit2.load();
    expect(
      cubit2.state.preferences.cliExecutablePathFor('flashskyai'),
      '/a/b/flashskyai',
    );
  });

  test('setAutoLaunchAllMembersOnConnect persists the flag', () async {
    final cubit = await makeCubit(located: null);
    await cubit.load();
    await cubit.setAutoLaunchAllMembersOnConnect(true);

    expect(cubit.state.preferences.autoLaunchAllMembersOnConnect, true);
  });

  test('setScopeSessionsToSelectedTeam persists the flag', () async {
    final cubit = await makeCubit(located: null);
    await cubit.load();
    await cubit.setScopeSessionsToSelectedTeam(true);

    expect(cubit.state.preferences.scopeSessionsToSelectedTeam, true);

    final cubit2 = await makeCubit(located: null);
    await cubit2.load();
    expect(cubit2.state.preferences.scopeSessionsToSelectedTeam, true);
  });

  test(
    'setDefaultSshWorkingDirectory persists the remote default cwd',
    () async {
      final cubit = await makeCubit(located: null);
      await cubit.load();
      await cubit.setDefaultSshWorkingDirectory(' ~/work ');

      expect(cubit.state.preferences.defaultSshWorkingDirectory, '~/work');

      final cubit2 = await makeCubit(located: null);
      await cubit2.load();
      expect(cubit2.state.preferences.defaultSshWorkingDirectory, '~/work');
    },
  );

  test('setSshUseLoginShell persists the shell launch flag', () async {
    final cubit = await makeCubit(located: null);
    await cubit.load();
    await cubit.setSshUseLoginShell(true);

    expect(cubit.state.preferences.sshUseLoginShell, true);
  });

  test(
    'setCliExecutablePathFor flashskyai trims whitespace and treats blank as cleared',
    () async {
      final cubit = await makeCubit(located: '/located');
      await cubit.load();
      await cubit.setCliExecutablePathFor(TeamCli.flashskyai, '   ');

      expect(cubit.state.preferences.cliExecutablePathFor('flashskyai'), '');
      expect(cubit.resolveExecutable(), '/located');
    },
  );

  test(
    'resolveExecutable resolves non-flashskyai tools independently',
    () async {
      final cubit = await makeCubit(
        locatedExecutables: const {
          TeamCli.flashskyai: '/usr/local/bin/flashskyai',
          TeamCli.claude: '/usr/local/bin/claude',
        },
      );
      await cubit.load();

      expect(
        cubit.resolveExecutable(TeamCli.flashskyai),
        '/usr/local/bin/flashskyai',
      );
      expect(cubit.resolveExecutable(TeamCli.claude), '/usr/local/bin/claude');
      expect(cubit.resolveExecutable(TeamCli.codex), 'codex');
    },
  );

  test('setCliExecutablePathFor persists tool-specific paths', () async {
    final cubit = await makeCubit(
      locatedExecutables: const {TeamCli.claude: '/usr/local/bin/claude'},
    );
    await cubit.load();
    await cubit.setCliExecutablePathFor(TeamCli.claude, ' /opt/claude ');

    expect(cubit.state.preferences.cliExecutablePaths, {
      'claude': '/opt/claude',
    });
    expect(cubit.resolveExecutable(TeamCli.claude), '/opt/claude');

    final cubit2 = await makeCubit();
    await cubit2.load();
    expect(cubit2.state.preferences.cliExecutablePaths, {
      'claude': '/opt/claude',
    });
  });

  test('setCliExecutablePathFor clears blank non-flashskyai paths', () async {
    final cubit = await makeCubit(
      locatedExecutables: const {TeamCli.claude: '/usr/local/bin/claude'},
    );
    await cubit.load();
    await cubit.setCliExecutablePathFor(TeamCli.claude, '/opt/claude');
    await cubit.setCliExecutablePathFor(TeamCli.claude, '   ');

    expect(cubit.state.preferences.cliExecutablePaths, isEmpty);
    expect(cubit.resolveExecutable(TeamCli.claude), '/usr/local/bin/claude');
  });
}
