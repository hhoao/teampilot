import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/services/cli/cursor/provider/cursor_home_layout.dart';
import 'package:teampilot/services/provider_usage/adapters/claude_official_subscription_auth.dart';
import 'package:teampilot/services/provider_usage/adapters/cursor_official_subscription_auth.dart';
import 'package:teampilot/services/provider_usage/cli_credential_source.dart';
import 'package:teampilot/services/provider_usage/managed_provider_usage_adapter.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  test('cli:cursor-account prefers isolated auth.json', () async {
    final fs = InMemoryFilesystem();
    final layout = CursorHomeLayout(pathContext: fs.pathContext);
    await fs.writeString(
      layout.authJson('/tp/providers/cursor/cursor-account/home'),
      jsonEncode({'accessToken': 'isolated-cursor'}),
    );
    await fs.writeString(
      layout.cliConfig('/tp/providers/cursor/cursor-account/home'),
      jsonEncode({'authInfo': {'userId': 'user_isolated'}}),
    );
    final scope = await CliCredentialSourceResolver(
      readers: {
        'cursor': CursorOfficialSubscriptionAuthReader(
          fs: fs,
          basePath: '/tp',
        ),
      },
    ).read('cli:cursor-account');
    expect(scope.valueFor('accessToken'), 'isolated-cursor');
    expect(scope.valueFor('accountId'), 'user_isolated');
  });

  test('unknown cli source is missingCredential', () async {
    await expectLater(
      CliCredentialSourceResolver(readers: {}).read('cli:nope'),
      throwsA(isA<ManagedProviderUsageQueryError>().having(
        (e) => e.code,
        'code',
        ManagedProviderUsageQueryErrorCode.missingCredential,
      )),
    );
  });

  test('per-entry cursor source resolves through the cursor reader',
      () async {
    final fs = InMemoryFilesystem();
    final layout = CursorHomeLayout(pathContext: fs.pathContext);
    await fs.writeString(
      layout.authJson('/tp/providers/cursor/cursor-mp-managed-7/home'),
      jsonEncode({'accessToken': 'entry-token'}),
    );
    final scope = await CliCredentialSourceResolver(
      readers: {
        'cursor': CursorOfficialSubscriptionAuthReader(
          fs: fs,
          basePath: '/tp',
        ),
      },
    ).read('cli:cursor-mp-managed-7');
    expect(scope.valueFor('accessToken'), 'entry-token');
  });

  test('per-entry claude source resolves through the claude reader',
      () async {
    final fs = InMemoryFilesystem();
    await fs.writeString(
      '/tp/providers/claude/claude-mp-managed-7/.credentials.json',
      jsonEncode({
        'claudeAiOauth': {'accessToken': 'entry-token'},
      }),
    );
    final scope = await CliCredentialSourceResolver(
      readers: {
        'claude': ClaudeOfficialSubscriptionAuthReader(
          fs: fs,
          basePath: '/tp',
        ),
      },
    ).read('cli:claude-mp-managed-7');
    expect(scope.valueFor('accessToken'), 'entry-token');
  });

  test('legacy cursor-account source resolves through the cursor reader',
      () async {
    final fs = InMemoryFilesystem();
    final layout = CursorHomeLayout(pathContext: fs.pathContext);
    await fs.writeString(
      layout.authJson('/tp/providers/cursor/cursor-account/home'),
      jsonEncode({'accessToken': 'legacy-token'}),
    );
    final scope = await CliCredentialSourceResolver(
      readers: {
        'cursor': CursorOfficialSubscriptionAuthReader(
          fs: fs,
          basePath: '/tp',
        ),
      },
    ).read('cli:cursor-account');
    expect(scope.valueFor('accessToken'), 'legacy-token');
  });

  test('unmapped cli still reports missingCredential', () async {
    final fs = InMemoryFilesystem();
    await fs.writeString(
      '/tp/providers/claude/claude-mp-x/.credentials.json',
      jsonEncode({
        'claudeAiOauth': {'accessToken': 't'},
      }),
    );
    await expectLater(
      CliCredentialSourceResolver(
        readers: {
          'cursor': CursorOfficialSubscriptionAuthReader(
            fs: fs,
            basePath: '/tp',
          ),
        },
      ).read('cli:claude-mp-x'),
      throwsA(isA<ManagedProviderUsageQueryError>().having(
        (e) => e.code,
        'code',
        ManagedProviderUsageQueryErrorCode.missingCredential,
      )),
    );
  });
}
