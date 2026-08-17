import 'package:flutter/foundation.dart';

/// One-shot subprocess invocation on a host runtime plane (native / WSL / SSH).
@immutable
class HostRunRequest {
  const HostRunRequest({
    required this.executable,
    this.arguments = const [],
    this.workingDirectory,
    this.environment,
    this.includeParentEnvironment = true,
    this.allocateTty = false,
  });

  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
  final Map<String, String>? environment;
  final bool includeParentEnvironment;

  /// When true, POSIX hosts wrap the process in `script` so CLIs that
  /// block-buffer stdout on a pipe (Rust `println!`) flush login banners.
  final bool allocateTty;
}
