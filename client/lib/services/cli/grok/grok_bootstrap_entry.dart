import '../registry/cli_bootstrap.dart';
import '../../provider/credential_lease_endpoint.dart';
import '../../provider/oauth_credential_authority.dart';
import 'provider/grok_credential_adapter.dart';

/// Grok runtime services injected after home storage is ready.
///
/// The API key source is a sync closure because the ACP environment is built
/// synchronously; provider rows load asynchronously and are cached by the app
/// shell.
final class GrokBootstrapEntry implements CliBootstrapEntry {
  const GrokBootstrapEntry({
    required this.credentialSource,
    required this.authority,
    required this.adapter,
    required this.leaseEndpoint,
  });

  /// Returns the stored xAI API key, or null when unset (API-key seats only).
  final String? Function() credentialSource;

  /// Control-plane single owner of the xAI refresh token.
  final OAuthCredentialAuthority authority;

  /// Session-home credential injection.
  final GrokCredentialAdapter adapter;

  /// HTTP handler attached to the bus gateway.
  final CredentialLeaseEndpoint leaseEndpoint;
}
