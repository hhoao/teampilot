import 'dart:convert' show jsonDecode;
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../../models/credential_link_result.dart';
import '../../../../models/team_config.dart';
import '../../../../models/launch_security_policy.dart';
import '../../../provider/credential_binding.dart';
import '../../../storage/app_storage.dart';
import '../../registry/capabilities/headless_capability.dart';
import '../../registry/headless/headless_provision_support.dart';
import '../../registry/launch/headless_launch_context_adapter.dart';
import '../../registry/launch/cli_launch_arg_contribution.dart';
import '../../registry/launch/cli_launch_arg_provider.dart';
import '../capabilities/model_launch.dart';
import 'permission_launch.dart';
import 'session_selection_launch.dart';
import 'workspace_access_launch.dart';
import '../../registry/launch/user_extra_args_provider.dart';
import '../provider/claude_official_provider.dart';
import '../provider/claude_provider_credentials_service.dart';
import '../provider/claude_provider_settings_resolver.dart';
import 'provider.dart';

/// Claude one-shot via `claude -p`. Effort is expressed through a temp
/// `settings.json` (`effortLevel`) under `CLAUDE_CONFIG_DIR`. Provisions the
/// isolated config dir (settings.json + credentials) for the run, mirroring
/// the standalone launch path without persisting under `config-profiles/`.
final class ClaudeHeadlessCapability
    with HeadlessProvisionSupport
    implements HeadlessCapability {
  const ClaudeHeadlessCapability();

  @override
  bool get isSupported => true;

  @override
  bool get supportsStreaming => true;

  @override
  String get executable => 'claude';

  @override
  Map<String, String> buildEnvironment(HeadlessLaunchContext context) => {
    'CLAUDE_CONFIG_DIR': context.configDir,
  };

  @override
  List<HeadlessConfigFile> configFiles(HeadlessRunContext ctx) => const [];

  @override
  Iterable<CliLaunchArgContribution> buildHeadlessLaunchArgs(
    CliHeadlessLaunchContext ctx,
  ) sync* {
    final interactive = interactiveContextForHeadless(ctx, CliTool.claude);
    yield CliLaunchArgContribution(
      key: 'claude-headless-command',
      phase: LaunchArgPhase.command,
      args: ['-p'],
    );
    yield* const ClaudeSessionSelectionLaunch().buildLaunchArgs(interactive);
    yield* const ClaudeWorkspaceAccessLaunch().buildLaunchArgs(interactive);
    yield* const ClaudeModelLaunch().buildLaunchArgs(interactive);
    yield* const ClaudePermissionLaunch().buildLaunchArgs(interactive);
    yield CliLaunchArgContribution(
      key: 'claude-headless-prompt',
      phase: LaunchArgPhase.prompt,
      args: [ctx.prompt],
    );
    if (ctx.stream) {
      yield CliLaunchArgContribution(
        key: 'claude-headless-stream-format',
        phase: LaunchArgPhase.prompt,
        args: ['--output-format', 'stream-json', '--verbose'],
      );
    } else if (ctx.expectJson) {
      yield CliLaunchArgContribution(
        key: 'claude-headless-json-format',
        phase: LaunchArgPhase.prompt,
        args: ['--output-format', 'json'],
      );
    }
    yield* const UserExtraArgsProvider().buildLaunchArgs(interactive);
  }

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

  @override
  Future<HeadlessProvisionResult> provision(
    HeadlessProvisionContext ctx,
  ) async {
    final fs = this.fs;
    final basePath = this.basePath;
    await fs.ensureDir(ctx.configDir);

    final warnings = <String>[];
    final resolver = ClaudeProviderSettingsResolver(
      basePath: basePath,
      repository: repository,
      generator: generator,
    );
    final providerSettings = await resolver.resolve(ctx.providerId);
    if (providerSettings == null) {
      return const HeadlessProvisionResult(
        warnings: ['claude_provider_missing'],
        credentialsReady: false,
      );
    }

    final settings = Map<String, Object?>.from(providerSettings);
    final env = <String, Object?>{
      ...?((settings['env'] as Map?)?.map(
        (key, value) => MapEntry(key.toString(), value),
      )),
    };
    env['CLAUDE_CODE_NO_FLICKER'] = '1';
    env.putIfAbsent('CCGUI_CLI_LOGIN_AUTHORIZED', () => '1');
    env.putIfAbsent('CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC', () => '1');
    env.remove('CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS');

    final modelLabel = ctx.model.trim();
    if (modelLabel.isNotEmpty) {
      // Pin every tier default to the selected model so the one-shot call uses
      // exactly it, regardless of which tier the CLI routes background work to.
      // `--model` is also passed by the invocation; these env vars are a
      // belt-and-braces guarantee for a single headless run (not an interactive
      // session), so the cost of pinning Haiku-tier tasks is negligible.
      env['ANTHROPIC_MODEL'] = modelLabel;
      env['ANTHROPIC_DEFAULT_HAIKU_MODEL'] = modelLabel;
      env['ANTHROPIC_DEFAULT_SONNET_MODEL'] = modelLabel;
      env['ANTHROPIC_DEFAULT_OPUS_MODEL'] = modelLabel;
    }

    settings['env'] = env;
    final effortLabel = ctx.effort.trim();
    if (effortLabel.isNotEmpty) {
      settings['effortLevel'] = effortLabel;
    }
    if (ctx.securityPolicy == LaunchSecurityPolicy.fullAccess) {
      settings['skipDangerousModePermissionPrompt'] = true;
    }
    settings.remove('teammateMode');

    await writeJson(p.join(ctx.configDir, 'settings.json'), settings);

    final directories = <String>[
      if (ctx.workingDirectory != null &&
          ctx.workingDirectory!.trim().isNotEmpty)
        ctx.workingDirectory!.trim(),
    ];
    if (directories.isNotEmpty) {
      final metadataPath = p.join(
        ctx.configDir,
        ClaudeProviderCapability.metadataFileName,
      );
      final metadata = await profileInfra.metadataWithTrustedProjects(
        metadataPath: metadataPath,
        defaultMetadata: ClaudeProviderCapability.defaultMetadata,
        defaultProjectConfig: ClaudeProviderCapability.defaultProjectConfig,
        directories: directories,
      );
      await writeJson(metadataPath, metadata);
    }

    var credentialsReady = true;
    if (isOfficialClaudeSettings(providerSettings)) {
      final credentials = ClaudeProviderCredentialsService(
        fs: fs,
        basePath: basePath,
        resolveHomeDirectory: () => AppStorage.home,
      );
      final binding = ctx.provider == null
          ? CredentialBindingKind.linked
          : resolveCredentialBinding(ctx.provider!);
      final link = await credentials.ensureLinked(
        ctx.configDir,
        ctx.providerId,
        binding: binding,
        homeDirectory: AppStorage.home,
      );
      if (link == CredentialLinkResult.missing) {
        credentialsReady = false;
        warnings.add('claude_credentials_missing');
      }
    }

    return HeadlessProvisionResult(
      warnings: warnings,
      credentialsReady: credentialsReady,
    );
  }
}
