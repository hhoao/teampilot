import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/services/provider_usage/adapters/claude_official_subscription_auth.dart';
import 'package:teampilot/services/provider_usage/adapters/codex_official_subscription_auth.dart';
import 'package:teampilot/services/provider_usage/adapters/official_subscription_adapter.dart';
import 'package:teampilot/services/provider_usage/managed_provider_usage_adapter.dart';

import '../../support/in_memory_filesystem.dart';

ManagedProvider _provider(String adapterId) => ManagedProvider(
  id: 'p1',
  name: 'Official',
  kind: ManagedProviderKind.subscriptionQuota,
  adapterId: adapterId,
);

void main() {
  late InMemoryFilesystem fs;

  setUp(() {
    fs = InMemoryFilesystem();
  });

  test('Claude auth prefers the isolated TeamPilot credential file', () async {
    await fs.writeString(
      '/tp/providers/claude/claude-official/.credentials.json',
      jsonEncode({
        'claudeAiOauth': {'accessToken': 'isolated-token'},
      }),
    );
    await fs.writeString(
      '/home/.claude/.credentials.json',
      jsonEncode({
        'claudeAiOauth': {'accessToken': 'global-token'},
      }),
    );

    final scope = await ClaudeOfficialSubscriptionAuthReader(
      fs: fs,
      basePath: '/tp',
      homeDirectory: () => '/home',
    ).read(_provider('official-claude-subscription'));

    expect(scope?.valueFor('accessToken'), 'isolated-token');
    expect(scope.toString(), isNot(contains('isolated-token')));
  });

  test('Claude auth falls back to ~/.claude credentials', () async {
    await fs.writeString(
      '/home/.claude/.credentials.json',
      jsonEncode({
        'claudeAiOauth': {'accessToken': 'global-token'},
      }),
    );

    final scope = await ClaudeOfficialSubscriptionAuthReader(
      fs: fs,
      basePath: '/tp',
      homeDirectory: () => '/home',
    ).read(_provider('official-claude-subscription'));

    expect(scope?.valueFor('accessToken'), 'global-token');
  });

  test('Codex auth skips non-chatgpt auth_mode files', () async {
    await fs.writeString(
      '/tp/providers/codex/openai-official/auth.json',
      jsonEncode({
        'auth_mode': 'apikey',
        'tokens': {'access_token': 'api-mode'},
      }),
    );
    await fs.writeString(
      '/home/.codex/auth.json',
      jsonEncode({
        'auth_mode': 'chatgpt',
        'tokens': {'access_token': 'oauth-token', 'account_id': 'acct-1'},
      }),
    );

    final scope = await CodexOfficialSubscriptionAuthReader(
      fs: fs,
      basePath: '/tp',
      homeDirectory: () => '/home',
    ).read(_provider('official-codex-subscription'));

    expect(scope?.valueFor('accessToken'), 'oauth-token');
    expect(scope?.valueFor('accountId'), 'acct-1');
  });

  test('missing official auth is a typed secret-free failure', () async {
    await expectLater(
      ClaudeOfficialSubscriptionAuthReader(
        fs: fs,
        basePath: '/tp',
        homeDirectory: () => '/home',
      ).read(_provider('official-claude-subscription')),
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
