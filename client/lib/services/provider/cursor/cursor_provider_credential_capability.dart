import '../../../models/app_provider_config.dart';
import '../../../models/claude_credential_link_result.dart';
import '../../../models/credential_action_result.dart';
import '../../cli/registry/capabilities/provider_credential_capability.dart';
import 'cursor_provider_credentials_service.dart';

final class CursorProviderCredentialCapability
    implements ProviderCredentialCapability {
  CursorProviderCredentialCapability({CursorProviderCredentialsService? credentials})
    : _credentials = credentials;

  final CursorProviderCredentialsService? _credentials;

  CursorProviderCredentialsService? get _service => _credentials;

  @override
  bool appliesTo(AppProviderConfig provider) =>
      provider.cli == CliTool.cursor && provider.isOfficial;

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
      ProviderCredentialActionSpec(
        kind: ProviderCredentialActionKind.importDirectory,
      ),
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
    return service.probe(provider.id);
  }

  @override
  Future<CredentialActionResult> execute({
    required String providerId,
    required ProviderCredentialActionKind kind,
    ProviderCredentialActionInput input = const ProviderCredentialActionInput(),
  }) async {
    final service = _service;
    if (service == null) return CredentialActionResult.serviceUnavailable();
    final path = input.pickedPath?.trim() ?? '';
    return switch (kind) {
      ProviderCredentialActionKind.login => service.runAuthLogin(providerId),
      ProviderCredentialActionKind.importGlobal => service.importFromGlobal(
        providerId,
        homeDirectory: input.homeDirectory?.trim() ?? '',
        replace: input.replace,
      ),
      ProviderCredentialActionKind.importDirectory =>
        path.isEmpty
            ? CredentialActionResult.failure(
                const CredentialActionFailure(
                  code: CredentialActionFailureCode.pathRequired,
                ),
              )
            : _importCursorPath(
                service,
                providerId: providerId,
                path: path,
                replace: input.replace,
              ),
      ProviderCredentialActionKind.importFile =>
        path.isEmpty
            ? CredentialActionResult.failure(
                const CredentialActionFailure(
                  code: CredentialActionFailureCode.pathRequired,
                ),
              )
            : service.importAuthJsonFile(
                providerId,
                path,
                replace: input.replace,
              ),
      ProviderCredentialActionKind.revoke => service.revokeCredentials(
        providerId,
      ),
    };
  }
}

Future<CredentialActionResult> _importCursorPath(
  CursorProviderCredentialsService service, {
  required String providerId,
  required String path,
  required bool replace,
}) async {
  if (path.endsWith('auth.json')) {
    return service.importAuthJsonFile(providerId, path, replace: replace);
  }
  return service.importFromCursorDirectory(
    providerId,
    path,
    replace: replace,
  );
}
