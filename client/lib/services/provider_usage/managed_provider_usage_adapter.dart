import '../../models/managed_provider.dart';
import '../../models/provider_usage_snapshot.dart';
import 'managed_provider_secret_store.dart';

export 'managed_provider_secret_store.dart'
    show ProviderCredentialResolver, ProviderCredentialScope;

/// The transport request passed to a managed-provider HTTP client.
///
/// The adapter supplies request metadata; the injected client owns the actual
/// network request and platform-specific HTTP implementation.
class ProviderUsageHttpRequest {
  ProviderUsageHttpRequest({
    required this.method,
    required this.uri,
    Map<String, String> headers = const {},
    this.body,
  }) : headers = Map.unmodifiable(headers);

  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final String? body;
}

class ProviderUsageHttpResponse {
  const ProviderUsageHttpResponse({
    required this.statusCode,
    required this.body,
    this.headers = const {},
  });

  final int statusCode;
  final String body;
  final Map<String, String> headers;
}

/// Injectable transport boundary for managed-provider usage requests.
abstract interface class ProviderUsageHttpClient {
  Future<ProviderUsageHttpResponse> send(ProviderUsageHttpRequest request);
}

abstract interface class ManagedProviderUsageAdapter {
  String get id;

  Future<ProviderUsageSnapshot> fetch(
    ManagedProvider provider, {
    required ProviderCredentialResolver credentials,
    required ProviderUsageHttpClient http,
    required DateTime now,
  });
}

enum ManagedProviderUsageQueryErrorCode {
  missingCredential,
  authenticationFailed,
  networkFailed,
  httpFailed,
  responseParseFailed,
  unsupported,
}

/// Secret-free, typed failures from a usage adapter query.
class ManagedProviderUsageQueryError implements Exception {
  const ManagedProviderUsageQueryError(this.code);

  final ManagedProviderUsageQueryErrorCode code;

  String get message => 'Managed provider usage query ${code.name}.';

  @override
  String toString() => 'ManagedProviderUsageQueryError: $message';
}

typedef ProviderUsageQueryError = ManagedProviderUsageQueryError;
typedef ProviderUsageQueryErrorCode = ManagedProviderUsageQueryErrorCode;
