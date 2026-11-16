import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/grok/grok_bootstrap_entry.dart';
import 'package:teampilot/services/cli/grok/provider/grok_credential_adapter.dart';
import 'package:teampilot/services/cli/registry/built_in_cli_tools.dart';
import 'package:teampilot/services/cli/registry/capabilities/session_credential_capability.dart';
import 'package:teampilot/services/cli/registry/cli_bootstrap.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/provider/credential_lease_endpoint.dart';
import 'package:teampilot/services/provider/oauth_credential_authority.dart';
import 'package:teampilot/services/provider/session_provider_registry.dart';

import '../../../support/in_memory_filesystem.dart';

final class _CountingRefresher implements CredentialRefresher {
  int calls = 0;
  String? lastRefreshToken;

  @override
  Future<CredentialRefreshOutcome> refresh(String refreshToken) async {
    calls++;
    lastRefreshToken = refreshToken;
    return RefreshSucceeded(
      accessToken: 'fresh-$calls',
      refreshToken: 'rt-$calls',
      expiresAt: DateTime.utc(2026, 11, 14, 12, 0, 0),
    );
  }
}

void main() {
  test(
    'real registry assembly exposes SessionCredentialCapability and drives '
    'forceRefresh through onAuthRequired',
    () async {
      final fs = InMemoryFilesystem();
      final refresher = _CountingRefresher();
      final now = DateTime.utc(2026, 11, 14, 11, 0, 0);
      final authority = OAuthCredentialAuthority(
        fs: fs,
        basePath: '/tp',
        cliNamespace: 'grok',
        refresher: refresher,
        now: () => now,
      );
      // A usable credential: without forceRefresh, lease() would short-circuit
      // and never call the refresher.
      await authority.importFromLogin(
        'xai',
        utf8.encode(
          jsonEncode({
            'scope': {
              'key': 'access-old',
              'refresh_token': 'rt-old',
              'expires_at': '2026-11-14T11:30:00Z',
            },
          }),
        ),
      );
      // Mirrors wireCliBootstrap: adapter writes the session->provider record
      // at materialize time, endpoint reads it on every lease request.
      final sessionProviderRegistry = SessionProviderRegistry();
      final adapter = GrokCredentialAdapter(
        authority: authority,
        sessionProviderId: sessionProviderRegistry.providerFor,
        onSessionMaterialized: sessionProviderRegistry.register,
        now: () => now,
      );
      final entry = GrokBootstrapEntry(
        credentialSource: () => null,
        authority: authority,
        adapter: adapter,
        leaseEndpoint: CredentialLeaseEndpoint(
          authority: authority,
          sessionProviderId: sessionProviderRegistry.providerFor,
        ),
      );

      // Build a real registry through the same path production uses, including
      // a bootstrap entry. All the registerBuiltInCliTools asserts must hold.
      final registry = CliToolRegistry();
      registerBuiltInCliTools(
        registry,
        bootstrap: CliBootstrap(
          {CliTool.grok: entry},
          storage: fakeHomeStorage(filesystem: fs),
        ),
      );

      final capability =
          registry.capability<SessionCredentialCapability>(CliTool.grok);
      expect(
        capability,
        isNotNull,
        reason: 'acp_runtime_attach reads this capability for auth_required',
      );
      expect(capability, same(adapter));

      // onAuthRequired -> recover(forceRefresh: true) -> lease -> refresh.
      // The endpoint is no longer backed by a hardcoded 'xai' stub: a session
      // that never went through materialize is unknown and must be refused.
      expect(
        (await entry.leaseEndpoint.serve(
          sessionId: 'never-launched',
          busToken: 'bus-token',
          providerId: 'xai',
          forceRefresh: false,
        )).statusCode,
        401,
      );

      expect(refresher.calls, 0);
      final recovered = await capability!.onAuthRequired(
        providerId: 'xai',
        sessionId: 'session-1',
      );
      expect(recovered, isTrue);
      expect(
        refresher.calls,
        1,
        reason: 'forceRefresh must reach the refresher via the real assembly',
      );

      // A custom provider row: recovery arrives with the model provider name
      // ('xai') but must refresh the credential id this seat registered
      // ('work'), otherwise multi-account seats recover the wrong account.
      await authority.importFromLogin(
        'work',
        utf8.encode(
          jsonEncode({
            'scope': {
              'key': 'access-work',
              'refresh_token': 'rt-work',
              'expires_at': '2026-11-14T11:30:00Z',
            },
          }),
        ),
      );
      sessionProviderRegistry.register('session-1', 'work');
      final recoveredCustom = await capability.onAuthRequired(
        providerId: 'xai',
        sessionId: 'session-1',
      );
      expect(recoveredCustom, isTrue);
      expect(refresher.calls, 2);
      expect(refresher.lastRefreshToken, 'rt-work');
    },
  );
}
