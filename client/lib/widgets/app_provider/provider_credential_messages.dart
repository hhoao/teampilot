import '../../l10n/app_localizations.dart';
import '../../models/app_provider_config.dart';
import '../../models/credential_action_result.dart';

String providerCredentialSuccessMessage(AppLocalizations l10n, CliTool cli) {
  return switch (cli) {
    CliTool.claude => l10n.claude.officialCredentialsActionSuccess,
    CliTool.cursor => l10n.cursor.credentialsActionSuccess,
    CliTool.codex => l10n.codex.credentialsActionSuccess,
    CliTool.opencode => l10n.opencode.credentialsActionSuccess,
    CliTool.flashskyai => l10n.appProvider.toolFlashskyai,
    CliTool.gemini => l10n.appProvider.toolGemini,
    CliTool.codebuddy => l10n.codebuddy.credentialsSignedIn,
    CliTool.antigravity => l10n.antigravity.credentialsSignedIn,
    CliTool.qoder => l10n.qoder.credentialsSignedIn,
    CliTool.qoderCn => l10n.qoder.credentialsSignedIn,
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
      l10n.provider.credentialsFailureUnsupported,
    CredentialActionFailureCode.serviceUnavailable =>
      l10n.provider.credentialsFailureServiceUnavailable,
    CredentialActionFailureCode.providerNotFound =>
      l10n.provider.credentialsFailureProviderNotFound,
    CredentialActionFailureCode.pathRequired =>
      l10n.provider.credentialsFailurePathRequired,
    CredentialActionFailureCode.sourceMissing =>
      l10n.provider.credentialsFailureSourceMissing(
        path: failure.path ?? failure.detail ?? '',
      ),
    CredentialActionFailureCode.sourceUnreadable =>
      l10n.provider.credentialsFailureSourceUnreadable(
        path: failure.path ?? failure.detail ?? '',
      ),
    CredentialActionFailureCode.providerEntryMissing =>
      _providerEntryMissingMessage(l10n, failure),
    CredentialActionFailureCode.invalidCredential =>
      l10n.provider.credentialsFailureInvalidCredential,
    CredentialActionFailureCode.destinationExists =>
      l10n.provider.credentialsFailureDestinationExists,
    CredentialActionFailureCode.requiredFileMissing =>
      l10n.provider.credentialsFailureRequiredFileMissing(
        path: failure.path ?? failure.detail ?? '',
      ),
    CredentialActionFailureCode.loginFailed =>
      l10n.provider.credentialsFailureLoginFailed(
        exitCode: failure.exitCode ?? -1,
      ),
    CredentialActionFailureCode.loginProcessError =>
      l10n.provider.credentialsFailureLoginProcessError(
        detail: failure.detail ?? '',
      ),
    CredentialActionFailureCode.revokeFailed =>
      l10n.provider.credentialsFailureRevokeFailed,
    CredentialActionFailureCode.verifyFailed =>
      l10n.provider.credentialsFailureVerifyFailed,
    CredentialActionFailureCode.statusRefreshFailed =>
      l10n.provider.credentialsFailureStatusRefreshFailed,
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
    return l10n.provider.credentialsFailureProviderEntryMissingWithKeys(
      providerId: providerId,
      path: path,
      keys: keys.join(', '),
    );
  }
  return l10n.provider.credentialsFailureProviderEntryMissing(
    providerId: providerId,
    path: path,
  );
}

String _genericFailureMessage(AppLocalizations l10n, CliTool cli) {
  return switch (cli) {
    CliTool.claude => l10n.claude.officialCredentialsActionFailed,
    CliTool.cursor => l10n.cursor.credentialsActionFailed,
    CliTool.codex => l10n.codex.credentialsActionFailed,
    CliTool.opencode => l10n.opencode.credentialsActionFailed,
    CliTool.flashskyai => l10n.appProvider.toolFlashskyai,
    CliTool.gemini => l10n.appProvider.toolGemini,
    CliTool.codebuddy => l10n.codebuddy.credentialsActionFailed,
    CliTool.antigravity => l10n.antigravity.credentialsActionFailed,
    CliTool.qoder => l10n.qoder.credentialsActionFailed,
    CliTool.qoderCn => l10n.qoder.credentialsActionFailed,
  };
}
