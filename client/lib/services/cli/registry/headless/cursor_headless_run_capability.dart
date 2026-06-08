import 'dart:io';

import '../capabilities/headless_run_capability.dart';

/// Cursor one-shot via `cursor-agent -p`.
final class CursorHeadlessRunCapability implements HeadlessRunCapability {
  const CursorHeadlessRunCapability();

  @override
  bool get isSupported => true;

  @override
  List<HeadlessConfigFile> configFiles(HeadlessRunContext ctx) => const [];

  @override
  HeadlessInvocation buildInvocation(HeadlessRunContext ctx) {
    final args = <String>['-p', ctx.prompt];
    final model = ctx.model.trim();
    if (model.isNotEmpty) args.addAll(['--model', model]);
    return HeadlessInvocation(
      executable: 'cursor-agent',
      arguments: args,
      environment: {'CURSOR_CONFIG_DIR': ctx.configDir},
    );
  }

  @override
  String extractText(ProcessResult result) =>
      (result.stdout as String? ?? '').trim();
}
