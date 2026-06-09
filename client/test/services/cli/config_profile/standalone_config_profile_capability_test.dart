import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/project_profile.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/cli_data_layout.dart';
import 'package:teampilot/services/cli/registry/config_profile/claude_config_profile_capability.dart';
import 'package:teampilot/services/cli/registry/config_profile/codex_config_profile_capability.dart';
import 'package:teampilot/services/cli/registry/config_profile/cursor_config_profile_capability.dart';
import 'package:teampilot/services/cli/registry/config_profile/flashskyai_config_profile_capability.dart';
import 'package:teampilot/services/cli/registry/config_profile/opencode_config_profile_capability.dart';
import 'package:teampilot/services/cli/registry/config_profile/opencode_idle_plugin.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';

String _standaloneToolDir(
  String base,
  String projectId,
  String sessionId,
  String tool,
) =>
    p.join(
      base,
      'config-profiles',
      'standalone',
      'projects',
      projectId,
      'sessions',
      sessionId,
      tool,
    );

void main() {
  late Directory base;
  late ConfigProfileService service;
  late CliDataLayout layout;

  setUp(() async {
    base = await Directory.systemTemp.createTemp('standalone_cap_');
    final fs = LocalFilesystem();
    layout = CliDataLayout(teampilotRoot: base.path, fs: fs);
    service = ConfigProfileService(
      basePath: base.path,
      fs: fs,
      layout: layout,
    );
  });

  tearDown(() async {
    if (await base.exists()) await base.delete(recursive: true);
  });

  ConfigProfileLaunchContext standaloneContext({
    required String projectId,
    required String sessionId,
    required ProjectProfile profile,
  }) {
    final standaloneScope = StandaloneLaunchProfileScope(
      projectId: projectId,
      sessionId: sessionId,
    );
    return ConfigProfileLaunchContext(
      teamId: '',
      sessionId: sessionId,
      scope: launchScopeForStandalone(standaloneScope),
      standaloneScope: standaloneScope,
      profile: profile,
      members: const [],
      paths: service,
    );
  }

  test('claude standalone uses standalone session dir without agent-teams env',
      () async {
    const projectId = 'p-claude';
    const sessionId = 's-claude';
    const profile = ProjectProfile(projectId: projectId, cli: CliTool.claude);

    final contribution = await const ClaudeConfigProfileCapability()
        .contributeLaunch(
          standaloneContext(
            projectId: projectId,
            sessionId: sessionId,
            profile: profile,
          ),
        );

    final expectedDir = _standaloneToolDir(
      base.path,
      projectId,
      sessionId,
      'claude',
    );
    expect(contribution.environment['CLAUDE_CONFIG_DIR'], expectedDir);
    expect(
      contribution.environment,
      isNot(contains('CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS')),
    );
    expect(await Directory(expectedDir).exists(), isTrue);
  });

  test('flashskyai standalone sets FLASHSKYAI_CONFIG_DIR under standalone path',
      () async {
    const projectId = 'p-fs';
    const sessionId = 's-fs';
    const profile = ProjectProfile(
      projectId: projectId,
      cli: CliTool.flashskyai,
      agent: ProjectAgentConfig(agent: 'solo', model: 'test'),
    );

    final contribution = await const FlashskyaiConfigProfileCapability()
        .contributeLaunch(
          standaloneContext(
            projectId: projectId,
            sessionId: sessionId,
            profile: profile,
          ),
        );

    final expectedDir = _standaloneToolDir(
      base.path,
      projectId,
      sessionId,
      'flashskyai',
    );
    expect(
      contribution.environment[FlashskyaiConfigProfileCapability.configDirEnvKey],
      expectedDir,
    );
    expect(
      contribution.environment[FlashskyaiConfigProfileCapability.sessionHomeDirEnvKey],
      expectedDir,
    );
    expect(contribution.environment['LLM_CONFIG_PATH'], isNotEmpty);
  });

  test('cursor standalone uses CURSOR_CONFIG_DIR only', () async {
    const projectId = 'p-cursor';
    const sessionId = 's-cursor';
    const profile = ProjectProfile(projectId: projectId, cli: CliTool.cursor);

    final contribution = await const CursorConfigProfileCapability()
        .contributeLaunch(
          standaloneContext(
            projectId: projectId,
            sessionId: sessionId,
            profile: profile,
          ),
        );

    final expectedDir = _standaloneToolDir(
      base.path,
      projectId,
      sessionId,
      'cursor',
    );
    expect(contribution.environment, {'CURSOR_CONFIG_DIR': expectedDir});
    expect(contribution.environment, isNot(contains('HOME')));
  });

  test('opencode standalone sets OPENCODE_CONFIG_DIR without idle plugin', () async {
    const projectId = 'p-oc';
    const sessionId = 's-oc';
    const profile = ProjectProfile(projectId: projectId, cli: CliTool.opencode);

    final contribution = await const OpencodeConfigProfileCapability()
        .contributeLaunch(
          standaloneContext(
            projectId: projectId,
            sessionId: sessionId,
            profile: profile,
          ),
        );

    final expectedDir = _standaloneToolDir(
      base.path,
      projectId,
      sessionId,
      'opencode',
    );
    expect(contribution.environment['OPENCODE_CONFIG_DIR'], expectedDir);
    expect(contribution.environment.containsKey('OPENCODE'), isFalse);
    expect(
      await File(p.join(expectedDir, opencodeIdlePluginFileName)).exists(),
      isFalse,
    );
  });

  test('codex standalone sets CODEX_HOME without bus overlay', () async {
    const projectId = 'p-codex';
    const sessionId = 's-codex';
    const profile = ProjectProfile(projectId: projectId, cli: CliTool.codex);

    final contribution = await const CodexConfigProfileCapability().contributeLaunch(
      standaloneContext(
        projectId: projectId,
        sessionId: sessionId,
        profile: profile,
      ),
    );

    final expectedDir = _standaloneToolDir(
      base.path,
      projectId,
      sessionId,
      'codex',
    );
    expect(contribution.environment['CODEX_HOME'], expectedDir);
    expect(contribution.warnings, contains('codex_provider_missing'));
  });
}
