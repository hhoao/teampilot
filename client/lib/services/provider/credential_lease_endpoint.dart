import '../../models/credential_lease.dart';
import '../../utils/logging/logger_utils.dart';
import 'oauth_credential_authority.dart';

class LeaseHttpResponse {
  const LeaseHttpResponse(this.statusCode, this.body);

  final int statusCode;
  final Map<String, Object?> body;
}

/// Pure-Dart HTTP semantics for the credential lease route. The gateway owns
/// JSON decoding/encoding so this class is testable without an HttpServer.
final class CredentialLeaseEndpoint {
  CredentialLeaseEndpoint({
    required this.authority,
    required this.sessionProviderId,
    DateTime Function()? now,
  }) : _now = now ?? (() => DateTime.now().toUtc());

  static const path = '/credentials/lease';

  final OAuthCredentialAuthority authority;

  /// Maps a session id to the provider id it is allowed to request. Returns
  /// null when the session is unknown.
  final String? Function(String sessionId) sessionProviderId;
  final DateTime Function() _now;

  Future<LeaseHttpResponse> serve({
    required String sessionId,
    required String? busToken,
    required String providerId,
    required bool forceRefresh,
  }) async {
    if (sessionId.trim().isEmpty ||
        (busToken ?? '').trim().isEmpty ||
        providerId.trim().isEmpty) {
      AppLogger.instance.w(
        'CredentialLeaseEndpoint: 401 unauthorized (missing session/token/'
        'provider) for provider=$providerId',
      );
      return const LeaseHttpResponse(401, {'error': 'unauthorized'});
    }
    final allowed = sessionProviderId(sessionId);
    if (allowed == null || allowed != providerId) {
      AppLogger.instance.w(
        'CredentialLeaseEndpoint: 401 provider mismatch for '
        'provider=$providerId',
      );
      return const LeaseHttpResponse(401, {'error': 'unauthorized'});
    }

    try {
      final lease = await authority.lease(
        providerId: providerId,
        sessionId: sessionId,
        forceRefresh: forceRefresh,
      );
      return LeaseHttpResponse(200, {
        'access_token': lease.accessToken,
        'expires_in': lease.expiresInSeconds(_now()),
        'epoch': lease.epoch,
      });
    } on CredentialUnavailableException catch (error) {
      AppLogger.instance.w(
        'CredentialLeaseEndpoint: 409 unavailable for provider=$providerId '
        'health=${error.health.name}',
      );
      return LeaseHttpResponse(409, {'health': error.health.name});
    } on CredentialTransientException {
      // IdP outage / timeout: the RT is intact, so tell the shim (and the
      // cubit recovery path) to retry rather than sign in. Never log the
      // cause (it may quote token material).
      AppLogger.instance.w(
        'CredentialLeaseEndpoint: 503 temporarily unavailable for '
        'provider=$providerId',
      );
      return const LeaseHttpResponse(503, {
        'error': 'temporarily_unavailable',
      });
    }
  }
}
