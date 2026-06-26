import 'package:flutter/foundation.dart';

import 'runtime_target.dart';

/// Resolved argv/cwd for [TerminalSession.connectWorkspaceShell].
@immutable
class WorkspaceShellLaunchPlan {
  const WorkspaceShellLaunchPlan({
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
    required this.useWslPaths,
    required this.inheritHostEnvironment,
    required this.runtimeTarget,
    required this.usesRemoteTransport,
  });

  final String executable;
  final List<String> arguments;
  final String workingDirectory;
  final bool useWslPaths;
  final bool inheritHostEnvironment;
  final RuntimeTarget runtimeTarget;
  final bool usesRemoteTransport;
}
