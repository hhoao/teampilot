import 'dart:convert' show jsonDecode;
import 'dart:io';

import '../../../../models/launch_security_policy.dart';
import '../../../../models/team_config.dart';
import 'package:path/path.dart' as p;

import '../../registry/capabilities/headless_capability.dart';
import '../../registry/headless/headless_provision_support.dart';
import '../../registry/launch/cli_launch_arg_contribution.dart';
import '../../registry/launch/headless_launch_context_adapter.dart';
import '../../registry/launch/user_extra_args_provider.dart';
import 'model_launch.dart';
import 'permission_launch.dart';
import 'session_selection_launch.dart';
import 'workspace_access_launch.dart';
import 'provider.dart';

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
  String get executable => 'flashskyai';

  @override
  Map<String, String> buildEnvironment(HeadlessLaunchContext context) => {
    FlashskyaiProviderCapability.configDirEnvKey: context.configDir,
    FlashskyaiProviderCapability.sessionHomeDirEnvKey: context.configDir,
  };

  @override
  List<HeadlessConfigFile> configFiles(HeadlessRunContext ctx) => const [];

  @override
  Iterable<CliLaunchArgContribution> buildHeadlessLaunchArgs(
    CliHeadlessLaunchContext ctx,
  ) sync* {
    final interactive = interactiveContextForHeadless(ctx, CliTool.flashskyai);
    yield CliLaunchArgContribution(
      key: 'flashskyai-headless-command',
      phase: LaunchArgPhase.command,
      args: ['-p'],
    );
    yield* const FlashskyaiSessionSelectionLaunch().buildLaunchArgs(
      interactive,
    );
    yield* const FlashskyaiWorkspaceAccessLaunch().buildLaunchArgs(interactive);
    yield* const FlashskyaiModelLaunch().buildLaunchArgs(interactive);
    yield* const FlashskyaiPermissionLaunch().buildLaunchArgs(interactive);
    yield CliLaunchArgContribution(
      key: 'flashskyai-headless-prompt',
      phase: LaunchArgPhase.prompt,
      args: [ctx.prompt],
    );
    if (ctx.stream) {
      yield CliLaunchArgContribution(
        key: 'flashskyai-headless-stream-format',
        phase: LaunchArgPhase.prompt,
        args: ['--output-format', 'stream-json', '--verbose'],
      );
    }
    yield* const UserExtraArgsProvider().buildLaunchArgs(interactive);
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
        FlashskyaiProviderCapability.metadataFileName,
      );
      final metadata = await profileInfra.metadataWithTrustedProjects(
        metadataPath: metadataPath,
        defaultMetadata: FlashskyaiProviderCapability.defaultMetadata,
        defaultProjectConfig: FlashskyaiProviderCapability.defaultProjectConfig,
        directories: directories,
      );
      await writeJson(metadataPath, metadata);
    }

    // flashskyai is a Claude-style CLI, so reasoning effort is carried via
    // settings.json `effortLevel` (mirrors the Claude provisioner).
    final settings = <String, Object?>{};
    if (ctx.securityPolicy == LaunchSecurityPolicy.fullAccess) {
      settings['skipDangerousModePermissionPrompt'] = true;
    }
    final effortLabel = ctx.effort.trim();
    if (effortLabel.isNotEmpty) {
      settings['effortLevel'] = effortLabel;
    }
    await writeJson(
      p.join(ctx.configDir, FlashskyaiProviderCapability.settingsFileName),
      settings,
    );

    return HeadlessProvisionResult(
      extraEnvironment: {
        FlashskyaiProviderCapability.configDirEnvKey: ctx.configDir,
        FlashskyaiProviderCapability.sessionHomeDirEnvKey: ctx.configDir,
        'LLM_CONFIG_PATH': layout.appFlashskyaiLlmConfigFile,
        'FLASHSKYAI_CODE_NO_FLICKER': '1',
      },
    );
  }
}
