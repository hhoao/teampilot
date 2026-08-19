import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/extension/extension_detector.dart';
import 'package:teampilot/services/host/host_execution_environment.dart';
import 'package:teampilot/services/host/script_file_hook_provisioner.dart';
import 'package:teampilot/services/storage/runtime_context.dart';
import 'package:teampilot/models/config_bundle.dart';

const _testWorkspaceId = 'workspace-1';

void main() {
  group('ConfigProfileService extension settings hooks', () {
    late Directory base;
    late ConfigProfileService service;
    late int rtkScriptLoads;

    setUp(() async {
      base = await Directory.systemTemp.createTemp('cfg_profile_rtk_');
      rtkScriptLoads = 0;
      AppPathsBootstrapper.setCurrentForTesting(AppPaths(base.path));
      final fs = LocalFilesystem();
      service = ConfigProfileService(
        basePath: base.path,
        fs: fs,
        layout: RuntimeLayout(teampilotRoot: base.path, fs: fs),
        loadEnabledExtensionIds: ({teamId, workspaceId}) async => {'rtk'},
        extensionDetector: ExtensionDetector(
          processRunner: (executable, arguments, {environment}) async {
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
        hostEnvironment: HostExecutionEnvironment.resolve(
          isWindowsHost: false,
          storageMode: StorageBackendMode.native,
        ),
        extensionHookProvisioners: {
          'rtk-rewrite': ScriptFileHookProvisioner(
            fs: fs,
            runner: HostExecutionEnvironment.resolve(
              isWindowsHost: false,
              storageMode: StorageBackendMode.native,
            ).scriptRunner,
            baseFileName: 'rtk-rewrite',
            loadScript: (_) async {
              rtkScriptLoads += 1;
              return '#!/bin/bash\n# rtk-hook-version: 3\n';
            },
          ),
        },
      );
    });

    tearDown(() async {
      AppPathsBootstrapper.resetForTesting();
      if (await base.exists()) await base.delete(recursive: true);
    });

    test('writes PreToolUse hook when RTK extension enabled', () async {
      final outcome = await service.prepareTeamLaunch(
        workspaceId: _testWorkspaceId,
        sessionId: configProfileAdhocSessionId,
        teamId: 'team-a',
        cliTeamName: 'team-a',
        cli: CliTool.flashskyai,
        runtimeBundle: const ConfigBundle(),
      );

      expect(outcome.warnings, isEmpty);

      final memberDir = p.join(
        base.path,
        'workspace',
        'workspaces',
        _testWorkspaceId,
        'sessions',
        configProfileAdhocSessionId,
        'runtime',
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
      // Task 18 收敛：扩展 settings-hook 走统一 writer（glue 包装，id 前缀
      // 含扩展 id，跨扩展同事件不碰撞）。
      expect(
        command,
        contains(
          'teampilot-hook-teampilot-extension-settings-hook-rtk-'
          'PreToolUse.sh',
        ),
      );
    });

    test('does not collect RTK hooks twice for the launch member', () async {
      const member = TeamMemberConfig(id: 'developer', name: 'Developer');
      const team = TeamProfile(
        id: 'team-a',
        name: 'Team A',
        cli: CliTool.flashskyai,
        members: [member],
        forceTeamLeadDelegateMode: false,
      );

      await service.prepareTeamLaunch(
        workspaceId: _testWorkspaceId,
        sessionId: configProfileAdhocSessionId,
        teamId: team.id,
        cliTeamName: team.id,
        cli: team.cli,
        members: team.members,
        member: member,
        team: team,
        runtimeBundle: const ConfigBundle(),
      );

      expect(rtkScriptLoads, 1);
    });

    test('emits warning when extension enabled but binary missing', () async {
      service = ConfigProfileService(
        basePath: base.path,
        fs: LocalFilesystem(),
        layout: RuntimeLayout(teampilotRoot: base.path, fs: LocalFilesystem()),
        loadEnabledExtensionIds: ({teamId, workspaceId}) async => {'rtk'},
        extensionDetector: ExtensionDetector(processRunner: _alwaysMissing),
      );

      final outcome = await service.prepareTeamLaunch(
        workspaceId: _testWorkspaceId,
        sessionId: configProfileAdhocSessionId,
        teamId: 'team-b',
        cliTeamName: 'team-b',
        cli: CliTool.flashskyai,
        runtimeBundle: const ConfigBundle(),
      );

      expect(outcome.warnings, contains('rtk_enabled_not_found'));
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
