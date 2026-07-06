import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/launch/launch_manifest.dart';
import 'package:teampilot/services/launch/launch_manifest_paths.dart';
import 'package:teampilot/services/provider/cursor/cursor_launch_environment.dart';
import 'package:teampilot/services/session/session_lifecycle_service.dart';
import 'package:teampilot/services/storage/app_storage.dart';

import '../../support/in_memory_filesystem.dart';
import '../../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test('workPathContextFor uses POSIX when work root is remote', () {
    final windowsFs = InMemoryFilesystem(
      pathContext: p.Context(style: p.Style.windows),
    );
    const workRoot = '/root/.local/share/com.hhoa.teampilot';
    final ctx = workPathContextFor(
      readDelegate: windowsFs,
      workTeampilotRoot: workRoot,
    );
    expect(ctx.style, p.Style.posix);
    expect(
      ctx.join(workRoot, 'workspace', 'workspaces', 'ws1'),
      '/root/.local/share/com.hhoa.teampilot/workspace/workspaces/ws1',
    );
  });

  test('CursorLaunchEnvironment.forMixed normalizes backslashes on remote', () {
    final env = CursorLaunchEnvironment.forMixed(
      homeRoot:
          r'/root/.local/share/com.hhoa.teampilot\workspace\workspaces\ws\sessions\s\runtime\builder\cursor\home',
      useWslPaths: false,
    );
    expect(env['HOME'], contains('/'));
    expect(env['HOME'], isNot(contains(r'\')));
    expect(env['HOME'], env['USERPROFILE']);
  });

  test(
    'stageTeamLaunch emits POSIX manifest paths for Windows control → remote work',
    () async {
      const workRoot = '/root/.local/share/com.hhoa.teampilot';
      final windowsFs = InMemoryFilesystem(
        pathContext: p.Context(style: p.Style.windows),
      );
      final lifecycle = SessionLifecycleService(
        appDataBasePath: AppStorage.paths.basePath,
      );
      final homeRoots = await lifecycle.resolveWorkContextForTargetId('local');
      final svc = await lifecycle.configProfileServiceFor(homeRoots);
      const sessionId = '00000000-0000-4000-8000-000000000099';
      const builder = TeamMemberConfig(
        id: 'builder',
        name: 'builder',
        cli: CliTool.cursor,
      );
      final staged = await svc.stageTeamLaunch(
        readDelegate: windowsFs,
        workTeampilotRoot: workRoot,
        workspaceId: 'ws1',
        sessionId: sessionId,
        teamId: 'team-a',
        cliTeamName: sessionId,
        cli: CliTool.cursor,
        members: const [builder],
        member: builder,
        team: const TeamProfile(
          id: 'team-a',
          name: 'team-a',
          cli: CliTool.claude,
          teamMode: TeamMode.mixed,
          members: [builder],
        ),
      );
      expect(staged.manifest.entries, isNotEmpty);
      for (final entry in staged.manifest.entries) {
        final path = switch (entry) {
          ManifestEnsureDir(:final path) => path,
          ManifestWriteFile(:final path) => path,
          ManifestSymlink(:final linkPath) => linkPath,
          ManifestRemoveRecursive(:final path) => path,
          ManifestRename(:final to) => to,
          ManifestCopyFile(:final destination) => destination,
          ManifestCopyTree(:final destination) => destination,
        };
        if (!path.startsWith(workRoot)) continue;
        expect(path, isNot(contains(r'\')));
      }
    },
  );
}
