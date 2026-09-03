import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/services/cli/cursor/provider/cursor_home_layout.dart';
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
        'cursor-account': CursorOfficialSubscriptionAuthReader(
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
}
