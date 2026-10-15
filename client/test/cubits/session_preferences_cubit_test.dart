import 'package:teampilot/cubits/session_preferences_cubit.dart';
import 'package:teampilot/models/cli_binary_kind.dart';
import 'package:teampilot/models/launch_security_policy.dart';
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
    Map<CliTool, String> locatedAcpAdapters = const {},
    Map<String, String> locatedToolchains = const {},
  }) async {
    final prefs = await SharedPreferences.getInstance();
    return SessionPreferencesCubit(
      repository: SessionPreferencesRepository(prefs),
      locatedExecutables: locatedExecutables,
      locatedAcpAdapters: locatedAcpAdapters,
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

  test('setClaudePersonalAcpDefault persists the flag', () async {
    final cubit = await makeCubit();
    await cubit.load();
    expect(cubit.state.preferences.claudePersonalAcpDefault, true);

    await cubit.setClaudePersonalAcpDefault(false);
    expect(cubit.state.preferences.claudePersonalAcpDefault, false);

    final cubit2 = await makeCubit();
    await cubit2.load();
    expect(cubit2.state.preferences.claudePersonalAcpDefault, false);
  });

  test('setCursorPersonalAcpDefault persists the flag', () async {
    final cubit = await makeCubit();
    await cubit.load();
    expect(cubit.state.preferences.cursorPersonalAcpDefault, true);

    await cubit.setCursorPersonalAcpDefault(false);
    expect(cubit.state.preferences.cursorPersonalAcpDefault, false);

    final cubit2 = await makeCubit();
    await cubit2.load();
    expect(cubit2.state.preferences.cursorPersonalAcpDefault, false);
  });

  test('setOpencodePersonalAcpDefault persists the flag', () async {
    final cubit = await makeCubit();
    await cubit.load();
    expect(cubit.state.preferences.opencodePersonalAcpDefault, true);

    await cubit.setOpencodePersonalAcpDefault(false);
    expect(cubit.state.preferences.opencodePersonalAcpDefault, false);

    final cubit2 = await makeCubit();
    await cubit2.load();
    expect(cubit2.state.preferences.opencodePersonalAcpDefault, false);
  });

  test('setCodexPersonalAcpDefault persists the flag', () async {
    final cubit = await makeCubit();
    await cubit.load();
    expect(cubit.state.preferences.codexPersonalAcpDefault, true);

    await cubit.setCodexPersonalAcpDefault(false);
    expect(cubit.state.preferences.codexPersonalAcpDefault, false);

    final cubit2 = await makeCubit();
    await cubit2.load();
    expect(cubit2.state.preferences.codexPersonalAcpDefault, false);
    expect(cubit2.state.preferences.claudePersonalAcpDefault, true);
  });

  test('setAcpPermissionDefault persists ask', () async {
    final cubit = await makeCubit();
    await cubit.load();
    expect(
      cubit.state.preferences.acpPermissionDefault,
      LaunchSecurityPolicy.fullAccess,
    );
    await cubit.setAcpPermissionDefault(LaunchSecurityPolicy.ask);
    expect(
      cubit.state.preferences.acpPermissionDefault,
      LaunchSecurityPolicy.ask,
    );
    final cubit2 = await makeCubit();
    await cubit2.load();
    expect(
      cubit2.state.preferences.acpPermissionDefault,
      LaunchSecurityPolicy.ask,
    );
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
    expect(
      cubit.hasKnownToolchainExecutable(SessionPreferences.toolchainGit, 'git'),
      isTrue,
    );
    expect(
      cubit.resolveToolchainExecutable(SessionPreferences.toolchainGit, 'git'),
      '/usr/bin/git',
    );
  });

  test(
    'hasKnownToolchainExecutable is true for bare discovered git name',
    () async {
      final cubit = await makeCubit(
        locatedToolchains: const {SessionPreferences.toolchainGit: 'git'},
      );
      await cubit.load();

      expect(
        cubit.hasKnownToolchainExecutable(
          SessionPreferences.toolchainGit,
          'git',
        ),
        isTrue,
      );
    },
  );

  test(
    'mergeLocatedAcpAdapters bumps revision and ignores bare names',
    () async {
      final cubit = await makeCubit();
      await cubit.load();
      cubit.mergeLocatedAcpAdapters(const {
        CliTool.claude: '/opt/claude-agent-acp',
        CliTool.codex: 'codex-acp',
      });
      expect(
        cubit.discoveredAcpAdapterPath(CliTool.claude),
        '/opt/claude-agent-acp',
      );
      expect(cubit.hasKnownAcpAdapter(CliTool.claude), isTrue);
      expect(cubit.hasKnownAcpAdapter(CliTool.codex), isFalse);
      final rev = cubit.state.locatedExecutablesRevision;
      cubit.mergeLocatedAcpAdapters(const {
        CliTool.claude: '/opt/claude-agent-acp',
      });
      expect(cubit.state.locatedExecutablesRevision, rev);
    },
  );

  test('setAcpAdapterPathFor persists and beats discovery', () async {
    final cubit = await makeCubit();
    await cubit.load();
    cubit.mergeLocatedAcpAdapters({
      CliTool.claude: '/discovered/claude-agent-acp',
    });
    await cubit.setAcpAdapterPathFor(CliTool.claude, '/opt/claude-agent-acp');
    expect(
      cubit.configuredAcpAdapterPath(CliTool.claude),
      '/opt/claude-agent-acp',
    );
    expect(
      cubit.resolveAcpAdapterPath(CliTool.claude),
      '/opt/claude-agent-acp',
    );
    expect(cubit.hasKnownAcpAdapter(CliTool.claude), isTrue);

    cubit.mergeLocatedAcpAdapters({CliTool.claude: '/other/claude-agent-acp'});
    expect(
      cubit.resolveAcpAdapterPath(CliTool.claude),
      '/opt/claude-agent-acp',
    );
    expect(
      cubit.state.preferences.acpAdapterPaths['claude'],
      '/opt/claude-agent-acp',
    );
  });

  test(
    'resolveAcpAdapterPath falls back to discovery when stored empty',
    () async {
      final cubit = SessionPreferencesCubit(
        repository: SessionPreferencesRepository(
          await SharedPreferences.getInstance(),
        ),
        locatedAcpAdapters: const {CliTool.claude: '/usr/bin/claude-agent-acp'},
      );
      await cubit.load();
      expect(cubit.configuredAcpAdapterPath(CliTool.claude), '');
      expect(
        cubit.resolveAcpAdapterPath(CliTool.claude),
        '/usr/bin/claude-agent-acp',
      );
    },
  );

  test('mergeBinaryVersion stores installed and latest per kind', () async {
    final cubit = await makeCubit();
    await cubit.load();
    cubit.mergeBinaryVersion(
      cli: CliTool.claude,
      kind: CliBinaryKind.cli,
      installed: '2.1.4',
      latest: '2.2.0',
    );
    expect(cubit.installedVersion(CliTool.claude, CliBinaryKind.cli), '2.1.4');
    expect(cubit.latestVersion(CliTool.claude, CliBinaryKind.cli), '2.2.0');
  });

  test('setPersonalAcpDefaultFor writes the matching preference', () async {
    final cubit = await makeCubit();
    await cubit.load();
    await cubit.setPersonalAcpDefaultFor(CliTool.cursor, false);
    expect(cubit.personalAcpDefaultFor(CliTool.cursor), isFalse);
    expect(cubit.state.preferences.cursorPersonalAcpDefault, isFalse);
  });
}
