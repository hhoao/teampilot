import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/cli/session_lifecycle/cursor/cursor_session_lifecycle_paths.dart';
import 'package:teampilot/services/cli/registry/resources/cursor_resource_capability.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/provider/cursor/cursor_home_layout.dart';
import 'package:teampilot/services/provider/cursor/cursor_workspace_trust.dart';
import 'package:teampilot/services/provider/cursor/cursor_workspace_warm_tier.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

import '../../../../support/cursor_warm_tier_manifest_paths.dart';
import '../../../../support/in_memory_filesystem.dart';

void main() {
  const workspaceId = 'ws';
  const workingDirectory = '/home/hhoa/git/hhoa/teampilot';
  const slug = 'home-hhoa-git-hhoa-teampilot';
  final pathContext = p.context;
  final teamRuntimeRoot = pathContext.join(
    '/tp',
    'workspace',
    'workspaces',
    workspaceId,
    'runtime',
    'teams',
    cursorTestTeamId,
  );

  group('CursorSessionLifecyclePaths path resolution', () {
    late RuntimeLayout layout;
    late CursorSessionLifecyclePaths paths;

    setUp(() {
      layout = RuntimeLayout(teampilotRoot: '/tp', fs: LocalFilesystem());
      paths = CursorSessionLifecyclePaths(
        fs: LocalFilesystem(),
        layout: layout,
        workspaceId: workspaceId,
        teamId: cursorTestTeamId,
        workingDirectory: workingDirectory,
      );
    });

    test('workspaceSlug matches CursorWorkspaceTrust slugify', () {
      expect(
        paths.workspaceSlug,
        CursorWorkspaceTrust.slugifyWorkspacePath(workingDirectory),
      );
      expect(paths.workspaceSlug, slug);
    });

    test('sharedRoot is under workspace runtime/teams/{teamId}/cursor', () {
      expect(paths.sharedRoot(), pathContext.join(teamRuntimeRoot, 'cursor'));
    });

    test('sharedProjectsDir(slug) is under workspace projects', () {
      expect(
        paths.sharedProjectsDir(slug),
        pathContext.join(teamRuntimeRoot, 'cursor', 'projects', slug),
      );
    });

    test('memberHomeRoot points at team-scoped member cursor home', () {
      expect(
        paths.memberHomeRoot('team-lead'),
        pathContext.join(teamRuntimeRoot, 'team-lead', 'cursor', 'home'),
      );
      expect(paths.memberHomeRoot('team-lead'), isNot(contains('/sessions/')));
    });
  });

  group('CursorSessionLifecyclePaths layout helpers', () {
    late InMemoryFilesystem fs;
    late RuntimeLayout layout;
    late CursorSessionLifecyclePaths paths;
    late CursorHomeLayout homeLayout;

    setUp(() {
      fs = InMemoryFilesystem();
      layout = RuntimeLayout(teampilotRoot: '/tp', fs: fs);
      homeLayout = CursorHomeLayout(pathContext: fs.pathContext);
      paths = CursorSessionLifecyclePaths(
        fs: fs,
        layout: layout,
        workspaceId: workspaceId,
        teamId: cursorTestTeamId,
        workingDirectory: workingDirectory,
        homeLayout: homeLayout,
      );
    });

    test(
      'ensureSharedDirs creates shared root and workspace slug dir',
      () async {
        await paths.ensureSharedDirs();

        expect((await fs.stat(paths.sharedRoot())).isDirectory, isTrue);
        expect((await fs.stat(paths.sharedProjectsDir())).isDirectory, isTrue);
      },
    );

    test(
      'ensureMemberHomeLayout symlinks projects dir to shared projects root',
      () async {
        await paths.ensureSharedDirs();

        const memberId = 'team-lead';
        const realHome = '/home/user';
        await fs.ensureDir(realHome);
        await fs.ensureDir(fs.pathContext.join(realHome, '.rustup'));
        await paths.ensureMemberHomeLayout(
          memberId: memberId,
          realHomeRoot: realHome,
        );

        final memberHome = paths.memberHomeRoot(memberId);
        final memberProjects = fs.pathContext.join(
          homeLayout.cursorDir(memberHome),
          CursorWorkspaceTrust.projectsDirName,
        );
        final sharedProjectsRoot = fs.pathContext.join(
          paths.sharedRoot(),
          CursorWorkspaceTrust.projectsDirName,
        );

        expect((await fs.stat(memberHome)).isDirectory, isTrue);
        expect(
          (await fs.stat(homeLayout.cursorDir(memberHome))).isDirectory,
          isTrue,
        );
        expect(await fs.readSymlinkTarget(memberProjects), sharedProjectsRoot);
        expect(
          await fs.readSymlinkTarget(
            fs.pathContext.join(memberHome, '.rustup'),
          ),
          fs.pathContext.join(realHome, '.rustup'),
        );
      },
    );

    test('ensureSharedDirs creates warm-tier plugin and skills dirs', () async {
      await paths.ensureSharedDirs();

      expect(
        (await fs.stat(paths.sharedPluginsLocalDir())).isDirectory,
        isTrue,
      );
      expect(
        (await fs.stat(paths.sharedPluginsMarketplacesDir())).isDirectory,
        isTrue,
      );
      expect(
        (await fs.stat(paths.sharedSkillsCursorDir())).isDirectory,
        isTrue,
      );
    });

    test(
      'ensureMemberHomeLayout symlinks warm-tier artifacts to shared root',
      () async {
        await paths.ensureSharedDirs();
        await fs.atomicWrite(
          paths.sharedSettingsFile(),
          '{"enabledPlugins":[]}',
        );

        const memberId = 'architect';
        const realHome = '/home/user';
        await fs.ensureDir(realHome);
        await paths.ensureMemberHomeLayout(
          memberId: memberId,
          realHomeRoot: realHome,
        );

        final memberHome = paths.memberHomeRoot(memberId);
        final cursorDir = homeLayout.cursorDir(memberHome);
        final memberPluginsDir = fs.pathContext.join(
          cursorDir,
          CursorWorkspaceWarmTier.pluginsDirName,
        );

        expect(
          await fs.readSymlinkTarget(
            fs.pathContext.join(
              memberPluginsDir,
              CursorWorkspaceWarmTier.localPluginsSegment,
            ),
          ),
          paths.sharedPluginsLocalDir(),
        );
        expect(
          await fs.readSymlinkTarget(
            fs.pathContext.join(
              memberPluginsDir,
              CursorWorkspaceWarmTier.marketplacesSegment,
            ),
          ),
          paths.sharedPluginsMarketplacesDir(),
        );
        expect(
          await fs.readSymlinkTarget(
            fs.pathContext.join(
              cursorDir,
              CursorWorkspaceWarmTier.settingsFileName,
            ),
          ),
          paths.sharedSettingsFile(),
        );
        expect(
          await fs.readSymlinkTarget(
            fs.pathContext.join(
              cursorDir,
              CursorResourceCapability.skillsSubdirName,
            ),
          ),
          paths.sharedSkillsCursorDir(),
        );
      },
    );

    test('ensureMemberAuthDir creates per-member auth directory', () async {
      const memberId = 'architect';
      final memberHome = paths.memberHomeRoot(memberId);
      await fs.ensureDir(memberHome);

      await paths.ensureMemberAuthDir(memberHome: memberHome);

      expect(
        (await fs.stat(homeLayout.configCursorDir(memberHome))).isDirectory,
        isTrue,
      );
      expect((await fs.stat(paths.memberAuthFile(memberHome))).exists, isFalse);
    });
  });
}
