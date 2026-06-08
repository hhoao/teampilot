import '../../../models/app_provider_config.dart';
import '../../../models/claude_credential_link_result.dart';
import '../../cli/registry/capabilities/provider_credential_capability.dart';
import 'claude_official_provider.dart';
import 'claude_provider_credentials_service.dart';

final class ClaudeProviderCredentialCapability
    implements ProviderCredentialCapability {
  ClaudeProviderCredentialCapability({ClaudeProviderCredentialsService? credentials})
    : _credentials = credentials;

  final ClaudeProviderCredentialsService? _credentials;

  ClaudeProviderCredentialsService? get _service => _credentials;

  @override
  bool appliesTo(AppProviderConfig provider) =>
      isOfficialClaudeProvider(provider);

  @override
  bool hidesApiKeyFields(AppProviderConfig provider) => appliesTo(provider);

  @override
  List<ProviderCredentialActionSpec> actionsFor(AppProviderConfig provider) {
    if (!appliesTo(provider)) return const [];
    return const [
      ProviderCredentialActionSpec(
        kind: ProviderCredentialActionKind.login,
        primary: true,
        showWhenReady: false,
      ),
      ProviderCredentialActionSpec(kind: ProviderCredentialActionKind.importGlobal),
      ProviderCredentialActionSpec(kind: ProviderCredentialActionKind.importFile),
      ProviderCredentialActionSpec(
        kind: ProviderCredentialActionKind.revoke,
        showWhenReady: true,
      ),
    ];
  }

  @override
  Future<CredentialProbe> probe(String providerId) async {
    final service = _service;
    if (service == null) {
      return CredentialProbe(
        providerId: providerId,
        status: CredentialStatus.missing,
        credentialPath: '',
      );
    }
    return service.probe(providerId);
  }

  @override
  Future<bool> execute({
    required String providerId,
    required ProviderCredentialActionKind kind,
    ProviderCredentialActionInput input = const ProviderCredentialActionInput(),
  }) async {
    final service = _service;
    if (service == null) return false;
    return switch (kind) {
      ProviderCredentialActionKind.login => service.runAuthLogin(providerId),
      ProviderCredentialActionKind.importGlobal => service.importFromGlobal(
        providerId,
        homeDirectory: input.homeDirectory?.trim() ?? '',
        replace: input.replace,
      ),
      ProviderCredentialActionKind.importFile => service.importFromFile(
        providerId,
        input.pickedPath?.trim() ?? '',
        replace: input.replace,
      ),
      ProviderCredentialActionKind.importDirectory => false,
      ProviderCredentialActionKind.revoke => service.revokeCredentials(
        providerId,
      ),
    };
  }
}
