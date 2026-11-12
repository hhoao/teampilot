import 'package:http/http.dart' as http;

import '../../services/provider_usage/managed_provider_usage_adapter.dart';
import '../../services/provider_usage/managed_provider_usage_coordinator.dart';

/// Production transport for the provider-usage adapter boundary. Keeping the
/// `http` package behind this interface means adapters and tests never depend
/// on a concrete client, and no UI layer can accidentally perform I/O.
class DefaultProviderUsageHttpClient implements ProviderUsageHttpClient {
  DefaultProviderUsageHttpClient({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  Future<void> close() async => _client.close();

  @override
  Future<ProviderUsageHttpResponse> send(
    ProviderUsageHttpRequest request,
  ) async {
    final outgoing = http.Request(request.method.toUpperCase(), request.uri)
      ..headers.addAll(request.headers);
    if (request.body != null) outgoing.body = request.body!;
    final response = await _client
        .send(outgoing)
        .timeout(ManagedProviderUsageCoordinator.queryTimeout);
    return ProviderUsageHttpResponse(
      statusCode: response.statusCode,
      body: await response.stream.bytesToString(),
      headers: response.headers,
    );
  }
}
