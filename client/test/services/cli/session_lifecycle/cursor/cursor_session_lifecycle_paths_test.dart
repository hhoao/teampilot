import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/session_lifecycle/cursor/cursor_session_lifecycle_paths.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/provider/cursor/cursor_home_layout.dart';
import 'package:teampilot/services/provider/cursor/cursor_workspace_trust.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

import '../../../../support/in_memory_filesystem.dart';

void main() {
  const workspaceId = 'ws';
  const sessionId = 'sess';
  const workingDirectory = '/home/hhoa/git/hhoa/teampilot';
  const slug = 'home-hhoa-git-hhoa-teampilot';

  group('CursorSessionLifecyclePaths path resolution', () {
    late RuntimeLayout layout;
    late CursorSessionLifecyclePaths paths;

    setUp(() {
      layout = RuntimeLayout(teampilotRoot: '/tp', fs: LocalFilesystem());
      paths = CursorSessionLifecyclePaths(
        fs: LocalFilesystem(),
        layout: layout,
        workspaceId: workspaceId,
        sessionId: sessionId,
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

    test('sharedRoot is under runtime/_shared/cursor', () {
      expect(
        paths.sharedRoot(),
        '/tp/workspace/workspaces/ws/sessions/sess/runtime/_shared/cursor',
      );
    });

    test('sharedAuthDir is under shared root', () {
      expect(
        paths.sharedAuthDir(),
        '/tp/workspace/workspaces/ws/sessions/sess/runtime/_shared/cursor/auth',
      );
    });

    test('sharedProjectsDir(slug) is under shared projects', () {
      expect(
        paths.sharedProjectsDir(slug),
        '/tp/workspace/workspaces/ws/sessions/sess/runtime/_shared/cursor/projects/$slug',
      );
    });

    test('memberHomeRoot points at runtime/{memberId}/cursor/home', () {
      expect(
        paths.memberHomeRoot('team-lead'),
        '/tp/workspace/workspaces/ws/sessions/sess/runtime/team-lead/cursor/home',
      );
      expect(paths.memberHomeRoot('team-lead'), isNot(contains('/_shared/')));
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
        sessionId: sessionId,
        workingDirectory: workingDirectory,
        homeLayout: homeLayout,
      );
    });

    test('ensureSharedDirs creates shared root, auth, and workspace slug dir', () async {
      await paths.ensureSharedDirs();

      expect((await fs.stat(paths.sharedRoot())).isDirectory, isTrue);
      expect((await fs.stat(paths.sharedAuthDir())).isDirectory, isTrue);
      expect((await fs.stat(paths.sharedProjectsDir())).isDirectory, isTrue);
    });

    test('ensureMemberHomeLayout symlinks projects dir to shared projects root', () async {
      await paths.ensureSharedDirs();

      const memberId = 'team-lead';
      await paths.ensureMemberHomeLayout(memberId: memberId);

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
      expect((await fs.stat(homeLayout.cursorDir(memberHome))).isDirectory, isTrue);
      expect(await fs.readSymlinkTarget(memberProjects), sharedProjectsRoot);
    });

    test('linkOrCopyAuth symlinks member .config/cursor to shared auth dir', () async {
      await paths.ensureSharedDirs();
      await fs.writeString(
        fs.pathContext.join(paths.sharedAuthDir(), CursorHomeLayout.authFileName),
        '{"accessToken":"tok"}',
      );

      const memberId = 'architect';
      final memberHome = paths.memberHomeRoot(memberId);
      await fs.ensureDir(memberHome);

      await paths.linkOrCopyAuth(memberHome: memberHome);

      final memberAuthDir = homeLayout.configCursorDir(memberHome);
      expect(await fs.readSymlinkTarget(memberAuthDir), paths.sharedAuthDir());
    });

    test(
      'linkOrCopyAuth copies auth.json when symlink is unavailable',
      () async {
        await paths.ensureSharedDirs();
        const authBody = '{"accessToken":"tok"}';
        await fs.writeString(
          fs.pathContext.join(
            paths.sharedAuthDir(),
            CursorHomeLayout.authFileName,
          ),
          authBody,
        );

        const memberId = 'architect';
        final memberHome = paths.memberHomeRoot(memberId);
        await fs.ensureDir(memberHome);

        final failingFs = _SymlinkFailingFilesystem(fs);
        final copyPaths = CursorSessionLifecyclePaths(
          fs: failingFs,
          layout: layout,
          workspaceId: workspaceId,
          sessionId: sessionId,
          workingDirectory: workingDirectory,
          homeLayout: homeLayout,
        );

        await copyPaths.linkOrCopyAuth(memberHome: memberHome);

        final memberAuthJson = homeLayout.authJson(memberHome);
        expect(await failingFs.readString(memberAuthJson), authBody);
        expect((await failingFs.stat(memberAuthJson)).isFile, isTrue);
      },
      skip: Platform.isWindows ? 'Windows uses junction/copy paths in integration' : false,
    );
  });
}

/// Delegates to [delegate] but refuses symlinks so auth fallback is exercised.
final class _SymlinkFailingFilesystem implements Filesystem {
  _SymlinkFailingFilesystem(this.delegate);

  final Filesystem delegate;

  @override
  get pathContext => delegate.pathContext;

  @override
  Future<FsStat> stat(String path) => delegate.stat(path);

  @override
  Future<void> ensureDir(String path) => delegate.ensureDir(path);

  @override
  Future<void> removeRecursive(String path) => delegate.removeRecursive(path);

  @override
  Future<void> rename(String from, String to) => delegate.rename(from, to);

  @override
  Future<String?> readString(String path) => delegate.readString(path);

  @override
  Future<List<int>?> readBytes(String path) => delegate.readBytes(path);

  @override
  Future<void> writeString(String path, String content) =>
      delegate.writeString(path, content);

  @override
  Future<void> writeBytes(String path, List<int> bytes) =>
      delegate.writeBytes(path, bytes);

  @override
  Future<void> atomicWrite(String path, String content) =>
      delegate.atomicWrite(path, content);

  @override
  Future<List<FsDirEntry>> listDir(String path) => delegate.listDir(path);

  @override
  Future<bool> createSymlink({
    required String target,
    required String linkPath,
  }) async =>
      false;

  @override
  Future<String?> readSymlinkTarget(String linkPath) =>
      delegate.readSymlinkTarget(linkPath);

  @override
  Future<String?> resolveSymlink(String path) => delegate.resolveSymlink(path);

  @override
  Future<void> copyTree({
    required String source,
    required String destination,
  }) =>
      delegate.copyTree(source: source, destination: destination);

  @override
  Future<void> copyFile(String source, String destination) =>
      delegate.copyFile(source, destination);

  @override
  Future<List<FsDirEntry>> listDirRecursive(String path) =>
      delegate.listDirRecursive(path);

  @override
  Future<String> createTempDir({String? prefix, String? parent}) =>
      delegate.createTempDir(prefix: prefix, parent: parent);

  @override
  Future<void> appendString(String path, String content) =>
      delegate.appendString(path, content);
}
