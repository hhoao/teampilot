import '../../../models/managed_provider.dart';
import '../managed_provider_usage_adapter.dart';
import 'official_subscription_adapter.dart';
import 'official_subscription_parse.dart';

const _claudeUsageUrl = 'https://api.anthropic.com/api/oauth/usage';
const _claudeBeta = 'oauth-2025-04-20';
const _claudeUserAgent = 'claude-code/2.1.0';

const _claudeWindowLabels = <String, String>{
  'five_hour': '5h',
  'seven_day': 'Weekly',
  'seven_day_opus': 'Weekly Opus',
  'seven_day_sonnet': 'Weekly Sonnet',
};

class ClaudeOfficialSubscriptionClient implements OfficialSubscriptionClient {
  ClaudeOfficialSubscriptionClient(this._http);

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
    final response = await _http.send(
      ProviderUsageHttpRequest(
        method: 'GET',
        uri: Uri.parse(_claudeUsageUrl),
        headers: {
          'Authorization': 'Bearer $token',
          'anthropic-beta': _claudeBeta,
          'Accept': 'application/json',
          'User-Agent': _claudeUserAgent,
        },
      ),
    );
    throwOfficialHttpStatus(response.statusCode);
    final windows = parseClaudeOfficialWindows(response.body);
    if (windows.isEmpty) {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.responseParseFailed,
      );
    }
    return OfficialSubscriptionResponse(
      windows: windows,
      staleAfter: const Duration(minutes: 10),
      adapterVersion: 'claude-oauth-usage-v1',
    );
  }
}

List<OfficialSubscriptionWindow> parseClaudeOfficialWindows(String body) {
  final decoded = decodeOfficialJsonObject(body);
  final windows = <OfficialSubscriptionWindow>[];
  for (final entry in decoded.entries) {
    if (entry.key == 'extra_usage') continue;
    final window = entry.value;
    if (window is! Map) continue;
    final used = readOfficialPercent(
      window['utilization'] ?? window['used_percentage'],
    );
    if (used == null) continue;
    windows.add(
      officialPercentWindow(
        label: _claudeWindowLabels[entry.key] ?? entry.key,
        used: used,
        resetsAt: parseOfficialResetAt(window['resets_at']),
      ),
    );
  }
  return windows;
}
