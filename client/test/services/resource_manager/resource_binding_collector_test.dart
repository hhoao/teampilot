import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/git_worktree.dart';
import 'package:teampilot/services/resource_manager/resource_binding.dart';
import 'package:teampilot/services/resource_manager/resource_binding_collector.dart';

GitWorktree _wt(
  String path, {
  bool main = false,
  String? branch,
}) =>
    GitWorktree(
      path: path,
      branch: branch ?? 'refs/heads/${path.split('/').last}',
      head: 'abc1234567890',
      isBare: false,
      isMainWorktree: main,
    );

void main() {
  final worktrees = [
    _wt('/repo', main: true, branch: 'refs/heads/main'),
    _wt('/wt/feat', branch: 'refs/heads/feat/x'),
  ];

  test('chat keys follow chat:{sessionId}:{memberId} scheme', () {
    final bindings = collectResourceBindings(
      workspaceId: 'ws1',
      chatShells: const [
        ChatMemberShellRef(
          workspaceId: 'ws1',
          sessionId: 's1',
          memberId: 'm1',
          sessionTitle: 'Fix bug',
          memberName: 'Alice',
          sessionPrimaryPath: '/repo/lib',
          connected: true,
        ),
      ],
      workspaceShells: const [],
      worktrees: worktrees,
    );

    expect(bindings, hasLength(1));
    expect(bindings.single.key, 'chat:s1:m1');
    expect(bindings.single.kind, ResourceBindingKind.chatMember);
    expect(bindings.single.sessionId, 's1');
    expect(bindings.single.memberId, 'm1');
  });

  test('shell keys follow shell:{workspaceId}:{entryId} scheme', () {
    final bindings = collectResourceBindings(
      workspaceId: 'ws1',
      chatShells: const [],
      workspaceShells: const [
        WorkspaceShellRef(
          workspaceId: 'ws1',
          entryId: 'e1',
          titleLabel: 'Shell 1',
          cwd: '/repo',
          connected: true,
        ),
      ],
      worktrees: worktrees,
    );

    expect(bindings, hasLength(1));
    expect(bindings.single.key, 'shell:ws1:e1');
    expect(bindings.single.kind, ResourceBindingKind.workspaceShell);
    expect(bindings.single.workspaceId, 'ws1');
    expect(bindings.single.shellEntryId, 'e1');
  });

  test('groups chat shells by session primary path worktree match', () {
    final bindings = collectResourceBindings(
      workspaceId: 'ws1',
      chatShells: const [
        ChatMemberShellRef(
          workspaceId: 'ws1',
          sessionId: 's1',
          memberId: 'm1',
          sessionTitle: 'On main',
          memberName: '',
          sessionPrimaryPath: '/repo/src',
          connected: true,
        ),
        ChatMemberShellRef(
          workspaceId: 'ws1',
          sessionId: 's2',
          memberId: 'm1',
          sessionTitle: 'On feat',
          memberName: 'Bob',
          sessionPrimaryPath: '/wt/feat/lib',
          connected: true,
        ),
        ChatMemberShellRef(
          workspaceId: 'ws1',
          sessionId: 's3',
          memberId: 'm1',
          sessionTitle: 'Orphan path',
          memberName: '',
          sessionPrimaryPath: '/elsewhere',
          connected: true,
        ),
      ],
      workspaceShells: const [],
      worktrees: worktrees,
    );

    final bySession = {for (final b in bindings) b.sessionId!: b};
    // Main-worktree match and unmatched orphans share one 'main' bucket.
    expect(bySession['s1']!.groupKey, 'main');
    expect(bySession['s1']!.groupLabel, 'main');
    expect(bySession['s2']!.groupKey, '/wt/feat');
    expect(bySession['s2']!.groupLabel, 'feat/x');
    expect(bySession['s3']!.groupKey, 'main');
    expect(bySession['s3']!.groupLabel, 'main');
  });

  test('coalesces main-worktree and unmatched into one main groupKey', () {
    final bindings = collectResourceBindings(
      workspaceId: 'ws1',
      chatShells: const [
        ChatMemberShellRef(
          workspaceId: 'ws1',
          sessionId: 's1',
          memberId: 'm1',
          sessionTitle: 'Under main wt',
          memberName: '',
          sessionPrimaryPath: '/repo/src',
          connected: true,
        ),
        ChatMemberShellRef(
          workspaceId: 'ws1',
          sessionId: 's2',
          memberId: 'm1',
          sessionTitle: 'Orphan',
          memberName: '',
          sessionPrimaryPath: '/elsewhere',
          connected: true,
        ),
      ],
      workspaceShells: const [
        WorkspaceShellRef(
          workspaceId: 'ws1',
          entryId: 'e1',
          titleLabel: 'Under main cwd',
          cwd: '/repo',
          connected: true,
        ),
      ],
      worktrees: worktrees,
    );

    expect(bindings.map((b) => b.groupKey).toSet(), {'main'});
    expect(bindings.every((b) => b.groupLabel == 'main'), isTrue);
  });

  test('groups workspace shells by cwd worktree match', () {
    final bindings = collectResourceBindings(
      workspaceId: 'ws1',
      chatShells: const [],
      workspaceShells: const [
        WorkspaceShellRef(
          workspaceId: 'ws1',
          entryId: 'e1',
          titleLabel: 'Main shell',
          cwd: '/repo/tmp',
          connected: true,
        ),
        WorkspaceShellRef(
          workspaceId: 'ws1',
          entryId: 'e2',
          titleLabel: 'Feat shell',
          cwd: '/wt/feat',
          connected: true,
        ),
        WorkspaceShellRef(
          workspaceId: 'ws1',
          entryId: 'e3',
          titleLabel: 'Outside',
          cwd: '/tmp',
          connected: true,
        ),
      ],
      worktrees: worktrees,
    );

    final byEntry = {for (final b in bindings) b.shellEntryId!: b};
    expect(byEntry['e1']!.groupKey, 'main');
    expect(byEntry['e1']!.groupLabel, 'main');
    expect(byEntry['e2']!.groupKey, '/wt/feat');
    expect(byEntry['e2']!.groupLabel, 'feat/x');
    expect(byEntry['e3']!.groupKey, 'main');
    expect(byEntry['e3']!.groupLabel, 'main');
  });

  test('chat title prefers sessionTitle · memberName', () {
    final bindings = collectResourceBindings(
      workspaceId: 'ws1',
      chatShells: const [
        ChatMemberShellRef(
          workspaceId: 'ws1',
          sessionId: 's1',
          memberId: 'm1',
          sessionTitle: 'Fix bug',
          memberName: 'Alice',
          sessionPrimaryPath: '/repo',
          connected: true,
        ),
        ChatMemberShellRef(
          workspaceId: 'ws1',
          sessionId: 's2',
          memberId: 'm1',
          sessionTitle: 'Solo',
          memberName: '',
          sessionPrimaryPath: '/repo',
          connected: true,
        ),
        ChatMemberShellRef(
          workspaceId: 'ws1',
          sessionId: 's3',
          memberId: 'm1',
          sessionTitle: 'Whitespace member',
          memberName: '   ',
          sessionPrimaryPath: '/repo',
          connected: true,
        ),
      ],
      workspaceShells: const [],
      worktrees: worktrees,
    );

    final bySession = {for (final b in bindings) b.sessionId!: b};
    expect(bySession['s1']!.title, 'Fix bug · Alice');
    expect(bySession['s2']!.title, 'Solo');
    expect(bySession['s3']!.title, 'Whitespace member');
  });

  test('workspace shell title uses titleLabel', () {
    final bindings = collectResourceBindings(
      workspaceId: 'ws1',
      chatShells: const [],
      workspaceShells: const [
        WorkspaceShellRef(
          workspaceId: 'ws1',
          entryId: 'e1',
          titleLabel: 'Bottom Shell',
          cwd: '/repo',
          connected: true,
        ),
      ],
      worktrees: worktrees,
    );

    expect(bindings.single.title, 'Bottom Shell');
  });

  test('includes disconnected shells', () {
    final bindings = collectResourceBindings(
      workspaceId: 'ws1',
      chatShells: const [
        ChatMemberShellRef(
          workspaceId: 'ws1',
          sessionId: 's1',
          memberId: 'm1',
          sessionTitle: 'Offline chat',
          memberName: 'Alice',
          sessionPrimaryPath: '/repo',
          connected: false,
        ),
      ],
      workspaceShells: const [
        WorkspaceShellRef(
          workspaceId: 'ws1',
          entryId: 'e1',
          titleLabel: 'Offline shell',
          cwd: '/repo',
          connected: false,
        ),
      ],
      worktrees: worktrees,
    );

    expect(bindings, hasLength(2));
    expect(bindings.every((b) => !b.connected), isTrue);
  });

  test('filters to requested workspaceId only', () {
    final bindings = collectResourceBindings(
      workspaceId: 'ws1',
      chatShells: const [
        ChatMemberShellRef(
          workspaceId: 'ws1',
          sessionId: 's1',
          memberId: 'm1',
          sessionTitle: 'Keep',
          memberName: '',
          sessionPrimaryPath: '/repo',
          connected: true,
        ),
        ChatMemberShellRef(
          workspaceId: 'ws2',
          sessionId: 's2',
          memberId: 'm1',
          sessionTitle: 'Drop',
          memberName: '',
          sessionPrimaryPath: '/repo',
          connected: true,
        ),
      ],
      workspaceShells: const [
        WorkspaceShellRef(
          workspaceId: 'ws1',
          entryId: 'e1',
          titleLabel: 'Keep shell',
          cwd: '/repo',
          connected: true,
        ),
        WorkspaceShellRef(
          workspaceId: 'ws2',
          entryId: 'e2',
          titleLabel: 'Drop shell',
          cwd: '/repo',
          connected: true,
        ),
      ],
      worktrees: worktrees,
    );

    expect(bindings, hasLength(2));
    expect(bindings.map((b) => b.key).toSet(), {'chat:s1:m1', 'shell:ws1:e1'});
  });

  test('copies livePid onto ResourceBinding when present', () {
    final bindings = collectResourceBindings(
      workspaceId: 'ws1',
      chatShells: const [
        ChatMemberShellRef(
          workspaceId: 'ws1',
          sessionId: 's1',
          memberId: 'm1',
          sessionTitle: 'With pid',
          memberName: '',
          sessionPrimaryPath: '/repo',
          connected: true,
          livePid: 42,
        ),
      ],
      workspaceShells: const [
        WorkspaceShellRef(
          workspaceId: 'ws1',
          entryId: 'e1',
          titleLabel: 'Shell pid',
          cwd: '/repo',
          connected: true,
          livePid: 99,
        ),
      ],
      worktrees: worktrees,
    );

    final byKey = {for (final b in bindings) b.key: b};
    expect(byKey['chat:s1:m1']!.livePid, 42);
    expect(byKey['shell:ws1:e1']!.livePid, 99);
  });
}
