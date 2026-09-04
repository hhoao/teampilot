import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/services/provider_usage/adapters/claude_official_subscription_auth.dart';
import 'package:teampilot/services/provider_usage/adapters/codex_official_subscription_auth.dart';
import 'package:teampilot/services/provider_usage/adapters/cursor_official_subscription_auth.dart';
import 'package:teampilot/services/cli/cursor/provider/cursor_home_layout.dart';
import 'package:teampilot/services/provider_usage/managed_provider_usage_adapter.dart';

import '../../support/in_memory_filesystem.dart';

ManagedProvider _provider(String rowId) => ManagedProvider(
  id: rowId,
  name: 'Official',
  kind: ManagedProviderKind.subscriptionQuota,
  adapterId: 'http-json',
);

void main() {
  late InMemoryFilesystem fs;
  late CursorHomeLayout layout;

  setUp(() {
    fs = InMemoryFilesystem();
    layout = CursorHomeLayout(pathContext: fs.pathContext);
  });

  test('Claude auth reads only the per-entry isolated credential file', () async {
    await fs.writeString(
      '/tp/providers/claude/claude-mp-managed-1/.credentials.json',
      jsonEncode({
        'claudeAiOauth': {'accessToken': 'per-entry-token'},
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
    ).read(_provider('claude-mp-managed-1'));

    expect(scope?.valueFor('accessToken'), 'per-entry-token');
    expect(scope.toString(), isNot(contains('per-entry-token')));
  });

  test('Claude auth never falls back to ~/.claude credentials', () async {
    await fs.writeString(
      '/home/.claude/.credentials.json',
      jsonEncode({
        'claudeAiOauth': {'accessToken': 'global-token'},
      }),
    );

    await expectLater(
      ClaudeOfficialSubscriptionAuthReader(fs: fs, basePath: '/tp')
          .read(_provider('claude-mp-managed-1')),
      throwsA(
        isA<ManagedProviderUsageQueryError>().having(
          (error) => error.code,
          'code',
          ManagedProviderUsageQueryErrorCode.missingCredential,
        ),
      ),
    );
  });

  test('Codex auth reads only the per-entry isolated auth.json', () async {
    await fs.writeString(
      '/tp/providers/codex/codex-mp-managed-1/auth.json',
      jsonEncode({
        'auth_mode': 'chatgpt',
        'tokens': {'access_token': 'per-entry', 'account_id': 'acct-1'},
      }),
    );
    await fs.writeString(
      '/home/.codex/auth.json',
      jsonEncode({
        'auth_mode': 'chatgpt',
        'tokens': {'access_token': 'global', 'account_id': 'acct-g'},
      }),
    );

    final scope = await CodexOfficialSubscriptionAuthReader(
      fs: fs,
      basePath: '/tp',
    ).read(_provider('codex-mp-managed-1'));

    expect(scope?.valueFor('accessToken'), 'per-entry');
    expect(scope?.valueFor('accountId'), 'acct-1');
  });

  test('Codex auth never falls back to ~/.codex and skips apikey mode',
      () async {
    await fs.writeString(
      '/home/.codex/auth.json',
      jsonEncode({
        'auth_mode': 'apikey',
        'tokens': {'access_token': 'api-mode'},
      }),
    );

    await expectLater(
      CodexOfficialSubscriptionAuthReader(fs: fs, basePath: '/tp')
          .read(_provider('codex-mp-managed-1')),
      throwsA(
        isA<ManagedProviderUsageQueryError>().having(
          (error) => error.code,
          'code',
          ManagedProviderUsageQueryErrorCode.missingCredential,
        ),
      ),
    );
  });

  test('Cursor auth reads only the per-entry isolated auth.json', () async {
    final home = '/tp/providers/cursor/cursor-mp-managed-1/home';
    await fs.writeString(
      layout.authJson(home),
      jsonEncode({'accessToken': 'per-entry-cursor', 'userId': 'user-1'}),
    );
    // Global IDE login exists — must be ignored.
    await fs.writeString(
      layout.authJson('/home'),
      jsonEncode({'accessToken': 'global-cursor'}),
    );

    final scope = await CursorOfficialSubscriptionAuthReader(
      fs: fs,
      basePath: '/tp',
    ).read(_provider('cursor-mp-managed-1'));

    expect(scope?.valueFor('accessToken'), 'per-entry-cursor');
    expect(scope?.valueFor('accountId'), 'user-1');
  });

  test('Cursor auth never falls back to global cursor auth.json', () async {
    await fs.writeString(
      layout.authJson('/home'),
      jsonEncode({'accessToken': 'global-cursor'}),
    );

    await expectLater(
      CursorOfficialSubscriptionAuthReader(fs: fs, basePath: '/tp')
          .read(_provider('cursor-mp-managed-1')),
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
