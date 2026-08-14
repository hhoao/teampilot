import 'dart:convert' show jsonDecode;
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../registry/capabilities/headless_capability.dart';
import '../../registry/headless/headless_provision_support.dart';
import 'config_profile.dart';

/// flashskyai one-shot via `-p` print mode (Claude-style CLI), plus
/// provisioning of the isolated config dir (settings + trusted workspaces)
/// and the env it needs for the run.
final class FlashskyaiHeadlessCapability
    with HeadlessProvisionSupport
    implements HeadlessCapability {
  const FlashskyaiHeadlessCapability();

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

  @override
  Future<HeadlessProvisionResult> provision(
    HeadlessProvisionContext ctx,
  ) async {
    await fs.ensureDir(ctx.configDir);

    final layout = profileInfra.layout;
    final directories = <String>[
      if (ctx.workingDirectory != null &&
          ctx.workingDirectory!.trim().isNotEmpty)
        ctx.workingDirectory!.trim(),
    ];
    if (directories.isNotEmpty) {
      final metadataPath = p.join(
        ctx.configDir,
        FlashskyaiConfigProfileCapability.metadataFileName,
      );
      final metadata = await profileInfra.metadataWithTrustedProjects(
        metadataPath: metadataPath,
        defaultMetadata: FlashskyaiConfigProfileCapability.defaultMetadata,
        defaultProjectConfig:
            FlashskyaiConfigProfileCapability.defaultProjectConfig,
        directories: directories,
      );
      await writeJson(metadataPath, metadata);
    }

    // flashskyai is a Claude-style CLI, so reasoning effort is carried via
    // settings.json `effortLevel` (mirrors the Claude provisioner).
    final settings = <String, Object?>{
      'skipDangerousModePermissionPrompt': true,
    };
    final effortLabel = ctx.effort.trim();
    if (effortLabel.isNotEmpty) {
      settings['effortLevel'] = effortLabel;
    }
    await writeJson(
      p.join(ctx.configDir, FlashskyaiConfigProfileCapability.settingsFileName),
      settings,
    );

    return HeadlessProvisionResult(
      extraEnvironment: {
        FlashskyaiConfigProfileCapability.configDirEnvKey: ctx.configDir,
        FlashskyaiConfigProfileCapability.sessionHomeDirEnvKey: ctx.configDir,
        'LLM_CONFIG_PATH': layout.appFlashskyaiLlmConfigFile,
        'FLASHSKYAI_CODE_NO_FLICKER': '1',
      },
    );
  }
}
