import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/run/run_target_resolver.dart';

void main() {
  test('resolver uses owning folder path and targetId', () {
    final plan = RunTargetResolver().resolve(
      owner: const WorkspaceFolder(path: '/proj', targetId: 'local'),
      cwd: r'${workspaceFolder}/app',
    );
    expect(
      plan.workingDirectory,
      Platform.isWindows ? r'\proj\app' : '/proj/app',
    );
    expect(plan.runtimeTarget, RuntimeTarget.local());
    expect(plan.targetId, 'local');
    expect(plan.useWslPaths, isFalse);
  });

  test('resolver defaults cwd to owner path when omitted', () {
    final plan = RunTargetResolver().resolve(
      owner: const WorkspaceFolder(path: '/proj', targetId: 'local'),
    );
    expect(plan.workingDirectory, '/proj');
  });

  test('resolver expands env variables in cwd', () {
    final plan = RunTargetResolver().resolve(
      owner: const WorkspaceFolder(path: '/proj', targetId: 'local'),
      cwd: r'${workspaceFolder}/${env:APP}',
      env: const {'APP': 'server'},
    );
    expect(
      plan.workingDirectory,
      Platform.isWindows ? r'\proj\server' : '/proj/server',
    );
  });

  test('resolver returns wsl plan for wsl targetId', () {
    final plan = RunTargetResolver().resolve(
      owner: const WorkspaceFolder(path: '/proj', targetId: 'wsl:Ubuntu'),
      cwd: r'${workspaceFolder}/app',
    );
    expect(plan.workingDirectory, '/proj/app');
    expect(plan.runtimeTarget.kind, RuntimeKind.wsl);
    expect(plan.runtimeTarget.wslDistro, 'Ubuntu');
    expect(plan.useWslPaths, isTrue);
  });

  test('resolver returns ssh plan for ssh targetId', () {
    final plan = RunTargetResolver().resolve(
      owner: const WorkspaceFolder(path: '/proj', targetId: 'ssh:profile-1'),
      cwd: '/proj',
    );
    expect(plan.runtimeTarget.kind, RuntimeKind.ssh);
    expect(plan.runtimeTarget.sshProfileId, 'profile-1');
    expect(plan.useWslPaths, isFalse);
  });

  test('resolves local owner to ssh home', () {
    final home = RuntimeTarget.ssh('p1', label: 'box');
    final plan = RunTargetResolver(
      homeTarget: () => home,
    ).resolve(owner: const WorkspaceFolder(path: '/repo'));
    expect(plan.runtimeTarget.kind, RuntimeKind.ssh);
    expect(plan.targetId, 'ssh:p1');
  });

  test('re-spells Windows backslash cwd into posix for ssh targets', () {
    final plan = RunTargetResolver().resolve(
      owner: const WorkspaceFolder(path: '/proj', targetId: 'ssh:profile-1'),
      cwd: r'${workspaceFolder}\client',
    );
    expect(plan.workingDirectory, '/proj/client');
    expect(plan.pathStyle, p.Style.posix);
  });

  test('wsl targets resolve to posix style', () {
    final plan = RunTargetResolver().resolve(
      owner: const WorkspaceFolder(path: '/proj', targetId: 'wsl:Ubuntu'),
      cwd: r'${workspaceFolder}\app',
    );
    expect(plan.workingDirectory, '/proj/app');
    expect(plan.pathStyle, p.Style.posix);
  });

  test('local targets use the host path style', () {
    final plan = RunTargetResolver().resolve(
      owner: const WorkspaceFolder(path: '/proj', targetId: 'local'),
      cwd: r'${workspaceFolder}/app',
    );
    expect(
      plan.pathStyle,
      Platform.isWindows ? p.Style.windows : p.Style.posix,
    );
  });
}
