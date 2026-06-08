import 'dart:io';

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

/// Per-CLI one-shot (non-interactive) invocation support.
///
/// One implementation per CLI tool, registered alongside [LaunchArgsCapability]
/// on the tool definition. Pure: it returns data (files, invocation) and parses
/// stdout; the service owns the filesystem and process execution.
abstract interface class HeadlessRunCapability implements CliCapability {
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
}
