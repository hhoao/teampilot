import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../../models/team_config.dart';
import '../../../storage/home_storage.dart';
import '../../registry/capabilities/headless_capability.dart';
import '../../registry/headless/headless_provision_support.dart';
import '../../registry/launch/cli_launch_arg_contribution.dart';
import '../../registry/launch/cli_launch_context.dart';
import '../../registry/launch/headless_launch_context_adapter.dart';
import '../../registry/launch/user_extra_args_provider.dart';
import 'agent_launch.dart';
import 'model_launch.dart';
import 'session_selection_launch.dart';
import '../provider/opencode_credential_kind.dart';
import '../provider/opencode_credential_materializer.dart';
import '../provider/opencode_provider_settings_resolver.dart';
import 'provider.dart';
import 'standalone_launch.dart';

/// opencode one-shot via `opencode run`, plus provisioning of an isolated
/// config dir (opencode.json + auth env).
final class OpencodeHeadlessCapability
    with HeadlessProvisionSupport
    implements HeadlessCapability {
  const OpencodeHeadlessCapability({this.storage});

  @override
  final HomeStorage? storage;

  @override
  bool get isSupported => true;

  @override
  bool get supportsStreaming => false;

  @override
  bool get supportsPromptStdin => false;

  @override
  String get executable => 'opencode';

  @override
  Map<String, String> buildEnvironment(HeadlessLaunchContext context) => {
    'OPENCODE_CONFIG_DIR': context.configDir,
  };

  @override
  List<HeadlessConfigFile> configFiles(HeadlessRunContext ctx) => const [];

  @override
  Iterable<CliLaunchArgContribution> buildHeadlessLaunchArgs(
    CliHeadlessLaunchContext ctx,
  ) sync* {
    final interactive = interactiveContextForHeadless(ctx, CliTool.opencode);
    yield* const OpencodeStandaloneLaunch().buildLaunchArgs(interactive);
    yield CliLaunchArgContribution(
      key: 'opencode-headless-command',
      phase: LaunchArgPhase.command,
      args: ['run'],
    );
    yield* const OpencodeSessionSelectionLaunch().buildLaunchArgs(interactive);
    yield* const OpencodeModelLaunch().buildHeadlessLaunchArgs(interactive);
    yield* const OpencodeAgentLaunch().buildHeadlessLaunchArgs(interactive);
    yield CliLaunchArgContribution(
      key: 'opencode-headless-prompt',
      phase: LaunchArgPhase.prompt,
      args: [ctx.prompt],
    );
    yield* const UserExtraArgsProvider().buildLaunchArgs(interactive);
  }

  @override
  String extractText(ProcessResult result) =>
      (result.stdout as String? ?? '').trim();

  @override
  String? streamResultText(String line) => null;

  @override
  Future<HeadlessProvisionResult> provision(
    HeadlessProvisionContext ctx,
  ) async {
    final fs = this.fs;
    await fs.ensureDir(ctx.configDir);

    final warnings = <String>[];
    final resolver = OpencodeProviderSettingsResolver(
      basePath: basePath,
      storage: storage ?? _missingHomeStorage(),
      repository: repository,
    );
    final resolved = ctx.provider ?? await resolver.findById(ctx.providerId);
    if (resolved == null) {
      return const HeadlessProvisionResult(
        warnings: ['opencode_provider_missing'],
        credentialsReady: false,
      );
    }

    final configPath = p.join(
      ctx.configDir,
      OpencodeProviderCapability.opencodeConfigFileName,
    );
    var config = await readJsonMap(configPath);
    config = mergeOpencodeProvider(config, resolved);
    config = mergeOpencodeDefaultModel(
      config,
      providerId: resolved.id,
      modelId: ctx.model,
    );
    config = mergeOpencodeSecurityPolicy(config, ctx.securityPolicy);
    final externalDirectories = <String>[
      for (final directory in ctx.additionalDirectories)
        if (directory.trim().isNotEmpty)
          normalizePathForCli(directory.trim(), useWslPaths: ctx.useWslPaths),
    ];
    if (externalDirectories.isNotEmpty) {
      config = mergeOpencodeExternalDirectories(config, externalDirectories);
    }
    await writeJson(configPath, config);

    final extraEnvironment = <String, String>{};
    final authContent = OpencodeCredentialMaterializer.authJsonContent(
      resolved,
    );
    if (authContent != null) {
      extraEnvironment[OpencodeProviderCapability.authContentEnv] = authContent;
    } else if (OpencodeCredentialKindResolver.needsCredential(resolved)) {
      warnings.add('opencode_credentials_missing');
      return HeadlessProvisionResult(
        warnings: warnings,
        credentialsReady: false,
      );
    }

    return HeadlessProvisionResult(
      extraEnvironment: extraEnvironment,
      warnings: warnings,
    );
  }

  HomeStorage _missingHomeStorage() {
    throw StateError(
      'OpencodeHeadlessCapability was constructed without HomeStorage; storage use requires the '
      'registry configured with CliBootstrap(storage: …).',
    );
  }
}
