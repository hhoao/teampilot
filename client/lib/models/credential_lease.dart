import 'dart:convert';

/// Fine-grained credential health. Crosses the control-plane boundary;
/// `CredentialProbe`'s binary `CredentialStatus` is derived from this.
enum CredentialHealth { ready, expiring, rejected, missing }

/// Short-lived, non-rotating credential minted for one session.
/// Contains NO refresh token.
class CredentialLease {
  const CredentialLease({
    required this.accessToken,
    required this.expiresAt,
    required this.epoch,
  });

  final String accessToken;
  final DateTime expiresAt;

  /// Authority generation at mint time; late concurrent refreshes with a
  /// lower epoch are discarded.
  final int epoch;

  bool isUsable(DateTime now) =>
      accessToken.isNotEmpty && expiresAt.isAfter(now);

  int expiresInSeconds(DateTime now) => expiresAt.difference(now).inSeconds;

  /// stdout contract for grok's external auth provider:
  /// `{"access_token": "...", "expires_in": <seconds>}`.
  String toProviderJson(DateTime now) => jsonEncode({
        'access_token': accessToken,
        'expires_in': expiresInSeconds(now),
      });
}

/// Thrown when no lease can be minted; `health` tells the caller whether to
/// prompt for a fresh login (`rejected` / `missing`) or retry.
class CredentialUnavailableException implements Exception {
  const CredentialUnavailableException(this.health);

  final CredentialHealth health;

  @override
  String toString() => 'CredentialUnavailableException($health)';
}

/// Refresh failed for a retryable reason: network error, timeout, 429/5xx, or
/// an unparsable IdP response.
///
/// The stored refresh token is still valid, so the Authority must keep it. This
/// deliberately does NOT extend [CredentialUnavailableException]: a transient
/// outage is not "the user needs to sign in".
class CredentialTransientException implements Exception {
  const CredentialTransientException(this.cause);

  /// Failure class or status, never token material.
  final Object cause;

  @override
  String toString() => 'CredentialTransientException($cause)';
}
