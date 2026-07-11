import 'package:flutter/foundation.dart';

import '../../models/runtime_target.dart';
import '../../models/workspace_folder.dart';
import '../session/launch_command_builder.dart';
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

  final String workingDirectory;
  final RuntimeTarget runtimeTarget;
  final String targetId;
  final bool useWslPaths;
}

/// Maps an owning [WorkspaceFolder] to a process/adapter execution plan.
class RunTargetResolver {
  const RunTargetResolver();

  RunTargetPlan resolve({
    required WorkspaceFolder owner,
    String? cwd,
    Map<String, String> env = const {},
  }) {
    final runtimeTarget = _runtimeTargetFromId(owner.targetId);
    final expandedCwd = _expandedCwd(
      owner: owner,
      cwd: cwd,
      env: env,
    );
    final useWslPaths = runtimeTarget.kind == RuntimeKind.wsl;
    final workingDirectory = LaunchCommandBuilder.workingDirectoryForProcess(
      expandedCwd,
      useWslPaths: useWslPaths,
    );

    return RunTargetPlan(
      workingDirectory: workingDirectory,
      runtimeTarget: runtimeTarget,
      targetId: owner.targetId,
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

  RuntimeTarget _runtimeTargetFromId(String id) => switch (runtimeKindOfId(id)) {
    RuntimeKind.ssh => RuntimeTarget.ssh(sshProfileIdOfId(id) ?? '', label: ''),
    RuntimeKind.wsl => RuntimeTarget.wsl(wslDistroOfId(id) ?? ''),
    RuntimeKind.local => RuntimeTarget.local(),
  };
}
