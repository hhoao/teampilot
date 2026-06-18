import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/workspace_agent_config.dart';
import 'package:teampilot/models/personal_identity.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';
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
  String workspaceId,
  String sessionId,
  String tool,
) =>
    p.join(
      base,
      'workspace',
      'workspaces',
      workspaceId,
      'sessions',
      sessionId,
      'runtime',
      tool,
    );

void main() {
  late Directory base;
  late ConfigProfileService service;
  late RuntimeLayout layout;

  setUp(() async {
    base = await Directory.systemTemp.createTemp('standalone_cap_');
    final fs = LocalFilesystem();
    layout = RuntimeLayout(teampilotRoot: base.path, fs: fs);
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
    required String workspaceId,
    required String sessionId,
    required PersonalIdentity personal,
  }) {
    final standaloneScope = StandaloneLaunchProfileScope(
      workspaceId: workspaceId,
      sessionId: sessionId,
    );
    return ConfigProfileLaunchContext(
      workspaceId: workspaceId,
      teamId: '',
      sessionId: sessionId,
      scope: launchScopeForStandalone(standaloneScope),
      standaloneScope: standaloneScope,
      personal: personal,
      members: const [],
      paths: service,
    );
  }

  test('claude standalone uses standalone session dir without agent-teams env',
      () async {
    const workspaceId = 'p-claude';
    const sessionId = 's-claude';
    const profile = PersonalIdentity(id: workspaceId, display: workspaceId); // TODO: migrate to presets — cli removed

    final contribution = await const ClaudeConfigProfileCapability()
        .contributeLaunch(
          standaloneContext(
            workspaceId: workspaceId,
            sessionId: sessionId,
            personal: profile,
          ),
        );

    final expectedDir = _standaloneToolDir(
      base.path,
      workspaceId,
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
    const workspaceId = 'p-fs';
    const sessionId = 's-fs';
    const profile = PersonalIdentity(id: workspaceId, display: workspaceId,
      // TODO: migrate to presets — cli removed
      agent: WorkspaceAgentConfig(agent: 'solo') // TODO: migrate to presets — model removed,
    );

    final contribution = await const FlashskyaiConfigProfileCapability()
        .contributeLaunch(
          standaloneContext(
            workspaceId: workspaceId,
            sessionId: sessionId,
            personal: profile,
          ),
        );

    final expectedDir = _standaloneToolDir(
      base.path,
      workspaceId,
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
    const workspaceId = 'p-cursor';
    const sessionId = 's-cursor';
    const profile = PersonalIdentity(id: workspaceId, display: workspaceId); // TODO: migrate to presets — cli removed

    final contribution = await const CursorConfigProfileCapability()
        .contributeLaunch(
          standaloneContext(
            workspaceId: workspaceId,
            sessionId: sessionId,
            personal: profile,
          ),
        );

    final expectedDir = _standaloneToolDir(
      base.path,
      workspaceId,
      sessionId,
      'cursor',
    );
    expect(contribution.environment, {'CURSOR_CONFIG_DIR': expectedDir});
    expect(contribution.environment, isNot(contains('HOME')));
  });

  test('opencode standalone sets OPENCODE_CONFIG_DIR without idle plugin', () async {
    const workspaceId = 'p-oc';
    const sessionId = 's-oc';
    const profile = PersonalIdentity(id: workspaceId, display: workspaceId); // TODO: migrate to presets — cli removed

    final contribution = await const OpencodeConfigProfileCapability()
        .contributeLaunch(
          standaloneContext(
            workspaceId: workspaceId,
            sessionId: sessionId,
            personal: profile,
          ),
        );

    final expectedDir = _standaloneToolDir(
      base.path,
      workspaceId,
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
    const workspaceId = 'p-codex';
    const sessionId = 's-codex';
    const profile = PersonalIdentity(id: workspaceId, display: workspaceId); // TODO: migrate to presets — cli removed

    final contribution = await const CodexConfigProfileCapability().contributeLaunch(
      standaloneContext(
        workspaceId: workspaceId,
        sessionId: sessionId,
        personal: profile,
      ),
    );

    final expectedDir = _standaloneToolDir(
      base.path,
      workspaceId,
      sessionId,
      'codex',
    );
    expect(contribution.environment['CODEX_HOME'], expectedDir);
    expect(contribution.warnings, contains('codex_provider_missing'));
  });
}
