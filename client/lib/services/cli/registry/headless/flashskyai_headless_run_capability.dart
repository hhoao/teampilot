import 'dart:io';

import '../capabilities/headless_run_capability.dart';
import '../config_profile/flashskyai_config_profile_capability.dart';

/// flashskyai one-shot via `-p` print mode (Claude-style CLI).
final class FlashskyaiHeadlessRunCapability implements HeadlessRunCapability {
  const FlashskyaiHeadlessRunCapability();

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
}
