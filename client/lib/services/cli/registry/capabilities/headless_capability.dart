import 'dart:io';

import '../../../../models/app_provider_config.dart';
import '../../../../models/launch_security_policy.dart';
import '../cli_capability.dart';
import '../launch/cli_headless_launch_arg_provider.dart';
import '../launch/cli_headless_launch_context.dart';

export '../launch/cli_headless_launch_context.dart';

typedef HeadlessLaunchContext = CliHeadlessLaunchContext;
typedef HeadlessRunContext = CliHeadlessLaunchContext;

/// A file the service writes into [HeadlessRunContext.configDir] before running.
class HeadlessConfigFile {
  const HeadlessConfigFile({
    required this.relativePath,
    required this.contents,
  });

  final String relativePath;
  final String contents;
}

/// Result of materializing an isolated CLI config dir for a headless run.
class HeadlessProvisionResult {
  const HeadlessProvisionResult({
    this.extraEnvironment = const {},
    this.warnings = const [],
    this.credentialsReady = true,
  });

  /// Extra process env entries (e.g. `OPENCODE_AUTH_CONTENT`).
  final Map<String, String> extraEnvironment;

  /// Machine-readable provisioning warnings (e.g. `claude_credentials_missing`).
  final List<String> warnings;

  /// False when OAuth credentials are required but missing for the provider.
  final bool credentialsReady;
}

/// Inputs for provisioning a temp config dir before a one-shot CLI call.
class HeadlessProvisionContext {
  const HeadlessProvisionContext({
    required this.provider,
    required this.providerId,
    required this.model,
    required this.effort,
    required this.configDir,
    this.workingDirectory,
    this.additionalDirectories = const [],
    this.securityPolicy = LaunchSecurityPolicy.fullAccess,
    this.useWslPaths = false,
  });

  final AppProviderConfig? provider;
  final String providerId;
  final String model;
  final String effort;
  final String configDir;
  final String? workingDirectory;
  final List<String> additionalDirectories;
  final LaunchSecurityPolicy securityPolicy;
  final bool useWslPaths;
}

/// Per-CLI one-shot (non-interactive) invocation support, plus credential /
/// settings provisioning for the isolated config dir.
///
/// One implementation per CLI tool, registered alongside [CliSessionCapability]
/// on the tool definition. Pure: it returns data (files, invocation, provision
/// result) and parses stdout; the service owns the filesystem and process
/// execution. A CLI with no provisioning needs (e.g. cursor) returns the
/// default [HeadlessProvisionResult] from [provision].
abstract interface class HeadlessCapability
    implements CliCapability, CliHeadlessLaunchArgProvider {
  /// Executable name resolved to a path by [HeadlessAiService].
  String get executable;

  /// Environment entries required for the isolated config home.
  Map<String, String> buildEnvironment(HeadlessLaunchContext context);

  /// Whether this CLI can run a one-shot headless call.
  bool get isSupported;

  /// Whether this CLI can stream NDJSON events for a one-shot call.
  bool get supportsStreaming;

  /// Config files to materialize into [HeadlessLaunchContext.configDir] first.
  List<HeadlessConfigFile> configFiles(HeadlessLaunchContext ctx);

  /// Extract the model's final text from process stdout (unwrap any envelope).
  String extractText(ProcessResult result);

  /// Given one NDJSON stdout line, return the final result text if this line is
  /// the terminal result event, else null. Only meaningful when
  /// [supportsStreaming] and the context requested [HeadlessRunContext.stream].
  String? streamResultText(String line);

  Future<HeadlessProvisionResult> provision(HeadlessProvisionContext ctx);
}
