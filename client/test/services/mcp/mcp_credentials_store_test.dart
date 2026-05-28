import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/mcp/mcp_credentials_store.dart';
import 'package:teampilot/services/mcp/mcp_oauth_server_key.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('mcp_creds_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('saves and reads oauth tokens in claude credentials shape', () async {
    final store = McpCredentialsStore();
    final configDir = root.path;
    const serverName = 'Context7';
    final serverConfig = {
      'type': 'http',
      'url': 'https://context7-mcp--upstash.run.tools',
    };

    await store.saveOAuthTokens(
      configDir: configDir,
      serverName: serverName,
      serverConfig: serverConfig,
      accessToken: 'access-xyz',
      refreshToken: 'refresh-abc',
      expiresAtMs: 1_700_000_000_000,
      scope: 'mcp',
    );

    final data = await store.read(configDir);
    expect(
      store.hasAccessToken(data, serverName, serverConfig),
      isTrue,
    );

    final file = File('${root.path}/.credentials.json');
    final parsed = jsonDecode(await file.readAsString()) as Map;
    final key = mcpOAuthServerKey(serverName, serverConfig);
    final entry = (parsed['mcpOAuth'] as Map)[key] as Map;
    expect(entry['accessToken'], 'access-xyz');
    expect(entry['refreshToken'], 'refresh-abc');
    expect(entry['serverName'], serverName);
  });

  test('mergeInto copies mcpOAuth to member config dir', () async {
    final store = McpCredentialsStore();
    final appDir = Directory('${root.path}/app')..createSync();
    final memberDir = Directory('${root.path}/member')..createSync();

    await store.saveOAuthTokens(
      configDir: appDir.path,
      serverName: 'srv',
      serverConfig: const {'type': 'http', 'url': 'https://a.test'},
      accessToken: 'tok',
      expiresAtMs: 1,
    );

    await store.mergeInto(
      fromConfigDir: appDir.path,
      toConfigDir: memberDir.path,
    );

    final member = await store.read(memberDir.path);
    expect(
      store.hasAccessToken(member, 'srv', const {
        'type': 'http',
        'url': 'https://a.test',
      }),
      isTrue,
    );
  });
}
