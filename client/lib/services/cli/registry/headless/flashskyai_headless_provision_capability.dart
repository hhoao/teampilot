import 'package:path/path.dart' as p;

import '../capabilities/headless_provision_capability.dart';
import '../config_profile/flashskyai_config_profile_capability.dart';
import 'headless_provision_support.dart';

/// Provisions an isolated flashskyai config dir (settings + trusted workspaces)
/// and the env it needs for a one-shot `flashskyai -p` run.
final class FlashskyaiHeadlessProvisionCapability
    with HeadlessProvisionSupport
    implements HeadlessProvisionCapability {
  const FlashskyaiHeadlessProvisionCapability();

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
      final metadata = await profileInfra.metadataWithTrustedWorkspaces(
        metadataPath: metadataPath,
        defaultMetadata: FlashskyaiConfigProfileCapability.defaultMetadata,
        defaultWorkspaceConfig:
            FlashskyaiConfigProfileCapability.defaultWorkspaceConfig,
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
