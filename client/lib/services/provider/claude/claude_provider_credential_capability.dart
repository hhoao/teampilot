import '../../../models/app_provider_config.dart';
import '../../../models/claude_credential_link_result.dart';
import '../../../models/credential_action_result.dart';
import '../../cli/registry/capabilities/provider_credential_capability.dart';
import '../../storage/app_storage.dart';
import '../../storage/runtime_storage_context.dart';
import '../credential_binding.dart';
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
  Future<CredentialProbe> probe(AppProviderConfig provider) async {
    final service = _service;
    if (service == null) {
      return CredentialProbe(
        providerId: provider.id,
        status: CredentialStatus.missing,
        credentialPath: '',
      );
    }
    final binding = resolveCredentialBinding(provider);
    return service.probe(
      provider.id,
      binding: binding,
      homeDirectory: _resolveHomeDirectory(),
    );
  }

  static String _resolveHomeDirectory() {
    if (!RuntimeStorageContext.isInstalled) return '';
    try {
      return AppStorage.home;
    } on Object {
      return '';
    }
  }

  @override
  Future<CredentialActionResult> execute({
    required String providerId,
    required ProviderCredentialActionKind kind,
    ProviderCredentialActionInput input = const ProviderCredentialActionInput(),
  }) async {
    final service = _service;
    if (service == null) return CredentialActionResult.serviceUnavailable();
    final provider = input.provider;
    final binding = provider == null
        ? CredentialBindingKind.linked
        : resolveCredentialBinding(provider);
    final home = input.homeDirectory?.trim().isNotEmpty == true
        ? input.homeDirectory!.trim()
        : _resolveHomeDirectory();
    return switch (kind) {
      ProviderCredentialActionKind.login => service.runAuthLogin(
        providerId,
        binding: binding,
        homeDirectory: home,
      ),
      ProviderCredentialActionKind.importGlobal => service.importFromGlobal(
        providerId,
        homeDirectory: home,
        replace: input.replace,
        binding: binding,
      ),
      ProviderCredentialActionKind.importFile => service.importFromFile(
        providerId,
        input.pickedPath?.trim() ?? '',
        replace: input.replace,
      ),
      ProviderCredentialActionKind.importDirectory =>
        CredentialActionResult.unsupported(),
      ProviderCredentialActionKind.revoke => service.revokeCredentials(
        providerId,
        binding: binding,
        homeDirectory: home,
      ),
    };
  }
}
