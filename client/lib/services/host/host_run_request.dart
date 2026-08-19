import 'package:flutter/foundation.dart';

/// One-shot subprocess invocation on a host runtime plane (native / WSL / SSH).
@immutable
class HostRunRequest {
  const HostRunRequest({
    required this.executable,
    this.arguments = const [],
    this.workingDirectory,
    this.environment,
    this.pathPrepend = const [],
    this.includeParentEnvironment = true,
    this.allocateTty = false,
  });

  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
  final Map<String, String>? environment;

  /// Paths to place before the target runtime's existing PATH.
  ///
  /// The host runner applies this using the target runtime's environment
  /// semantics, so `$PATH` is expanded remotely rather than on the control
  /// plane.
  final List<String> pathPrepend;
  final bool includeParentEnvironment;

  /// When true, POSIX hosts wrap the process in `script` so CLIs that
  /// block-buffer stdout on a pipe (Rust `println!`) flush login banners.
  final bool allocateTty;
}
