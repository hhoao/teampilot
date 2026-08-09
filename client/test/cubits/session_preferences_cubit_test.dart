import 'package:teampilot/cubits/session_preferences_cubit.dart';
import 'package:teampilot/models/session_preferences.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/session_preferences_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<SessionPreferencesCubit> makeCubit({
    Map<CliTool, String> locatedExecutables = const {},
    Map<String, String> locatedToolchains = const {},
  }) async {
    final prefs = await SharedPreferences.getInstance();
    return SessionPreferencesCubit(
      repository: SessionPreferencesRepository(prefs),
      locatedExecutables: locatedExecutables,
      locatedToolchains: locatedToolchains,
    );
  }

  test('resolveExecutable prefers user path over located path', () async {
    final cubit = await makeCubit(
      locatedExecutables: const {
        CliTool.flashskyai: '/usr/local/bin/flashskyai',
      },
    );
    await cubit.load();
    await cubit.setCliExecutablePathFor(
      CliTool.flashskyai,
      '/opt/custom/flashskyai',
    );

    expect(
      cubit.resolveExecutable(CliTool.flashskyai),
      '/opt/custom/flashskyai',
    );
  });

  test(
    'resolveExecutable falls back to located path when user path empty',
    () async {
      final cubit = await makeCubit(
        locatedExecutables: const {
          CliTool.flashskyai: '/usr/local/bin/flashskyai',
        },
      );
      await cubit.load();

      expect(
        cubit.resolveExecutable(CliTool.flashskyai),
        '/usr/local/bin/flashskyai',
      );
    },
  );

  test(
    'resolveExecutable falls back to bare flashskyai when nothing known',
    () async {
      final cubit = await makeCubit();
      await cubit.load();

      expect(cubit.resolveExecutable(CliTool.flashskyai), 'flashskyai');
    },
  );

  test(
    'setCliExecutablePathFor flashskyai persists and emits new state',
    () async {
      final cubit = await makeCubit();
      await cubit.load();
      await cubit.setCliExecutablePathFor(
        CliTool.flashskyai,
        '/a/b/flashskyai',
      );

      expect(
        cubit.state.preferences.cliExecutablePathFor('flashskyai'),
        '/a/b/flashskyai',
      );

      final cubit2 = await makeCubit();
      await cubit2.load();
      expect(
        cubit2.state.preferences.cliExecutablePathFor('flashskyai'),
        '/a/b/flashskyai',
      );
    },
  );

  test('setAutoLaunchAllMembersOnConnect persists the flag', () async {
    final cubit = await makeCubit();
    await cubit.load();
    await cubit.setAutoLaunchAllMembersOnConnect(true);

    expect(cubit.state.preferences.autoLaunchAllMembersOnConnect, true);
  });

  test('setReclaimIdleTerminals persists the flag', () async {
    final cubit = await makeCubit();
    await cubit.load();
    await cubit.setReclaimIdleTerminals(false);

    expect(cubit.state.preferences.reclaimIdleTerminals, false);

    final cubit2 = await makeCubit();
    await cubit2.load();
    expect(cubit2.state.preferences.reclaimIdleTerminals, false);
  });

  test('setReclaimIdleTerminalAfterMinutes stores seconds', () async {
    final cubit = await makeCubit();
    await cubit.load();
    await cubit.setReclaimIdleTerminalAfterMinutes(2);

    expect(cubit.state.preferences.reclaimIdleTerminalAfterSeconds, 120);
  });

  test('setScopeSessionsToSelectedTeam persists the flag', () async {
    final cubit = await makeCubit();
    await cubit.load();
    await cubit.setScopeSessionsToSelectedTeam(true);

    expect(cubit.state.preferences.scopeSessionsToSelectedTeam, true);

    final cubit2 = await makeCubit();
    await cubit2.load();
    expect(cubit2.state.preferences.scopeSessionsToSelectedTeam, true);
  });

  test(
    'terminalLinkClickOpensInApp defaults to true and persists toggle',
    () async {
      final cubit = await makeCubit();
      await cubit.load();
      expect(cubit.state.preferences.terminalLinkClickOpensInApp, true);

      await cubit.setTerminalLinkClickOpensInApp(false);
      expect(cubit.state.preferences.terminalLinkClickOpensInApp, false);

      final cubit2 = await makeCubit();
      await cubit2.load();
      expect(cubit2.state.preferences.terminalLinkClickOpensInApp, false);
    },
  );

  test('notifyOnSessionIdle defaults to true and persists toggle', () async {
    final cubit = await makeCubit();
    await cubit.load();
    expect(cubit.state.preferences.notifyOnSessionIdle, true);

    await cubit.setNotifyOnSessionIdle(false);
    expect(cubit.state.preferences.notifyOnSessionIdle, false);

    final cubit2 = await makeCubit();
    await cubit2.load();
    expect(cubit2.state.preferences.notifyOnSessionIdle, false);
  });

  test(
    'simpleModeDefaultFullAccess defaults to true and persists toggle',
    () async {
      final cubit = await makeCubit();
      await cubit.load();
      expect(cubit.state.preferences.simpleModeDefaultFullAccess, true);

      await cubit.setSimpleModeDefaultFullAccess(false);
      expect(cubit.state.preferences.simpleModeDefaultFullAccess, false);

      final cubit2 = await makeCubit();
      await cubit2.load();
      expect(cubit2.state.preferences.simpleModeDefaultFullAccess, false);
    },
  );

  test(
    'setDefaultSshWorkingDirectory persists the remote default cwd',
    () async {
      final cubit = await makeCubit();
      await cubit.load();
      await cubit.setDefaultSshWorkingDirectory(' ~/work ');

      expect(cubit.state.preferences.defaultSshWorkingDirectory, '~/work');

      final cubit2 = await makeCubit();
      await cubit2.load();
      expect(cubit2.state.preferences.defaultSshWorkingDirectory, '~/work');
    },
  );

  test('setSshUseLoginShell persists the shell launch flag', () async {
    final cubit = await makeCubit();
    await cubit.load();
    await cubit.setSshUseLoginShell(true);

    expect(cubit.state.preferences.sshUseLoginShell, true);
  });

  test(
    'setCliExecutablePathFor flashskyai trims whitespace and treats blank as cleared',
    () async {
      final cubit = await makeCubit(
        locatedExecutables: const {CliTool.flashskyai: '/located'},
      );
      await cubit.load();
      await cubit.setCliExecutablePathFor(CliTool.flashskyai, '   ');

      expect(cubit.state.preferences.cliExecutablePathFor('flashskyai'), '');
      expect(cubit.resolveExecutable(CliTool.flashskyai), '/located');
    },
  );

  test(
    'resolveExecutable resolves non-flashskyai tools independently',
    () async {
      final cubit = await makeCubit(
        locatedExecutables: const {
          CliTool.flashskyai: '/usr/local/bin/flashskyai',
          CliTool.claude: '/usr/local/bin/claude',
        },
      );
      await cubit.load();

      expect(
        cubit.resolveExecutable(CliTool.flashskyai),
        '/usr/local/bin/flashskyai',
      );
      expect(cubit.resolveExecutable(CliTool.claude), '/usr/local/bin/claude');
      expect(cubit.resolveExecutable(CliTool.codex), 'codex');
    },
  );

  test('setCliExecutablePathFor persists tool-specific paths', () async {
    final cubit = await makeCubit(
      locatedExecutables: const {CliTool.claude: '/usr/local/bin/claude'},
    );
    await cubit.load();
    await cubit.setCliExecutablePathFor(CliTool.claude, ' /opt/claude ');

    expect(cubit.state.preferences.cliExecutablePaths, {
      'claude': '/opt/claude',
    });
    expect(cubit.resolveExecutable(CliTool.claude), '/opt/claude');

    final cubit2 = await makeCubit();
    await cubit2.load();
    expect(cubit2.state.preferences.cliExecutablePaths, {
      'claude': '/opt/claude',
    });
  });

  test('setCliExecutablePathFor clears blank non-flashskyai paths', () async {
    final cubit = await makeCubit(
      locatedExecutables: const {CliTool.claude: '/usr/local/bin/claude'},
    );
    await cubit.load();
    await cubit.setCliExecutablePathFor(CliTool.claude, '/opt/claude');
    await cubit.setCliExecutablePathFor(CliTool.claude, '   ');

    expect(cubit.state.preferences.cliExecutablePaths, isEmpty);
    expect(cubit.resolveExecutable(CliTool.claude), '/usr/local/bin/claude');
  });

  test('mergeLocatedExecutables bumps revision when paths change', () async {
    final cubit = await makeCubit();
    await cubit.load();
    expect(cubit.state.locatedExecutablesRevision, 0);

    cubit.mergeLocatedExecutables(const {
      CliTool.claude: '/usr/local/bin/claude',
    });
    expect(cubit.state.locatedExecutablesRevision, 1);
    expect(cubit.hasKnownCliExecutable(CliTool.claude), isTrue);

    cubit.mergeLocatedExecutables(const {
      CliTool.claude: '/usr/local/bin/claude',
    });
    expect(cubit.state.locatedExecutablesRevision, 1);
  });

  test('hasKnownCliExecutable is false for bare PATH fallback', () async {
    final cubit = await makeCubit();
    await cubit.load();

    expect(cubit.hasKnownCliExecutable(CliTool.claude), isFalse);
    expect(cubit.resolveExecutable(CliTool.claude), 'claude');
  });

  test('hasKnownCliExecutable is true for configured path', () async {
    final cubit = await makeCubit();
    await cubit.load();
    await cubit.setCliExecutablePathFor(CliTool.claude, '/opt/claude');

    expect(cubit.hasKnownCliExecutable(CliTool.claude), isTrue);
  });

  test('mergeLocatedToolchains bumps revision and resolves path', () async {
    final cubit = await makeCubit();
    await cubit.load();

    cubit.mergeLocatedToolchains(const {
      SessionPreferences.toolchainGit: '/usr/bin/git',
      SessionPreferences.toolchainNode: '/usr/bin/node',
    });

    expect(cubit.state.locatedExecutablesRevision, 1);
    expect(cubit.hasKnownToolchainExecutable(SessionPreferences.toolchainGit, 'git'), isTrue);
    expect(
      cubit.resolveToolchainExecutable(SessionPreferences.toolchainGit, 'git'),
      '/usr/bin/git',
    );
  });

  test('hasKnownToolchainExecutable is true for bare discovered git name', () async {
    final cubit = await makeCubit(
      locatedToolchains: const {SessionPreferences.toolchainGit: 'git'},
    );
    await cubit.load();

    expect(cubit.hasKnownToolchainExecutable(SessionPreferences.toolchainGit, 'git'), isTrue);
  });
}
