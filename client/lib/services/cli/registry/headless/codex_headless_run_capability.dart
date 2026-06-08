import 'dart:io';

import '../capabilities/headless_run_capability.dart';

/// Codex one-shot via `codex exec`. Effort via `-c model_reasoning_effort=`.
final class CodexHeadlessRunCapability implements HeadlessRunCapability {
  const CodexHeadlessRunCapability();

  @override
  bool get isSupported => true;

  @override
  List<HeadlessConfigFile> configFiles(HeadlessRunContext ctx) => const [];

  @override
  HeadlessInvocation buildInvocation(HeadlessRunContext ctx) {
    final args = <String>['exec'];
    final model = ctx.model.trim();
    if (model.isNotEmpty) args.addAll(['--model', model]);
    final effort = ctx.effort.trim();
    if (effort.isNotEmpty) {
      args.addAll(['-c', 'model_reasoning_effort=$effort']);
    }
    args.add(ctx.prompt);
    return HeadlessInvocation(
      executable: 'codex',
      arguments: args,
      environment: {'CODEX_HOME': ctx.configDir},
    );
  }

  @override
  String extractText(ProcessResult result) =>
      (result.stdout as String? ?? '').trim();
}
