import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/ssh/mcp/session_ssh_mcp_resolver.dart';

import '../../../support/in_memory_filesystem.dart';

SshProfile _profile(String id, {String name = ''}) => SshProfile(
  id: id,
  name: name.isEmpty ? id : name,
  host: '$id.example',
  username: 'alice',
);

Workspace _workspace({
  List<WorkspaceFolder> folders = const [],
  bool injectSessionSshMcp = true,
}) => Workspace(
  workspaceId: 'ws',
  createdAt: 1,
  folders: folders,
  injectSessionSshMcp: injectSessionSshMcp,
);

Workspace _mixedLocalSsh({bool injectSessionSshMcp = true}) => _workspace(
  injectSessionSshMcp: injectSessionSshMcp,
  folders: const [
    WorkspaceFolder(path: '/local', targetId: WorkspaceFolder.localTargetId),
    WorkspaceFolder(path: '/home', targetId: 'ssh:home'),
  ],
);

void main() {
  late InMemoryFilesystem localFs;

  setUp(() {
    localFs = InMemoryFilesystem();
  });

  test('mixed workspace resolves enabled context with targets and local roots', () {
    final session = AppSession(
      sessionId: 'sess-1',
      workspaceId: 'ws',
      createdAt: 1,
    );
    final workspace = _mixedLocalSsh();
    final home = _profile('home', name: 'Home');

    final context = resolveSessionSshMcpContext(
      session: session,
      workspace: workspace,
      profileOf: (id) => id == 'home' ? home : null,
      localFs: localFs,
      localUsesPosixPaths: true,
    );

    expect(context.enabled, isTrue);
    expect(context.targets.map((t) => t.profile.id), ['home']);
    expect(context.targets.single.folderPaths, ['/home']);
    expect(context.localAllowedRoots, ['/local']);
    expect(context.localUsesPosixPaths, isTrue);
    expect(context.localFs, same(localFs));
  });

  test('toggle off still returns context with enabled false', () {
    final session = AppSession(
      sessionId: 'sess-1',
      workspaceId: 'ws',
      createdAt: 1,
    );
    final workspace = _mixedLocalSsh(injectSessionSshMcp: false);
    final home = _profile('home');

    final context = resolveSessionSshMcpContext(
      session: session,
      workspace: workspace,
      profileOf: (_) => home,
      localFs: localFs,
      localUsesPosixPaths: true,
    );

    expect(context.enabled, isFalse);
    expect(context.targets, isNotEmpty);
    expect(context.localAllowedRoots, ['/local']);
  });

  test('missing ssh profile is skipped from targets', () {
    final session = AppSession(
      sessionId: 'sess-1',
      workspaceId: 'ws',
      createdAt: 1,
    );
    final workspace = _workspace(
      folders: const [
        WorkspaceFolder(path: '/local', targetId: WorkspaceFolder.localTargetId),
        WorkspaceFolder(path: '/gone', targetId: 'ssh:gone'),
        WorkspaceFolder(path: '/ok', targetId: 'ssh:home'),
      ],
    );
    final home = _profile('home');

    final context = resolveSessionSshMcpContext(
      session: session,
      workspace: workspace,
      profileOf: (id) => id == 'home' ? home : null,
      localFs: localFs,
      localUsesPosixPaths: true,
    );

    expect(context.targets.map((t) => t.profile.id), ['home']);
    expect(context.targets.single.folderPaths, ['/ok']);
  });

  test('memberId adds ssh-target work dirs absent from local-only roots', () {
    final folders = const [
      WorkspaceFolder(path: '/local', targetId: WorkspaceFolder.localTargetId),
      WorkspaceFolder(path: '/remote/home', targetId: 'ssh:home'),
      WorkspaceFolder(path: '/remote/proj', targetId: 'ssh:home'),
      WorkspaceFolder(path: '/remote/build', targetId: 'ssh:build'),
    ];
    final session = AppSession(
      sessionId: 'sess-1',
      workspaceId: 'ws',
      folders: folders,
      memberTargets: const {'m1': 'ssh:home'},
      createdAt: 1,
    );
    final workspace = _workspace(folders: folders);
    final home = _profile('home');

    final withoutMember = resolveSessionSshMcpContext(
      session: session,
      workspace: workspace,
      profileOf: (_) => home,
      localFs: localFs,
      localUsesPosixPaths: true,
    );
    expect(withoutMember.localAllowedRoots, ['/local']);

    final withMember = resolveSessionSshMcpContext(
      session: session,
      workspace: workspace,
      profileOf: (_) => home,
      localFs: localFs,
      localUsesPosixPaths: true,
      memberId: 'm1',
    );
    expect(
      withMember.localAllowedRoots,
      ['/local', '/remote/home', '/remote/proj'],
    );
    expect(withMember.localAllowedRoots, isNot(withoutMember.localAllowedRoots));
  });

  test('local-only workspace resolves enabled false', () {
    final session = AppSession(
      sessionId: 'sess-1',
      workspaceId: 'ws',
      createdAt: 1,
    );
    final localOnly = _workspace(
      folders: const [
        WorkspaceFolder(path: '/local', targetId: WorkspaceFolder.localTargetId),
      ],
    );

    final context = resolveSessionSshMcpContext(
      session: session,
      workspace: localOnly,
      profileOf: (_) => null,
      localFs: localFs,
      localUsesPosixPaths: true,
    );

    expect(context.enabled, isFalse);
  });

  test('pure remote ssh workspace resolves enabled', () {
    final session = AppSession(
      sessionId: 'sess-1',
      workspaceId: 'ws',
      createdAt: 1,
    );
    final workspace = _workspace(
      folders: const [WorkspaceFolder(path: '/home', targetId: 'ssh:home')],
    );
    final home = _profile('home');

    final context = resolveSessionSshMcpContext(
      session: session,
      workspace: workspace,
      profileOf: (_) => home,
      localFs: localFs,
      localUsesPosixPaths: true,
    );

    expect(context.enabled, isTrue);
    expect(context.targets.map((t) => t.profile.id), ['home']);
  });
}
