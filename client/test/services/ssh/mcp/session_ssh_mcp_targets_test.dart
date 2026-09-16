import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/ssh/mcp/session_ssh_mcp_targets.dart';

SshProfile profile(String id, {String name = ''}) => SshProfile(
  id: id,
  name: name.isEmpty ? id : name,
  host: '$id.example',
  username: 'alice',
);

void main() {
  test('collects unique ssh folders and skips local/wsl', () {
    final targets = sessionSshMcpTargetsFromFolders(
      folders: const [
        WorkspaceFolder(path: '/local', targetId: WorkspaceFolder.localTargetId),
        WorkspaceFolder(path: '/a', targetId: 'ssh:home'),
        WorkspaceFolder(path: '/b', targetId: 'ssh:home'),
        WorkspaceFolder(path: '/wsl', targetId: 'wsl:ubuntu'),
        WorkspaceFolder(path: '/c', targetId: 'ssh:build'),
      ],
      profileOf: (id) => switch (id) {
        'home' => profile('home', name: 'Home'),
        'build' => profile('build', name: 'Build'),
        _ => null,
      },
    );
    expect(targets.map((t) => t.profile.id), ['home', 'build']);
    expect(targets.first.folderPaths, ['/a', '/b']);
  });

  test('skips ssh folders with missing profiles', () {
    final targets = sessionSshMcpTargetsFromFolders(
      folders: const [
        WorkspaceFolder(path: '/gone', targetId: 'ssh:gone'),
        WorkspaceFolder(path: '/ok', targetId: 'ssh:home'),
      ],
      profileOf: (id) => id == 'home' ? profile('home') : null,
    );
    expect(targets.map((t) => t.profile.id), ['home']);
    expect(targets.single.folderPaths, ['/ok']);
  });

  test('skips termux folders', () {
    final targets = sessionSshMcpTargetsFromFolders(
      folders: const [
        WorkspaceFolder(path: '/termux', targetId: 'termux:default'),
      ],
      profileOf: (_) => profile('termux'),
    );
    expect(targets, isEmpty);
  });

  test('folderPaths are not mutable by callers', () {
    final target = SessionSshMcpTarget(profile: profile('home'), folderPaths: ['/a']);
    expect(() => target.folderPaths.add('/b'), throwsUnsupportedError);
  });

  test('resolveConnectionName prefers profileId then unique name', () {
    final targets = [
      SessionSshMcpTarget(profile: profile('home', name: 'Home'), folderPaths: ['/a']),
      SessionSshMcpTarget(profile: profile('build', name: 'Build'), folderPaths: ['/c']),
    ];
    expect(resolveSessionSshMcpConnection(targets, 'home')?.profile.id, 'home');
    expect(resolveSessionSshMcpConnection(targets, 'Build')?.profile.id, 'build');
    expect(resolveSessionSshMcpConnection(targets, null)?.profile.id, isNull);
    expect(
      resolveSessionSshMcpConnection(
        [targets.first],
        null,
      )?.profile.id,
      'home',
    );
    expect(resolveSessionSshMcpConnection(targets, 'missing'), isNull);
  });

  test('profileId wins over another target display name', () {
    final targets = [
      SessionSshMcpTarget(profile: profile('box', name: 'A'), folderPaths: ['/a']),
      SessionSshMcpTarget(profile: profile('b', name: 'box'), folderPaths: ['/b']),
    ];
    expect(resolveSessionSshMcpConnection(targets, 'box')?.profile.id, 'box');
  });

  test('trims connection name before matching', () {
    final targets = [
      SessionSshMcpTarget(profile: profile('home', name: 'Home'), folderPaths: ['/a']),
    ];
    expect(resolveSessionSshMcpConnection(targets, '  home  ')?.profile.id, 'home');
  });

  test('blank connection name omits unless exactly one target', () {
    final two = [
      SessionSshMcpTarget(profile: profile('a'), folderPaths: ['/a']),
      SessionSshMcpTarget(profile: profile('b'), folderPaths: ['/b']),
    ];
    expect(resolveSessionSshMcpConnection(two, '   '), isNull);

    final one = [two.first];
    expect(resolveSessionSshMcpConnection(one, '   ')?.profile.id, 'a');
  });

  test('duplicate display names require profileId', () {
    final targets = [
      SessionSshMcpTarget(profile: profile('a', name: 'Box'), folderPaths: ['/a']),
      SessionSshMcpTarget(profile: profile('b', name: 'Box'), folderPaths: ['/b']),
    ];
    expect(resolveSessionSshMcpConnection(targets, 'Box'), isNull);
    expect(resolveSessionSshMcpConnection(targets, 'a')?.profile.id, 'a');
  });
}
