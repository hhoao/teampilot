import 'dart:io';

import '../../../../models/app_provider_config.dart';
import '../cli_capability.dart';

/// Inputs for building a one-shot headless CLI call.
class HeadlessRunContext {
  const HeadlessRunContext({
    required this.prompt,
    required this.model,
    required this.effort,
    required this.configDir,
    this.workingDirectory,
    this.expectJson = false,
    this.stream = false,
  });

  /// The full prompt text to send to the model.
  final String prompt;

  /// Resolved model id (may be empty to use the CLI default).
  final String model;

  /// Resolved reasoning effort (empty = not applicable / CLI default).
  final String effort;

  /// Isolated, already-created temp config dir the CLI may use.
  final String configDir;

  /// Working directory for the run (repo root for commit generation).
  final String? workingDirectory;

  /// When true, ask the CLI for machine-readable output if it supports it.
  final bool expectJson;

  /// When true, request NDJSON streaming output from CLIs that support it.
  final bool stream;
}

/// A file the service writes into [HeadlessRunContext.configDir] before running.
class HeadlessConfigFile {
  const HeadlessConfigFile({
    required this.relativePath,
    required this.contents,
  });

  final String relativePath;
  final String contents;
}

/// A fully-specified one-shot process invocation.
class HeadlessInvocation {
  const HeadlessInvocation({
    required this.executable,
    required this.arguments,
    this.environment = const {},
  });

  /// Executable name (resolved to a path by the service via the locator).
  final String executable;
  final List<String> arguments;

  /// Extra environment entries (merged onto the parent environment).
  final Map<String, String> environment;
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
  });

  final AppProviderConfig? provider;
  final String providerId;
  final String model;
  final String effort;
  final String configDir;
  final String? workingDirectory;
}

/// Per-CLI one-shot (non-interactive) invocation support, plus credential /
/// settings provisioning for the isolated config dir.
///
/// One implementation per CLI tool, registered alongside [CliSessionCapability]
/// on the tool definition. Pure: it returns data (files, invocation, provision
/// result) and parses stdout; the service owns the filesystem and process
/// execution. A CLI with no provisioning needs (e.g. cursor) returns the
/// default [HeadlessProvisionResult] from [provision].
abstract interface class HeadlessCapability implements CliCapability {
  /// Whether this CLI can run a one-shot headless call.
  bool get isSupported;

  /// Whether this CLI can stream NDJSON events for a one-shot call.
  bool get supportsStreaming;

  /// Config files to materialize into [HeadlessRunContext.configDir] first.
  List<HeadlessConfigFile> configFiles(HeadlessRunContext ctx);

  /// Build the executable + args + env for the one-shot call.
  HeadlessInvocation buildInvocation(HeadlessRunContext ctx);

  /// Extract the model's final text from process stdout (unwrap any envelope).
  String extractText(ProcessResult result);

  /// Given one NDJSON stdout line, return the final result text if this line is
  /// the terminal result event, else null. Only meaningful when
  /// [supportsStreaming] and the context requested [HeadlessRunContext.stream].
  String? streamResultText(String line);

  Future<HeadlessProvisionResult> provision(HeadlessProvisionContext ctx);
}
