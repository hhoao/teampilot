import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/cli/registry/config_profile/flashskyai_config_profile_capability.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';
import 'package:teampilot/services/provider/cursor/cursor_workspace_trust.dart';
import 'package:teampilot/services/provider/cursor/cursor_windows_home_junction.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/host/host_execution_environment.dart';
import 'package:teampilot/services/storage/runtime_context.dart';

import '../../support/post_frame_test_harness.dart';

String _simpleSessionClaudeDir(
  String base,
  String workspaceId,
  String sessionId,
) => p.join(
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
  late LocalFilesystem fs;
  late ConfigProfileService service;

  setUp(() async {
    setUpTestAppStorage();
    base = Directory(AppStorage.paths.basePath);
    fs = LocalFilesystem();
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

  tearDown(() {
    tearDownTestAppStorage();
  });

  test(
    'prepareSimpleSessionLaunch for flashskyai sets FLASHSKYAI_CONFIG_DIR '
    'under session runtime',
    () async {
      const workspaceId = 'proj-simple-fs';
      const sessionId = 'sess-simple-fs';

      final outcome = await service.prepareSimpleSessionLaunch(
        workspaceId: workspaceId,
        sessionId: sessionId,
        runtimeBundle: const ConfigBundle(),
        member: const TeamMemberConfig(
          id: 'solo',
          name: 'solo',
          agent: 'solo',
          cli: CliTool.flashskyai,
        ),
        workingDirectory: '/workspace/simple',
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
    'prepareSimpleSessionLaunch for claude sets CLAUDE_CONFIG_DIR under '
    'session runtime without identities-runtime',
    () async {
      const workspaceId = 'proj-simple';
      const sessionId = 'sess-simple';
      final outcome = await service.prepareSimpleSessionLaunch(
        workspaceId: workspaceId,
        sessionId: sessionId,
        runtimeBundle: const ConfigBundle(),
        member: const TeamMemberConfig(id: 'solo', name: 'solo', agent: 'solo'),
        workingDirectory: '/workspace/simple',
      );

      final claudeDir = _simpleSessionClaudeDir(
        base.path,
        workspaceId,
        sessionId,
      );
      expect(await Directory(claudeDir).exists(), isTrue);
      expect(outcome.environment['CLAUDE_CONFIG_DIR'], claudeDir);
      expect(outcome.warnings, isEmpty);
      expect(
        await Directory(p.join(base.path, 'identities-runtime')).exists(),
        isFalse,
      );
    },
  );

  test(
    'prepareSimpleSessionLaunch for cursor pre-trusts workspace under '
    'runtime home',
    () async {
      const workspaceId = 'proj-simple-cursor';
      const sessionId = 'sess-simple-cursor';
      const workspace = '/home/hhoa/git/hhoa/teampilot';

      await service.provisionWorkspace(
        workspaceId: workspaceId,
        cli: CliTool.cursor,
        trustedDirectories: [workspace],
      );

      final outcome = await service.prepareSimpleSessionLaunch(
        workspaceId: workspaceId,
        sessionId: sessionId,
        runtimeBundle: const ConfigBundle(),
        member: const TeamMemberConfig(
          id: 'solo',
          name: 'solo',
          agent: 'solo',
          cli: CliTool.cursor,
        ),
        workingDirectory: workspace,
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
      final canonicalHome = p.join(cursorDir, 'home');
      final home = await CursorWindowsHomeJunction.ensureAgentHome(
        fs: fs,
        canonicalHome: canonicalHome,
      );
      expect(await Directory(cursorDir).exists(), isTrue);
      expect(outcome.environment['HOME'], home);
      expect(outcome.environment['CURSOR_CONFIG_DIR'], p.join(home, '.cursor'));
      expect(outcome.warnings, isEmpty);

      final trustPath = CursorWorkspaceTrust.trustMarkerPath(home, workspace);
      expect(await File(trustPath).exists(), isTrue);
    },
  );
}
