import 'dart:convert' show jsonDecode;
import 'dart:io';

import '../capabilities/headless_run_capability.dart';

/// Claude one-shot via `claude -p`. Effort is expressed through a temp
/// `settings.json` (`effortLevel`) under `CLAUDE_CONFIG_DIR`.
final class ClaudeHeadlessRunCapability implements HeadlessRunCapability {
  const ClaudeHeadlessRunCapability();

  @override
  bool get isSupported => true;

  @override
  List<HeadlessConfigFile> configFiles(HeadlessRunContext ctx) => const [];

  @override
  HeadlessInvocation buildInvocation(HeadlessRunContext ctx) {
    final args = <String>['-p', ctx.prompt];
    final model = ctx.model.trim();
    if (model.isNotEmpty) {
      args.addAll(['--model', model]);
    }
    if (ctx.expectJson) {
      args.addAll(['--output-format', 'json']);
    }
    return HeadlessInvocation(
      executable: 'claude',
      arguments: args,
      environment: {'CLAUDE_CONFIG_DIR': ctx.configDir},
    );
  }

  @override
  String extractText(ProcessResult result) {
    final out = (result.stdout as String? ?? '').trim();
    if (out.isEmpty) return '';
    try {
      final decoded = jsonDecode(out);
      if (decoded is Map && decoded['result'] is String) {
        return (decoded['result'] as String).trim();
      }
    } on FormatException {
      // Plain-text mode: stdout is the message itself.
    }
    return out;
  }
}
