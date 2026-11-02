import 'dart:convert';
import 'dart:io';

import '../../../../models/app_provider_config.dart';
import '../../../../models/team_config.dart';
import '../../../../utils/logging/logger_utils.dart';
import '../../../storage/home_storage.dart';
import '../../registry/capabilities/headless_capability.dart';
import '../../registry/headless/headless_provision_support.dart';
import '../../registry/launch/cli_launch_arg_contribution.dart';
import '../../registry/launch/headless_launch_context_adapter.dart';
import '../../registry/launch/user_extra_args_provider.dart';
import '../provider/qoder_auth_store.dart';
import '../provider/qoder_provider_settings_resolver.dart';

/// Qoder one-shot via `qodercli -p`.
///
/// `QODER_CONFIG_DIR` points at the one-shot temp config dir. Qoder is
/// account-only (no API key / base URL), so provisioning writes the model
/// selection to `settings.json` and seeds `.auth` from the provider store or
/// the machine login — a fresh config dir cannot authenticate on its own.
final class QoderHeadlessCapability
    with HeadlessProvisionSupport
    implements HeadlessCapability {
  const QoderHeadlessCapability({this.storage});

  @override
  final HomeStorage? storage;

  static const configDirEnvKey = 'QODER_CONFIG_DIR';
  static const credentialsMissingWarning = 'qoder_credentials_missing';

  @override
  bool get isSupported => true;

  @override
  bool get supportsStreaming => true;

  @override
  bool get supportsPromptStdin => true;

  @override
  String get executable => 'qodercli';

  @override
  Map<String, String> buildEnvironment(HeadlessLaunchContext context) => {
    configDirEnvKey: context.configDir,
  };

  @override
  List<HeadlessConfigFile> configFiles(HeadlessRunContext ctx) => const [];

  @override
  Iterable<CliLaunchArgContribution> buildHeadlessLaunchArgs(
    CliHeadlessLaunchContext ctx,
  ) sync* {
    final interactive = interactiveContextForHeadless(ctx, CliTool.qoder);
    // No `--model` here: the model is selected through settings.json (see
    // provision()) so the one-shot call uses the same provider-config path as
    // an ACP session.
    yield CliLaunchArgContribution(
      key: 'qoder-headless-command',
      phase: LaunchArgPhase.command,
      args: const ['-p'],
    );
    yield CliLaunchArgContribution(
      key: 'qoder-headless-permission',
      phase: LaunchArgPhase.behavior,
      args: ctx.securityPolicy == LaunchSecurityPolicy.fullAccess
          ? const ['--permission-mode', 'bypass_permissions']
          : const ['--permission-mode', 'default'],
    );
    // In stdin mode the piped content is the prompt; no positional prompt.
    if (!ctx.promptViaStdin) {
      yield CliLaunchArgContribution(
        key: 'qoder-headless-prompt',
        phase: LaunchArgPhase.prompt,
        args: [ctx.prompt],
      );
    }
    if (ctx.stream) {
      yield CliLaunchArgContribution(
        key: 'qoder-headless-stream-format',
        phase: LaunchArgPhase.prompt,
        args: const ['--output-format', 'stream-json'],
      );
    } else if (ctx.expectJson) {
      yield CliLaunchArgContribution(
        key: 'qoder-headless-json-format',
        phase: LaunchArgPhase.prompt,
        args: const ['--output-format', 'json'],
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
    await fs.ensureDir(ctx.configDir);

    final provider = await _resolveProvider(ctx);
    final settingsPath = fs.pathContext.join(ctx.configDir, 'settings.json');
    final settings = await readJsonMap(settingsPath);

    final model = _resolveModel(ctx, provider);
    if (model.isNotEmpty) settings['model'] = model;
    final effort = ctx.effort.trim();
    if (effort.isNotEmpty) settings['reasoningEffort'] = effort;
    await writeJson(settingsPath, settings);

    final providerId = (provider?.id ?? ctx.providerId).trim();
    if (providerId.isEmpty) return const HeadlessProvisionResult();

    final store = QoderAuthStore(
      fs: fs,
      basePath: basePath,
      pathContext: fs.pathContext,
      machineHome: home,
    );
    if (await store.seedSessionAuth(
      providerId: providerId,
      sessionConfigDir: ctx.configDir,
    )) {
      return const HeadlessProvisionResult();
    }
    AppLogger.instance.w(
      'qoder: headless .auth not seeded; the run will need a sign-in '
      '(provider "$providerId")',
    );
    return const HeadlessProvisionResult(
      warnings: [credentialsMissingWarning],
      credentialsReady: false,
    );
  }

  Future<AppProviderConfig?> _resolveProvider(
    HeadlessProvisionContext ctx,
  ) async {
    if (ctx.provider != null) return ctx.provider;
    final home = storage;
    if (home == null) return null;
    final resolver = QoderProviderSettingsResolver(
      basePath: basePath,
      fs: fs,
      storage: home,
    );
    final byId = await resolver.findById(ctx.providerId);
    if (byId != null) return byId;
    return resolver.resolveSole();
  }

  String _resolveModel(
    HeadlessProvisionContext ctx,
    AppProviderConfig? provider,
  ) {
    final fromCtx = ctx.model.trim();
    if (fromCtx.isNotEmpty) return fromCtx;
    // No model chosen anywhere → leave settings.model untouched so the CLI's
    // own account default applies.
    return provider?.defaultModel.trim() ?? '';
  }
}
