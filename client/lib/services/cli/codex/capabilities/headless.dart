import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../../models/app_provider_config.dart';
import '../../registry/capabilities/headless_capability.dart';
import '../../registry/headless/headless_provision_support.dart';
import '../provider/codex_auth_artifacts.dart';
import '../provider/codex_home_provisioner.dart';
import '../provider/codex_official_provider.dart';
import '../provider/codex_provider_settings_resolver.dart';

/// Codex one-shot via `codex exec` (effort via `-c model_reasoning_effort=`),
/// plus provisioning of an isolated `CODEX_HOME` (config + auth).
final class CodexHeadlessCapability
    with HeadlessProvisionSupport
    implements HeadlessCapability {
  const CodexHeadlessCapability();

  @override
  bool get isSupported => true;

  @override
  bool get supportsStreaming => false;

  @override
  List<HeadlessConfigFile> configFiles(HeadlessRunContext ctx) => const [];

  @override
  HeadlessInvocation buildInvocation(HeadlessRunContext ctx) {
    final args = <String>['exec'];
    final model = ctx.model.trim();
    if (model.isNotEmpty) args.addAll(['--model', model]);
    final effort = ctx.effort.trim();
    if (effort.isNotEmpty) {
      args.addAll(['-c', 'model_reasoning_effort=$effort']);
    }
    args.add(ctx.prompt);
    return HeadlessInvocation(
      executable: 'codex',
      arguments: args,
      environment: {'CODEX_HOME': ctx.configDir},
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
    final resolved =
        ctx.provider ??
        await CodexProviderSettingsResolver(
          basePath: basePath,
          repository: repository,
        ).findById(ctx.providerId);
    if (resolved == null) {
      return const HeadlessProvisionResult(
        warnings: ['codex_provider_missing'],
        credentialsReady: false,
      );
    }

    final trusted = <String>[
      if (ctx.workingDirectory != null &&
          ctx.workingDirectory!.trim().isNotEmpty)
        ctx.workingDirectory!.trim(),
    ];
    try {
      await CodexHomeProvisioner(fs: fs).provision(
        codexHome: ctx.configDir,
        provider: resolved,
        trustedProjectDirectories: trusted,
        storedAuthPath: _storedCodexAuthPath(resolved),
        reasoningEffortOverride: ctx.effort.trim().isNotEmpty
            ? ctx.effort.trim()
            : null,
        providerDir: p.join(basePath, 'providers', 'codex', resolved.id),
      );
    } on CodexHomeProvisionException catch (e) {
      warnings.add('codex_config_invalid: $e');
      return HeadlessProvisionResult(
        warnings: warnings,
        credentialsReady: false,
      );
    }

    if (isOfficialCodexOAuthProvider(resolved)) {
      final authPath = p.join(ctx.configDir, CodexAuthArtifacts.authFileName);
      if (!(await fs.stat(authPath)).isFile) {
        warnings.add('codex_credentials_missing');
        return HeadlessProvisionResult(
          warnings: warnings,
          credentialsReady: false,
        );
      }
    }

    return HeadlessProvisionResult(warnings: warnings);
  }

  String? _storedCodexAuthPath(AppProviderConfig provider) {
    if (!isOfficialCodexOAuthProvider(provider)) return null;
    return p.join(
      basePath,
      'providers',
      'codex',
      provider.id,
      CodexAuthArtifacts.authFileName,
    );
  }
}
