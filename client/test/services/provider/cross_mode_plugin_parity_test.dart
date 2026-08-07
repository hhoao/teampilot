@Tags(['integration'])
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/config_profile/config_profile_scope.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';
import 'package:teampilot/services/team/claude_team_roster_service.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  Future<void> installDemoPlugin() async {
    final fs = AppStorage.fs;
    final root = AppStorage.paths.basePath;
    await fs.ensureDir(
      p.join(root, 'plugins', 'installed', 'demo-bundle', '.plugin'),
    );
    await fs.writeString(
      p.join(
        root,
        'plugins',
        'installed',
        'demo-bundle',
        '.plugin',
        'plugin.json',
      ),
      '{"name":"demo","version":"1.0.0","description":""}',
    );
    await fs.writeString(
      p.join(root, 'plugins', 'plugins.json'),
      jsonEncode({
        'plugins': [
          {
            'id': 'acme/demo',
            'name': 'demo',
            'version': '1.0.0',
            'directory': 'demo-bundle',
          },
        ],
      }),
    );
  }

  Future<Map<String, Object?>> enabledPluginsOf(
    RuntimeLayout layout,
    String workspaceId,
    String sessionId, {
    String? memberId,
  }) async {
    final fs = AppStorage.fs;
    final dir = p.join(
      layout.sessionRuntimeToolDir(
        workspaceId,
        sessionId,
        'claude',
        memberId: memberId,
      ),
      'settings.json',
    );
    final raw = await fs.readString(dir);
    final settings = raw == null ? <String, Object?>{} : (jsonDecode(raw) as Map).cast<String, Object?>();
    return (settings['enabledPlugins'] as Map?)?.cast<String, Object?>() ??
        const {};
  }

  test(
    'the same enabled plugin lands identically in personal, native, and mixed modes',
    () async {
      final fs = AppStorage.fs;
      final root = AppStorage.paths.basePath;
      final layout = RuntimeLayout(teampilotRoot: root, fs: fs);
      await installDemoPlugin();

      final service = ConfigProfileService(
        basePath: root,
        fs: fs,
        layout: layout,
      );

      await service.prepareSimpleSessionLaunch(
        workspaceId: 'p',
        sessionId: 's',
        runtimeBundle: const ConfigBundle(pluginIds: ['acme/demo']),
        member: const TeamMemberConfig(
          id: 'solo',
          name: 'solo',
          cli: CliTool.claude,
        ),
      );

      await service.prepareTeamLaunch(
        workspaceId: 'workspace-1',
        sessionId: 'tn-1',
        teamId: 'tn',
        cliTeamName: 'tn-1',
        cli: CliTool.claude,
        team: const TeamProfile(
          id: 'tn',
          name: 'TN',
          cli: CliTool.claude,
          pluginIds: ['acme/demo'],
        ),
        runtimeBundle: const ConfigBundle(pluginIds: ['acme/demo']),
      );

      const mixedMember = TeamMemberConfig(id: 'm1', name: 'M1');
      await service.prepareTeamLaunch(
        workspaceId: 'workspace-1',
        sessionId: 'tm-1',
        teamId: 'tm',
        cliTeamName: 'tm-1',
        cli: CliTool.claude,
        member: mixedMember,
        team: const TeamProfile(
          id: 'tm',
          name: 'TM',
          cli: CliTool.claude,
          teamMode: TeamMode.mixed,
          pluginIds: ['acme/demo'],
        ),
        runtimeBundle: const ConfigBundle(pluginIds: ['acme/demo']),
      );

      final personal = await enabledPluginsOf(layout, 'p', 's');
      final native = await enabledPluginsOf(layout, 'workspace-1', 'tn-1');

      final mixedSessionId = mixedModeMemberScopeSessionId(
        fs.pathContext,
        'tm-1',
        mixedMember,
      );
      final expectedMixedSessionId = fs.pathContext.join(
        'tm-1',
        ClaudeTeamRosterService.safeClaudePathSegment('m1'),
      );
      expect(mixedSessionId, expectedMixedSessionId);
      final mixed = await enabledPluginsOf(
        layout,
        'workspace-1',
        'tm-1',
        memberId: 'm1',
      );

      expect(personal, contains('demo@local'),
          reason: 'personal mode must register the enabled plugin');
      expect(native, contains('demo@local'),
          reason: 'native team mode must register the enabled plugin');
      expect(mixed, contains('demo@local'),
          reason: 'mixed team mode must register the enabled plugin per-member');

      expect(personal, native,
          reason: 'personal and native must register the same plugins');
      expect(personal, mixed,
          reason: 'personal and mixed must register the same plugins');
    },
  );
}
