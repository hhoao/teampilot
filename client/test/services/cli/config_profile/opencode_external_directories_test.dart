import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/opencode/capabilities/config_profile.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

void main() {
  test('mergeOpencodeExternalDirectories adds allow patterns per directory', () {
    final merged = mergeOpencodeExternalDirectories(
      <String, Object?>{},
      <String>['/repo/a', '/repo/b'],
    );
    final permission = merged['permission'] as Map;
    final external = (permission['external_directory'] as Map)
        .cast<String, Object?>();
    expect(external, <String, Object?>{
      '/repo/a/**': 'allow',
      '/repo/b/**': 'allow',
    });
  });

  test(
    'mergeOpencodeExternalDirectories preserves existing permission entries',
    () {
      final merged = mergeOpencodeExternalDirectories(
        <String, Object?>{
          'permission': <String, Object?>{
            'edit': 'deny',
            'external_directory': <String, Object?>{
              '/existing/**': 'allow',
            },
          },
        },
        <String>['/repo/a'],
      );
      final permission = merged['permission'] as Map;
      expect(permission['edit'], 'deny');
      final external = (permission['external_directory'] as Map)
          .cast<String, Object?>();
      expect(external.keys, containsAll(<String>['/existing/**', '/repo/a/**']));
      expect(external['/existing/**'], 'allow');
      expect(external['/repo/a/**'], 'allow');
    },
  );

  test('mergeOpencodeExternalDirectories is idempotent and skips empties', () {
    final once = mergeOpencodeExternalDirectories(
      <String, Object?>{},
      <String>['/repo/a', '  '],
    );
    final twice = mergeOpencodeExternalDirectories(
      once,
      <String>['/repo/a', '  '],
    );
    expect(twice, once);
  });

  test('composeOpencodeWorkspaceDirectoriesPrompt lists absolute paths', () {
    final prompt = composeOpencodeWorkspaceDirectoriesPrompt(
      <String>['/repo/a', '/repo/b'],
    );
    expect(prompt, contains('## Workspace directories'));
    expect(prompt, contains('- /repo/a'));
    expect(prompt, contains('- /repo/b'));
    expect(prompt, contains('absolute paths'));
  });

  test('composeOpencodeWorkspaceDirectoriesPrompt is empty without dirs', () {
    expect(composeOpencodeWorkspaceDirectoriesPrompt(const []), isEmpty);
    expect(composeOpencodeWorkspaceDirectoriesPrompt(const ['  ']), isEmpty);
  });

  test(
    'contributeLaunch writes external_directory permission and AGENTS.md '
    'section for additional directories',
    () async {
      final base = await Directory.systemTemp.createTemp('opencode_dirs_');
      addTearDown(() async {
        if (await base.exists()) await base.delete(recursive: true);
      });
      final sibling = Directory(
        '${base.path}/sibling-repo',
      )..createSync();

      final fs = LocalFilesystem();
      final service = ConfigProfileService(
        basePath: base.path,
        fs: fs,
        layout: RuntimeLayout(teampilotRoot: base.path, fs: fs),
      );

      const member = TeamMemberConfig(id: 'm1', name: 'Member', model: 'test');
      const team = TeamProfile(
        id: 'team-a',
        name: 'agent',
        cli: CliTool.opencode,
        teamMode: TeamMode.native,
        members: [member],
      );
      final scope = resolveLaunchProfileScope(
        workspaceId: 'workspace-1',
        teamId: 'team-a',
        appSessionId: 'session-1',
        cliTeamName: 'session-1',
        memberId: 'm1',
      );

      await const OpencodeConfigProfileCapability().contributeLaunch(
        ConfigProfileLaunchContext(
          workspaceId: 'workspace-1',
          teamId: 'team-a',
          sessionId: scope.sessionId,
          scope: scope,
          team: team,
          member: member,
          members: const [member],
          additionalDirectories: const ['/abs/missing/repo', ''],
          paths: service,
          catalog: service,
        ),
      );

      final opencodeDir = service.sessionToolDir(
        scope.workspaceId,
        scope.sessionId,
        'opencode',
        memberId: scope.memberId,
      );

      final agents = await fs.readString(
        '$opencodeDir/${OpencodeConfigProfileCapability.agentsFileName}',
      );
      expect(agents, isNotNull);
      expect(agents, contains('## Workspace directories'));
      expect(agents, contains('- /abs/missing/repo'));
      expect(agents, isNot(contains('-  ')));

      final raw = await fs.readString(
        '$opencodeDir/${OpencodeConfigProfileCapability.opencodeConfigFileName}',
      );
      final config = jsonDecode(raw!) as Map<String, dynamic>;
      final permission = config['permission'] as Map;
      final external = (permission['external_directory'] as Map)
          .cast<String, Object?>();
      expect(external, <String, Object?>{
        '/abs/missing/repo/**': 'allow',
      });
      expect(sibling.existsSync(), isTrue);
    },
  );
}
