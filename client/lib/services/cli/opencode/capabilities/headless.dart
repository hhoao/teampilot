import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../../models/app_provider_config.dart';
import '../../registry/capabilities/headless_capability.dart';
import '../../registry/headless/headless_provision_support.dart';
import '../provider/opencode_auth_artifacts.dart';
import '../provider/opencode_data_layout.dart';
import '../provider/opencode_provider_settings_resolver.dart';
import 'provider.dart';

/// opencode one-shot via `opencode run`, plus provisioning of an isolated
/// config dir (opencode.json + auth env).
final class OpencodeHeadlessCapability
    with HeadlessProvisionSupport
    implements HeadlessCapability {
  const OpencodeHeadlessCapability();

  static const _layout = OpencodeDataLayout();

  @override
  bool get isSupported => true;

  @override
  bool get supportsStreaming => false;

  @override
  List<HeadlessConfigFile> configFiles(HeadlessRunContext ctx) => const [];

  @override
  HeadlessInvocation buildInvocation(HeadlessRunContext ctx) {
    final args = <String>['run'];
    final model = ctx.model.trim();
    if (model.isNotEmpty) args.addAll(['--model', model]);
    args.add(ctx.prompt);
    return HeadlessInvocation(
      executable: 'opencode',
      arguments: args,
      environment: {'OPENCODE_CONFIG_DIR': ctx.configDir},
    );
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
    config = _mergeOpencodeProvider(config, resolved);
    await writeJson(configPath, config);

    final extraEnvironment = <String, String>{};
    final authContent = await _readOpencodeAuthContent(resolved);
    if (authContent != null) {
      extraEnvironment[OpencodeProviderCapability.authContentEnv] =
          authContent;
    } else if (resolved.isOfficial) {
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

  Future<String?> _readOpencodeAuthContent(AppProviderConfig provider) async {
    if (!provider.isOfficial) return null;
    final authPath = _layout.providerAuthJsonPath(
      p.join(basePath, 'providers', 'opencode', provider.id),
    );
    if (!(await fs.stat(authPath)).isFile) return null;
    final content = await fs.readString(authPath);
    if (content == null || content.trim().isEmpty) return null;
    if (!OpencodeAuthArtifacts.authJsonIndicatesReady(content, provider.id)) {
      return null;
    }
    return content.trim();
  }

  Map<String, Object?> _mergeOpencodeProvider(
    Map<String, Object?> config,
    AppProviderConfig provider,
  ) {
    final id = provider.id.trim();
    if (id.isEmpty) return config;

    final providers = <String, Object?>{
      ...((config['provider'] as Map?)?.cast<String, Object?>() ??
          const <String, Object?>{}),
    };
    final existing =
        (providers[id] as Map?)?.cast<String, Object?>() ?? <String, Object?>{};
    final entry = <String, Object?>{...existing};
    final options = <String, Object?>{
      ...((existing['options'] as Map?)?.cast<String, Object?>() ??
          const <String, Object?>{}),
    };

    final apiKey = provider.apiKey.trim();
    if (apiKey.isNotEmpty) options['apiKey'] = apiKey;
    final baseUrl = provider.baseUrl.trim();
    if (baseUrl.isNotEmpty) options['baseURL'] = baseUrl;

    final npm = provider.config['npm'];
    if (npm is String && npm.trim().isNotEmpty && entry['npm'] == null) {
      entry['npm'] = npm.trim();
    }

    if (options.isNotEmpty) entry['options'] = options;
    if (entry.isEmpty) return config;

    providers[id] = entry;
    return {...config, 'provider': providers};
  }
}
