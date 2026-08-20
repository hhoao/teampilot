import '../../../models/managed_provider.dart';
import '../managed_provider_usage_adapter.dart';
import 'official_subscription_adapter.dart';
import 'official_subscription_parse.dart';

const _codexUsageUrl = 'https://chatgpt.com/backend-api/wham/usage';

class CodexOfficialSubscriptionClient implements OfficialSubscriptionClient {
  CodexOfficialSubscriptionClient(this._http);

  final ProviderUsageHttpClient _http;

  @override
  Future<OfficialSubscriptionResponse> fetch(
    ManagedProvider provider, {
    required ProviderCredentialScope credentials,
    required DateTime now,
  }) async {
    final token = credentials.valueFor('accessToken')?.trim() ?? '';
    if (token.isEmpty) {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.missingCredential,
      );
    }
    final accountId = credentials.valueFor('accountId')?.trim() ?? '';
    final response = await _http.send(
      ProviderUsageHttpRequest(
        method: 'GET',
        uri: Uri.parse(_codexUsageUrl),
        headers: {
          'Authorization': 'Bearer $token',
          'User-Agent': 'codex-cli',
          'Accept': 'application/json',
          if (accountId.isNotEmpty) 'ChatGPT-Account-Id': accountId,
        },
      ),
    );
    throwOfficialHttpStatus(response.statusCode);
    final windows = parseCodexOfficialWindows(response.body);
    if (windows.isEmpty) {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.responseParseFailed,
      );
    }
    return OfficialSubscriptionResponse(
      windows: windows,
      staleAfter: const Duration(minutes: 5),
      adapterVersion: 'codex-wham-usage-v1',
    );
  }
}

List<OfficialSubscriptionWindow> parseCodexOfficialWindows(String body) {
  final decoded = decodeOfficialJsonObject(body);
  final rateLimit = decoded['rate_limit'];
  if (rateLimit is! Map) return const [];
  final windows = <OfficialSubscriptionWindow>[];
  for (final key in const ['primary_window', 'secondary_window']) {
    final raw = rateLimit[key];
    if (raw is! Map) continue;
    final used = readOfficialPercent(raw['used_percent']);
    if (used == null) continue;
    final seconds = raw['limit_window_seconds'];
    windows.add(
      officialPercentWindow(
        label: officialCodexWindowLabel(
          seconds is num ? seconds.toInt() : null,
        ),
        used: used,
        resetsAt: parseOfficialResetAt(raw['reset_at']),
      ),
    );
  }
  return windows;
}
