import '../../../../models/credential_lease.dart';
import '../cli_capability.dart';

/// Credential boundary for a CLI whose account token can be refreshed.
///
/// Implementations own ONLY the injection into a session; the refresh token
/// itself stays on the control plane (`OAuthCredentialAuthority`). This is the
/// extension point for future CLIs — no `if (cli == …)` in pages/cubits.
abstract interface class SessionCredentialCapability implements CliCapability {
  /// Mint (or reuse) a lease for [sessionId]. Throws
  /// [CredentialUnavailableException] when the provider needs a login.
  Future<CredentialLease> leaseCredentials({
    required String providerId,
    required String sessionId,
    bool forceRefresh = false,
  });

  /// Fine-grained health for provider UI and pre-launch gating.
  Future<CredentialHealth> credentialStatus(String providerId);

  /// Called on ACP `auth_required`. Returns true when a fresh lease was
  /// produced and the caller may retry the launch once.
  Future<bool> onAuthRequired({
    required String providerId,
    required String sessionId,
  });
}
