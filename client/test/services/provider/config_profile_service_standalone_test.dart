import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/project_profile.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/cli/registry/config_profile/flashskyai_config_profile_capability.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';
import 'package:teampilot/services/host/host_execution_environment.dart';
import 'package:teampilot/services/storage/runtime_storage_context.dart';

String _standaloneSessionClaudeDir(
  String base,
  String projectId,
  String sessionId,
) =>
    p.join(
      base,
      'workspace',
      'projects',
      projectId,
      'sessions',
      sessionId,
      'runtime',
      'claude',
    );

void main() {
  late Directory base;
  late ConfigProfileService service;

  setUp(() async {
    base = await Directory.systemTemp.createTemp('cfg_profile_standalone_');
    final fs = LocalFilesystem();
    service = ConfigProfileService(
      basePath: base.path,
      fs: fs,
      layout: RuntimeLayout(teampilotRoot: base.path, fs: fs),
      hostEnvironment: HostExecutionEnvironment.resolve(
        isWindowsHost: false,
        storageMode: StorageBackendMode.native,
      ),
    );
  });

  tearDown(() async {
    if (await base.exists()) await base.delete(recursive: true);
  });

  test(
    'prepareProjectLaunch for flashskyai sets FLASHSKYAI_CONFIG_DIR under session runtime',
    () async {
      const projectId = 'proj-standalone-fs';
      const sessionId = 'sess-standalone-fs';
      const profile = ProjectProfile(
        projectId: projectId,
        agent: ProjectAgentConfig(agent: 'solo'),
      );
      const flashskyaiPreset = CliPreset(
        id: 'p-fs',
        name: 'FlashskyAI',
        cli: CliTool.flashskyai,
        provider: '',
        model: '',
        createdAt: 0,
        updatedAt: 0,
      );

      final outcome = await service.prepareProjectLaunch(
        projectId: projectId,
        sessionId: sessionId,
        profile: profile,
        workingDirectory: '/workspace/personal',
        preset: flashskyaiPreset,
      );

      final flashskyaiDir = p.join(
        base.path,
        'workspace',
        'projects',
        projectId,
        'sessions',
        sessionId,
        'runtime',
        'flashskyai',
      );
      expect(await Directory(flashskyaiDir).exists(), isTrue);
      expect(
        outcome.environment[FlashskyaiConfigProfileCapability.configDirEnvKey],
        flashskyaiDir,
      );
      expect(outcome.warnings, isEmpty);
    },
  );

  test(
    'prepareProjectLaunch for claude sets CLAUDE_CONFIG_DIR under session runtime',
    () async {
      const projectId = 'proj-standalone';
      const sessionId = 'sess-standalone';
      const profile = ProjectProfile(
        projectId: projectId,
        // TODO: migrate to presets — cli removed
      );

      final outcome = await service.prepareProjectLaunch(
        projectId: projectId,
        sessionId: sessionId,
        profile: profile,
        workingDirectory: '/workspace/personal',
      );

      final claudeDir = _standaloneSessionClaudeDir(
        base.path,
        projectId,
        sessionId,
      );
      expect(await Directory(claudeDir).exists(), isTrue);
      expect(outcome.environment['CLAUDE_CONFIG_DIR'], claudeDir);
      expect(outcome.warnings, isEmpty);
    },
  );
}
