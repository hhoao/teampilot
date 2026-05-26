// client/test/models/plugin_model_test.dart
import 'package:teampilot/models/plugin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Plugin round-trips through json with capabilities', () {
    const plugin = Plugin(
      id: 'acme/market/my-plugin',
      name: 'my-plugin',
      description: 'desc',
      version: '1.2.3',
      directory: 'acme__market__my-plugin',
      marketplaceOwner: 'acme',
      marketplaceName: 'market',
      marketplaceBranch: 'main',
      capabilities: PluginCapabilities(
        commands: [PluginCommand(name: 'deploy', description: 'd')],
        agents: [],
        skills: [PluginSkillRef(name: 'tdd', description: null)],
        hooks: [PluginHook(event: 'PreCommit', matcher: '*.dart')],
        mcpServers: [PluginMcpServer(name: 'github', type: 'stdio')],
      ),
      contentHash: 'abc123',
      installedAt: 1000,
      updatedAt: 2000,
    );

    final decoded = Plugin.fromJson(plugin.toJson());
    expect(decoded, plugin);
    expect(decoded.source, 'acme/market');
  });

  test('Plugin source is local when marketplaceOwner is null', () {
    const plugin = Plugin(
      id: 'local/dev-plugin',
      name: 'dev-plugin',
      description: '',
      version: '0.0.0+local',
      directory: 'local__dev-plugin',
      capabilities: PluginCapabilities(),
      installedAt: 0,
      updatedAt: 0,
    );
    expect(plugin.source, 'local');
  });

  test('PluginMarketplace round-trips', () {
    const m = PluginMarketplace(
      owner: 'acme', name: 'market', branch: 'main',
      enabled: false, displayName: 'Acme Market');
    final decoded = PluginMarketplace.fromJson(m.toJson());
    expect(decoded, m);
    expect(decoded.fullName, 'acme/market');
    expect(decoded.githubUrl, 'https://github.com/acme/market');
  });

  test('DiscoverablePlugin round-trips', () {
    const d = DiscoverablePlugin(
      key: 'acme:market:p',
      name: 'p',
      description: 'desc',
      version: '1.0.0',
      readmeUrl: 'https://...',
      marketplaceOwner: 'acme',
      marketplaceName: 'market',
      marketplaceBranch: 'main',
      source: '.',
      categories: ['dev'],
      keywords: ['k1'],
    );
    final decoded = DiscoverablePlugin.fromJson(d.toJson());
    expect(decoded, d);
  });

  test('DiscoverablePlugin == considers readmeUrl', () {
    const a = DiscoverablePlugin(
      key: 'k', name: 'n', description: 'd', version: '1.0.0',
      readmeUrl: 'http://a',
      marketplaceOwner: 'o', marketplaceName: 'm', marketplaceBranch: 'main',
      source: '.');
    const b = DiscoverablePlugin(
      key: 'k', name: 'n', description: 'd', version: '1.0.0',
      readmeUrl: 'http://b',
      marketplaceOwner: 'o', marketplaceName: 'm', marketplaceBranch: 'main',
      source: '.');
    expect(a == b, isFalse);
  });

  test('PluginMarketplace.copyWith can clear displayName', () {
    const m = PluginMarketplace(
      owner: 'o', name: 'n', displayName: 'D');
    final cleared = m.copyWith(clearDisplayName: true);
    expect(cleared.displayName, isNull);
  });

  test('PluginUpdateInfo round-trips', () {
    const u = PluginUpdateInfo(
      id: 'acme/market/p', name: 'p', remoteHash: 'r1', currentHash: 'c1');
    expect(PluginUpdateInfo.fromJson(u.toJson()), u);
  });

  test('PluginBackup round-trips', () {
    const plugin = Plugin(
      id: 'a/b/c', name: 'c', description: '', version: '1.0.0',
      directory: 'a__b__c',
      capabilities: PluginCapabilities(),
      installedAt: 1, updatedAt: 2);
    const b = PluginBackup(
      backupId: 'bk1', backupPath: '/tmp/bk', createdAt: 100, plugin: plugin);
    expect(PluginBackup.fromJson(b.toJson()), b);
  });

  test('UnmanagedPlugin holds directory/name/path', () {
    const u = UnmanagedPlugin(directory: 'foo', name: 'foo', path: '/tmp/foo');
    expect(u.directory, 'foo');
  });
}
