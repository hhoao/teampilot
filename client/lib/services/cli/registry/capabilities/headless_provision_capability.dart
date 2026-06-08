import '../../../../models/app_provider_config.dart';
import '../cli_capability.dart';

/// Result of materializing an isolated CLI config dir for a headless run.
class HeadlessProvisionResult {
  const HeadlessProvisionResult({
    this.extraEnvironment = const {},
    this.warnings = const [],
    this.credentialsReady = true,
  });

  /// Extra process env entries (e.g. `OPENCODE_AUTH_CONTENT`).
  final Map<String, String> extraEnvironment;

  /// Machine-readable provisioning warnings (e.g. `claude_credentials_missing`).
  final List<String> warnings;

  /// False when OAuth credentials are required but missing for the provider.
  final bool credentialsReady;
}

/// Inputs for provisioning a temp config dir before a one-shot CLI call.
class HeadlessProvisionContext {
  const HeadlessProvisionContext({
    required this.provider,
    required this.providerId,
    required this.model,
    required this.effort,
    required this.configDir,
    this.workingDirectory,
  });

  final AppProviderConfig? provider;
  final String providerId;
  final String model;
  final String effort;
  final String configDir;
  final String? workingDirectory;
}

/// Per-CLI credential/settings provisioning for headless runs.
///
/// One implementation per CLI, registered on the tool definition and dispatched
/// via the registry (mirrors [HeadlessRunCapability]). Replaces the former
/// single `HeadlessConfigProvisioner` switch. A CLI with no provisioning needs
/// (e.g. cursor) simply omits the capability — the caller falls back to a
/// default [HeadlessProvisionResult].
abstract interface class HeadlessProvisionCapability implements CliCapability {
  Future<HeadlessProvisionResult> provision(HeadlessProvisionContext ctx);
}
