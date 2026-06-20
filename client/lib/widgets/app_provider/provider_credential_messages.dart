import '../../l10n/app_localizations.dart';
import '../../models/app_provider_config.dart';
import '../../models/credential_action_result.dart';

String providerCredentialSuccessMessage(
  AppLocalizations l10n,
  CliTool cli,
) {
  return switch (cli) {
    CliTool.claude => l10n.claudeOfficialCredentialsActionSuccess,
    CliTool.cursor => l10n.cursorCredentialsActionSuccess,
    CliTool.codex => l10n.codexCredentialsActionSuccess,
    CliTool.opencode => l10n.opencodeCredentialsActionSuccess,
    _ => l10n.claudeOfficialCredentialsActionSuccess,
  };
}

String providerCredentialFailureMessage(
  AppLocalizations l10n,
  CliTool cli,
  CredentialActionResult result,
) {
  final failure = result.failure;
  if (failure == null) {
    return _genericFailureMessage(l10n, cli);
  }

  return switch (failure.code) {
    CredentialActionFailureCode.unsupported =>
      l10n.providerCredentialsFailureUnsupported,
    CredentialActionFailureCode.serviceUnavailable =>
      l10n.providerCredentialsFailureServiceUnavailable,
    CredentialActionFailureCode.providerNotFound =>
      l10n.providerCredentialsFailureProviderNotFound,
    CredentialActionFailureCode.pathRequired =>
      l10n.providerCredentialsFailurePathRequired,
    CredentialActionFailureCode.sourceMissing =>
      l10n.providerCredentialsFailureSourceMissing(
        failure.path ?? failure.detail ?? '',
      ),
    CredentialActionFailureCode.sourceUnreadable =>
      l10n.providerCredentialsFailureSourceUnreadable(
        failure.path ?? failure.detail ?? '',
      ),
    CredentialActionFailureCode.providerEntryMissing =>
      _providerEntryMissingMessage(l10n, failure),
    CredentialActionFailureCode.invalidCredential =>
      l10n.providerCredentialsFailureInvalidCredential,
    CredentialActionFailureCode.destinationExists =>
      l10n.providerCredentialsFailureDestinationExists,
    CredentialActionFailureCode.requiredFileMissing =>
      l10n.providerCredentialsFailureRequiredFileMissing(
        failure.path ?? failure.detail ?? '',
      ),
    CredentialActionFailureCode.loginFailed =>
      l10n.providerCredentialsFailureLoginFailed(failure.exitCode ?? -1),
    CredentialActionFailureCode.loginProcessError =>
      l10n.providerCredentialsFailureLoginProcessError(
        failure.detail ?? '',
      ),
    CredentialActionFailureCode.revokeFailed =>
      l10n.providerCredentialsFailureRevokeFailed,
    CredentialActionFailureCode.verifyFailed =>
      l10n.providerCredentialsFailureVerifyFailed,
    CredentialActionFailureCode.statusRefreshFailed =>
      l10n.providerCredentialsFailureStatusRefreshFailed,
  };
}

String _providerEntryMissingMessage(
  AppLocalizations l10n,
  CredentialActionFailure failure,
) {
  final path = failure.path ?? '';
  final providerId = failure.providerId ?? '';
  final keys = failure.availableProviderIds;
  if (keys.isNotEmpty) {
    return l10n.providerCredentialsFailureProviderEntryMissingWithKeys(
      providerId,
      path,
      keys.join(', '),
    );
  }
  return l10n.providerCredentialsFailureProviderEntryMissing(
    providerId,
    path,
  );
}

String _genericFailureMessage(AppLocalizations l10n, CliTool cli) {
  return switch (cli) {
    CliTool.claude => l10n.claudeOfficialCredentialsActionFailed,
    CliTool.cursor => l10n.cursorCredentialsActionFailed,
    CliTool.codex => l10n.codexCredentialsActionFailed,
    CliTool.opencode => l10n.opencodeCredentialsActionFailed,
    _ => l10n.claudeOfficialCredentialsActionFailed,
  };
}
