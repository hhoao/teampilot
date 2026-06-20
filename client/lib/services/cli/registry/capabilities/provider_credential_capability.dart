import '../../../../models/app_provider_config.dart';
import '../../../../models/claude_credential_link_result.dart';
import '../../../../models/credential_action_result.dart';
import '../cli_capability.dart';

/// Credential actions exposed in provider add/edit/detail UI.
enum ProviderCredentialActionKind {
  login,
  importGlobal,
  importFile,
  importDirectory,
  revoke,
}

/// Declares which actions a CLI supports for a given provider row.
class ProviderCredentialActionSpec {
  const ProviderCredentialActionSpec({
    required this.kind,
    this.primary = false,
    this.showWhenReady = true,
  });

  final ProviderCredentialActionKind kind;

  /// Renders as [FilledButton.tonal] when true.
  final bool primary;

  /// When false, hide this action after credentials are ready (e.g. login).
  /// When true, keep visible when ready (e.g. import, revoke / sign out).
  final bool showWhenReady;
}

/// Optional inputs for file/directory credential imports.
class ProviderCredentialActionInput {
  const ProviderCredentialActionInput({
    this.pickedPath,
    this.replace = false,
    this.homeDirectory,
  });

  final String? pickedPath;
  final bool replace;
  final String? homeDirectory;
}

/// Per-CLI OAuth / filesystem credential flows for official account providers.
abstract interface class ProviderCredentialCapability implements CliCapability {
  bool appliesTo(AppProviderConfig provider);

  List<ProviderCredentialActionSpec> actionsFor(AppProviderConfig provider);

  Future<CredentialProbe> probe(String providerId);

  Future<CredentialActionResult> execute({
    required String providerId,
    required ProviderCredentialActionKind kind,
    ProviderCredentialActionInput input = const ProviderCredentialActionInput(),
  });

  /// Hides API-key style fields on add/edit forms when credentials are managed
  /// out-of-band (OAuth HOME dirs, auth.json, …).
  bool hidesApiKeyFields(AppProviderConfig provider);
}
