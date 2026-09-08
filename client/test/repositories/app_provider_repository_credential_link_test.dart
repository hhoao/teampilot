import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

import '../support/in_memory_filesystem.dart';

AppProviderConfig _linkedRow() => const AppProviderConfig(
  id: 'deepseek',
  cli: CliTool.claude,
  name: 'DeepSeek',
  category: AppProviderCategory.thirdParty,
  credentialLink: 'm1',
);

void main() {
  late InMemoryFilesystem fs;
  String? linkedSecret;

  setUp(() {
    fs = InMemoryFilesystem();
    linkedSecret = null;
  });

  AppProviderRepository repo() => AppProviderRepository(
    fs: fs,
    basePath: '/tp',
    linkedCredentialLookup: (id) async => id == 'm1' ? linkedSecret : null,
  );

  test('load resolves linked apiKey in memory without persisting it', () async {
    linkedSecret = 'sk-live';
    final r = repo();
    await r.saveProviders(CliTool.claude, [_linkedRow()]);
    final loaded = await r.loadProviders(CliTool.claude);
    expect(loaded.single.apiKey, 'sk-live');
    expect(loaded.single.credentialStatus, 'ready');
    // Disk keeps the linked row's key empty.
    final raw = await fs.readString('/tp/providers/claude/providers.json');
    expect(raw, isNotNull);
    expect(raw!.contains('sk-live'), isFalse);
    expect(raw.contains('"credentialLink": "m1"'), isTrue);
  });

  test('missing managed secret yields empty key and missing status', () async {
    linkedSecret = null; // entry or secret absent
    final r = repo();
    await r.saveProviders(CliTool.claude, [_linkedRow()]);
    final loaded = await r.loadProviders(CliTool.claude);
    expect(loaded.single.apiKey, '');
    expect(loaded.single.credentialStatus, 'missing');
  });

  test('save strips a stale resolved key on a linked row', () async {
    final r = repo();
    await r.saveProviders(CliTool.claude, [_linkedRow()]);
    // Simulate a caller handing back the in-memory-resolved row.
    final loaded = await r.loadProviders(CliTool.claude);
    await r.saveProviders(CliTool.claude, loaded);
    final raw = await fs.readString('/tp/providers/claude/providers.json');
    expect(raw!.contains('"apiKey": "sk'), isFalse);
  });

  test('unlinked providers keep preserved-secret merge behavior', () async {
    final r = repo();
    const withKey = AppProviderConfig(
      id: 'plain',
      cli: CliTool.claude,
      name: 'Plain',
      category: AppProviderCategory.thirdParty,
      apiKey: 'sk-own',
    );
    await r.saveProviders(CliTool.claude, [withKey]);
    final loaded = await r.loadProviders(CliTool.claude);
    // Blank key on an unlinked row preserves the stored secret (existing rule).
    await r.saveProviders(
      CliTool.claude,
      [loaded.single.copyWith(apiKey: '')],
    );
    final reloaded = await r.loadProviders(CliTool.claude);
    expect(reloaded.single.apiKey, 'sk-own');
  });

  test('linked rows materialize native config with the resolved key',
      () async {
    // Flashskyai materializes cli-defaults/flashskyai/llm_config.json on save.
    // The path is derived exactly as the strategy does (RuntimeLayout without
    // an injected fs), so the assertion holds under any platform path style.
    final r = AppProviderRepository(
      fs: fs,
      basePath: '/tp',
      linkedCredentialLookup: (id) async => id == 'm1' ? 'sk-live' : null,
    );
    await r.saveProviders(
      CliTool.flashskyai,
      [_linkedRow().copyWith(cli: CliTool.flashskyai, baseUrl: 'https://x')],
    );
    final configFile = RuntimeLayout(
      teampilotRoot: '/tp',
    ).appFlashskyaiLlmConfigFile;
    final raw = await fs.readString(configFile);
    expect(raw, isNotNull);
    expect(raw!.contains('sk-live'), isTrue);
  });
}
