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
  });

  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
  final Map<String, String>? environment;
  final bool includeParentEnvironment;
}
