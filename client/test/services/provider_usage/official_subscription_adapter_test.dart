import 'package:flutter_test/flutter_test.dart';

import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/models/provider_usage_snapshot.dart';
import 'package:teampilot/services/provider_usage/adapters/claude_subscription_adapter.dart';
import 'package:teampilot/services/provider_usage/adapters/codex_subscription_adapter.dart';
import 'package:teampilot/services/provider_usage/adapters/official_subscription_adapter.dart';
import 'package:teampilot/services/provider_usage/managed_provider_usage_adapter.dart';

class _AuthReader implements OfficialSubscriptionAuthReader {
  _AuthReader(this.scope);

  final ProviderCredentialScope? scope;

  @override
  Future<ProviderCredentialScope?> read(ManagedProvider provider) async =>
      scope;
}

class _Resolver implements ProviderCredentialResolver {
  @override
  Future<ProviderCredentialScope?> resolve(ManagedProvider provider) async =>
      null;
}

class _Scope implements ProviderCredentialScope {
  @override
  Iterable<String> get fields => const ['accessToken'];

  @override
  bool get isEmpty => false;

  @override
  String? valueFor(String field) => field == 'accessToken' ? 'transient' : null;
}

class _Client implements OfficialSubscriptionClient {
  @override
  Future<OfficialSubscriptionResponse> fetch(
    ManagedProvider provider, {
    required ProviderCredentialScope credentials,
    required DateTime now,
  }) async {
    return OfficialSubscriptionResponse(
      windows: const [
        OfficialSubscriptionWindow(
          label: '5h',
          kind: ProviderUsageMeasureKind.quota,
          total: '100.000000000000000005',
          used: '25.25',
          unit: 'requests',
          resetsAt: 1_800_000_000_000,
        ),
        OfficialSubscriptionWindow(
          label: 'Weekly',
          kind: ProviderUsageMeasureKind.quota,
          remaining: '42.00',
          unit: 'requests',
        ),
      ],
      staleAfter: const Duration(minutes: 5),
      adapterVersion: 'fixture-v1',
    );
  }
}

ManagedProvider _provider(String adapterId) => ManagedProvider(
  id: 'p1',
  name: 'Official',
  kind: ManagedProviderKind.subscriptionQuota,
  adapterId: adapterId,
  credentialRef: 'managed-provider:p1',
);

void main() {
  test('Claude adapter exposes stable ID and normalizes all windows', () async {
    final adapter = ClaudeSubscriptionAdapter(
      authReader: _AuthReader(_Scope()),
      client: _Client(),
    );

    final snapshot = await adapter.fetch(
      _provider(adapter.id),
      credentials: _Resolver(),
      http: _UnusedHttpClient(),
      now: DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000),
    );

    expect(adapter.id, 'official-claude-subscription');
    expect(adapter.officialProviderId, 'claude');
    expect(snapshot.status, ProviderUsageStatus.ready);
    expect(snapshot.measures, hasLength(2));
    expect(snapshot.measures.first.total, '100.000000000000000005');
    expect(snapshot.measures.first.resetsAt, 1_800_000_000_000);
    expect(snapshot.staleAt, 1_700_000_300_000);
    expect(snapshot.adapterVersion, 'fixture-v1');
  });

  test('missing official auth is a typed, secret-free failure', () async {
    final adapter = CodexSubscriptionAdapter(
      authReader: _AuthReader(null),
      client: _Client(),
    );

    expect(
      () => adapter.fetch(
        _provider(adapter.id),
        credentials: _Resolver(),
        http: _UnusedHttpClient(),
        now: DateTime.now(),
      ),
      throwsA(
        isA<ManagedProviderUsageQueryError>().having(
          (error) => error.code,
          'code',
          ManagedProviderUsageQueryErrorCode.missingCredential,
        ),
      ),
    );
  });
}

class _UnusedHttpClient implements ProviderUsageHttpClient {
  @override
  Future<ProviderUsageHttpResponse> send(ProviderUsageHttpRequest request) {
    throw StateError('not used');
  }
}
