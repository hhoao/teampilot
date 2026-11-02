import 'dart:convert' show jsonDecode;
import 'dart:io';

import '../../../../models/launch_security_policy.dart';
import '../../registry/capabilities/headless_capability.dart';
import '../../registry/launch/cli_launch_arg_contribution.dart';

/// Antigravity one-shot via `agy -p`.
///
/// Runs against an isolated `HOME` so the CLI never reads or writes the user's
/// real `~/.gemini`. Provider credentials (Gemini API key / ADC) are inherited
/// from the process env contributed by the provider stack; they are never
/// re-materialized here.
final class AntigravityHeadlessCapability implements HeadlessCapability {
  const AntigravityHeadlessCapability();

  @override
  String get executable => 'agy';

  @override
  bool get isSupported => true;

  @override
  bool get supportsStreaming => true;

  @override
  bool get supportsPromptStdin => true;

  @override
  Map<String, String> buildEnvironment(HeadlessLaunchContext context) {
    final home = '${context.configDir}/home';
    return {'HOME': home, 'USERPROFILE': home, 'GEMINI_HOME': '$home/.gemini'};
  }

  @override
  List<HeadlessConfigFile> configFiles(HeadlessLaunchContext ctx) => const [];

  @override
  Iterable<CliLaunchArgContribution> buildHeadlessLaunchArgs(
    CliHeadlessLaunchContext context,
  ) => [
    CliLaunchArgContribution(
      key: 'antigravity-headless',
      phase: LaunchArgPhase.command,
      args: [
        // In stdin mode the piped content is the prompt; `-p` without a value
        // would otherwise consume the next flag as its argument.
        if (!context.promptViaStdin) ...['-p', context.prompt],
        if (context.model.isNotEmpty) ...['--model', context.model],
        if (context.effort.isNotEmpty) ...['--effort', context.effort],
        if (context.securityPolicy == LaunchSecurityPolicy.fullAccess)
          '--dangerously-skip-permissions',
        // `stream-json` supersedes `json`; passing both is invalid.
        if (context.stream) ...['--output-format', 'stream-json'],
        if (context.expectJson && !context.stream) ...[
          '--output-format',
          'json',
        ],
      ],
    ),
  ];

  @override
  String? streamResultText(String line) {
    final Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException {
      return null;
    }
    if (decoded is! Map || decoded['event'] != 'result') return null;
    final result = decoded['result'];
    return result is Map ? result['response']?.toString() : null;
  }

  @override
  String extractText(ProcessResult result) {
    final text = (result.stdout as String? ?? '').trim();
    if (text.isEmpty) return '';
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map && decoded['response'] is String) {
        return (decoded['response'] as String).trim();
      }
    } on FormatException {
      // Plain-text mode: stdout is the message itself.
    }
    return text;
  }

  @override
  Future<HeadlessProvisionResult> provision(
    HeadlessProvisionContext ctx,
  ) async => const HeadlessProvisionResult();
}
