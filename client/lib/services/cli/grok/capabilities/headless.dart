import 'dart:convert';
import 'dart:io';

import '../../../../models/team_config.dart';
import '../../../storage/home_storage.dart';
import '../../registry/capabilities/headless_capability.dart';
import '../../registry/headless/headless_provision_support.dart';
import '../../registry/launch/cli_launch_arg_contribution.dart';
import '../../registry/launch/headless_launch_context_adapter.dart';
import '../../registry/launch/user_extra_args_provider.dart';
import '../grok_constants.dart';
import '../grok_toml.dart';
import '../provider/grok_auth_store.dart';
import '../provider/grok_provider_settings_resolver.dart';

/// Grok one-shot via `grok -p <prompt>`, plus seeding of an isolated
/// `GROK_HOME` (config.toml model + auth.json or XAI_API_KEY).
final class GrokHeadlessCapability
    with HeadlessProvisionSupport
    implements HeadlessCapability {
  const GrokHeadlessCapability({this.storage});

  @override
  final HomeStorage? storage;

  @override
  bool get isSupported => true;

  @override
  bool get supportsStreaming => true;

  @override
  bool get supportsPromptStdin => false;

  @override
  String get executable => GrokConstants.executableName;

  @override
  Map<String, String> buildEnvironment(HeadlessLaunchContext context) => {
    GrokConstants.homeEnvKey: context.configDir,
    'GROK_DISABLE_AUTOUPDATER': '1',
  };

  @override
  List<HeadlessConfigFile> configFiles(HeadlessRunContext ctx) => const [];

  @override
  Iterable<CliLaunchArgContribution> buildHeadlessLaunchArgs(
    CliHeadlessLaunchContext ctx,
  ) sync* {
    final interactive = interactiveContextForHeadless(ctx, CliTool.grok);
    final model = ctx.model.trim();
    if (model.isNotEmpty) {
      yield CliLaunchArgContribution(
        key: 'grok-headless-model',
        phase: LaunchArgPhase.model,
        args: ['--model', model],
      );
    }
    final effort = ctx.effort.trim();
    if (effort.isNotEmpty) {
      yield CliLaunchArgContribution(
        key: 'grok-headless-effort',
        phase: LaunchArgPhase.behavior,
        args: ['--reasoning-effort', effort],
      );
    }
    if (ctx.securityPolicy == LaunchSecurityPolicy.fullAccess) {
      yield CliLaunchArgContribution(
        key: 'grok-headless-permission',
        phase: LaunchArgPhase.behavior,
        args: ['--always-approve'],
      );
    } else {
      yield CliLaunchArgContribution(
        key: 'grok-headless-permission',
        phase: LaunchArgPhase.behavior,
        args: ['--permission-mode', 'default'],
      );
    }
    final resume = ctx.resumeSessionId?.trim() ?? '';
    if (resume.isNotEmpty) {
      yield CliLaunchArgContribution(
        key: 'grok-headless-resume',
        phase: LaunchArgPhase.session,
        args: ['--resume', resume],
      );
    }
    if (!ctx.promptViaStdin) {
      yield CliLaunchArgContribution(
        key: 'grok-headless-prompt',
        phase: LaunchArgPhase.prompt,
        args: ['-p', ctx.prompt],
      );
    }
    if (ctx.stream) {
      yield CliLaunchArgContribution(
        key: 'grok-headless-stream-format',
        phase: LaunchArgPhase.behavior,
        args: ['--output-format', 'streaming-json'],
      );
    } else if (ctx.expectJson) {
      yield CliLaunchArgContribution(
        key: 'grok-headless-json-format',
        phase: LaunchArgPhase.behavior,
        args: ['--output-format', 'json'],
      );
    }
    yield* const UserExtraArgsProvider().buildLaunchArgs(interactive);
  }

  @override
  String? streamResultText(String line) {
    // `streaming-json` terminal `end` carries metadata, not the final text.
    // The accumulated `text` events are reconstructed by [extractText].
    return null;
  }

  @override
  String extractText(ProcessResult result) {
    final out = (result.stdout as String? ?? '').trim();
    if (out.isEmpty) return '';
    // json (single object) and streaming-json (NDJSON) both start with `{`.
    final objects = <Map<String, Object?>>[];
    if (out.startsWith('{')) {
      try {
        final decoded = jsonDecode(out);
        if (decoded is Map) {
          objects.add(Map<String, Object?>.from(decoded));
        }
      } on FormatException {
        for (final line in out.split('\n')) {
          final trimmed = line.trim();
          if (!trimmed.startsWith('{')) continue;
          try {
            final decoded = jsonDecode(trimmed);
            if (decoded is Map) {
              objects.add(Map<String, Object?>.from(decoded));
            }
          } on FormatException {
            // Skip malformed stream lines.
          }
        }
      }
    }
    if (objects.isEmpty) return out;

    // Single-object `json`: `text` is the response. `--output-format json`
    // does not use the Messages `result` field.
    for (final object in objects) {
      final type = object['type']?.toString() ?? '';
      if (type == 'result' || type == 'end') {
        final text = object['result'] ?? object['text'];
        if (text is String && text.trim().isNotEmpty) return text.trim();
      }
    }
    final text = objects
        .where((object) => object['type']?.toString() == 'text')
        .map((object) => object['data']?.toString() ?? '')
        .join();
    if (text.trim().isNotEmpty) return text.trim();
    for (final object in objects) {
      final value = object['text'];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return out;
  }

  @override
  Future<HeadlessProvisionResult> provision(
    HeadlessProvisionContext ctx,
  ) async {
    final fs = this.fs;
    await fs.ensureDir(ctx.configDir);

    final provider =
        ctx.provider ??
        await GrokProviderSettingsResolver(
          basePath: basePath,
          storage: storage!,
        ).findById(ctx.providerId);
    final model = ctx.model.trim().isNotEmpty
        ? ctx.model.trim()
        : provider?.defaultModel.trim() ?? '';
    final configPath = fs.pathContext.join(
      ctx.configDir,
      GrokConstants.configFileName,
    );
    if (model.isNotEmpty) {
      await mergeGrokTomlSection(
        fs: fs,
        configPath: configPath,
        section: 'models',
        values: {'default': model},
      );
    }
    await writeGrokIsolationDefaults(fs, configPath);

    final warnings = <String>[];
    final extraEnvironment = <String, String>{};
    final apiKey = provider?.apiKey.trim() ?? '';
    if (apiKey.isNotEmpty) {
      extraEnvironment[GrokConstants.apiKeyEnvKey] = apiKey;
    } else {
      final store = GrokAuthStore(
        fs: fs,
        basePath: basePath,
        pathContext: fs.pathContext,
        machineHome: home,
      );
      final providerId = provider?.id.trim() ?? ctx.providerId.trim();
      final seeded = await store.seedSessionAuth(
        providerId: providerId,
        sessionFs: fs,
        sessionPathContext: fs.pathContext,
        sessionConfigDir: ctx.configDir,
      );
      if (!seeded) {
        warnings.add('grok_credentials_missing');
        return HeadlessProvisionResult(
          extraEnvironment: extraEnvironment,
          warnings: warnings,
          credentialsReady: false,
        );
      }
    }

    return HeadlessProvisionResult(
      extraEnvironment: extraEnvironment,
      warnings: warnings,
    );
  }
}
