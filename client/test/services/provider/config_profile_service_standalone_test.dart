import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/workspace_agent_config.dart';
import 'package:teampilot/models/personal_profile.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/cli/registry/config_profile/flashskyai_config_profile_capability.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';
import 'package:teampilot/services/provider/cursor/cursor_workspace_trust.dart';
import 'package:teampilot/services/host/host_execution_environment.dart';
import 'package:teampilot/services/storage/runtime_storage_context.dart';

String _standaloneSessionClaudeDir(
  String base,
  String workspaceId,
  String sessionId,
) =>
    p.join(
      base,
      'workspace',
      'workspaces',
      workspaceId,
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
      home: p.join(base.path, 'user-home'),
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
    'prepareWorkspaceLaunch for flashskyai sets FLASHSKYAI_CONFIG_DIR under session runtime',
    () async {
      const workspaceId = 'proj-standalone-fs';
      const sessionId = 'sess-standalone-fs';
      const profile = PersonalProfile(id: workspaceId, display: workspaceId,
        agent: WorkspaceAgentConfig(agent: 'solo'),
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

      final outcome = await service.prepareWorkspaceLaunch(profileId: 'personal-default', 
        workspaceId: workspaceId,
        sessionId: sessionId,
        personal: profile,
        workingDirectory: '/workspace/personal',
        preset: flashskyaiPreset,
      );

      final flashskyaiDir = p.join(
        base.path,
        'workspace',
        'workspaces',
        workspaceId,
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
    'prepareWorkspaceLaunch for claude sets CLAUDE_CONFIG_DIR under session runtime',
    () async {
      const workspaceId = 'proj-standalone';
      const sessionId = 'sess-standalone';
      const profile = PersonalProfile(id: workspaceId, display: workspaceId,
        // TODO: migrate to presets — cli removed
      );

      final outcome = await service.prepareWorkspaceLaunch(profileId: 'personal-default', 
        workspaceId: workspaceId,
        sessionId: sessionId,
        personal: profile,
        workingDirectory: '/workspace/personal',
      );

      final claudeDir = _standaloneSessionClaudeDir(
        base.path,
        workspaceId,
        sessionId,
      );
      expect(await Directory(claudeDir).exists(), isTrue);
      expect(outcome.environment['CLAUDE_CONFIG_DIR'], claudeDir);
      expect(outcome.warnings, isEmpty);
    },
  );

  test(
    'prepareWorkspaceLaunch for cursor pre-trusts workspace under runtime home',
    () async {
      const workspaceId = 'proj-standalone-cursor';
      const sessionId = 'sess-standalone-cursor';
      const workspace = '/home/hhoa/git/hhoa/teampilot';
      const profile = PersonalProfile(id: workspaceId, display: workspaceId,
        agent: WorkspaceAgentConfig(agent: 'solo'),
      );
      const cursorPreset = CliPreset(
        id: 'p-cursor',
        name: 'Cursor',
        cli: CliTool.cursor,
        provider: '',
        model: '',
        createdAt: 0,
        updatedAt: 0,
      );

      final outcome = await service.prepareWorkspaceLaunch(profileId: 'personal-default', 
        workspaceId: workspaceId,
        sessionId: sessionId,
        personal: profile,
        workingDirectory: workspace,
        preset: cursorPreset,
      );

      final cursorDir = p.join(
        base.path,
        'workspace',
        'workspaces',
        workspaceId,
        'sessions',
        sessionId,
        'runtime',
        'cursor',
      );
      final home = p.join(cursorDir, 'home');
      expect(await Directory(cursorDir).exists(), isTrue);
      expect(outcome.environment['HOME'], home);
      expect(outcome.environment['CURSOR_CONFIG_DIR'], p.join(home, '.cursor'));
      expect(outcome.warnings, isEmpty);

      final trustPath = CursorWorkspaceTrust.trustMarkerPath(home, workspace);
      expect(await File(trustPath).exists(), isTrue);
    },
  );
}
