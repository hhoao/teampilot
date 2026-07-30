import 'package:flutter/foundation.dart';

import '../../models/runtime_target.dart';
import '../../models/workspace_folder.dart';
import '../session/launch_command_builder.dart';
import '../storage/work_target_canonicalizer.dart';
import 'launch_variable_expander.dart';

/// Resolved cwd and runtime target for a run configuration's owning folder.
@immutable
class RunTargetPlan {
  const RunTargetPlan({
    required this.workingDirectory,
    required this.runtimeTarget,
    required this.targetId,
    required this.useWslPaths,
  });

  /// Target-native working directory (POSIX path on WSL/SSH).
  final String workingDirectory;

  final RuntimeTarget runtimeTarget;
  final String targetId;
  final bool useWslPaths;

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
  }) {
    final raw = cwd?.trim();
    if (raw == null || raw.isEmpty) {
      return owner.path;
    }
    return LaunchVariableExpander.expand(
      raw,
      workspaceFolder: owner.path,
      env: env,
    );
  }
}
