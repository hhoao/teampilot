import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/cli/cursor/capabilities/session_lifecycle_paths.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/cli/cursor/provider/cursor_home_layout.dart';
import 'package:teampilot/services/cli/cursor/provider/cursor_workspace_trust.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

import '../../../../support/cursor_warm_tier_manifest_paths.dart';
import '../../../../support/in_memory_filesystem.dart';

void main() {
  const workspaceId = 'ws';
  const workingDirectory = '/home/hhoa/git/hhoa/teampilot';
  const slug = 'home-hhoa-git-hhoa-teampilot';
  String slash(String path) => path.replaceAll(r'\', '/');
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
        sessionId: 'sess',
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

    test('memberHomeRoot points at session-scoped member cursor home', () {
      expect(
        paths.memberHomeRoot('team-lead'),
        pathContext.join(
          '/tp',
          'workspace',
          'workspaces',
          workspaceId,
          'sessions',
          'sess',
          'runtime',
          'team-lead',
          'cursor',
          'home',
        ),
      );
      expect(
        slash(paths.memberHomeRoot('team-lead')),
        contains('/sessions/sess/'),
      );
      expect(
        paths.memberHomeRoot('team-lead'),
        isNot(contains('/runtime/teams/')),
      );
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
        sessionId: 'sess',
        teamId: cursorTestTeamId,
        workingDirectory: workingDirectory,
        homeLayout: homeLayout,
      );
    });

    test('ensureManifestDir creates lifecycle manifest root only', () async {
      await paths.ensureManifestDir();

      expect((await fs.stat(paths.sharedRoot())).isDirectory, isTrue);
    });

    test(
      'ensureMemberHomeLayout creates member cursor resource dirs without passthrough',
      () async {
        const memberId = 'team-lead';
        const realHome = '/home/user';
        await fs.ensureDir(realHome);
        await fs.ensureDir(fs.pathContext.join(realHome, '.rustup'));
        await paths.ensureMemberHomeLayout(memberId: memberId);

        final memberHome = paths.memberHomeRoot(memberId);

        expect((await fs.stat(memberHome)).isDirectory, isTrue);
        expect(
          (await fs.stat(homeLayout.cursorDir(memberHome))).isDirectory,
          isTrue,
        );
        expect(
          (await fs.stat(paths.memberProjectsDir(memberHome))).isDirectory,
          isTrue,
        );
        expect(
          (await fs.stat(paths.memberPluginsLocalDir(memberHome))).isDirectory,
          isTrue,
        );
        expect(
          (await fs.stat(paths.memberSkillsCursorDir(memberHome))).isDirectory,
          isTrue,
        );
        expect(
          await fs.readSymlinkTarget(
            fs.pathContext.join(memberHome, '.rustup'),
          ),
          isNull,
        );
      },
    );

    test('ensureMemberAuthDir creates per-member auth directory', () async {
      const memberId = 'architect';
      final memberHome = paths.memberHomeRoot(memberId);
      await fs.ensureDir(memberHome);

      await paths.ensureMemberAuthDir(memberHome: memberHome);

      // The platform's auth anchor (macOS ~/.cursor, others ~/.config/cursor).
      expect(
        (await fs.stat(homeLayout.authDir(memberHome))).isDirectory,
        isTrue,
      );
      expect((await fs.stat(paths.memberAuthFile(memberHome))).exists, isFalse);
    });
  });
}
