import 'package:flutter_test/flutter_test.dart';
import 'package:ai_message_core/ai_message_core.dart';
import 'package:teampilot/cubits/editor_cubit.dart';
import 'package:teampilot/cubits/floating_workspace/floating_workspace_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/layout_preferences.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/models/workspace_launch_context.dart';
import 'package:teampilot/services/editor/markdown_view_mode_store.dart';
import 'package:teampilot/services/session/session_lifecycle_service.dart';
import 'package:teampilot/services/storage/runtime_context.dart';
import 'package:teampilot/services/workbench/ai_tool_file_open_coordinator.dart';
import 'package:teampilot/services/workbench/session_member_filesystem.dart';
import 'package:teampilot/services/workbench/workbench_editor_opener.dart';
import 'package:teampilot/services/workspace/workspace_tools_context.dart';
import 'package:teampilot/services/workspace/workspace_tools_scope.dart';

import '../../support/in_memory_filesystem.dart';
import '../../support/test_runtime_context.dart';

void main() {
  const workspaceId = 'ws-1';

  WorkspaceLaunchContext launchCtx(AppSession session) =>
      WorkspaceLaunchContext(
        session: session,
        workspace: Workspace(
          workspaceId: session.workspaceId,
          folders: session.folders,
          createdAt: 0,
        ),
      );

  test(
    'prefers member ssh filesystem over active local tools plane',
    () async {
      final localFs = InMemoryFilesystem();
      final remoteFs = InMemoryFilesystem();
      remoteFs.files['/remote/src/foo.dart'] = 'remote\n';

      final home = testRuntimeContext('/home-root');
      final localCtx = RuntimeContext(
        target: RuntimeTarget.local(),
        filesystem: localFs,
        home: '/local-home',
        cwd: '/local',
        appDataRoot: '/local-home',
        paths: home.paths,
      );
      final lifecycle = SessionLifecycleService(
        storageRootsResolver: () async => localCtx,
        workContextResolver: (target) async {
          if (target.kind == RuntimeKind.ssh) {
            return RuntimeContext(
              target: target,
              filesystem: remoteFs,
              home: '/remote',
              cwd: '/remote',
              appDataRoot: '/remote/app',
              paths: home.paths,
            );
          }
          return localCtx;
        },
      );

      final session = AppSession(
        sessionId: 's1',
        workspaceId: workspaceId,
        sessionTeam: 'team',
        cliTeamName: 'team-1',
        folders: const [
          WorkspaceFolder(path: '/local', targetId: 'local'),
          WorkspaceFolder(path: '/remote', targetId: 'ssh:p1'),
        ],
        memberTargets: const {'builder': 'ssh:p1'},
        createdAt: 1,
      );
      final ctx = launchCtx(session);

      // Active tools plane follows local cwd — the bug source for remote seats.
      final toolsScope = WorkspaceToolsScopeState(
        tools: WorkspaceToolsContext(targetId: 'local', context: localCtx),
        roots: const ['/local'],
        targetSlices: [
          WorkspaceTargetSlice(
            targetId: 'local',
            tools: WorkspaceToolsContext(targetId: 'local', context: localCtx),
            roots: const ['/local'],
          ),
        ],
        effectiveFolders: session.folders,
        resolving: false,
      );

      final resolved = await resolveSessionMemberFilesystem(
        lifecycle: lifecycle,
        launchContext: ctx,
        memberId: 'builder',
        toolsScope: toolsScope,
      );

      expect(identical(resolved, remoteFs), isTrue);
      expect(
        sessionMemberFolderPaths(
          lifecycle: lifecycle,
          launchContext: ctx,
          memberId: 'builder',
        ),
        ['/remote'],
      );
    },
  );

  test(
    'tool file open uses member filesystem so remote absolute paths resolve',
    () async {
      final localFs = InMemoryFilesystem();
      final remoteFs = InMemoryFilesystem();
      remoteFs.files['/remote/src/foo.dart'] = 'line1\nline2\n';

      final home = testRuntimeContext('/home-root');
      final localCtx = RuntimeContext(
        target: RuntimeTarget.local(),
        filesystem: localFs,
        home: '/local-home',
        cwd: '/local',
        appDataRoot: '/local-home',
        paths: home.paths,
      );
      final lifecycle = SessionLifecycleService(
        storageRootsResolver: () async => localCtx,
        workContextResolver: (target) async {
          if (target.kind == RuntimeKind.ssh) {
            return RuntimeContext(
              target: target,
              filesystem: remoteFs,
              home: '/remote',
              cwd: '/remote',
              appDataRoot: '/remote/app',
              paths: home.paths,
            );
          }
          return localCtx;
        },
      );

      final session = AppSession(
        sessionId: 's1',
        workspaceId: workspaceId,
        folders: const [
          WorkspaceFolder(path: '/local', targetId: 'local'),
          WorkspaceFolder(path: '/remote', targetId: 'ssh:p1'),
        ],
        memberTargets: const {'builder': 'ssh:p1'},
        createdAt: 1,
      );
      final ctx = launchCtx(session);

      final toolsScope = WorkspaceToolsScopeState(
        tools: WorkspaceToolsContext(targetId: 'local', context: localCtx),
        roots: const ['/local'],
        resolving: false,
      );

      final fs = await resolveSessionMemberFilesystem(
        lifecycle: lifecycle,
        launchContext: ctx,
        memberId: 'builder',
        toolsScope: toolsScope,
      );

      final editor = EditorCubit(fs: localFs);
      final workbench = WorkbenchCubit();
      final floating = FloatingWorkspaceCubit();
      addTearDown(() {
        editor.close();
        workbench.close();
        floating.close();
      });
      final coordinator = AiToolFileOpenCoordinator(
        opener: WorkbenchEditorOpener(
          editor: editor,
          workbench: workbench,
          floating: floating,
          markdownViewModes: MarkdownViewModeStore(),
          readMarkdownOpenMode: () => MarkdownOpenMode.preview,
        ),
        editor: editor,
      );

      // Wrong FS (active local plane) cannot see the remote file.
      final missing = await coordinator.openToolFile(
        workspaceId: workspaceId,
        target: const AiToolFileTarget(path: '/remote/src/foo.dart'),
        sessionWorkingDirectory: '/remote',
        workspaceFolderPaths: const ['/local', '/remote'],
        fs: localFs,
      );
      expect(missing.isMissing, isTrue);

      final result = await coordinator.openToolFile(
        workspaceId: workspaceId,
        target: const AiToolFileTarget(path: '/remote/src/foo.dart'),
        sessionWorkingDirectory: '/remote',
        workspaceFolderPaths: sessionMemberFolderPaths(
          lifecycle: lifecycle,
          launchContext: ctx,
          memberId: 'builder',
        ),
        fs: fs,
      );

      expect(result.isMissing, isFalse);
      expect(result.resolvedPath, '/remote/src/foo.dart');
      expect(
        editor.state.bucket(workspaceId).openFilePaths,
        ['/remote/src/foo.dart'],
      );
    },
  );

  test(
    'uses matching tools-scope slice without re-resolving launch context',
    () async {
      final remoteFs = InMemoryFilesystem();
      final home = testRuntimeContext('/home-root');
      var resolveCount = 0;
      final lifecycle = SessionLifecycleService(
        storageRootsResolver: () async => home,
        workContextResolver: (target) async {
          resolveCount++;
          return RuntimeContext(
            target: target,
            filesystem: remoteFs,
            home: '/remote',
            cwd: '/remote',
            appDataRoot: '/remote/app',
            paths: home.paths,
          );
        },
      );
      final remoteCtx = RuntimeContext(
        target: RuntimeTarget.ssh('p1', label: 'box'),
        filesystem: remoteFs,
        home: '/remote',
        cwd: '/remote',
        appDataRoot: '/remote/app',
        paths: home.paths,
      );
      final session = AppSession(
        sessionId: 's1',
        workspaceId: workspaceId,
        folders: const [
          WorkspaceFolder(path: '/local', targetId: 'local'),
          WorkspaceFolder(path: '/remote', targetId: 'ssh:p1'),
        ],
        memberTargets: const {'builder': 'ssh:p1'},
        createdAt: 1,
      );

      final fs = await resolveSessionMemberFilesystem(
        lifecycle: lifecycle,
        launchContext: launchCtx(session),
        memberId: 'builder',
        toolsScope: WorkspaceToolsScopeState(
          tools: WorkspaceToolsContext(targetId: 'local', context: home),
          roots: const ['/local'],
          targetSlices: [
            WorkspaceTargetSlice(
              targetId: 'local',
              tools: WorkspaceToolsContext(targetId: 'local', context: home),
              roots: const ['/local'],
            ),
            WorkspaceTargetSlice(
              targetId: 'ssh:p1',
              tools: WorkspaceToolsContext(
                targetId: 'ssh:p1',
                context: remoteCtx,
              ),
              roots: const ['/remote'],
            ),
          ],
          resolving: false,
        ),
      );

      expect(identical(fs, remoteFs), isTrue);
      expect(resolveCount, 0);
    },
  );

  test('falls back to launchWorkContext when tools scope omits member target', () async {
    final remoteFs = InMemoryFilesystem();
    final home = testRuntimeContext('/home-root');
    final lifecycle = SessionLifecycleService(
      storageRootsResolver: () async => home,
      workContextResolver: (target) async {
        if (target.kind == RuntimeKind.ssh) {
          return RuntimeContext(
            target: target,
            filesystem: remoteFs,
            home: '/remote',
            cwd: '/remote',
            appDataRoot: '/remote/app',
            paths: home.paths,
          );
        }
        return home;
      },
    );
    final session = AppSession(
      sessionId: 's1',
      workspaceId: workspaceId,
      folders: const [
        WorkspaceFolder(path: '/local', targetId: 'local'),
        WorkspaceFolder(path: '/remote', targetId: 'ssh:p1'),
      ],
      memberTargets: const {'builder': 'ssh:p1'},
      createdAt: 1,
    );

    final fs = await resolveSessionMemberFilesystem(
      lifecycle: lifecycle,
      launchContext: launchCtx(session),
      memberId: 'builder',
      toolsScope: const WorkspaceToolsScopeState(
        resolving: false,
      ),
    );

    expect(identical(fs, remoteFs), isTrue);
  });
}
