import 'package:path/path.dart' as p;

import '../../../../models/app_provider_config.dart';
import '../../../provider/codex/codex_auth_artifacts.dart';
import '../../../provider/codex/codex_home_provisioner.dart';
import '../../../provider/codex/codex_official_provider.dart';
import '../../../provider/codex/codex_provider_settings_resolver.dart';
import '../capabilities/headless_provision_capability.dart';
import 'headless_provision_support.dart';

/// Provisions an isolated `CODEX_HOME` (config + auth) for a one-shot
/// `codex exec` run.
final class CodexHeadlessProvisionCapability
    with HeadlessProvisionSupport
    implements HeadlessProvisionCapability {
  const CodexHeadlessProvisionCapability();

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
        reasoningEffortOverride:
            ctx.effort.trim().isNotEmpty ? ctx.effort.trim() : null,
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
