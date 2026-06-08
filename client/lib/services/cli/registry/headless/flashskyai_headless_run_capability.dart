import 'dart:convert' show jsonDecode;
import 'dart:io';

import '../capabilities/headless_run_capability.dart';
import '../config_profile/flashskyai_config_profile_capability.dart';

/// flashskyai one-shot via `-p` print mode (Claude-style CLI).
final class FlashskyaiHeadlessRunCapability implements HeadlessRunCapability {
  const FlashskyaiHeadlessRunCapability();

  @override
  bool get isSupported => true;

  @override
  bool get supportsStreaming => true;

  @override
  List<HeadlessConfigFile> configFiles(HeadlessRunContext ctx) => const [];

  @override
  HeadlessInvocation buildInvocation(HeadlessRunContext ctx) {
    final args = <String>['-p', ctx.prompt];
    final model = ctx.model.trim();
    if (model.isNotEmpty) args.addAll(['--model', model]);
    if (ctx.stream) {
      args.addAll(['--output-format', 'stream-json', '--verbose']);
    }
    return HeadlessInvocation(
      executable: 'flashskyai',
      arguments: args,
      environment: {
        FlashskyaiConfigProfileCapability.configDirEnvKey: ctx.configDir,
        FlashskyaiConfigProfileCapability.sessionHomeDirEnvKey: ctx.configDir,
      },
    );
  }

  @override
  String extractText(ProcessResult result) =>
      (result.stdout as String? ?? '').trim();

  @override
  String? streamResultText(String line) {
    try {
      final decoded = jsonDecode(line);
      if (decoded is Map &&
          decoded['type'] == 'result' &&
          decoded['result'] is String) {
        return (decoded['result'] as String).trim();
      }
    } on FormatException {
      // Not a JSON event line.
    }
    return null;
  }
}
