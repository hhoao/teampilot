import '../../models/credential_lease.dart';
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
      return const LeaseHttpResponse(401, {'error': 'unauthorized'});
    }
    final allowed = sessionProviderId(sessionId);
    if (allowed == null || allowed != providerId) {
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
      return LeaseHttpResponse(409, {'health': error.health.name});
    }
  }
}
