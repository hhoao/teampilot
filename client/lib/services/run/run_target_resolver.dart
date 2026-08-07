import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../models/runtime_target.dart';
import '../../models/workspace_folder.dart';
import '../session/launch_command_builder.dart';
import '../storage/work_target_canonicalizer.dart';
import 'launch_variable_expander.dart';

/// Path style for a run target's machine — how a `cwd` must be spelled inside
/// the process/terminal on that target.
p.Style pathStyleForTarget(RuntimeTarget target) => switch (target.kind) {
  RuntimeKind.wsl || RuntimeKind.ssh || RuntimeKind.termux => p.Style.posix,
  RuntimeKind.local => Platform.isWindows ? p.Style.windows : p.Style.posix,
};

/// Resolved cwd and runtime target for a run configuration's owning folder.
@immutable
class RunTargetPlan {
  const RunTargetPlan({
    required this.workingDirectory,
    required this.runtimeTarget,
    required this.targetId,
    required this.useWslPaths,
  });

  /// Target-native working directory (POSIX path on WSL/SSH), expanded and
  /// re-spelled in [pathStyle].
  final String workingDirectory;

  final RuntimeTarget runtimeTarget;
  final String targetId;
  final bool useWslPaths;

  /// Path style of [runtimeTarget]'s machine.
  p.Style get pathStyle => pathStyleForTarget(runtimeTarget);

  /// CreateProcess cwd for local/`wsl.exe` spawn (may differ on Windows+WSL).
  String get hostProcessWorkingDirectory =>
      LaunchCommandBuilder.workingDirectoryForProcess(
        workingDirectory,
        useWslPaths: useWslPaths,
      );
}

/// Maps an owning [WorkspaceFolder] to a process/adapter execution plan.
class RunTargetResolver {
  RunTargetResolver({RuntimeTarget Function()? homeTarget})
    : _homeTarget = homeTarget ?? (() => RuntimeTarget.local());

  final RuntimeTarget Function() _homeTarget;

  /// Resolves [owner]'s execution target without expanding a cwd.
  RuntimeTarget targetFor(WorkspaceFolder owner) =>
      WorkTargetCanonicalizer.resolve(owner.targetId, home: _homeTarget());

  RunTargetPlan resolve({
    required WorkspaceFolder owner,
    String? cwd,
    Map<String, String> env = const {},
  }) {
    final resolved = WorkTargetCanonicalizer.resolve(
      owner.targetId,
      home: _homeTarget(),
    );
    final expandedCwd = _expandedCwd(
      owner: owner,
      cwd: cwd,
      env: env,
      target: resolved,
    );
    final useWslPaths = resolved.kind == RuntimeKind.wsl;

    return RunTargetPlan(
      workingDirectory: expandedCwd,
      runtimeTarget: resolved,
      targetId: resolved.id,
      useWslPaths: useWslPaths,
    );
  }

  String _expandedCwd({
    required WorkspaceFolder owner,
    String? cwd,
    required Map<String, String> env,
    required RuntimeTarget target,
  }) {
    final raw = cwd?.trim();
    if (raw == null || raw.isEmpty) {
      return owner.path;
    }
    return LaunchVariableExpander.expandPath(
      raw,
      workspaceFolder: owner.path,
      env: env,
      style: pathStyleForTarget(target),
    );
  }
}
