import 'dart:io';

import '../capabilities/headless_run_capability.dart';

/// opencode one-shot via `opencode run`.
final class OpencodeHeadlessRunCapability implements HeadlessRunCapability {
  const OpencodeHeadlessRunCapability();

  @override
  bool get isSupported => true;

  @override
  bool get supportsStreaming => false;

  @override
  List<HeadlessConfigFile> configFiles(HeadlessRunContext ctx) => const [];

  @override
  HeadlessInvocation buildInvocation(HeadlessRunContext ctx) {
    final args = <String>['run'];
    final model = ctx.model.trim();
    if (model.isNotEmpty) args.addAll(['--model', model]);
    args.add(ctx.prompt);
    return HeadlessInvocation(
      executable: 'opencode',
      arguments: args,
      environment: {'OPENCODE_CONFIG_DIR': ctx.configDir},
    );
  }

  @override
  String extractText(ProcessResult result) =>
      (result.stdout as String? ?? '').trim();

  @override
  String? streamResultText(String line) => null;
}
