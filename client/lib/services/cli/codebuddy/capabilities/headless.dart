import 'dart:convert';
import 'dart:io';

import '../../../../models/app_provider_config.dart';
import '../../../../models/team_config.dart';
import '../../../storage/home_storage.dart';
import '../../registry/capabilities/headless_capability.dart';
import '../../registry/headless/headless_provision_support.dart';
import '../../registry/launch/cli_launch_arg_contribution.dart';
import '../../registry/launch/headless_launch_context_adapter.dart';
import '../../registry/launch/user_extra_args_provider.dart';
import '../provider/codebuddy_auth_store.dart';
import '../provider/codebuddy_provider_settings_resolver.dart';

/// CodeBuddy one-shot via `codebuddy -p`.
///
/// `CODEBUDDY_CONFIG_DIR` points at the one-shot temp config dir; provider
/// settings (`settings.json`, `models.json`) are materialized there and the
/// API key travels only in the process env.
final class CodebuddyHeadlessCapability
    with HeadlessProvisionSupport
    implements HeadlessCapability {
  const CodebuddyHeadlessCapability({this.storage});

  @override
  final HomeStorage? storage;

  static const configDirEnvKey = 'CODEBUDDY_CONFIG_DIR';
  static const apiKeyEnvKey = 'CODEBUDDY_API_KEY';
  static const baseUrlEnvKey = 'CODEBUDDY_BASE_URL';

  @override
  bool get isSupported => true;

  @override
  bool get supportsStreaming => true;

  @override
  bool get supportsPromptStdin => true;

  @override
  String get executable => 'codebuddy';

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
    final interactive = interactiveContextForHeadless(ctx, CliTool.codebuddy);
    yield CliLaunchArgContribution(
      key: 'codebuddy-headless-command',
      phase: LaunchArgPhase.command,
      args: ['-p'],
    );
    final model = ctx.model.trim();
    if (model.isNotEmpty) {
      yield CliLaunchArgContribution(
        key: 'codebuddy-headless-model',
        phase: LaunchArgPhase.behavior,
        args: ['--model', model],
      );
    }
    yield CliLaunchArgContribution(
      key: 'codebuddy-headless-permission',
      phase: LaunchArgPhase.behavior,
      args: ctx.securityPolicy == LaunchSecurityPolicy.fullAccess
          ? const ['-y']
          : const ['--permission-mode', 'default'],
    );
    if (!ctx.promptViaStdin) {
      yield CliLaunchArgContribution(
        key: 'codebuddy-headless-prompt',
        phase: LaunchArgPhase.prompt,
        args: [ctx.prompt],
      );
    }
    if (ctx.stream) {
      yield CliLaunchArgContribution(
        key: 'codebuddy-headless-stream-format',
        phase: LaunchArgPhase.prompt,
        args: ['--output-format', 'stream-json', '--verbose'],
      );
    } else if (ctx.expectJson) {
      yield CliLaunchArgContribution(
        key: 'codebuddy-headless-json-format',
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
    await fs.ensureDir(ctx.configDir);

    final provider = await _resolveProvider(ctx);
    final settings = await readJsonMap(
      fs.pathContext.join(ctx.configDir, 'settings.json'),
    );

    final model = _resolveModel(ctx, provider);
    if (model.isNotEmpty) settings['model'] = model;
    final effort = ctx.effort.trim();
    if (effort.isNotEmpty) {
      settings['reasoningEffort'] = effort;
    }
    await writeJson(
      fs.pathContext.join(ctx.configDir, 'settings.json'),
      settings,
    );

    final extraEnvironment = <String, String>{};
    final store = CodebuddyAuthStore(
      fs: fs,
      basePath: basePath,
      pathContext: fs.pathContext,
    );
    final authProviderId = (provider?.id ?? ctx.providerId).trim();
    if (authProviderId.isNotEmpty) {
      final token = store.accessTokenFor(
        await store.readProviderAuth(authProviderId),
      );
      if (token != null) {
        extraEnvironment[CodebuddyAuthStore.apiKeyEnvKey] = token;
      }
    }
    if (provider != null) {
      final apiKey = provider.apiKey.trim();
      if (apiKey.isNotEmpty) extraEnvironment[apiKeyEnvKey] = apiKey;
      final baseUrl = provider.baseUrl.trim();
      if (baseUrl.isNotEmpty) {
        extraEnvironment[baseUrlEnvKey] = baseUrl;
        if (model.isNotEmpty) {
          await _writeModelsJson(
            configDir: ctx.configDir,
            provider: provider,
            model: model,
          );
        }
      }
    }

    return HeadlessProvisionResult(extraEnvironment: extraEnvironment);
  }

  Future<AppProviderConfig?> _resolveProvider(
    HeadlessProvisionContext ctx,
  ) async {
    if (ctx.provider != null) return ctx.provider;
    final home = storage;
    if (home == null) return null;
    final resolver = CodebuddyProviderSettingsResolver(
      basePath: basePath,
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
    return provider?.defaultModel.trim() ?? '';
  }

  Future<void> _writeModelsJson({
    required String configDir,
    required AppProviderConfig provider,
    required String model,
  }) async {
    final baseUrl = provider.baseUrl.trim();
    final url = baseUrl.endsWith('/chat/completions')
        ? baseUrl
        : '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/chat/completions';
    final Map<String, Object?> payload = {
      'models': [
        <String, Object?>{
          'id': model,
          'name': model,
          'vendor': provider.name.trim().isEmpty ? 'custom' : provider.name,
          'apiKey': r'${CODEBUDDY_API_KEY}',
          'url': url,
          'supportsToolCall': true,
          'supportsImages': true,
        },
      ],
      'availableModels': [model],
    };
    await writeJson(fs.pathContext.join(configDir, 'models.json'), payload);
  }
}
