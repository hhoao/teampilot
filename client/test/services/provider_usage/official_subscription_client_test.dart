import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/models/provider_usage_snapshot.dart';
import 'package:teampilot/services/provider_usage/adapters/claude_official_subscription_client.dart';
import 'package:teampilot/services/provider_usage/adapters/codex_official_subscription_client.dart';
import 'package:teampilot/services/provider_usage/adapters/official_subscription_adapter.dart';
import 'package:teampilot/services/provider_usage/managed_provider_secret_store.dart';
import 'package:teampilot/services/provider_usage/managed_provider_usage_adapter.dart';

class _Scope implements ProviderCredentialScope {
  _Scope({this.accessToken = 'token', this.accountId});

  final String accessToken;
  final String? accountId;

  @override
  Iterable<String> get fields => [
    'accessToken',
    if (accountId != null) 'accountId',
  ];

  @override
  bool get isEmpty => accessToken.isEmpty;

  @override
  String? valueFor(String field) => switch (field) {
    'accessToken' => accessToken,
    'accountId' => accountId,
    _ => null,
  };
}

class _Http implements ProviderUsageHttpClient {
  _Http({this.statusCode = 200, this.body = '{}'});

  int statusCode;
  String body;
  ProviderUsageHttpRequest? lastRequest;

  @override
  Future<ProviderUsageHttpResponse> send(
    ProviderUsageHttpRequest request,
  ) async {
    lastRequest = request;
    return ProviderUsageHttpResponse(statusCode: statusCode, body: body);
  }
}

ManagedProvider _provider(String adapterId) => ManagedProvider(
  id: 'p1',
  name: 'Official',
  kind: ManagedProviderKind.subscriptionQuota,
  adapterId: adapterId,
);

void main() {
  test('Claude client maps oauth usage windows', () async {
    final http = _Http(
      body: '''
{
  "five_hour": {"utilization": 12, "resets_at": 1800000000},
  "seven_day": {"utilization": 34, "resets_at": "2026-08-21T00:00:00Z"}
}
''',
    );
    final client = ClaudeOfficialSubscriptionClient(http);
    final response = await client.fetch(
      _provider('official-claude-subscription'),
      credentials: _Scope(),
      now: DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000),
    );

    expect(
      http.lastRequest?.uri.toString(),
      'https://api.anthropic.com/api/oauth/usage',
    );
    expect(http.lastRequest?.headers['Authorization'], 'Bearer token');
    expect(http.lastRequest?.headers['anthropic-beta'], 'oauth-2025-04-20');
    expect(response.windows, hasLength(2));
    expect(response.windows.first.label, '5h');
    expect(response.windows.first.used, '12');
    expect(response.windows.first.total, '100');
    expect(response.windows.first.unit, '%');
    expect(response.windows.first.resetsAt, 1_800_000_000_000);
    expect(response.windows.last.label, 'Weekly');
    expect(response.windows.last.used, '34');
  });

  test('Codex client maps primary and secondary windows', () async {
    final http = _Http(
      body: '''
{
  "rate_limit": {
    "primary_window": {
      "used_percent": 41.5,
      "limit_window_seconds": 18000,
      "reset_at": 1800000000
    },
    "secondary_window": {
      "used_percent": 12,
      "limit_window_seconds": 604800
    }
  }
}
''',
    );
    final client = CodexOfficialSubscriptionClient(http);
    final response = await client.fetch(
      _provider('official-codex-subscription'),
      credentials: _Scope(accountId: 'acct-1'),
      now: DateTime.now(),
    );

    expect(
      http.lastRequest?.uri.toString(),
      'https://chatgpt.com/backend-api/wham/usage',
    );
    expect(http.lastRequest?.headers['ChatGPT-Account-Id'], 'acct-1');
    expect(http.lastRequest?.headers['User-Agent'], 'codex-cli');
    expect(response.windows.first.label, '5h');
    expect(response.windows.first.used, '41.5');
    expect(response.windows.last.label, 'Weekly');
    expect(response.windows.last.used, '12');
  });

  test('Claude 401 is authenticationFailed', () async {
    final client = ClaudeOfficialSubscriptionClient(_Http(statusCode: 401));
    await expectLater(
      client.fetch(
        _provider('official-claude-subscription'),
        credentials: _Scope(),
        now: DateTime.now(),
      ),
      throwsA(
        isA<ManagedProviderUsageQueryError>().having(
          (error) => error.code,
          'code',
          ManagedProviderUsageQueryErrorCode.authenticationFailed,
        ),
      ),
    );
  });
}
