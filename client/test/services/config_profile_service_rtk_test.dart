import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/app_storage.dart';
import 'package:teampilot/services/cli_data_layout.dart';
import 'package:teampilot/services/config_profile_service.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/rtk_detector.dart';
import 'package:teampilot/services/rtk_hook_provisioner.dart';

void main() {
  group('ConfigProfileService RTK', () {
    late Directory base;
    late ConfigProfileService service;

    setUp(() async {
      base = await Directory.systemTemp.createTemp('cfg_profile_rtk_');
      AppPathsBootstrapper.setCurrentForTesting(AppPaths(base.path));
      final fs = LocalFilesystem();
      service = ConfigProfileService(
        basePath: base.path,
        fs: fs,
        layout: CliDataLayout(teampilotRoot: base.path, fs: fs),
        loadRtkEnabled: () async => true,
        rtkDetector: RtkDetector(
          processRunner: (executable, arguments, {environment}) async {
            // RtkDetector locates binaries via `which` on POSIX and `where`
            // on Windows, so match on the queried name rather than the locator.
            const locators = {'which', 'where'};
            if (locators.contains(executable) && arguments.first == 'rtk') {
              return ProcessResult(0, 0, '/usr/bin/rtk\n', '');
            }
            if (locators.contains(executable) && arguments.first == 'jq') {
              return ProcessResult(0, 0, '/usr/bin/jq\n', '');
            }
            if (arguments.contains('--version')) {
              return ProcessResult(0, 0, 'rtk 0.41.0\n', '');
            }
            return ProcessResult(1, 1, '', '');
          },
        ),
        rtkHookProvisioner: RtkHookProvisioner(
          fs: fs,
          loadHookScript: () async => '#!/bin/bash\n# rtk-hook-version: 3\n',
        ),
      );
    });

    tearDown(() async {
      AppPathsBootstrapper.resetForTesting();
      if (await base.exists()) await base.delete(recursive: true);
    });

    test('writes PreToolUse hook when RTK enabled', () async {
      final outcome = await service.prepareTeamLaunch(
        teamId: 'team-a',
        cli: TeamCli.flashskyai,
      );

      expect(outcome.warnings, isEmpty);

      final memberDir = p.join(
        base.path,
        'config-profiles',
        'teams',
        'team-a',
        'members',
        configProfileAdhocSessionId,
        'flashskyai',
      );
      final settingsPath = p.join(memberDir, 'settings.json');
      final hookPath = p.join(memberDir, 'hooks', 'rtk-rewrite.sh');

      expect(File(hookPath).existsSync(), isTrue);

      final settings =
          jsonDecode(File(settingsPath).readAsStringSync())
              as Map<String, dynamic>;
      final pre = (settings['hooks'] as Map)['PreToolUse'] as List;
      expect(pre, isNotEmpty);
      final command =
          ((pre.first as Map)['hooks'] as List).first['command'] as String;
      expect(command, contains('rtk-rewrite.sh'));
    });

    test('emits warning when RTK enabled but binary missing', () async {
      service = ConfigProfileService(
        basePath: base.path,
        fs: LocalFilesystem(),
        layout: CliDataLayout(teampilotRoot: base.path, fs: LocalFilesystem()),
        loadRtkEnabled: () async => true,
        rtkDetector: RtkDetector(processRunner: _alwaysMissing),
      );

      final outcome = await service.prepareTeamLaunch(
        teamId: 'team-b',
        cli: TeamCli.flashskyai,
      );

      expect(outcome.warnings, contains(rtkWarningEnabledNotFound));
    });
  });
}

Future<ProcessResult> _alwaysMissing(
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
}) async {
  return ProcessResult(1, 1, '', '');
}
